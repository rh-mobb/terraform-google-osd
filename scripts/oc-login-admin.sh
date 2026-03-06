#!/bin/bash
# Log into the OSD cluster as admin using API URL and password.
#
# Usage:
#   export CLUSTER_NAME=pczarkow
#   export OSD_ADMIN_PASSWORD='your-password'
#   ./scripts/oc-login-admin.sh
#
# Or with API URL directly:
#   export API_URL=https://api.example.openshift.com:6443
#   export OSD_ADMIN_PASSWORD='your-password'
#   ./scripts/oc-login-admin.sh

set -e

ADMIN_USER="${ADMIN_USER:-admin}"
OSD_ADMIN_PASSWORD="${OSD_ADMIN_PASSWORD:-Passw0rd12345!}"

# Resolve API URL
if [[ -n "${API_URL}" ]]; then
  echo "Using API_URL from environment: ${API_URL}"
elif [[ -n "${CLUSTER_NAME}" ]]; then
  if ! command -v ocm &>/dev/null; then
    echo "ERROR: ocm CLI required to resolve API URL from CLUSTER_NAME. Install ocm or set API_URL directly."
    exit 1
  fi
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq required to parse cluster info. Install jq or set API_URL directly."
    exit 1
  fi
  CLUSTER_ID=$(ocm list clusters --no-headers --columns id,name 2>/dev/null | grep "${CLUSTER_NAME}" | awk '{print $1}' | head -1)
  if [[ -z "$CLUSTER_ID" ]]; then
    echo "ERROR: Cluster ${CLUSTER_NAME} not found. Run 'ocm login' and ensure cluster exists."
    exit 1
  fi
  API_URL=$(ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID 2>/dev/null | jq -r '.api.url')
  if [[ -z "$API_URL" || "$API_URL" == "null" ]]; then
    echo "ERROR: Could not get API URL for cluster ${CLUSTER_NAME}"
    exit 1
  fi
  echo "Resolved API URL from cluster ${CLUSTER_NAME}: ${API_URL}"
else
  echo "ERROR: Set API_URL or CLUSTER_NAME"
  exit 1
fi

if ! command -v oc &>/dev/null; then
  echo "ERROR: oc CLI is not installed."
  exit 1
fi

if ! command -v curl &>/dev/null; then
  echo "ERROR: curl is required to check API availability."
  exit 1
fi

# Phase 1: Wait for API to respond (accept any cert; API may have self-signed cert initially)
echo ""
echo "Waiting for API to respond (accepting any cert)..."
API_OK_ATTEMPTS=60
API_ATTEMPT=0
while [ $API_ATTEMPT -lt $API_OK_ATTEMPTS ]; do
  HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 10 -k "${API_URL}/healthz" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" =~ ^[2345][0-9][0-9]$ ]]; then
    echo "API is responding (HTTP ${HTTP_CODE})."
    break
  fi
  API_ATTEMPT=$((API_ATTEMPT + 1))
  echo "[$(date '+%H:%M:%S')] Attempt ${API_ATTEMPT}/${API_OK_ATTEMPTS}: API not ready, retrying in 10s..."
  sleep 10
done

if [ $API_ATTEMPT -ge $API_OK_ATTEMPTS ]; then
  echo "ERROR: API did not respond after ${API_OK_ATTEMPTS} attempts (10 minutes)."
  exit 1
fi

# Phase 2: Wait for API to present a valid (trusted) certificate (cluster replaces self-signed when ready)
echo ""
echo "Waiting for API to present valid TLS certificate..."
CERT_OK_ATTEMPTS=60
CERT_ATTEMPT=0
while [ $CERT_ATTEMPT -lt $CERT_OK_ATTEMPTS ]; do
  HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 10 "${API_URL}/healthz" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" =~ ^[2345][0-9][0-9]$ ]]; then
    echo "API has valid TLS certificate (HTTP ${HTTP_CODE})."
    break
  fi
  CERT_ATTEMPT=$((CERT_ATTEMPT + 1))
  echo "[$(date '+%H:%M:%S')] Attempt ${CERT_ATTEMPT}/${CERT_OK_ATTEMPTS}: Certificate not yet trusted, retrying in 10s..."
  sleep 10
done

if [ $CERT_ATTEMPT -ge $CERT_OK_ATTEMPTS ]; then
  echo "WARNING: API certificate not trusted after ${CERT_OK_ATTEMPTS} attempts. Proceeding with --insecure-skip-tls-verify."
  INSECURE_LOGIN="--insecure-skip-tls-verify"
else
  INSECURE_LOGIN=""
fi

# Phase 3: Log in; retry on 401 - htpasswd admin can take a while to propagate after cluster is ready.
echo ""
echo "Logging in as ${ADMIN_USER}..."
OC_ERR=$(mktemp)
LOGIN_MAX_ATTEMPTS=60
LOGIN_ATTEMPT=0

while true; do
  LOGIN_ATTEMPT=$((LOGIN_ATTEMPT + 1))
  if oc login "${API_URL}" -u "${ADMIN_USER}" -p "${OSD_ADMIN_PASSWORD}" ${INSECURE_LOGIN} 2>"${OC_ERR}"; then
    break
  fi

  if grep -qE 'certificate|unknown authority|tls.*verif' "${OC_ERR}" 2>/dev/null && [[ -z "$INSECURE_LOGIN" ]]; then
    echo "WARNING: TLS certificate not trusted by oc. Retrying with --insecure-skip-tls-verify..."
    INSECURE_LOGIN="--insecure-skip-tls-verify"
    continue
  fi

  if grep -qE '401|Unauthorized' "${OC_ERR}" 2>/dev/null; then
    if [ $LOGIN_ATTEMPT -ge $LOGIN_MAX_ATTEMPTS ]; then
      echo "ERROR: Login failed after ${LOGIN_MAX_ATTEMPTS} attempts (401 Unauthorized)."
      echo "Verify you have provided the correct credentials."
      cat "${OC_ERR}" >&2
      rm -f "${OC_ERR}"
      exit 1
    fi
    echo "[$(date '+%H:%M:%S')] Attempt ${LOGIN_ATTEMPT}/${LOGIN_MAX_ATTEMPTS}: 401 Unauthorized - htpasswd admin may not be ready yet. Retrying in 30s..."
    sleep 30
    continue
  fi

  cat "${OC_ERR}" >&2
  rm -f "${OC_ERR}"
  exit 1
done
rm -f "${OC_ERR}"

echo ""
echo "Logged in successfully."
oc whoami
