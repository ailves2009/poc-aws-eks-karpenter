# Changes

Reverse-chronological log of structural / behavioural changes. Bug fixes that
don't change behaviour aren't listed unless they shaped the design.

## 0.3.0 — Argo CD and GitOps (phase 1)

### Added

- **Argo CD** (chart argo-cd 10.9.2 = v3.5.3) installed by the new `modules/argocd` /
  `workload/argocd` unit, together with one **root Application** (app-of-apps, auto + prune +
  selfHeal, no cascade on delete). UI through `kubectl port-forward` only.
- **Three GitOps repositories** (branch `master`):
  [poc-eks-gitops-root](https://github.com/ailves2009/poc-eks-gitops-root) (ApplicationSets,
  sync waves), [poc-eks-gitops-projects](https://github.com/ailves2009/poc-eks-gitops-projects)
  (AppProjects with kind whitelists, roles, sync window),
  [poc-eks-gitops-values](https://github.com/ailves2009/poc-eks-gitops-values) (values per cluster /
  environment; one service file = one Application).
- **`charts/poc-lib`** library chart and **`charts/demo-apps`** umbrella: one render = one service
  (`activeApp` is `required`), strict `values.schema.json` validating every values layer, images
  by digest, restricted securityContext by default.
- **CI**: contract tests + `kubeconform -strict` for the charts; CRD-schema validation and a
  cross-repo AppProject check in the root repo; full renders of every service file in the values
  repo.
- Runbooks [`gitops-argocd.md`](runbooks/gitops-argocd.md) and [`hibernate.md`](runbooks/hibernate.md).

### Changed

- **metrics-server** (chart 3.12.2 → 3.14.0) and the **nginx demo** moved from Terraform units to
  Argo CD. metrics-server is adopted in place; the demo moves from namespace `demo` to `demo-dev`
  (`<app>-<env>`), with `keepwarm` as a service of its own.

### Fixed

- Chart contract test matched the schema error text of Helm 4 only; Helm 3 (CI, and Argo CD's
  repo-server) words it differently. Errors are now matched by a case-insensitive pattern, and
  the tests pass on both.
- GitHub Actions moved to their Node 24 majors (`checkout@v6`, `setup-python@v6`,
  `setup-helm@v5`) in all four repositories.

### Verified on the live POC (EKS 1.37, 2026-10-11)

All five Applications `Synced / Healthy`; metrics-server adopted (Argo CD tracking id, `kubectl
top` works); nginx scheduled on a Karpenter spot node; `HTTP 200` through the new ALB; CI green
in all four repositories.

### Removed

- Units `workload/metrics-server`, `workload/nginx` and `terraform/charts/nginx-demo`.
  `modules/helm-release` stays for ad-hoc charts but is no longer used.

## 0.2.0 — Review fixes: Karpenter 1.15, EKS 1.37, bastion access

### Security

- `managed_role_names` now match the role names the modules really create
  (`KarpenterController-*`, `Karpenter-*`, `aws-load-balancer-controller-*`,
  `vpc-cni-*`).
- Bootstrap providers pinned with `allowed_account_ids`.
- Bastion: easy-rsa archive verified against a pinned SHA-256 (taken after
  a GPG signature check) and downloaded with `curl -f`; IMDS hop limit 2 → 1.

### Known issues (accepted for POC, fix before prod)

- **The CI/CD role can escalate to admin.** It can edit its own managed
  policies (`CreatePolicyVersion` / `SetDefaultPolicyVersion` on `policy/*`).
  `cicd-boundary` is `Allow *`, so a bounded role it creates with
  `AdministratorAccess` is effectively admin. Boundary set/delete is
  unconditioned. Fix: Deny on its own policies, role and boundary, a
  per-service allowlist boundary, and boundary-conditioned detach/delete.
  Tracked in README → Roadmap to production.

### Changed

- **Karpenter 1.2.0 → 1.15.0**, controller policy switched to v1
  (`enable_v1_permissions = true`) plus `iam:ListInstanceProfiles`,
  `ec2:DescribeInstanceStatus`, `ec2:DescribeCapacityReservations`.
- **CRDs via a separate `karpenter-crd` release** (Helm never upgrades a
  chart's `crds/`); main chart uses `skip_crds = true`.
- EC2NodeClass AMI pinned (`al2023@v20261003`) instead of `@latest`;
  default NodePool CPU limit 1000 → 32.
- `gavinbunney/kubectl` → maintained fork `alekc/kubectl` (same resource types).
- **EKS 1.32 → 1.37** (1.32 is on extended support since 2026-03-23). Addon
  versions pinned via `addon_versions` instead of `most_recent = true`.
- **nginx demo**: bitnami chart + frozen `bitnamilegacy/nginx` replaced by
  local [charts/nginx-demo](charts/nginx-demo) with
  `nginxinc/nginx-unprivileged:1.30.5-alpine` and `busybox:1.38.0`, both
  pinned by digest. Release name and selector labels unchanged.
- Terragrunt `dependency` mocks restricted to `init`/`validate`/`plan`.
- Bootstrap local state moved out of `.terragrunt-cache` (next to each
  unit's `terragrunt.hcl`); shared config in `bootstrap/bootstrap.hcl`.
- `default_tags` on all AWS providers; `required_version >= 1.10`
  (needed by `use_lockfile`); helm provider `>= 3.0`; s3-state AWS `>= 6.0`.
- Legacy `modules/iam`, `modules/metrics` (unused): broken ARNs, foreign
  project references and the CA decoding bug fixed.

### Fixed

- **Bastion was unreachable by SSM / Instance Connect.** The AMI filter
  `al2023-ami-*-arm64` matched `al2023-ami-minimal-*`, which ships without
  `amazon-ssm-agent` and `ec2-instance-connect`. The filter now selects the
  standard image, and cloud-init installs both packages explicitly. There
  is an optional SSH key pair (`bastion.pub`). The allowed CIDRs come from
  `BASTION_ALLOWED_CIDRS` and are never committed.

### Upgrade notes (existing deployment)

Step-by-step: [runbooks/upgrade-0.2.0.md](runbooks/upgrade-0.2.0.md).
Bastion rebuild and access: [runbooks/bastion-access.md](runbooks/bastion-access.md).

## 0.1.2 — VPC CNI on EKS Pod Identity

### Changed

- **`vpc-cni` addon now authenticates via EKS Pod Identity** instead of
  inheriting permissions from the node IAM role. A dedicated IAM role
  `vpc-cni-<cluster>` is created in `modules/eks` with trust on
  `pods.eks.amazonaws.com` and `AmazonEKS_CNI_Policy` attached, then bound
  to the `aws-node` ServiceAccount via the addon's `pod_identity_association`.
  Reduces blast radius: a pod compromised on a node can no longer obtain
  CNI credentials through IMDS (once `AmazonEKS_CNI_Policy` is removed from
  the node role — see [README → TODO](README.md#todo)).
- **All EKS addons set to `most_recent = true`** (`coredns`, `kube-proxy`,
  `vpc-cni`, `eks-pod-identity-agent`). AWS auto-selects the latest
  compatible version on apply. Appropriate for POC; for prod, pin
  `addon_version` explicitly and update on a controlled cadence.

### Added to cicd policy ([modules/iam-state](modules/iam-state))

Gaps discovered during the Pod Identity rollout:

- `iam:PutRolePermissionsBoundary` / `iam:DeleteRolePermissionsBoundary` in
  `IamModifyRoles` — needed to set the boundary on roles the upstream EKS
  module manages.
- `pods.eks.amazonaws.com` added to `IamPassRoleToAwsServices` condition —
  needed for EKS `UpdateAddon` to wire Pod Identity associations.

The `cicd-boundary` policy still **denies** `iam:PutRolePermissionsBoundary` on
the bounded roles themselves (anti-escalation), so the new permissions only
broaden what CI/CD can manage, not what individual managed roles can do.

### Known follow-ups

- `AmazonEKS_CNI_Policy` is still attached to the bootstrap node group role
  (upstream default) and to the Karpenter node role
  (`node_iam_role_attach_cni_policy = true`). Pod Identity works, but the
  least-privilege benefit on the node side is not realized until those
  are flipped to `false`. Tracked in [README → TODO](README.md#todo).

## 0.1.1 — Repo cleanup

### Removed

- **`modules/acm`** — kept until now as "not deployed in POC", but unused
  in any unit. Removed to reduce surface area. ACM / HTTPS path remains
  documented in README → TODO for whenever a real domain is delegated to
  this account.

### Changed

- Repo restructured: `terraform/` is now a sibling of `architecture/`
  under the project root. Internal layout of `terraform/` unchanged —
  all unit and module paths are the same.

## 0.1.0 — POC complete

### Added

- **Three-tier layout** under `non-prod/poc/us-east-1/`: `bootstrap/`, `persistent/`, `workload/`.
  Tiers separated by lifecycle, not by feature, so `terragrunt run --all destroy
  --working-dir workload` blows away the cluster without touching the cicd-role
  or state bucket.
- **`bootstrap/iam-state`** — `cicd-deployment-role` + scoped policies
  (s3-state, iam-management with `iam:PermissionsBoundary` condition,
  infra, runtime), `cicd-boundary` policy, `AWSServiceRoleForEC2Spot`.
- **`bootstrap/s3-state`** — KMS-encrypted tfstate bucket (`use_lockfile = true`,
  no DynamoDB).
- **`workload/vpc`** — wrapper over `terraform-aws-modules/vpc/aws`. Single NAT,
  EKS / Karpenter / ALB-controller subnet discovery tags.
- **`workload/eks`** — wrapper over `terraform-aws-modules/eks/aws`. EKS 1.32,
  public + private endpoint, Access Entries (cluster creator → ClusterAdmin),
  KMS envelope encryption, addons (CoreDNS, kube-proxy, VPC CNI, Pod Identity
  Agent). Bootstrap NG: 2× t4g.medium across AZs.
- **`workload/karpenter`** — wrapper over
  `terraform-aws-modules/eks/aws//modules/karpenter` (IRSA + node IAM role +
  SQS interruption queue + EventBridge) + Helm chart **vendored locally**
  at `modules/karpenter/charts/karpenter-1.2.0.tgz` + default
  `EC2NodeClass` and `NodePool` (multi-arch, spot+on-demand, c/m/r families,
  consolidate when empty/underutilized).
- **`workload/aws-lb-controller`** — IRSA via
  `terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks`
  + Helm release. Pinned to bootstrap NG, 2 replicas spread across AZs.
- **`workload/metrics-server`** — generic `helm-release` wrapper. Required for
  `kubectl top` and HPA. Pinned to bootstrap NG.
- **`workload/nginx`** — bitnami/nginx chart through `helm-release`, with HPA
  (2..10 replicas, 50% CPU target), `karpenter.sh/capacity-type=spot`
  nodeSelector, AWS LB Controller Ingress (HTTP only), `keepwarm` Deployment
  via chart's `extraDeploy` for non-zero baseline metrics.
- **`persistent/bastion`** — t4g.small in default VPC, EIP, IAM with
  `AmazonSSMManagedInstanceCore`, OpenVPN community via cloud-init.
  `create_dns_record = false` because no Route53 zone in this account.
- **`modules/helm-release`** — generic wrapper used by `metrics-server` and
  `nginx`. Configures helm provider with `aws eks get-token` exec auth.
- **Testing methodology** in README: health smoke, end-to-end ALB,
  Karpenter provisioning, HPA + Karpenter cascade.

### Changed / decided

- **Karpenter chart vendoring** instead of pulling from
  `oci://public.ecr.aws/karpenter` at every `terraform plan`. The helm
  provider v3 has a bug where the OCI auth token (TTL 12h) caches in state
  and fails with `403 expired` on subsequent applies.
- **HTTP-only Ingress** on nginx. ACM DNS-validation requires the cert's
  zone to live in this AWS account, which the POC's candidate domains did
  not (one was corp-managed, one was in a different account). Cross-account
  DNS automation is TODO.
- **Bitnami chart override**: `image.repository = bitnamilegacy/nginx` plus
  `global.security.allowInsecureImages = true`. Bitnami moved free-tier
  images in mid-2025.
- **Bootstrap node group sizing** done by manual
  `aws eks update-nodegroup-config` because
  `terraform-aws-modules/eks/aws//modules/eks-managed-node-group` ignores
  `desired_size` changes by design (lets HPA / autoscalers manage runtime
  scaling without diff).

### Known issues / TODO

See README.md → "TODO" section.
