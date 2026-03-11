#!/usr/bin/env bash
# Wait for all cluster nodes to be Ready.
# Called by Terraform null_resource after Cilium is installed.
# Usage: wait-for-nodes.sh <kubeconfig-path> <expected-node-count> <timeout-seconds>
set -euo pipefail

KUBECONFIG_PATH="$1"
EXPECTED_NODES="${2:-3}"
TIMEOUT="${3:-300}"

echo "Waiting for $EXPECTED_NODES nodes to be Ready (timeout: ${TIMEOUT}s)..."

start=$(date +%s)
while true; do
  ready_count=$(KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes --no-headers 2>/dev/null \
    | grep -c ' Ready' || echo "0")

  if [ "$ready_count" -ge "$EXPECTED_NODES" ]; then
    echo "All $ready_count/$EXPECTED_NODES nodes are Ready."
    exit 0
  fi

  elapsed=$(( $(date +%s) - start ))
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "ERROR: Timed out after ${TIMEOUT}s. Only $ready_count/$EXPECTED_NODES nodes Ready."
    KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes 2>/dev/null || true
    exit 1
  fi

  echo "  $ready_count/$EXPECTED_NODES Ready (${elapsed}s elapsed)..."
  sleep 10
done
