# Runbook: Argo CD + GitOps (0.3.0)

Installs Argo CD on the running POC, publishes the three GitOps repositories and hands
metrics-server and the nginx demo over from Terraform to Argo CD. Background:
[README → GitOps with Argo CD](../README.md#gitops-with-argo-cd). Downtime of the demo is
acceptable; metrics-server is adopted in place (a rolling update to chart 3.14.0, no downtime).

```bash
cd ~/Projects/gitlab/poc-aws-eks-karpenter
export AWS_PROFILE=ae-nyd-plt-init AWS_REGION=us-east-1
export KUBECONFIG=~/.kube/poc-plt-eks          # no spaces around "="
U=terraform/non-prod/poc/us-east-1
kubectl get nodes                              # cluster awake, 2 bootstrap nodes Ready
```

## 1. Hand the Helm releases over (before Argo CD exists)

Terraform must forget the two `helm_release`s without uninstalling them, while their unit
directories still exist.

```bash
# metrics-server: keep it running; Argo CD adopts it (same release name, same selector labels).
(cd $U/workload/metrics-server && terragrunt state rm helm_release.this)
kubectl -n kube-system delete secret -l owner=helm,name=metrics-server   # Helm's release record only

# nginx demo (old namespace `demo`): replaced by demo-dev. Deleting the namespace deletes the
# Ingress, and the LB controller deletes its ALB.
(cd $U/workload/nginx && terragrunt state rm helm_release.this)
kubectl delete namespace demo
aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'k8s-demo')].LoadBalancerName"   # → []
```

## 2. Commit the main repository (branch `feat/argocd-gitops`)

```bash
git checkout feat/argocd-gitops

git add charts .github .gitignore
git commit -m "feat(charts): poc-lib library chart and demo-apps umbrella with contract tests"

git add terraform/modules/argocd terraform/non-prod/poc/us-east-1/workload/argocd
git commit -m "feat(argocd): install Argo CD and the root app-of-apps from Terraform"

git rm -r -q $U/workload/metrics-server $U/workload/nginx terraform/charts/nginx-demo
git commit -m "refactor: hand metrics-server and the nginx demo over to Argo CD"

git add README.md terraform/README.md terraform/CHANGES.md terraform/runbooks
git commit -m "docs: GitOps architecture, Argo CD and hibernate runbooks"

git push -u origin feat/argocd-gitops

# The chart version Argo CD renders (chart.revision in the values repo):
git tag demo-apps-v1.0.0
git push origin demo-apps-v1.0.0
```

## 3. Publish the three GitOps repositories (branch `master`)

```bash
cd ~/Projects/gitlab
for r in projects root values; do
  ( cd poc-eks-gitops-$r \
    && git init -q -b master \
    && git add -A \
    && git commit -q -m "feat: initial $r repository for the poc-plt-eks GitOps setup" \
    && gh repo create ailves2009/poc-eks-gitops-$r --public --source . --remote origin --push \
         --description "GitOps ($r) for github.com/ailves2009/poc-aws-eks-karpenter" )
done
```

The root and values CIs read each other's `master`. With the push order above (projects → root →
values) all three normally pass on the first run; if one ran before its sibling existed, re-run it:

```bash
for r in root values projects; do gh run list -R ailves2009/poc-eks-gitops-$r -L 1; done
gh run rerun <run-id> -R ailves2009/poc-eks-gitops-<repo> --failed
```

## 4. Install Argo CD

```bash
cd ~/Projects/gitlab/poc-aws-eks-karpenter/$U/workload/argocd
terragrunt init
terragrunt plan     # expect: helm_release.argocd + kubectl_manifest.root to add, nothing else
terragrunt apply
cd -
```

## 5. Verify

```bash
kubectl -n argocd get pods                                    # all Running on bootstrap nodes
kubectl -n argocd get appprojects                             # default, demo, infra-poc-plt-eks
kubectl -n argocd get applicationsets                         # infra-poc-plt-eks, workloads-poc-plt-eks
kubectl -n argocd get applications -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
                                                              # root, projects, infra-poc-plt-eks-metrics-server,
                                                              # demo-dev-nginx, demo-dev-keepwarm  → Synced/Healthy
# multi-source Applications show REVISION <none> in the default columns — their revisions are a list:
kubectl -n argocd get application demo-dev-nginx -o jsonpath='{.status.sync.revisions}{"\n"}'
kubectl -n demo-dev get deploy,svc,ingress,hpa
kubectl get nodeclaims -w                                     # Karpenter adds spot capacity for nginx
kubectl top pods -n demo-dev                                  # metrics-server works (adopted, rolled to 3.14.0)

# UI
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:80      # http://localhost:8080, user admin

# End to end through the new ALB (a new DNS name — the old ALB was deleted in step 1)
ALB=$(kubectl -n demo-dev get ingress nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
HOST=$(kubectl -n demo-dev get ingress nginx -o jsonpath='{.spec.rules[0].host}')
curl -sI --resolve "$HOST:80:$(dig +short "$ALB" | head -1)" "http://$HOST/" | head -3
```

## 6. Show the GitOps loop (optional, for the demo)

```bash
cd ~/Projects/gitlab/poc-eks-gitops-values
# a) Change: minReplicas 2 → 3, push, watch Argo CD apply it (~3 min, or Refresh in the UI)
sed -i '' 's/minReplicas: 2/minReplicas: 3/' workloads/dev/demo/nginx.yaml
git commit -am "demo: nginx minReplicas 3" && git push
kubectl -n demo-dev get hpa nginx -w

# b) Guardrail: a typo is refused by the chart schema — CI fails and, if pushed anyway,
#    the Application shows ComparisonError instead of deploying
#    (add `replica: 3` under applications.nginx and look at the CI run / the UI)

# c) Drift: a manual change is reverted by selfHeal
kubectl -n demo-dev scale deploy keepwarm --replicas=3 && sleep 20 && kubectl -n demo-dev get deploy keepwarm
```

## 7. Pull request

```bash
cd ~/Projects/gitlab/poc-aws-eks-karpenter
gh pr create -R ailves2009/poc-aws-eks-karpenter --base review-fixes --head feat/argocd-gitops \
  --title "Argo CD + GitOps: library chart, umbrella chart, three GitOps repositories" \
  --body "$(printf 'Phase 1 of GitOps. See terraform/CHANGES.md (0.3.0) and terraform/runbooks/gitops-argocd.md.\n\n'; git log --format='- %s' review-fixes..HEAD)"
```

When PR #1 (`review-fixes`) is merged with `--delete-branch`, GitHub retargets this PR to
`master` automatically.

## Rollback

```bash
(cd $U/workload/argocd && terragrunt destroy)     # Argo CD + root; workloads stay (no cascade)
kubectl delete namespace demo-dev
git revert <commits of this change>               # brings the metrics-server/nginx units back
(cd $U/workload/metrics-server && terragrunt apply)
```
