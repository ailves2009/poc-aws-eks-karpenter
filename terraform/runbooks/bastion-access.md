# Runbook: bastion access (SSH, SSM, OpenVPN)

Bastion: `persistent/bastion`, EC2 `bastion-openvpn` in the default VPC of
`us-east-1`, Elastic IP from the `public_ip` output.

> The private IP (`172.31.x.x`) is reachable only from inside the default VPC
> or through the VPN. From a laptop always use the **Elastic IP**.

All commands run from `terraform/non-prod/poc/us-east-1/persistent/bastion`:

```bash
export AWS_PROFILE=ae-nyd-plt-init AWS_REGION=us-east-1
IP=$(terragrunt output -raw public_ip)
ID=$(terragrunt output -raw instance_id)
```

## 0. One-time: rebuild on the standard AMI

The first bastion was built from `al2023-ami-minimal-*`, which has no
`amazon-ssm-agent` and no `ec2-instance-connect`, and it has no key pair. That
instance cannot be reached by SSH or SSM. The AMI filter is fixed now, but
`ami` is in `ignore_changes`, so the instance has to be replaced explicitly.
The Elastic IP is kept. The OpenVPN PKI is regenerated, so old `.ovpn`
files stop working.

```bash
# 1. Your current IP for SG rules 22/tcp + 1194/udp (never committed)
export BASTION_ALLOWED_CIDRS="$(curl -s https://checkip.amazonaws.com)/32"

# 2. Optional but recommended: a dedicated key pair
ssh-keygen -t ed25519 -C bastion-poc -f ~/.ssh/ae/5353-us-east-1-bastion
cp ~/.ssh/ae/5353-us-east-1-bastion.pub bastion.pub   # public key only

# 3. Replace the instance
terragrunt plan  -replace=aws_instance.bastion   # expect: instance replace, key pair create, EIP update in-place
terragrunt apply -replace=aws_instance.bastion
```

`bastion.pub` holds a public key, so committing it is safe. Commit it if more
than one machine runs this unit. If the file is missing on a later apply, the
key pair is removed and the instance is replaced again.

The first boot takes about 3 minutes (DH parameter generation). Check progress:

```bash
aws ec2 get-console-output --instance-id "$ID" --latest --query Output --output text | tail -20
```

## 1. SSH

```bash
ssh-keygen -R "$IP"     # host key changes after every rebuild
ssh -i ~/.ssh/ae/5353-us-east-1-bastion ec2-user@"$IP"
```

If the connection times out, your IP has changed. Re-export
`BASTION_ALLOWED_CIDRS` and run `terragrunt apply`. Only the SG rules are
updated.

The keys in `~/.ssh/ae/*.pem` belong to other accounts or regions. EC2 key
pairs are per account and per region, so none of them works here.

EC2 Instance Connect without a key pair is installed on the instance, but
neither the `terraform` user nor `cicd-deployment-role` has
`ec2-instance-connect:SendSSHPublicKey`. That is why the key pair is the
primary path.

## 2. SSM Session Manager (no open ports needed)

`ssm:StartSession` belongs to `cicd-deployment-role`, which the
`ae-nyd-plt-target` profile assumes:

```bash
AWS_PROFILE=ae-nyd-plt-target aws ssm describe-instance-information \
  --filters Key=InstanceIds,Values="$ID" --query 'InstanceInformationList[].PingStatus'   # → Online
AWS_PROFILE=ae-nyd-plt-target aws ssm start-session --target "$ID"
```

If the status is not `Online`, check the agent from an SSH session:
`sudo systemctl status amazon-ssm-agent` and
`sudo tail -50 /var/log/amazon/ssm/amazon-ssm-agent.log`.

## 3. OpenVPN client config

```bash
ssh -i ~/.ssh/ae/5353-us-east-1-bastion ec2-user@"$IP" sudo /usr/local/bin/get-ovpn-config > client.ovpn
# or through SSM:
AWS_PROFILE=ae-nyd-plt-target aws ssm start-session --target "$ID" \
  --document-name AWS-StartInteractiveCommand --parameters command="sudo /usr/local/bin/get-ovpn-config" > client.ovpn
```

With SSM, delete the `Starting session…` and `Exiting session…` lines from the
file. `*.ovpn` is gitignored. The file contains the client private key.
