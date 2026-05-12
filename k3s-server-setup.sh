#!/bin/bash
set -e

NODE_IP="$1"

if [ -z "$NODE_IP" ]; then
  echo "Usage: $0 <node-ip>"
  exit 1
fi

# Auto-detect interface that holds NODE_IP
IFACE=$(ip -o -4 addr show | grep "$NODE_IP" | awk '{print $2}')

if [ -z "$IFACE" ]; then
  echo "ERROR: Could not find interface for IP $NODE_IP"
  ip -br a
  exit 1
fi

echo "=== Installing K3s server on $NODE_IP using iface $IFACE ==="

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --node-ip ${NODE_IP} \
  --node-external-ip ${NODE_IP} \
  --advertise-address ${NODE_IP} \
  --tls-san ${NODE_IP} \
  --flannel-iface ${IFACE} \
  --cluster-cidr 10.42.0.0/16 \
  --service-cidr 10.43.0.0/16 \
  --write-kubeconfig-mode 644" sh -

echo "=== K3s server installed ==="
sudo cat /var/lib/rancher/k3s/server/node-token
