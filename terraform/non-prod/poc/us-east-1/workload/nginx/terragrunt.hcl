# /non-prod/poc/us-east-1/workload/nginx/terragrunt.hcl
#
# Demo workload: official nginx (unprivileged) from the local chart
# terraform/charts/nginx-demo, HPA 2..10 replicas, ClusterIP behind an ALB
# Ingress, pinned to spot capacity. The `karpenter.sh/capacity-type=spot`
# nodeSelector guarantees the bootstrap node group can't host these pods →
# Karpenter must provision new node(s).

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region       = local.region_vars.locals.aws_region

  # Hostname clients use to reach the ALB. ALB matches Host header against
  # this value. POC has no real DNS in this account (see README), so the
  # standard test is `curl --resolve <hostname>:80:<ALB-IP> http://<hostname>/`.
  # Change account.hcl's `domain_name` to switch the suffix.
  hostname = "nginx.${local.account_vars.locals.domain_name}"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/helm-release"
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Ordering only: ensure Karpenter is up before any workload that asks for
# Karpenter-managed capacity.
dependency "karpenter" {
  config_path = "../karpenter"

  mock_outputs = {
    queue_name = "mock"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# HPA needs metrics-server's API to be available at scale time.
dependency "metrics_server" {
  config_path = "../metrics-server"

  mock_outputs = {
    status = "deployed"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# AWS Load Balancer Controller turns Ingress objects into ALBs.
dependency "aws_lb_controller" {
  config_path = "../aws-lb-controller"

  mock_outputs = {
    iam_role_arn = "arn:aws:iam::000000000000:role/mock-lb-controller"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name                       = dependency.eks.outputs.cluster_name
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  region                             = local.region

  name             = "nginx"
  namespace        = "demo"
  create_namespace = true

  # Local chart (repository = null). Image tags + digests live in the chart's
  # values.yaml. Bump `version` in Chart.yaml together with chart_version.
  chart         = "${get_repo_root()}/terraform/charts/nginx-demo"
  repository    = null
  chart_version = "1.0.0"

  values = {
    # Public-facing ALB on HTTP only — POC has no proper DNS delegation
    # for ACM cert validation, so HTTPS is deferred (see TODO in README).
    # ALB matches Host header = local.hostname; the user's external CNAME
    # `<hostname>` → ALB DNS provides the resolution.
    ingress = {
      enabled   = true
      hostname  = local.hostname
      className = "alb"

      annotations = {
        "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80}]"
        "alb.ingress.kubernetes.io/healthcheck-path" = "/"
      }
    }

    # Force Karpenter to provision the node — bootstrap NG nodes don't carry
    # the karpenter.sh/capacity-type label.
    nodeSelector = {
      "karpenter.sh/capacity-type" = "spot"
    }

    # Spread replicas across zones; Karpenter will provision multi-AZ.
    topologySpreadConstraints = [{
      maxSkew           = 1
      topologyKey       = "topology.kubernetes.io/zone"
      whenUnsatisfiable = "ScheduleAnyway"
      labelSelector = {
        matchLabels = {
          "app.kubernetes.io/name"     = "nginx"
          "app.kubernetes.io/instance" = "nginx"
        }
      }
    }]

    # 500m/1000m — sized so that scaling 2 → 10 replicas (5 vCPU total)
    # exceeds the capacity of the existing two spot nodes (~4 vCPU), which
    # forces Karpenter to provision additional nodes. This is the cascade we
    # want the demo to show.
    resources = {
      requests = {
        cpu    = "500m"
        memory = "128Mi"
      }
      limits = {
        cpu    = "1000m"
        memory = "256Mi"
      }
    }

    # HPA scales based on average CPU as a fraction of `requests.cpu`.
    # 50% target = 250m sustained per pod before scale-up.
    autoscaling = {
      enabled     = true
      minReplicas = 2
      maxReplicas = 10
      targetCPU   = 50
    }

    # ~1 RPS keep-warm loop against the nginx Service (see chart values).
    keepwarm = {
      enabled = true
    }
  }
}
