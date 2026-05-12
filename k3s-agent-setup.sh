#!/bin/bash
set -e

NODE_IP="$1"
SERVER_IP="$2"
TOKEN="$3"

if [ -z "$NODE_IP" ] || [ -z "$SERVER_IP" ] || [ -z "$TOKEN" ]; then
  echo "Usage: $0 <node-ip> <server-ip> <token>"
  exit 1
fi

# Auto-detect interface that has the node IP
IFACE=$(ip -o -4 addr show | grep "$NODE_IP" | awk '{print $2}')

if [ -z "$IFACE" ]; then
  echo "ERROR: Could not find interface for IP $NODE_IP"
  ip -br a
  exit 1
fi

echo "=== Installing K3s agent on $NODE_IP using iface $IFACE ==="

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent \
  --server https://${SERVER_IP}:6443 \
  --token ${TOKEN} \
  --node-ip ${NODE_IP} \
  --node-external-ip ${NODE_IP} \
  --flannel-iface ${IFACE}" sh -

echo "=== K3s agent installed ==="
