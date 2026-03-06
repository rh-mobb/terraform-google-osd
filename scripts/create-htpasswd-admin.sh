#!/bin/bash
# Create htpasswd IDP with admin user and add to cluster-admins group via OCM CLI.
# Run after cluster is ready. Uses cluster ID for ocm commands (resolved from CLUSTER_NAME if needed).
#
# Usage:
#   export CLUSTER_NAME=pczarkow
#   export OSD_ADMIN_PASSWORD='your-password'   # or use default
#   ./scripts/create-htpasswd-admin.sh
#
# Or with CLUSTER_ID directly:
#   export CLUSTER_ID=abc123xyz
#   export OSD_ADMIN_PASSWORD='your-password'
#   ./scripts/create-htpasswd-admin.sh

set -e

# Validate required env vars - need CLUSTER_ID or CLUSTER_NAME to resolve ID
if [[ -z "${CLUSTER_ID}" && -z "${CLUSTER_NAME}" ]]; then
  echo "ERROR: CLUSTER_ID or CLUSTER_NAME is required."
  exit 1
fi

# Default password if not set (matches Terraform default)
OSD_ADMIN_PASSWORD="${OSD_ADMIN_PASSWORD:-Passw0rd12345!}"
ADMIN_USER="${ADMIN_USER:-admin}"

# Check ocm
if ! command -v ocm &> /dev/null; then
  echo "ERROR: ocm CLI is not installed."
  exit 1
fi

if ! ocm whoami &>/dev/null; then
  echo "ERROR: Not logged in to OCM. Run 'ocm login'."
  exit 1
fi

# Resolve CLUSTER_ID if not provided
if [[ -z "${CLUSTER_ID}" ]]; then
  echo "Looking up cluster ID for ${CLUSTER_NAME}..."
  for i in {1..30}; do
    CLUSTER_ID=$(ocm list clusters --no-headers --columns id,name 2>/dev/null | grep "${CLUSTER_NAME}" | awk '{print $1}' | head -1)
    if [[ -n "${CLUSTER_ID}" ]]; then
      break
    fi
    echo "Cluster not found yet (attempt $i/30)..."
    sleep 10
  done
fi

if [[ -z "${CLUSTER_ID}" ]]; then
  echo "ERROR: Could not find cluster (CLUSTER_NAME=${CLUSTER_NAME:-<not set>})."
  exit 1
fi

echo "Using cluster ID: ${CLUSTER_ID}"

# Create htpasswd IDP with admin user (skip if already exists)
echo ""
if ocm list idps --cluster="${CLUSTER_ID}" 2>/dev/null | grep -q 'htpasswd'; then
  echo "htpasswd IDP already exists, skipping create."
else
  echo "Creating htpasswd IDP with user ${ADMIN_USER}..."
  ocm create idp --cluster="${CLUSTER_ID}" \
    --type=htpasswd \
    --name=htpasswd \
    --username="${ADMIN_USER}" \
    --password="${OSD_ADMIN_PASSWORD}"
fi

# Add admin to cluster-admins group (skip if already in group)
echo ""
if ocm list users --cluster="${CLUSTER_ID}" 2>/dev/null | grep -q "${ADMIN_USER}"; then
  echo "User ${ADMIN_USER} already configured, skipping add to cluster-admins."
else
  echo "Adding ${ADMIN_USER} to cluster-admins group..."
  ocm create user "${ADMIN_USER}" \
    --cluster="${CLUSTER_ID}" \
    --group=cluster-admins
fi

echo ""
echo "Done. User '${ADMIN_USER}' can log in with the provided password."
echo "Login: oc login <cluster-api-url> -u ${ADMIN_USER} -p '<password>'"
