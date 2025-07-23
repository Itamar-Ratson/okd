# OKD Single-Node Installation on AWS

This guide explains how to install a single-node OKD (OpenShift Kubernetes Distribution) cluster on AWS using the openshift-installer.

## Prerequisites

### AWS Setup
- AWS CLI configured with credentials
- IAM user with sufficient permissions (EC2, VPC, IAM, Route53)
- Route53 hosted zone for your domain

### Domain and SSH
- A registered domain name managed by Route53
- SSH key pair for cluster access

### Verify Prerequisites
```bash
# Test AWS access
aws sts get-caller-identity
aws ec2 describe-regions --region eu-north-1

# Check Route53 hosted zone
aws route53 list-hosted-zones --query 'HostedZones[?Name==`yourdomain.com.`]'

# Verify SSH keys
ls ~/.ssh/*.pub
```

## Installation Steps

### 1. Download OKD Installer and CLI

```bash
# Set the OKD version (check latest at https://github.com/okd-project/okd/releases)
export OKD_VERSION="4.20.0-okd-scos.ec.8"

# Download binaries
wget https://github.com/okd-project/okd/releases/download/${OKD_VERSION}/openshift-install-linux-${OKD_VERSION}.tar.gz
wget https://github.com/okd-project/okd/releases/download/${OKD_VERSION}/openshift-client-linux-${OKD_VERSION}.tar.gz

# Extract and make executable
tar -xzf openshift-install-linux-${OKD_VERSION}.tar.gz*
tar -xzf openshift-client-linux-${OKD_VERSION}.tar.gz*
chmod +x openshift-install oc

# Verify installation
./openshift-install version
./oc version --client
```

### 2. Create Pull Secret

For testing, create a minimal pull secret:
```bash
echo '{"auths":{"fake":{"auth": "aWQ6cGFzcwo="}}}' > pull-secret.txt
```

For production, get a real pull secret from: https://console.redhat.com/openshift/install/pull-secret

### 3. Create install-config.yaml

```yaml
apiVersion: v1
baseDomain: yourdomain.com
compute:
- name: worker
  replicas: 0                    # Single-node: no separate workers
controlPlane:
  name: master
  replicas: 1                    # Single control plane node
  platform:
    aws:
      type: m5.2xlarge           # Larger instance for single-node
      zones:
      - eu-north-1a
metadata:
  name: okd
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: eu-north-1
pullSecret: |
  {"auths":{"fake":{"auth": "aWQ6cGFzcwo="}}}
sshKey: |
  ssh-ed25519 AAAAC4LabK2aBPL8KTE5ATVJAI... # Your SSH public key
```

Replace:
- `yourdomain.com` with your actual domain
- `eu-north-1` with your preferred AWS region
- SSH key with your actual public key (`cat ~/.ssh/id_ed25519.pub`)

### 4. Run Installation

```bash
# Backup config (it gets consumed during installation)
cp install-config.yaml install-config.yaml.backup

# Create installation directory and start
mkdir okd-install
cp install-config.yaml okd-install/
./openshift-install create cluster --dir=okd-install --log-level=info
```

Installation takes ~30-40 minutes. **Do not interrupt** the process.

### 5. Connect to Cluster

```bash
# Set kubeconfig
export KUBECONFIG=$(pwd)/okd-install/auth/kubeconfig

# Test connection
./oc get nodes

# Check cluster status
./oc get clusteroperators

# Get console URL and admin password
./oc whoami --show-console
cat okd-install/auth/kubeadmin-password
```

### 6. Access Web Console

1. Open the console URL from `oc whoami --show-console`
2. Login with:
   - Username: `kubeadmin`
   - Password: (from `kubeadmin-password` file)

## Configuration Details

### Single-Node Specifics
- `compute.replicas: 0` - No separate worker nodes
- `controlPlane.replicas: 1` - Control plane becomes schedulable
- `m5.2xlarge` instance - 8 vCPU, 32GB RAM minimum for single-node

### Network Configuration
- Creates VPC with public/private subnets
- Load balancer for API access
- Route53 DNS records for `api.okd.yourdomain.com` and `*.apps.okd.yourdomain.com`

## Troubleshooting

### Installation Fails
```bash
# Check installation logs
tail -50 okd-install/.openshift_install.log

# Clean up failed installation
./openshift-install destroy cluster --dir=okd-install --log-level=info
```

### Connection Issues
```bash
# Verify kubeconfig is set correctly
echo $KUBECONFIG
./oc config current-context

# Check if API endpoint resolves
nslookup api.okd.yourdomain.com

# Test API connectivity
curl -k --connect-timeout 10 https://api.okd.yourdomain.com:6443/version
```

### Wrong Cluster Context
If `oc` points to wrong cluster:
```bash
unset KUBECONFIG
export KUBECONFIG=$(pwd)/okd-install/auth/kubeconfig
```

## Cleanup

To destroy the cluster and all AWS resources:
```bash
./openshift-install destroy cluster --dir=okd-install --log-level=info
```

## Cost Considerations

Single-node OKD runs on:
- 1x m5.2xlarge EC2 instance (~$0.384/hour in eu-north-1)
- Load balancers (~$0.0225/hour each)
- EBS storage (~$0.10/GB/month)

Estimated cost: ~$12-15/day for testing

## Notes

- This creates a true single-node cluster where control plane and worker functions run on the same node
- Suitable for development, testing, and small workloads
- For production, consider multi-node setup with separate control plane and workers
- Keep installation files (`okd-install/` directory) - required for cluster destruction
