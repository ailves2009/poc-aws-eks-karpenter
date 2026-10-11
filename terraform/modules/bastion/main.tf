# /modules/bastion/main.tf

# POC: deployed into the account default VPC. For production, move to a dedicated
# platform VPC and add a peering / TGW attachment to the workload VPC so VPN
# clients can reach EKS worker nodes.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Amazon Linux 2023 standard, ARM64 — matches t4g.* instances.
# The pattern must NOT match "al2023-ami-minimal-*": the minimal image ships
# without amazon-ssm-agent and ec2-instance-connect (the first bastion was
# built from it, which is why SSM never registered).
data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "bastion" {
  name        = "bastion"
  description = "Bastion: SSH (22/tcp) and OpenVPN (1194/udp) from allowed CIDRs"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(var.tags, { Name = "bastion" })
}

resource "aws_security_group_rule" "ssh_in" {
  security_group_id = aws_security_group.bastion.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidrs
  description       = "SSH"
}

resource "aws_security_group_rule" "openvpn_in" {
  security_group_id = aws_security_group.bastion.id
  type              = "ingress"
  from_port         = 1194
  to_port           = 1194
  protocol          = "udp"
  cidr_blocks       = var.allowed_cidrs
  description       = "OpenVPN"
}

resource "aws_security_group_rule" "egress_all" {
  security_group_id = aws_security_group.bastion.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Egress all"
}

# IAM role for the EC2 instance — gives SSM Session Manager access as a
# fallback path when SSH/VPN are broken. No outbound ports required for SSM.
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name                 = "bastion-role"
  assume_role_policy   = data.aws_iam_policy_document.assume_ec2.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "bastion-profile"
  role = aws_iam_role.bastion.name
}

# Optional SSH key pair. Without it, SSH works only via EC2 Instance Connect
# (temporary keys pushed through the API) and the fallback is SSM.
resource "aws_key_pair" "bastion" {
  count = var.ssh_public_key != "" ? 1 : 0

  key_name   = "bastion"
  public_key = var.ssh_public_key
  tags       = var.tags
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023_arm.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = true
  # Changing the key pair replaces the instance (and regenerates the PKI).
  key_name  = try(aws_key_pair.bastion[0].key_name, null)
  user_data = file("${path.module}/cloud-init.sh")

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1          # no containers on the host
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = merge(var.tags, { Name = "bastion-openvpn" })

  lifecycle {
    # AMI updates would replace the instance and wipe OpenVPN PKI;
    # rebuild the bastion deliberately when needed.
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id
  tags     = merge(var.tags, { Name = "bastion-eip" })
}

# Route53 record — only if the zone for var.domain_name exists in this
# account. For setups where DNS is managed elsewhere, add a CNAME pointing
# at `aws_eip.bastion.public_ip` (output as `public_ip`) yourself.
data "aws_route53_zone" "this" {
  count        = var.create_dns_record ? 1 : 0
  name         = "${var.domain_name}."
  private_zone = false
}

resource "aws_route53_record" "bastion" {
  count   = var.create_dns_record ? 1 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = "${var.subdomain}.${var.domain_name}"
  type    = "A"
  ttl     = 60
  records = [aws_eip.bastion.public_ip]
}
