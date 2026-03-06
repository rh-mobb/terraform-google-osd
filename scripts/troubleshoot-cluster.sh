#!/bin/bash
# Troubleshoot OSD cluster deployment. Run after a failed deploy to inspect cluster state.
# Usage: CLUSTER_NAME=pczarkow ./scripts/troubleshoot-cluster.sh
# Or: ./scripts/troubleshoot-cluster.sh pczarkow
set -e
CLUSTER_NAME="${1:-$CLUSTER_NAME}"
[[ -z "${CLUSTER_NAME}" ]] && { echo "Usage: CLUSTER_NAME=xxx $0  OR  $0 <cluster_name>"; exit 1; }

echo "=== OCM login status ==="
ocm whoami 2>/dev/null || echo "WARNING: ocm whoami failed - check OCM token"

echo ""
echo "=== Clusters matching '${CLUSTER_NAME}' ==="
ocm list clusters --no-headers 2>/dev/null | grep -i "${CLUSTER_NAME}" || echo "No clusters found"

echo ""
echo "=== Cluster details (API) ==="
CLUSTER_ID=$(ocm list clusters --no-headers --columns id,name 2>/dev/null | grep "${CLUSTER_NAME}" | awk '{print $1}' | head -1)
if [[ -z "${CLUSTER_ID}" ]]; then
    echo "Cluster not found. It may have failed to create or was never registered."
    exit 1
fi

echo "Cluster ID: ${CLUSTER_ID}"
ocm get "/api/clusters_mgmt/v1/clusters/${CLUSTER_ID}" | jq '{
  name,
  state,
  "status.state": .status.state,
  "status.description": .status.description,
  "status.provision_error_code": .status.provision_error_code,
  "status.provision_error_message": .status.provision_error_message,
  api: .api.url,
  console: .console.url
}'

echo ""
echo "=== Full status block ==="
ocm get "/api/clusters_mgmt/v1/clusters/${CLUSTER_ID}" 2>/dev/null | jq '.status'
