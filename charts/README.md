# charts

Helm charts deployed by Argo CD (see [`terraform/README.md` → GitOps](../terraform/README.md#gitops-with-argo-cd)).

| Chart | Type | Role |
|---|---|---|
| [`poc-lib`](poc-lib) | library | **How** a service renders: Deployment, Service, Ingress, HPA, ServiceAccount from `applications.<activeApp>` deep-merged over `common`. Renders nothing on its own. |
| [`demo-apps`](demo-apps) | application (umbrella) | **What** renders: the shape of each demo service in `values/<service>.yaml`, a strict `values.schema.json`, and one template line — `{{ include "poc-lib.app" . }}`. |

## One render = one service

Argo CD renders `demo-apps` once per service and passes `activeApp=<service>`. Without it the
render fails (`required` in the library and a `pattern` in the schema), so services never leak
into each other's Application.

Values layering for one Application (later wins):

1. `demo-apps/values.yaml` — shared shape (`common`: securityContext, default resources);
2. `demo-apps/values/<service>.yaml` — the service's shape (ports, probes, resources, volumes);
3. `poc-eks-gitops-values: workloads/<env>/<app>/_env.yaml` — the landscape;
4. `poc-eks-gitops-values: workloads/<env>/<app>/<service>.yaml` — image (by digest), replicas/HPA, ingress, placement;
5. `activeApp=<service>` — Helm parameter from the ApplicationSet.

Every layer is an ordinary values file, so `values.schema.json` validates all of them: an
unknown key (`replica:`), an image without a digest or `targetCPU: 500` fail the sync instead of
deploying something unintended.

## Adding a service

1. `demo-apps/values/<service>.yaml` here — shape only, no image.
2. `workloads/<env>/<app>/<service>.yaml` in `poc-eks-gitops-values` — `chart.path`,
   `chart.revision` (git tag of this repo) and the environment values.

No ApplicationSet change: the git files generator picks up the new file.

## Versions

Phase 1: `demo-apps` depends on `poc-lib` through `file://../poc-lib`, so both always come from
the same commit, and Argo CD renders a **git tag** of this repo (`demo-apps-vX.Y.Z`, set per
service in `chart.revision`). Phase 2 publishes `poc-lib` to GHCR (OCI) with release-please and
cosign — see the roadmap in `terraform/README.md`.

## Local render and tests

```bash
helm dependency build charts/demo-apps        # after every poc-lib edit: copies the library in
helm template nginx charts/demo-apps --set activeApp=nginx \
  -f charts/demo-apps/values/nginx.yaml \
  -f ../poc-eks-gitops-values/workloads/dev/demo/_env.yaml \
  -f ../poc-eks-gitops-values/workloads/dev/demo/nginx.yaml

python3 charts/tests/contract_test.py         # needs helm + PyYAML
```

CI ([`.github/workflows/charts.yaml`](../.github/workflows/charts.yaml)) runs the contract tests
and `kubeconform -strict` on every service render, with pinned tool versions.
