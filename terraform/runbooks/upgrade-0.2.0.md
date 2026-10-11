# Runbook: upgrade an existing deployment to 0.2.0

Applies the 0.2.0 changes (see [CHANGES.md](../CHANGES.md)) to the already
deployed POC: Karpenter 1.2 → 1.15, EKS 1.32 → 1.37, nginx chart switch,
bootstrap state relocation. Downtime is acceptable. **Order matters.**

```bash
cd terraform
export AWS_PROFILE=ae-nyd-plt-init AWS_REGION=us-east-1
U=non-prod/poc/us-east-1

# Separate kubeconfig file; the exec section inherits AWS_PROFILE.
# The `terraform` user and cicd-deployment-role both have EKS access entries.
aws eks update-kubeconfig --name poc-plt-eks --region us-east-1 \
  --kubeconfig ~/.kube/poc-plt-eks
export KUBECONFIG=~/.kube/poc-plt-eks      # no spaces around "="
kubectl get nodes
```

## 1. Bootstrap: move local state out of `.terragrunt-cache`

The state file now lives next to each unit's `terragrunt.hcl` (gitignored).
Copy the newest existing file, the one with the highest `serial`:

```bash
for u in iam-state s3-state; do
  for f in $U/bootstrap/$u/.terragrunt-cache/*/*/terraform.tfstate; do
    echo "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["serial"])' "$f") $f"
  done | sort -n | tail -1
done
# copy each winner:
cp <newest iam-state file> $U/bootstrap/iam-state/terraform.tfstate
cp <newest s3-state file>  $U/bootstrap/s3-state/terraform.tfstate

(cd $U/bootstrap/iam-state && terragrunt init -reconfigure && terragrunt plan)
#   expect: iam-management policy update (managed_role_names), tags; NO replacements
(cd $U/bootstrap/iam-state && terragrunt apply)
(cd $U/bootstrap/s3-state  && terragrunt init -reconfigure && terragrunt plan)
#   expect: tags only → apply
```

Back up both `terraform.tfstate` files. They exist only on this machine.

## 2. Wake up a stopped cluster (only if it was stopped)

Signs that the cluster is stopped:

- `aws eks list-nodegroups --cluster-name poc-plt-eks` is empty.
- The only nodes are `NotReady` ("Kubelet stopped posting node status").
- karpenter, coredns and the LB controller pods are `Pending`.

Karpenter cannot start without the bootstrap node group, and the Helm
release in step 3 waits for it. Recreate the node group at the **current**
version first:

```bash
cd $U/workload/eks
terragrunt plan  -var cluster_version=1.32 -var 'addon_versions={}'   # expect: node group create + tags
terragrunt apply -var cluster_version=1.32 -var 'addon_versions={}'
kubectl get nodes                     # 2 bootstrap nodes Ready
kubectl -n kube-system get pods       # karpenter, coredns, LB controller Running
cd -
```

The old Karpenter node has no EC2 instance anymore. Once the controller runs,
it removes the node and its NodeClaim, and the stuck `Terminating` pods go
with it. If they are still there after ~10 min:
`kubectl delete nodeclaim --all`.

## 3. Karpenter: CRD adoption, provider swap, 1.15.0

```bash
# CRD names listed explicitly: zsh does not word-split an unquoted $VAR.
kubectl label crd nodepools.karpenter.sh nodeclaims.karpenter.sh ec2nodeclasses.karpenter.k8s.aws \
  app.kubernetes.io/managed-by=Helm --overwrite
kubectl annotate crd nodepools.karpenter.sh nodeclaims.karpenter.sh ec2nodeclasses.karpenter.k8s.aws \
  meta.helm.sh/release-name=karpenter-crd meta.helm.sh/release-namespace=kube-system --overwrite

cd $U/workload/karpenter
terragrunt init
terragrunt state replace-provider -auto-approve \
  registry.terraform.io/gavinbunney/kubectl registry.terraform.io/alekc/kubectl
terragrunt plan    # expect: controller IAM policy update, helm_release.karpenter_crd create,
                   #         helm_release.karpenter update, EC2NodeClass ami alias change
terragrunt apply

kubectl -n kube-system rollout status deploy/karpenter
kubectl -n kube-system logs deploy/karpenter | grep -iE 'error|denied' | tail
kubectl get nodepools,ec2nodeclasses,nodeclaims
cd -
```

The pinned AMI marks the existing Karpenter nodes as drifted, so they are
replaced one by one.

## 4. EKS: one minor version per apply (~15–25 min each)

EKS cannot skip minor versions. `addon_versions={}` lets the intermediate
steps use the newest addon builds for that version. The final apply pins
them.

```bash
cd $U/workload/eks
terragrunt apply -var cluster_version=1.33 -var 'addon_versions={}'
terragrunt apply -var cluster_version=1.34 -var 'addon_versions={}'
terragrunt apply -var cluster_version=1.35 -var 'addon_versions={}'
terragrunt apply -var cluster_version=1.36 -var 'addon_versions={}'
terragrunt apply                       # 1.37 + pinned addons
kubectl get nodes -o wide              # every node on v1.37
cd -
```

## 5. Remaining workload units

```bash
for u in vpc aws-lb-controller metrics-server nginx; do (cd $U/workload/$u && terragrunt apply); done
```

- Every unit shows tag updates (`default_tags`).
- `nginx`: Helm switches from the bitnami chart to `charts/nginx-demo` in
  place (same release name and selector labels). If the upgrade fails:
  `helm -n demo uninstall nginx`, then apply again. The ALB is recreated
  with a new DNS name.
- If the cluster was stopped by scaling `deploy/nginx` to 0, it stays at 0.
  With HPA enabled the chart does not set `replicas`, and an HPA does not
  scale up from 0. Bring it back and watch Karpenter add spot nodes:

  ```bash
  kubectl -n demo scale deploy/nginx --replicas=2
  kubectl get nodeclaims -w
  ```

## 6. Bastion (optional)

See [bastion-access.md](bastion-access.md): rebuild on the standard AMI,
SSH key, SSM.
