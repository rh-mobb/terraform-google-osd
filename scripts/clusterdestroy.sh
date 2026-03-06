#!/bin/bash
# Delete OSD cluster via OCM. Requires env var: CLUSTER_NAME

set -e

# Validate required environment variables
if [[ -z "${CLUSTER_NAME}" ]]; then
    echo "ERROR: Required environment variable CLUSTER_NAME is not set."
    exit 1
fi

# Check for OCM installation
if ! command -v ocm &> /dev/null; then
    echo "ERROR: ocm CLI is not installed. Please install it first."
    exit 1
fi

# Check for jq
jq > /dev/null 2>&1 || { echo "Please ensure jq is installed"; exit 1; }

# Get cluster ID(s) - handle case where no cluster exists
CLUSTER_IDS=$(ocm get /api/clusters_mgmt/v1/clusters --parameter search="name like '${CLUSTER_NAME}%'" 2>/dev/null | jq -r '.items[].id' || true)

if [ -z "$CLUSTER_IDS" ]; then
    echo "No cluster found matching '${CLUSTER_NAME}%' - nothing to delete"
    exit 0
fi

# Delete each matching cluster (typically just one)
for CLUSTER_ID in $CLUSTER_IDS; do
    echo "Deleting cluster $CLUSTER_ID..."
    ocm delete cluster "$CLUSTER_ID"
done

# Wait for cluster(s) to be fully removed before Terraform destroys subnets/WIF
echo ""
echo "Waiting for cluster(s) to be fully destroyed (up to 60 minutes)..."
for i in {1..180}; do
    REMAINING=$(ocm get /api/clusters_mgmt/v1/clusters --parameter search="name like '${CLUSTER_NAME}%'" 2>/dev/null | jq -r '.items | length' 2>/dev/null || echo "0")
    if [[ -z "${REMAINING}" || "${REMAINING}" -eq 0 ]]; then
        echo ""
        echo "Cluster(s) matching '${CLUSTER_NAME}' have been fully destroyed."
        echo "Waiting 3 minutes for GCP to release disks (e.g. from Hyperdisk storage pool)..."
        sleep 180
        exit 0
    fi
    echo "[$(date '+%H:%M:%S')] Waiting for cluster removal... (attempt $i/180, ${REMAINING} cluster(s) still present)"
    sleep 20
done

echo "ERROR: Cluster(s) did not finish destroying within 60 minutes."
ocm get /api/clusters_mgmt/v1/clusters --parameter search="name like '${CLUSTER_NAME}%'" 2>/dev/null | jq -r '.items[] | "\(.id) \(.name) \(.status.state)"' 2>/dev/null || true
exit 1
