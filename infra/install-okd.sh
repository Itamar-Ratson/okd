#!/bin/bash
set -e

# Wait for network
sleep 30

# Download OKD installer
cd /home/core
wget -q https://github.com/okd-project/okd/releases/download/4.14.0-0.okd-2024-01-26-175629/openshift-install-linux-4.14.0-0.okd-2024-01-26-175629.tar.gz
tar -xf openshift-install-linux-*.tar.gz

# Download OC client
wget -q https://github.com/okd-project/okd/releases/download/4.14.0-0.okd-2024-01-26-175629/openshift-client-linux-4.14.0-0.okd-2024-01-26-175629.tar.gz
tar -xf openshift-client-linux-*.tar.gz
sudo mv oc kubectl /usr/local/bin/

# Create install directory
mkdir -p okd-install
cd okd-install

# Create install config
cat > install-config.yaml << 'EOF'
apiVersion: v1
baseDomain: nip.io
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 1
metadata:
  name: okd
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
bootstrapInPlace:
  installationDisk: /dev/xvda
pullSecret: '{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}'
sshKey: |
  ${ssh_key}
EOF

# Create ignition config
../openshift-install create single-node-ignition-config --dir .

# Install to disk
sudo coreos-installer install /dev/xvda \
  --ignition-file bootstrap-in-place-for-live-iso.ign \
  --insecure

# Schedule reboot
sudo shutdown -r +1
