# filepath: non-prod/us-east-1/region.hcl

# Set common variables for the region. This is automatically pulled in in the root root.hcl configuration to
# configure the remote state bucket and is accessible as inputs in child units.
locals {
  aws_region   = "us-east-1"
  cluster_name = "poc-plt-eks"
}
