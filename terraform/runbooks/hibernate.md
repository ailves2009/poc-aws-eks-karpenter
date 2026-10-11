# Runbook: deep sleep and wake-up

Puts the POC into its cheapest state and brings it back with one command. Everything that costs
money by the hour is destroyed; what stays is free or nearly free. On wake-up Terraform rebuilds
the platform and **Argo CD rebuilds every application from git** — nothing is restored by hand.

| | Running (approx., us-east-1) | Deep sleep |
|---|---|---|
| EKS control plane | ~$73/mo | — |
| NAT gateway (+ its public IPv4) | ~$36/mo + data | — |
| 2 × t4g.medium bootstrap nodes + EBS | ~$52/mo | — |
| Spot nodes (Karpenter) | ~$10–30/mo | — |
| ALB (+ public IPv4) | ~$24/mo | — |
| Bastion (t4g.small + EIP), if kept | ~$16/mo | — (destroyed too, optional) |
| S3 state bucket, KMS key of the state bucket, IAM | ~$1/mo | **~$1/mo** |

Wake-up takes about **30–40 minutes**, mostly the EKS control plane.

```bash
cd ~/Projects/gitlab/poc-aws-eks-karpenter/terraform
export AWS_PROFILE=ae-nyd-plt-init AWS_REGION=us-east-1
export KUBECONFIG=~/.kube/poc-plt-eks
U=non-prod/poc/us-east-1
```

## Deep sleep

Order matters: AWS resources created **by controllers inside the cluster** (the ALB by the LB
controller, spot instances by Karpenter) must be gone before Terraform destroys the cluster and
the VPC — otherwise they are orphaned and the VPC cannot be deleted (ENIs still attached).

```bash
# 1. Stop GitOps from recreating what we delete. The root has no finalizer and the
#    ApplicationSets preserve resources, so these deletions never cascade.
kubectl -n argocd delete application root
kubectl -n argocd delete applicationsets --all
kubectl -n argocd delete applications --all

# 2. Workloads → the LB controller deletes the ALB.
kubectl delete namespace demo-dev
until [ -z "$(aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'k8s-')].LoadBalancerName" --output text)" ]; do
  echo "waiting for the ALB to go..."; sleep 15; done

# 3. Karpenter nodes. Nothing is Pending any more, so Karpenter does not replace them.
kubectl delete nodeclaims --all --wait
kubectl get nodes                                  # only the 2 bootstrap nodes

# 4. Destroy the workload tier: argocd, aws-lb-controller, karpenter → eks → vpc (NAT, EIP).
terragrunt run --all destroy --working-dir $U/workload

# 5. Optional: the bastion (its OpenVPN PKI is regenerated on rebuild).
(cd $U/persistent/bastion && terragrunt destroy)
```

Leave `bootstrap/` alone: the CI/CD role, the boundary and the state bucket are needed to wake up.

### Check that nothing billable is left

```bash
aws eks list-clusters                                                            # []
aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value]' --output text
aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available --query 'NatGateways[].NatGatewayId'
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
aws ec2 describe-addresses --query 'Addresses[].[PublicIp,AssociationId]' --output text
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId'
```

Each of them should print nothing (or only what you deliberately kept, e.g. the bastion).

## Wake-up

```bash
terragrunt run --all apply --working-dir $U/workload      # vpc → eks → karpenter, lb-controller → argocd

aws eks update-kubeconfig --name poc-plt-eks --region us-east-1 --kubeconfig ~/.kube/poc-plt-eks
kubectl get nodes                                         # 2 bootstrap nodes Ready
kubectl -n argocd get applications -w                     # root → projects → metrics-server → demo-dev-*
kubectl get nodeclaims -w                                 # spot capacity for nginx
```

Argo CD comes back with a **new admin password** (`argocd-initial-admin-secret`) and the demo
with a **new ALB DNS name**.

### What changes on every rebuild

- **The EKS OIDC issuer.** IRSA roles of Karpenter and the LB controller are updated by
  Terraform in the same run (their trust policies are in `managed_role_names`).
- **The EKS secrets-encryption KMS key** is replaced; the old one waits out its deletion window.
- **The cluster endpoint and CA**: refresh the kubeconfig as above.

## If something is stuck

| Symptom | Cause | Fix |
|---|---|---|
| `vpc` destroy fails: `DependencyViolation` | an ENI/SG left by an ALB or a node | step 2/3 skipped: delete the leftover ALB / instance, re-run destroy |
| namespace `demo-dev` stays `Terminating` | the LB controller was destroyed before the Ingress | `kubectl patch ingress -n demo-dev nginx -p '{"metadata":{"finalizers":[]}}' --type=merge`, then delete the ALB by hand |
| `karpenter` destroy hangs | NodeClaims waiting for a terminated controller | step 3 first; otherwise terminate the instances tagged `karpenter.sh/nodepool` and remove the finalizers |
