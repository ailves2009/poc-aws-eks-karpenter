# POC — AWS EKS with Karpenter (Graviton + Spot)

Terragrunt-based infrastructure for a production-oriented EKS cluster with Karpenter autoscaling, multi-architecture (x86_64 + arm64) and Spot-first capacity strategy.

---

## ⚠️ Before you do ANYTHING

The repo ships with placeholder values that are intentionally invalid. `apply` will fail until each is replaced. Read this whole section before running any command.

### Placeholders to replace

| File                                                                                                                   | Placeholder                                    | Replace with                                                                         |
| ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------ |
| [`non-prod/poc/account.hcl`](non-prod/poc/account.hcl)                                                                 | `aws_account_id = "111122223333"`              | your AWS account ID                                                                  |
| [`non-prod/poc/account.hcl`](non-prod/poc/account.hcl)                                                                 | `s3_terraform_state = "nyd-plt-tf-state"`      | a globally-unique S3 bucket name                                                     |
| [`non-prod/poc/account.hcl`](non-prod/poc/account.hcl)                                                                 | `domain_name = "poc-eks-karpenter.domain.xyz"` | a domain you control (used as Ingress Host header; not actually resolved in the POC) |
| [`non-prod/poc/us-east-1/persistent/bastion/terragrunt.hcl`](non-prod/poc/us-east-1/persistent/bastion/terragrunt.hcl) | `allowed_cidrs = ["YOUR.PUBLIC.IP.HERE/32"]`   | your office/home IP — `curl ifconfig.me`                                             |

### Operational requirements

- **All commands below assume `cd terraform/` from the repo root.** Paths are relative to that.
- **Your IAM user MUST be named exactly `terraform`.** The `cicd-deployment-role` trust policy hardcodes this principal in [`bootstrap/iam-state/terragrunt.hcl`](non-prod/poc/us-east-1/bootstrap/iam-state/terragrunt.hcl). If you use a different name, `sts:AssumeRole` will fail after bootstrap and the main apply will not proceed.
- **For first-time bootstrap, attach `AdministratorAccess` to the IAM user.** After bootstrap completes you can detach it — `cicd-deployment-role` (with its scoped policies + permissions boundary) does all the work going forward.
- **Two AWS CLI profiles are assumed throughout this README:**
  - `ae-nyd-plt-init` — IAM user `terraform` access keys. Used by Terragrunt for bootstrap and as the AssumeRole source for everything else.
  - `ae-nyd-plt-target` — auto-AssumeRole into `cicd-deployment-role`. Used only by `kubectl` and ad-hoc AWS CLI calls that need cluster RBAC. **Configured later** — see [§kubectl access](#kubectl-access--two-aws-profiles); only needed once the cluster exists.

  Either create profiles with exactly these names, or grep+replace `ae-nyd-plt-init` / `ae-nyd-plt-target` globally before running anything.
- **Full apply takes ~35 minutes** (EKS cluster creation alone is ~15 min). Don't assume it's hung — `terragrunt run --all apply` is processing dependencies in order.

---

## Running workloads on x86 / Graviton (end-user guide)

The cluster's Karpenter [`NodePool`](modules/karpenter/main.tf) advertises **both `amd64` and `arm64`** as allowed architectures and prefers Spot. As a developer you don't manage nodes — you just submit a pod, and Karpenter picks the cheapest instance whose architecture, CPU, and memory satisfy your spec.

You control architecture in two places: the **container image** (must be built for that arch) and the **pod's `nodeSelector` / `nodeAffinity`** (tells the scheduler what to ask for). If those don't match, the pod stays `Pending`.

### Pin to Graviton (arm64)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-arm64
spec:
  replicas: 1
  selector: { matchLabels: { app: hello-arm64 } }
  template:
    metadata: { labels: { app: hello-arm64 } }
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
      containers:
        - name: app
          image: public.ecr.aws/docker/library/nginx:alpine   # multi-arch manifest
          resources:
            requests: { cpu: 100m, memory: 128Mi }
```

### Pin to x86_64 (amd64)

Identical, but `kubernetes.io/arch: amd64`.

### Multi-arch (let Karpenter choose the cheapest Spot)

Drop the `nodeSelector` entirely. The pod becomes schedulable on either arch, and Karpenter will provision whichever Spot instance type wins the price/availability lottery — typically arm64 for compute-bound workloads.

```yaml
spec:
  containers:
    - name: app
      image: public.ecr.aws/docker/library/nginx:alpine
      resources:
        requests: { cpu: 100m, memory: 128Mi }
```

> ⚠️ The image must be a multi-arch manifest (most official images on Docker Hub / ECR Public are). Single-arch images will `ImagePullBackOff` on the wrong node.

### Prefer arm64 but allow amd64 fallback

Use `preferredDuringSchedulingIgnoredDuringExecution` instead of a hard `nodeSelector`. If no arm64 Spot capacity is available, the pod falls back to amd64 instead of staying `Pending`.

```yaml
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          preference:
            matchExpressions:
              - key: kubernetes.io/arch
                operator: In
                values: [arm64]
```

### Force on-demand instead of Spot

By default Karpenter prefers Spot (cheaper, can be reclaimed with 2-min warning). For workloads that can't tolerate interruption, pin `karpenter.sh/capacity-type`:

```yaml
spec:
  nodeSelector:
    karpenter.sh/capacity-type: on-demand
    kubernetes.io/arch: arm64
```

### Verify what you got

```bash
kubectl get pod -o wide                                                  # which node
kubectl get node <node> -o jsonpath='{.metadata.labels}' | jq            # arch + capacity-type
# expect: kubernetes.io/arch=arm64, karpenter.sh/capacity-type=spot
```

The same `nodeSelector` pattern is used by the demo nginx service — see `workloads/dev/demo/nginx.yaml` in [poc-eks-gitops-values](https://github.com/ailves2009/poc-eks-gitops-values) for a real GitOps-managed example with HPA driving Karpenter scale-up.

---

## Project structure

```
terraform/
├── root.hcl                       # global Terragrunt config: s3 backend, AssumeRole, AWS provider
├── modules/                       # reusable Terraform modules
│   ├── iam-state/                 # CI/CD role, IAM policies, permissions boundary, EC2-Spot SLR
│   ├── s3-state/                  # S3 bucket + KMS for tfstate
│   ├── bastion/                   # OpenVPN bastion (default VPC, optional Route53 record)
│   ├── vpc/                       # thin wrapper over terraform-aws-modules/vpc/aws
│   ├── eks/                       # thin wrapper over terraform-aws-modules/eks/aws
│   ├── karpenter/                 # eks/aws//modules/karpenter + Helm + EC2NodeClass/NodePool (vendored chart)
│   ├── aws-lb-controller/         # IRSA + Helm release of aws-load-balancer-controller
│   ├── argocd/                    # Argo CD (Helm) + the root app-of-apps Application
│   └── helm-release/              # generic helm_release wrapper (unused since 0.3.0: apps are GitOps)
└── non-prod/                      # environment classification
    └── poc/                       # AWS account
        ├── account.hcl            # account-level vars (id, role names, tags, bucket)
        └── us-east-1/             # AWS region
            ├── region.hcl         # region-level vars (region, cluster_name)
            ├── bootstrap/         # tier 1 — one-time, never destroyed (local backend)
            │   ├── iam-state/     # cicd-deployment-role, boundary, ec2-spot SLR
            │   └── s3-state/      # tfstate bucket
            ├── persistent/        # tier 2 — survives workload destroy/apply
            │   └── bastion/       # OpenVPN bastion
            └── workload/          # tier 3 — frequently destroyed/recreated
                ├── vpc/
                ├── eks/
                ├── karpenter/
                ├── aws-lb-controller/
                └── argocd/        # Argo CD + root app; everything else Argo CD deploys is GitOps
```

Outside `terraform/`: [`charts/`](../charts) holds the Helm charts Argo CD deploys (`poc-lib`
library + `demo-apps` umbrella). metrics-server and the nginx demo are no longer Terraform units —
see [GitOps with Argo CD](#gitops-with-argo-cd).

Hierarchy reads as `env → account → region → tier → unit`. Tier separation is by **lifecycle**, not by feature: bootstrap once, persistent rarely, workload often. Scoped runs:

```bash
# blow away EKS + nodes + addons, leave bastion/cert/state intact:
terragrunt run --all destroy --working-dir non-prod/poc/us-east-1/workload
```

---

## How it works

### Two layers, one repo

- **Bootstrap** (`bootstrap/iam-state`, `bootstrap/s3-state`)
  - Does NOT include `root.hcl` — uses `backend "local"` (state on disk).
  - Runs with raw IAM user credentials (`AWS_PROFILE=ae-nyd-plt-init`).
  - Creates `cicd-deployment-role`, the IAM boundary, the S3 state bucket, KMS key.

- **Main** (everything else)
  - Includes `root.hcl` → inherits `remote_state` (S3 backend) and `iam_role`.
  - Terragrunt automatically does `sts:AssumeRole` into `cicd-deployment-role` and injects temporary credentials into Terraform.
  - The same `AWS_PROFILE=ae-nyd-plt-init` is used at invocation; Terragrunt handles AssumeRole.

### State

- Backend: S3 (`use_lockfile = true` — native S3 locking, no DynamoDB needed).
- Bucket name: `local.account_vars.locals.s3_terraform_state` (`account.hcl`).
- Key per unit: `${path_relative_to_include()}/tf.tfstate` — each unit gets its own state file.
- Bootstrap state is local; `.terraform/`, `terraform.tfstate*`, `.terragrunt-cache/` are gitignored. Do not commit them.

### Permissions boundary

`iam-state` creates a `cicd-boundary` IAM policy. The `cicd-deployment-role` cannot create any IAM role without this boundary attached (enforced by the `iam:PermissionsBoundary` condition in its own policy). Every IAM role created by downstream modules must reference it:

```hcl
resource "aws_iam_role" "example" {
  permissions_boundary = var.permissions_boundary_arn  # from iam-state output
  ...
}
```

### Pod-to-AWS authentication

Three mechanisms coexist in the cluster, picked by what the workload is:

| Workload | Mechanism | Where wired |
|---|---|---|
| `aws-node` (VPC CNI) | **EKS Pod Identity** — dedicated role `vpc-cni-<cluster>`, `pods.eks.amazonaws.com` trust | `vpc-cni` addon `pod_identity_association` in [modules/eks/main.tf](modules/eks/main.tf) |
| Karpenter controller | **IRSA** — OIDC trust on EKS cluster | [modules/karpenter/main.tf](modules/karpenter/main.tf) |
| AWS Load Balancer Controller | **IRSA** | [modules/aws-lb-controller/main.tf](modules/aws-lb-controller/main.tf) |
| Karpenter-launched nodes | node IAM role (worker policies) | upstream `terraform-aws-modules/eks/aws//modules/karpenter` |

Pod Identity Agent (`eks-pod-identity-agent` addon) is installed and ready to serve any additional associations — e.g. `aws-ebs-csi-driver` when PVs are added. New CNI mechanism keeps `AmazonEKS_CNI_Policy` off the node IAM role: a pod compromised on a node cannot pull CNI credentials through IMDS.

> **Cleanup TODO**: the upstream EKS / Karpenter modules still attach `AmazonEKS_CNI_Policy` to node roles by default. Remove via `node_iam_role_attach_cni_policy = false` once Pod Identity is verified in prod — see [TODO](#todo).

---

## GitOps with Argo CD

Terraform builds the platform (VPC, EKS, IAM/IRSA, Karpenter, AWS Load Balancer Controller) and
installs **Argo CD with one root Application**. Everything Argo CD deploys after that comes from
git: three small repositories plus the charts in this one.

```text
 Terraform (this repo)                 GitHub
 ──────────────────────                ──────────────────────────────────────────────────────────
 workload/argocd                       poc-eks-gitops-root        "what & where"
  ├─ helm_release argo-cd 10.9.2        clusters/poc-plt-eks/
  └─ root Application ──recurse,──────►  ├─ 00-projects.yaml        Application  (wave -1) ──┐
        prune, selfHeal                   ├─ 10-infra-appset.yaml    list gen.    (wave 0)    │
                                          └─ 20-workloads-appset.yaml git files gen.(wave 1)  │
                                                                                            │
                                       poc-eks-gitops-projects    "who may do what"  ◄──────┘
                                         projects/{infra-poc-plt-eks,demo}.yaml  (AppProject)

                                       poc-eks-gitops-values      "with which parameters"
                                         infra/poc-plt-eks/metrics-server.yaml
                                         workloads/dev/demo/{_env,nginx,keepwarm}.yaml

                                       poc-aws-eks-karpenter/charts   "how it renders"
                                         poc-lib (library)  +  demo-apps (umbrella)   @ git tag
```

| Repository | Owns | Synced by | Sync |
|---|---|---|---|
| [poc-eks-gitops-root](https://github.com/ailves2009/poc-eks-gitops-root) | ApplicationSets, the `projects` Application | root Application (Terraform) | auto, prune |
| [poc-eks-gitops-projects](https://github.com/ailves2009/poc-eks-gitops-projects) | AppProjects: source repos, destinations, kind whitelists, roles, sync windows | `projects` Application | auto, prune |
| [poc-eks-gitops-values](https://github.com/ailves2009/poc-eks-gitops-values) | values per cluster / environment; one service file = one Application | ApplicationSets (as `$values` source / git files generator) | — |
| this repo, [`charts/`](../charts) | `poc-lib` library + `demo-apps` umbrella | Applications (chart source, by git tag) | — |

### How a service gets deployed

1. **Shape** in the chart: `charts/demo-apps/values/<service>.yaml` (ports, probes, resources).
2. **Environment** in the values repo: `workloads/<env>/<app>/<service>.yaml` — `chart.path`,
   `chart.revision` (git tag), image **by digest**, HPA, ingress, placement.
3. The workloads ApplicationSet (git files generator) creates Application
   `<app>-<env>-<service>` in namespace `<app>-<env>`, project `<app>`, rendering
   `values.yaml < values/<svc>.yaml < _env.yaml < <svc>.yaml < activeApp=<svc>`.
4. The chart's `values.schema.json` validates every layer; `poc-lib` refuses to render
   without `activeApp` — one render, one service.

Infra components (metrics-server) use a **list** generator instead: adding one is a pull
request to the root repo, under platform control; the chart version is pinned in the element.

### Design decisions

Built on a common enterprise layout (Argo CD hub, separate root / settings / values
repositories, a shared library chart consumed by umbrella charts), keeping its strengths and
fixing its usual weak spots:

| Common weak spot | In this POC |
|---|---|
| Cross-repo **merge order** (project → values → root) kept by discipline; a slip gives "project not found" | **Sync waves** (projects −1, infra 0, workloads 1) + CI in the root repo fails when a referenced or path-derived AppProject is missing |
| Root with `prune: false`: objects deleted from git live on | Root and projects **auto + prune**; workloads protected by `preserveResourcesOnDeletion` on the ApplicationSets instead |
| Settings app synced by hand — a sync drags in other people's merged-but-unsynced changes | AppProjects auto-synced from their own repo, ordered by wave |
| No pre-merge validation; ApplicationSet template bugs surface on the cluster | CI in every repo: `kubeconform -strict` against **real** Argo CD CRD schemas, full renders of every service file with the chart tag it names |
| `templatePatch` that wraps only `automated:` renders `syncPolicy: null` and wipes the syncPolicy | The `if` wraps the whole patch (see `10-infra-appset.yaml`) |
| Library schema not enforced (values sit outside the library's subtree) and permissive (`additionalProperties: true`) | **Strict `values.schema.json` in the umbrella**: unknown keys, an image without a digest or `targetCPU: 500` fail the render |
| Service shape merged in-template via `.Files.Glob` — invisible to the schema, to `helm get values` and to Argo CD | Shape passed as an explicit `valueFiles` entry — every layer is visible and validated |
| `activeApp` optional: without it every service renders and global collections leak into every Application | `required` in the library + `pattern` in the schema; contract test asserts the render fails |
| Deep merge through `toYaml \| fromYaml` (type coercion), two spellings for many keys | `mergeOverwrite` on `deepCopy`, one spelling per key |
| Library versions bumped by grepping the merge-commit subject; never a major | Phase 1: library ships in the same commit (`file://`). Phase 2: Conventional Commits + release-please, golden-render diff, cosign |
| CI tools fetched at `latest`, hand-written fixture schemas | Pinned tool versions; generated CRD schemas |

Contract tests ([`charts/tests/contract_test.py`](../charts/tests/contract_test.py)) render every
service and assert: one Deployment, selector ⊆ pod labels, Service selects the pods and targets a
declared port, image pinned by digest, non-root, no privilege escalation, read-only root FS, no
auto-mounted SA token — and that renders without `activeApp`, with an unknown key or without a
digest **fail**.

### Access

No Ingress for Argo CD in the POC (no public endpoint):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80          # → http://localhost:8080
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Default policy `role:readonly`; project roles (`operator`, `developer`) grant `get` + `sync`.

### Roadmap (phase 2)

- **ACK** (AWS Controllers for Kubernetes): per-service AWS resources (S3, SQS…) declared in the
  service's values and rendered by a separate `aws` part of the library — with
  `deletionPolicy: retain` / `Prune=false` for stateful resources and unique-name rules
  (`create`-only, no silent adoption). ACK controllers + IRSA installed via the infra ApplicationSet.
- **CRD lifecycle in GitOps**: CRDs as their own Applications/charts (as already done for
  Karpenter in Terraform), earlier sync waves, `ServerSideApply`, `Replace` for large CRDs.
- **Karpenter and the LB controller to GitOps** (role ARNs from Terraform outputs into values).
- **poc-lib to GHCR (OCI)**: release-please (Conventional Commits) → Release PR → tag →
  `helm push` + cosign keyless signature; Renovate bumps consumers with a golden-render diff.
- **Argo CD manages itself** after bootstrap; **Notifications** on `SyncFailed`/`Degraded`.
- **Hub-spoke**: a separate hub cluster registering spokes through IAM (`awsAuthConfig` + EKS
  access entries with a minimal policy) instead of long-lived cluster-admin tokens.
- HA mode (repo-server replicas, controller sharding); Kyverno policies; Argo CD Image Updater or
  Kargo for promotion between environments.

---

## Prerequisites

- AWS account with an IAM user `terraform` (long-lived access keys).
- AWS CLI profile `ae-nyd-plt-init` configured with that user's keys (`~/.aws/config` + `~/.aws/credentials`).
- Terraform >= 1.10 (or OpenTofu >= 1.8).
- Terragrunt >= 1.0 (the `run --all` CLI).
- `kubectl`, `helm` (cluster operations, local chart renders); `gh` (GitHub CLI) for the GitOps repositories.
- Python 3 + PyYAML — only to run the chart contract tests locally (`charts/tests/contract_test.py`).
- The three GitOps repositories ([root](https://github.com/ailves2009/poc-eks-gitops-root), [projects](https://github.com/ailves2009/poc-eks-gitops-projects), [values](https://github.com/ailves2009/poc-eks-gitops-values)) on GitHub, public (Argo CD reads them without credentials), and the chart tag `demo-apps-v1.0.0` in this repo.
- **DNS for the demo Ingress**: external. The nginx Ingress matches Host header = `nginx.${var.domain_name}`. After `apply`, get the ALB DNS from `kubectl get ingress -n demo-dev nginx` and create a CNAME in whatever Route53 zone you own — or test via `curl --resolve` (see Testing methodology). **No Route53 zone is created in this account.**

The `terraform` IAM user needs permissions to bootstrap: create the IAM role, the boundary policy, and the S3 bucket. After bootstrap, the user is only ever used to assume `cicd-deployment-role`.

> Production note: the long-lived access keys are an antipattern. For real environments use OIDC (GitHub Actions / GitLab CI web identity) so there are no static credentials anywhere.

---

## Deploy

### First-time deploy (bootstrap + main)

The first run is a two-step process because `cicd-deployment-role` and the S3 state bucket don't exist yet.

```bash
# Step 1 — bootstrap (creates IAM role + boundary + S3 bucket; state stored locally)
AWS_PROFILE=ae-nyd-plt-init terragrunt run --all apply \
  --working-dir non-prod/poc/us-east-1/bootstrap

# Step 2 — main layer (uses the freshly created bucket and AssumeRole).
# The last unit, workload/argocd, installs Argo CD + the root Application; Argo CD then
# deploys metrics-server and the demo from the GitOps repositories on its own.
AWS_PROFILE=ae-nyd-plt-init terragrunt run --all apply
```

Applications are not deployed by Terraform: after Step 2 watch them converge with
`kubectl -n argocd get applications` (all `Synced / Healthy` within a few minutes). For a
migration of an existing pre-0.3.0 deployment use [runbooks/gitops-argocd.md](runbooks/gitops-argocd.md).

### Subsequent deploys

After bootstrap, infrastructure changes are one command. Bootstrap is idempotent and won't recreate anything. Application changes (images, replicas, new services) are **not** Terraform: they are pull requests to [poc-eks-gitops-values](https://github.com/ailves2009/poc-eks-gitops-values), applied by Argo CD.

```bash
AWS_PROFILE=ae-nyd-plt-init terragrunt run --all plan
AWS_PROFILE=ae-nyd-plt-init terragrunt run --all apply
```

### Single-unit operations

```bash
cd non-prod/poc/us-east-1/workload/eks
AWS_PROFILE=ae-nyd-plt-init terragrunt plan
AWS_PROFILE=ae-nyd-plt-init terragrunt apply
```

---

## kubectl access — two AWS profiles

Two AWS CLI profiles are used in this project:

| Profile             | What it uses                                                            | When                                                    |
| ------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------- |
| `ae-nyd-plt-init`   | IAM user `terraform` access keys (created out-of-band)                  | bootstrap apply; assume-role source for everything else |
| `ae-nyd-plt-target` | auto-AssumeRole into `cicd-deployment-role`, source = `ae-nyd-plt-init` | `kubectl`, ad-hoc AWS CLI calls that need cluster RBAC  |

`~/.aws/config`:

```ini
[profile ae-nyd-plt-init]
region = us-east-1

[profile ae-nyd-plt-target]
role_arn       = arn:aws:iam::111122223333:role/cicd-deployment-role
source_profile = ae-nyd-plt-init
region         = us-east-1
```

### Why two

The EKS cluster is created with `enable_cluster_creator_admin_permissions = true`, which grants cluster-admin only to the principal that ran `terraform apply`. Terragrunt assumes `cicd-deployment-role` (via `iam_role` in [root.hcl](root.hcl)), so the **role**, not the user, is the cluster admin. For `kubectl` to see the cluster as the same principal, the `aws eks get-token` call must also assume the role — hence the `ae-nyd-plt-target` profile.

### Generate kubeconfig

```bash
AWS_PROFILE=ae-nyd-plt-target aws eks update-kubeconfig \
  --region us-east-1 --name poc-plt-eks \
  --kubeconfig ~/.kube/ae-5353-us-east-1-kubeconfig

export KUBECONFIG=~/.kube/ae-5353-us-east-1-kubeconfig
kubectl get ns
```

`update-kubeconfig` writes `AWS_PROFILE: <whatever was in env>` into the kubeconfig's `users.user.exec.env`, so `kubectl` always re-assumes the role on each call. Switching back to `ae-nyd-plt-init` only requires re-running the command with that profile.

In Terragrunt this all happens automatically (root.hcl's `iam_role` does the assume); for kubectl it has to be wired manually through the AWS profile.

---

## Testing methodology

Run after `workload/*` apply succeeds. Tests are layered: each one builds on the previous and exercises one more piece of the stack.

### 0. Health smoke

Verifies every component is alive before exercising it.

```bash
# (a) nodes — expect 2 bootstrap nodes Ready in 2 AZs, t4g.medium / arm64
kubectl get nodes -L topology.kubernetes.io/zone -L node.kubernetes.io/instance-type -L kubernetes.io/arch

# (b) system pods — all Running: coredns, kube-proxy, aws-node (vpc-cni),
#     eks-pod-identity-agent, karpenter (×2), aws-load-balancer-controller (×2),
#     metrics-server (×1, deployed by Argo CD), argocd-* (×5)
kubectl get pods -A

# (c) cluster RBAC — cicd-deployment-role should hold ClusterAdmin via Access Entry
AWS_PROFILE=ae-nyd-plt-target aws eks list-access-entries --cluster-name poc-plt-eks

# (d) Karpenter CRDs — default EC2NodeClass and NodePool both Ready=True
kubectl get ec2nodeclass,nodepool

# (e) metrics API — `kubectl top` must work; HPA depends on it
kubectl top nodes
kubectl top pods -A | head -10

# (f) Ingress + ALB — should have CLASS=alb, ADDRESS=k8s-demodev-nginx-...elb.amazonaws.com
kubectl get ingress -n demo-dev

# (g) GitOps — root, projects, infra-poc-plt-eks-metrics-server, demo-dev-nginx,
#     demo-dev-keepwarm: all Synced / Healthy
kubectl -n argocd get applications -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
#     multi-source Applications report revisions in .status.sync.revisions (plural):
kubectl -n argocd get application demo-dev-nginx -o jsonpath='{.status.sync.revisions}{"\n"}'
```

### 0.5. End-to-end through the ALB

The nginx Ingress is reachable as `http://<hostname>/` where `<hostname>` is `nginx.${var.domain_name}` (default `nginx.poc-eks-karpenter.domain.xyz`). POC has no real DNS in this account, so test with `curl --resolve` to bypass DNS:

```bash
ALB=$(kubectl get ingress -n demo-dev nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
HOST=$(kubectl get ingress -n demo-dev nginx -o jsonpath='{.spec.rules[0].host}')
ALB_IP=$(dig +short "$ALB" | head -1)

curl -sI --resolve "$HOST:80:$ALB_IP" "http://$HOST/"
# Expect: HTTP/1.1 200 OK + Server: nginx
```

Why this works: `--resolve` overrides DNS for `$HOST`. ALB receives the request with `Host: $HOST` header, the listener rule matches `host-header == $HOST`, traffic forwards to the nginx target group. Same path a real CNAME would take, just resolved client-side.

For a permanent setup (so `curl http://$HOST/` works without `--resolve`): add a CNAME `$HOST → $ALB` in your authoritative zone. In this POC that lives in another AWS account (`example.com`); the cross-account automation is a TODO.

If anything fails, check the relevant component's logs:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=80 | grep -iE "error|warn"
kubectl logs -n kube-system -l app.kubernetes.io/name=metrics-server --tail=40
```

### Test 1 — Karpenter provisions a spot node

Schedule a pod the bootstrap NG can't host (no `karpenter.sh/capacity-type` label on bootstrap nodes), watch Karpenter create a NodeClaim and an EC2 instance, the pod lands.

```bash
# trigger
kubectl run pause-arm --image=public.ecr.aws/eks-distro/kubernetes/pause:3.7 \
  --overrides='{"spec":{"nodeSelector":{"karpenter.sh/capacity-type":"spot","kubernetes.io/arch":"arm64"}}}'

# observe (~30-60s)
kubectl get nodeclaim
kubectl get nodes -L karpenter.sh/capacity-type -L kubernetes.io/arch \
  -L node.kubernetes.io/instance-type -L topology.kubernetes.io/zone

# Karpenter logs (decision-making)
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=40 \
  | grep -iE "provision|launched|nodeclaim"
```

**Expected**: a new node with `CAPACITY-TYPE=spot`, `ARCH=arm64`, instance type chosen by Karpenter (cheapest fit — typically `c7g`/`c8g`/`m7g` family, `large`).

**Pass criteria**: pod `Running` within 90s, NodeClaim `READY=True`.

Repeat with `arm64 → amd64` to verify multi-arch:
```bash
kubectl run pause-amd --image=public.ecr.aws/eks-distro/kubernetes/pause:3.7 \
  --overrides='{"spec":{"nodeSelector":{"karpenter.sh/capacity-type":"spot","kubernetes.io/arch":"amd64"}}}'
```

Cleanup:
```bash
kubectl delete pod pause-arm pause-amd
# Karpenter consolidates ~30s after pods leave (consolidationPolicy: WhenEmptyOrUnderutilized)
```

### Test 2 — HPA + Karpenter cascade under load

Full POC story: realistic CPU-bound workload (nginx from `charts/demo-apps`, `autoscaling.targetCPU=50` in `workloads/dev/demo/nginx.yaml` of the values repo) → HPA scales pods → Karpenter scales nodes.

#### Setup

nginx is configured with (chart shape `charts/demo-apps/values/nginx.yaml` + environment file `workloads/dev/demo/nginx.yaml`):
- `requests.cpu = 500m`, `limits.cpu = 1000m` — sized so 10 replicas (5 vCPU) exceed the capacity of 2 spot nodes (~4 vCPU). Forces Karpenter to provision additional capacity.
- `autoscaling.minReplicas=2, maxReplicas=10, targetCPU=50` — scale up when avg CPU > 250m per pod.
- `nodeSelector: karpenter.sh/capacity-type=spot` — bootstrap NG cannot host these pods.
- `topologySpreadConstraints` on `topology.kubernetes.io/zone` (soft) — replicas spread across AZs when possible.

#### Watcher

In one terminal:
```bash
watch -n 2 '
echo "=== HPA ==="; kubectl get hpa -n demo-dev;
echo;
echo "=== Nginx pods ==="; kubectl get pods -n demo-dev -l app.kubernetes.io/name=nginx -o wide --no-headers;
echo;
echo "=== Spot nodes ==="; kubectl get nodes -L karpenter.sh/capacity-type --no-headers | grep spot;
echo;
echo "=== NodeClaims ==="; kubectl get nodeclaim --no-headers
'
```

#### Generate load

`fortio` produces sustained, controllable concurrency — far better than busybox `wget` loops which are sequential per pod.

```bash
kubectl run fortio -n demo-dev --image=fortio/fortio --restart=Never -- \
  load -c 200 -qps 0 -t 10m http://nginx.demo-dev.svc.cluster.local/
```

- `-c 200` — 200 concurrent connections.
- `-qps 0` — no rate limit (push as hard as the server allows).
- `-t 10m` — duration.

For even more intensity, run multiple busybox loops in parallel alongside fortio (as a quick "spam" generator):
```bash
for i in 1 2 3 4 5; do
  kubectl run -n demo-dev "loadgen-$i" --image=busybox:1.38.0 --restart=Never -- \
    /bin/sh -c "while sleep 0.005; do wget -q -O- http://nginx.demo-dev.svc.cluster.local; done" &
done
```

#### Expected timeline

| Time | What happens                                                                                                                                                               |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0:00 | Load generators start; fortio drives ~200 RPS× per nginx pod.                                                                                                              |
| 0:30 | metrics-server reports CPU climbing on nginx pods.                                                                                                                         |
| 0:45 | HPA: `cpu: 90%/50%, REPLICAS: 4`.                                                                                                                                          |
| 1:00 | HPA: `cpu: 110%/50%, REPLICAS: 8`.                                                                                                                                         |
| 1:15 | HPA hits `REPLICAS: 10`. New pods (8th, 9th, 10th) Pending — no capacity.                                                                                                  |
| 1:30 | Karpenter NodeClaim(s) created; `kubectl get nodeclaim` shows `READY=Unknown`.                                                                                             |
| 2:00 | New spot node(s) Ready and joined (typical types: `c7gn.large`, `c8gn.large`, `c6gd.large`, `m8gd.large`, `c7i-flex.large` — Karpenter picks cheapest spot in the moment). |
| 2:15 | Pending nginx pods scheduled on new node(s). Avg CPU per pod settles below 50%.                                                                                            |

**Pass criteria**:
- HPA `REPLICAS` reached `maxReplicas: 10`.
- Total spot nodes increased from 2 → 3+ during peak.
- All 10 nginx pods `Running` simultaneously.
- HPA `TARGETS` shows real CPU percentages (never `<unknown>`).

#### Cleanup

Stop load:
```bash
kubectl delete pod -n demo-dev loadgen-{1..5} fortio --ignore-not-found
```

Watch the unwind (this exercises consolidation, the second Karpenter superpower):

| Time  | What happens                                                                                                     |
| ----- | ---------------------------------------------------------------------------------------------------------------- |
| 0:00  | Load stops. CPU on nginx drops to ~0%.                                                                           |
| ~5:00 | HPA `REPLICAS` drops back to 2 (default `--horizontal-pod-autoscaler-downscale-stabilization=5m`).               |
| ~5:30 | Empty/underutilized spot nodes consolidate (`consolidateAfter: 30s`). NodeClaims terminate, instances shut down. |
| ~6:00 | Cluster steady-state: 2 bootstrap + 1-2 spot.                                                                    |

#### Tear down the demo entirely

The demo is GitOps-managed: remove its service files from
[poc-eks-gitops-values](https://github.com/ailves2009/poc-eks-gitops-values)
(`workloads/dev/demo/{nginx,keepwarm}.yaml`) and push. The Applications disappear, but the
workloads are preserved by design (`preserveResourcesOnDeletion`), so delete them explicitly:

```bash
kubectl delete namespace demo-dev   # Deployments, HPA, Ingress (→ the ALB) go; spot nodes consolidate
```

### Where Karpenter-managed nodes appear in the AWS Console

This trips people up: **Karpenter does NOT use EKS Managed Node Groups**. EKS Console → Compute → Node Groups shows only `bootstrap` (one row), regardless of how many spot nodes Karpenter has running.

| Component                  | Console location                                                          |
| -------------------------- | ------------------------------------------------------------------------- |
| Bootstrap NG               | EKS → Compute → Node Groups → `bootstrap`, also EC2 → Auto Scaling Groups |
| Karpenter spot nodes       | EC2 → Instances (filter by tag `karpenter.sh/nodepool=default`)           |
| Karpenter spot launches    | EC2 → Spot Requests (active fleet requests)                               |
| Karpenter launch templates | EC2 → Launch Templates (one per EC2NodeClass)                             |

In Kubernetes both kinds appear together via `kubectl get nodes`. Distinguish by labels:
```bash
kubectl get nodes -l eks.amazonaws.com/nodegroup=bootstrap   # bootstrap NG nodes
kubectl get nodes -l karpenter.sh/nodepool=default           # Karpenter nodes
```

---

## Networking choices

### VPC for the bastion: default VPC

The `bastion` module deploys into the **account default VPC** for POC simplicity. This is intentionally the lazy choice. For production, replace it with a dedicated platform VPC (small, public-only, no NAT) and reference it via `var.vpc_id`/`var.subnet_ids`.

### VPC for EKS workload: dedicated VPC

EKS will get its own VPC (`workload/vpc`) — public + private subnets, NAT, EKS-specific subnet tags. This is independent of the bastion VPC.

### Reaching workers from VPN

Because bastion VPC ≠ workload VPC, **VPN clients cannot reach EKS workers without VPC peering** between the two. For POC this is acceptable (debugging via `kubectl` against the EKS public+private endpoint works directly from a laptop). When/if EKS endpoint is locked to private only, add a VPC peering or Transit Gateway.

### EKS API endpoint

Plan: start with `endpoint_public_access = true` AND `endpoint_private_access = true`.
- Public lets you `kubectl` from a laptop without VPN.
- Private keeps in-VPC traffic (Karpenter, kubelet → API) off the internet.

Later, after the bastion + VPN are validated, you can flip `endpoint_public_access = false`. **Do not flip it without first testing kubectl through the VPN** — otherwise you lock yourself out of the cluster.

---

## Bastion / OpenVPN

`persistent/bastion` provisions a t4g.small EC2 in the account default VPC with:
- Elastic IP (output as `public_ip`).
- IAM instance-profile with `AmazonSSMManagedInstanceCore`.
- Security group: ingress on TCP/22 (SSH) and UDP/1194 (OpenVPN) restricted to `var.allowed_cidrs`.
- cloud-init that installs OpenVPN community + easy-rsa, generates a self-signed CA + server cert + one client cert (`client1`), brings up the OpenVPN server, and writes a helper `/usr/local/bin/get-ovpn-config` that prints a self-contained `.ovpn` to stdout.

### DNS

`create_dns_record = false` by default — the project doesn't manage Route53 in this account. Take `public_ip` from the module output and add a CNAME / A record manually in your authoritative zone (e.g. `bastion.poc.example.com`).

### Connecting

```bash
# Get the .ovpn (assumes SSM agent is online — see TODO if it isn't)
INSTANCE_ID=$(cd non-prod/poc/us-east-1/persistent/bastion && terragrunt output -raw instance_id)
AWS_PROFILE=ae-nyd-plt-target aws ssm start-session --target "$INSTANCE_ID"

# Inside the session:
sudo /usr/local/bin/get-ovpn-config > /tmp/client1.ovpn
exit

# Copy /tmp/client1.ovpn to your laptop and import into Tunnelblick / openvpn3.
```

For additional clients, ssh/SSM in and run `cd /etc/openvpn/easy-rsa && EASYRSA_BATCH=1 ./easyrsa gen-req clientN nopass && ./easyrsa sign-req client clientN`. PKI lives in `/etc/openvpn/easy-rsa/pki`.

> Lock down `allowed_cidrs` in `persistent/bastion/terragrunt.hcl` to your real public IP before applying. `0.0.0.0/0` opens SSH/UDP-1194 to the world.

---

## Karpenter

Capacity strategy:
- Spot-first, On-Demand fallback.
- Instance type diversification to reduce interruption risk.
- Multi-architecture: `amd64` (Intel/AMD) + `arm64` (Graviton).

Pinning workloads:

```yaml
# x86_64
spec:
  nodeSelector:
    kubernetes.io/arch: amd64

# arm64 (Graviton)
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
```

For production prefer `nodeAffinity` over `nodeSelector` — gives soft/hard preferences and richer expressions.

---

## Module strategy: thin wrappers around `terraform-aws-modules`

`vpc`, `eks`, `karpenter`, `aws-lb-controller` are **thin local wrappers** around the community modules at https://github.com/terraform-aws-modules — battle-tested, prod-quality. The local module fixes project conventions (tags, naming, boundary attachment, region pinning, vendoring of charts); the upstream module does the heavy lifting (security groups, addons, IAM, edge cases).

Custom-from-scratch is reserved for things that are simple enough to own (`iam-state`, `s3-state`, `bastion`, `helm-release`).

---

## Out of scope

- Observability stack (Prometheus, Grafana, Loki).
- Centralized logging, alerting (PagerDuty / OpsGenie).
- Service mesh.
- Multi-environment beyond `non-prod/poc/`.

---

## Known caveats

### CI/CD role can escalate to admin (POC only)

`cicd-deployment-role` ([modules/iam-state](modules/iam-state/main.tf)) can grant itself admin rights. It can rewrite its own managed policies (`CreatePolicyVersion` / `SetDefaultPolicyVersion` on `policy/*`). The permissions boundary `cicd-boundary` is `Allow *`, so a role it creates with `AdministratorAccess` attached is effectively admin. It can also set or remove boundaries on any role. This is accepted for the POC and **must be fixed before prod** (see [Roadmap to production](#roadmap-to-production)).

### Argo CD access is local admin + port-forward (POC only)

No Ingress and no SSO: the UI and API are reached with `kubectl port-forward`, and the local
`admin` account's password is in `argocd-initial-admin-secret` (a new one on every rebuild). For
anything beyond a POC: an OIDC/SSO connector bound to the project roles, `admin.enabled: false`,
and an internal Ingress.

### Runbooks

- [runbooks/upgrade-0.2.0.md](runbooks/upgrade-0.2.0.md): upgrade the deployed POC to 0.2.0 (Karpenter 1.15, EKS 1.37).
- [runbooks/bastion-access.md](runbooks/bastion-access.md): rebuild the bastion, SSH, SSM, OpenVPN client config.
- [runbooks/gitops-argocd.md](runbooks/gitops-argocd.md): install Argo CD, publish the GitOps repositories, hand metrics-server and the demo over to Argo CD (0.3.0).
- [runbooks/hibernate.md](runbooks/hibernate.md): put the POC into deep sleep (≈ $1–5/month) and wake it up with one command.

### No Bitnami charts

Since mid-2025 Bitnami restricted free-tier access to `docker.io/bitnami/*` and froze the old images under `docker.io/bitnamilegacy/*` (no security updates). Bitnami charts only work with Bitnami images, so the demo uses its own charts instead — [`charts/demo-apps`](../charts/demo-apps) on the [`poc-lib`](../charts/poc-lib) library — with the official `nginxinc/nginx-unprivileged` image pinned by tag + digest. Avoid bitnami charts for new components.

### EKS Spot service-linked role

`AWSServiceRoleForEC2Spot` must exist in the account before any spot launch (Karpenter or otherwise). It's a one-time AWS bootstrap. Created via `aws_iam_service_linked_role.ec2_spot` in `iam-state`. If you import the project to a new account, this is created automatically by the bootstrap apply.

---

## TODO

- **Karpenter chart vendored locally**. The chart `oci://public.ecr.aws/karpenter/karpenter` is pre-pulled into `modules/karpenter/charts/karpenter-<version>.tgz` and committed. Done because `helm provider v3` re-authenticates against OCI on every `plan`, and the auth token (TTL 12h from `data.aws_ecrpublic_authorization_token`) frequently fails with `403 expired` on subsequent applies. CRDs come from a separate vendored `karpenter-crd` chart (Helm never upgrades a chart's `crds/` directory). To bump the version: `helm pull oci://public.ecr.aws/karpenter/karpenter --version <X.Y.Z> --destination modules/karpenter/charts/` **and** the same for `oci://public.ecr.aws/karpenter/karpenter-crd`, update `var.karpenter_chart_version`, check the [upgrade guide](https://karpenter.sh/docs/upgrading/upgrade-guide/) for new controller IAM permissions (add them to `iam_policy_statements`), commit. Runtime image pulls (`public.ecr.aws/karpenter/controller`) are anonymous and unaffected. Tracked at https://github.com/hashicorp/terraform-provider-helm
- **Cross-account DNS automation**. The authoritative zone (`example.com`) is in a different AWS account from where the workload runs. Currently the operator manually adds CNAMEs. Two options to automate: (a) cross-account IAM trust — give this account a role in the DNS account that lets it `route53:ChangeResourceRecordSets` on `*.poc.example.com`; deploy `external-dns` here pointing at that role. (b) `external-dns` running in DNS account, watching the workload account's resources via cross-account read of LB addresses. (a) is more idiomatic. Once done, drop `--resolve` from the test methodology and use `curl http://$HOST/` directly.
- **HTTPS / ACM cert + real domain**. The demo Ingress on nginx is **HTTP-only**. ACM DNS-validation requires the cert's domain to be delegated to a Route53 zone in this AWS account; in the original POC neither candidate domain qualified (corp parent zone wasn't delegate-able; the personal alternative lived in a different AWS account). To enable HTTPS for prod: either (a) cross-account delegate a subdomain to this account's Route53 (NS records pointing at this account's nameservers), add a `persistent/acm` unit that issues a wildcard cert via DNS validation, and add the HTTPS listener (`alb.ingress.kubernetes.io/listen-ports`, `certificate-arn`) to the ingress annotations in `workloads/dev/demo/nginx.yaml` of the values repo; or (b) provision the cert externally and import via `aws_acm_certificate.import_*`.
- Bumping bootstrap node group `min_size`/`desired_size` after first apply requires a manual `aws eks update-nodegroup-config` because the upstream module (`terraform-aws-modules/eks/aws`) `ignore_changes = [scaling_config[0].desired_size]` on the managed NG. Workflow: AWS CLI to raise desired, then `terragrunt apply` for min/max. Document or wrap this in a small helper if it becomes routine.
- **Bastion SSM agent registration**: root cause found. The AMI filter matched `al2023-ami-minimal-*`, which has no `amazon-ssm-agent` and no `ec2-instance-connect`. The filter is fixed and cloud-init installs both packages. The deployed instance still has to be rebuilt; see [runbooks/bastion-access.md](runbooks/bastion-access.md).
- `workload/external-dns` (optional — auto-creates Route53 records for Service/Ingress). Limited utility while DNS is in another account; would need cross-account write permissions.
- `aws-ebs-csi-driver` EKS addon (currently disabled — requires IRSA role / Pod Identity Association for the controller pod). Add when PersistentVolumes are needed. Pattern: same as VPC CNI (dedicated role + `pod_identity_association` on the addon).
- **Remove `AmazonEKS_CNI_Policy` from node IAM roles** now that VPC CNI uses Pod Identity. Currently the policy is still attached on the bootstrap node group (upstream module default) and on the Karpenter node role (`node_iam_role_attach_cni_policy = true` in [modules/karpenter/main.tf](modules/karpenter/main.tf)). Until removed, CNI gets credentials from two sources — Pod Identity works, but the security win (no CNI permissions reachable via IMDS from a compromised pod) is not realized. Sequence: confirm Pod Identity is healthy → flip the flag to `false` → apply → spot-check that `aws-node` still works.
- VPC peering between bastion VPC (default) and workload VPC, so VPN clients can reach EKS workers.
- Switch EKS endpoint to private-only after VPN is validated.
- **`modules/helm-release`** is unused since 0.3.0 (applications are deployed by Argo CD): delete it, or keep it only for ad-hoc charts outside GitOps.
- **Migrate bootstrap state from local backend to S3** after deploy stabilizes. `bootstrap/iam-state` and `bootstrap/s3-state` use `backend "local"` with the state file next to each unit's `terragrunt.hcl` (gitignored; configured in [`bootstrap/bootstrap.hcl`](non-prod/poc/us-east-1/bootstrap/bootstrap.hcl)), so clearing `.terragrunt-cache` is safe — but the files exist only on one laptop. Back them up until migrated.

---

## Roadmap to production

- Replace static IAM user keys with OIDC for CI/CD.
- **Close the CI/CD privilege escalation** (see [Known caveats](#cicd-role-can-escalate-to-admin-poc-only)):
  - Explicit Deny on the role's own policies, its own role and `cicd-boundary`.
  - Replace the `Allow *` boundary with a per-service allowlist: no IAM writes except instance profiles and service-linked roles, no `sts:AssumeRole`.
  - Condition detach/delete/`PutRolePermissionsBoundary` on `iam:PermissionsBoundary`.
  - Drop `DeleteRolePermissionsBoundary`.
  - Scope `iam:PassRole` / `iam:DeleteRole` to project role-name prefixes.
- Migrate bootstrap state from local to S3 after the bucket exists.
- Narrow `infra` IAM policy from action wildcards (`eks:*`, `ec2:*`) to specific actions.
- Multi-env via separate AWS accounts (Organizations) and matching `account.hcl` per env.
- OPA / Kyverno admission policies, NetworkPolicies, Secrets Manager / Vault for app secrets.
- Replace default VPC for bastion with a dedicated platform VPC.
- GitOps phase 2 — ACK, CRD lifecycle, Karpenter / LB controller via Argo CD, `poc-lib` in GHCR with release-please + cosign, self-managed Argo CD, Notifications, hub-spoke: see [GitOps with Argo CD → Roadmap](#roadmap-phase-2).
