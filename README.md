> Series "Golden pipeline" - Each POC represents my vision of a modern enterprise platform, exploring a different platform engineering decision: what to standardise, what to automate, what to delegate to managed services, and where teams should retain control.

# Innovate Inc. — Platform POC

Cloud platform proposal and proof-of-concept for a Python/Flask + React + PostgreSQL SaaS that needs to scale from a few hundred users to millions.

## Layout

- [`architecture/`](architecture/) — **Architecture proposal**: AWS multi-account design, EKS + Karpenter compute, RDS → Aurora migration path, security/compliance posture, observability, cost optimization, and a 6-phase roadmap. Read this first.
- [`terraform/`](terraform/) — **POC implementation**: automated AWS EKS setup with Karpenter (multi-arch, Graviton + Spot), Pod Identity for VPC CNI, IRSA for in-cluster controllers, Argo CD bootstrap. See [terraform/README.md](terraform/README.md) for the deploy walkthrough, testing methodology, and end-user examples for running workloads on x86 / arm64.
- [`charts/`](charts/) — **Helm charts deployed by Argo CD**: `poc-lib` library chart + `demo-apps` umbrella, strict values schema and contract tests.

GitOps configuration lives in three companion repositories — [poc-eks-gitops-root](https://github.com/ailves2009/poc-eks-gitops-root) (what & where), [poc-eks-gitops-projects](https://github.com/ailves2009/poc-eks-gitops-projects) (who may do what) and [poc-eks-gitops-values](https://github.com/ailves2009/poc-eks-gitops-values) (with which parameters); see [terraform/README.md → GitOps with Argo CD](terraform/README.md#gitops-with-argo-cd).

Each directory is independently navigable from this root via the README inside it. License: MIT (see [LICENSE](LICENSE)).

## Related

[poc-aws-eks-auto](https://github.com/ailves2009/poc-aws-eks-auto) builds the same NGINX + HTTPS + node/pod autoscaling scenario on **Amazon EKS Auto Mode**, where AWS runs Karpenter, load balancing and Pod Identity for you. Read the two side by side to compare what you operate yourself here with what AWS runs for you there.
