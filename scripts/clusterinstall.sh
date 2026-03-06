#!/bin/bash
# Create OSD cluster via OCM. Requires env vars: CLUSTER_NAME, OSD_VERSION, VPC_NAME, CONTROL_PLANE_SUBNET,
# COMPUTE_SUBNET, GCP_REGION, GCP_ZONE, GCP_PROJECT, GCP_SA_FILE_LOC, GCP_AUTHENTICATION_TYPE,
# WIF_CONFIG_NAME, OSD_GCP_PRIVATE, OSD_GCP_PSC, PSC_SUBNET_NAME

set -e

# OpenShift version (default from Terraform var osd_version)
OSD_VERSION="${OSD_VERSION:-4.21.3}"

# Validate required environment variables
REQUIRED_VARS="CLUSTER_NAME VPC_NAME CONTROL_PLANE_SUBNET COMPUTE_SUBNET GCP_REGION GCP_ZONE GCP_PROJECT GCP_AUTHENTICATION_TYPE WIF_CONFIG_NAME OSD_GCP_PRIVATE OSD_GCP_PSC"
for VAR in $REQUIRED_VARS; do
    if [[ -z "${!VAR}" ]]; then
        echo "ERROR: Required environment variable $VAR is not set."
        exit 1
    fi
done
if [[ "${GCP_AUTHENTICATION_TYPE}" == "service_account" ]] && [[ -z "${GCP_SA_FILE_LOC}" ]]; then
    echo "ERROR: GCP_SA_FILE_LOC is required when GCP_AUTHENTICATION_TYPE is service_account."
    exit 1
fi
if [[ "${OSD_GCP_PSC}" == "true" ]] && [[ -z "${PSC_SUBNET_NAME}" ]]; then
    echo "ERROR: PSC_SUBNET_NAME is required when OSD_GCP_PSC is true."
    exit 1
fi

# Check for OCM installation and version
if ! command -v ocm &> /dev/null; then
    echo "ERROR: ocm CLI is not installed. Please install it first."
    exit 1
fi

OCM_VERSION=$(ocm version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
REQUIRED_VERSION="0.1.73"  # minimum version for PSC support

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$OCM_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo "ERROR: OCM version $OCM_VERSION is too old. PSC requires at least $REQUIRED_VERSION"
    echo "Please upgrade: https://github.com/openshift-online/ocm-cli/releases"
    exit 1
fi

# Check for jq
jq > /dev/null 2>&1 || { echo "Please ensure jq is installed"; exit 1; }

# Check if cluster already exists - if installing/pending, resume monitoring; if ready, we're done
EXISTING_ITEMS=$(ocm get /api/clusters_mgmt/v1/clusters --parameter search="name like '${CLUSTER_NAME}%'" 2>/dev/null | jq -r '.items[]? | "\(.id)|\(.state)"' 2>/dev/null) || true
if [[ -n "$EXISTING_ITEMS" ]]; then
    # Take first match (exact name preferred for "pczarkow" vs "pczarkow2")
    CLUSTER_ID=$(echo "$EXISTING_ITEMS" | head -1 | cut -d'|' -f1)
    EXISTING_STATE=$(echo "$EXISTING_ITEMS" | head -1 | cut -d'|' -f2)
    if [[ "$EXISTING_STATE" == "ready" ]]; then
        echo "Cluster ${CLUSTER_NAME} already exists and is READY."
        API_URL=$(ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID | jq -r '.api.url')
        CONSOLE_URL=$(ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID | jq -r '.console.url')
        echo "API URL: $API_URL"
        echo "Console URL: $CONSOLE_URL"
        exit 0
    elif [[ "$EXISTING_STATE" == "error" ]]; then
        ERROR_MSG=$(ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID 2>/dev/null | jq -r '.status.provision_error_message // .status.description // "Unknown"' 2>/dev/null) || true
        echo "Cluster ${CLUSTER_NAME} exists in error state. Clean it up first or select a new name."
        [[ -n "$ERROR_MSG" ]] && echo "Error: $ERROR_MSG"
        exit 1
    elif [[ "$EXISTING_STATE" == "installing" || "$EXISTING_STATE" == "pending" ]]; then
        echo "Cluster ${CLUSTER_NAME} exists and is ${EXISTING_STATE}. Resuming monitoring..."
        # Skip to monitoring section below
    else
        echo "Cluster ${CLUSTER_NAME} exists with state '${EXISTING_STATE}'. Clean it up first or select a new name."
        exit 1
    fi
else
    CLUSTER_ID=""
fi

# Set authentication params
if [[ "${GCP_AUTHENTICATION_TYPE}" == "service_account" ]]; then
  if [[ ! -f "${GCP_SA_FILE_LOC}" ]]; then
    echo "ERROR: Service account file not found: ${GCP_SA_FILE_LOC}"
    exit 1
  fi
  authentication_param_name='--service-account-file'
  authentication_param_value="${GCP_SA_FILE_LOC}"
else
  authentication_param_name='--wif-config'
  authentication_param_value="${WIF_CONFIG_NAME}"
fi

# Set network configuration flags
network_flags=""
if [[ "${OSD_GCP_PRIVATE}" == "true" ]]; then
  network_flags="$network_flags --private"
fi

# PSC configuration
psc_flags=""
if [[ "${OSD_GCP_PSC}" == "true" ]]; then
  psc_flags="--psc-subnet ${PSC_SUBNET_NAME}"
fi

# Compute machine type (optional - empty means OCM default)
compute_machine_flags=""
if [[ -n "${COMPUTE_MACHINE_TYPE:-}" ]]; then
  compute_machine_flags="--compute-machine-type ${COMPUTE_MACHINE_TYPE}"
fi

# Create the cluster (skip if we already have CLUSTER_ID from existing installing cluster)
if [[ -z "$CLUSTER_ID" ]]; then
    echo ""
    echo "======================================"
    echo "Executing OCM cluster create command (copy to run manually for debugging):"
    echo "ocm create cluster --provider gcp --debug --version ${OSD_VERSION} --vpc-name ${VPC_NAME} --region ${GCP_REGION} --control-plane-subnet ${CONTROL_PLANE_SUBNET} --compute-subnet ${COMPUTE_SUBNET} --subscription-type marketplace-gcp --marketplace-gcp-terms ${authentication_param_name} ${authentication_param_value} ${network_flags} ${psc_flags} ${compute_machine_flags} --ccs ${CLUSTER_NAME}"
    echo "======================================"

    ocm create cluster --provider gcp \
        --debug \
        --version "${OSD_VERSION}" \
        --vpc-name "${VPC_NAME}" \
        --region "${GCP_REGION}" \
        --control-plane-subnet "${CONTROL_PLANE_SUBNET}" \
        --compute-subnet "${COMPUTE_SUBNET}" \
        --subscription-type marketplace-gcp \
        --marketplace-gcp-terms  \
        "${authentication_param_name}" "${authentication_param_value}" \
        ${network_flags} ${psc_flags} \
        ${compute_machine_flags} \
        --ccs \
        "${CLUSTER_NAME}"
    OCM_EXIT=$?
    if [ $OCM_EXIT -ne 0 ]; then
        echo "ERROR: ocm create cluster failed with exit code $OCM_EXIT"
        echo "Check the error above (e.g. 'no WIF configurations available' means run: ocm gcp create wif-config --name ${WIF_CONFIG_NAME} --project ${GCP_PROJECT})"
        exit $OCM_EXIT
    fi

    echo ""
    echo "======================================"
    echo "Cluster creation initiated!"
    echo "This typically takes 30-45 minutes"
    echo "======================================"

    # Get cluster ID
    sleep 5
    CLUSTER_ID=$(ocm list clusters --no-headers --columns id,name | grep "${CLUSTER_NAME}" | awk '{print $1}')

    if [ -z "$CLUSTER_ID" ]; then
        echo "WARNING: Could not immediately find cluster ID. Waiting..."
        sleep 30
        CLUSTER_ID=$(ocm list clusters --no-headers --columns id,name | grep "${CLUSTER_NAME}" | awk '{print $1}')
    fi
fi

if [ -z "$CLUSTER_ID" ]; then
    echo "ERROR: Could not find cluster ${CLUSTER_NAME}"
    exit 1
fi

echo "Cluster ID: $CLUSTER_ID"
echo "Monitoring installation progress..."

# Monitor installation (retry ocm/jq to tolerate transient API failures)
MAX_ATTEMPTS=45
ATTEMPT=0
OCM_RETRIES=3

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    # Fetch cluster state with retries - transient OCM API failures can abort the whole deploy
    STATE=""
    PROGRESS=""
    for retry in $(seq 1 $OCM_RETRIES); do
        CLUSTER_JSON=$(ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID 2>/dev/null) || true
        if [[ -n "$CLUSTER_JSON" ]]; then
            STATE=$(echo "$CLUSTER_JSON" | jq -r '.state // empty' 2>/dev/null) || true
            PROGRESS=$(echo "$CLUSTER_JSON" | jq -r '.status.description // "Installing"' 2>/dev/null) || true
            [[ -n "$STATE" ]] && break
        fi
        if [[ $retry -lt $OCM_RETRIES ]]; then
            echo "[$(date '+%H:%M:%S')] OCM API call failed (attempt $retry/$OCM_RETRIES), retrying in 30s..."
            sleep 30
        fi
    done

    if [[ -z "$STATE" ]]; then
        echo "ERROR: Failed to get cluster state after $OCM_RETRIES attempts. Check OCM connectivity."
        exit 1
    fi

    echo "[$(date '+%H:%M:%S')] State: $STATE | Progress: $PROGRESS"

    if [ "$STATE" == "ready" ]; then
        echo ""
        echo "======================================"
        echo "Cluster ${CLUSTER_NAME} is READY!"
        echo "======================================"
        API_URL=$(echo "$CLUSTER_JSON" | jq -r '.api.url')
        CONSOLE_URL=$(echo "$CLUSTER_JSON" | jq -r '.console.url')
        echo "API URL: $API_URL"
        echo "Console URL: $CONSOLE_URL"
        echo ""
        echo "For private clusters: Configure IdP at https://console.redhat.com before accessing"
        echo "Then access via bastion: gcloud compute ssh ${CLUSTER_NAME}-bastion-vm --zone=${GCP_ZONE}"
        exit 0
    elif [ "$STATE" == "error" ]; then
        echo "Cluster installation failed!"
        ERROR_MSG=$(echo "$CLUSTER_JSON" | jq -r '.status.provision_error_message // .status.description')
        echo "Error: $ERROR_MSG"
        exit 1
    fi

    sleep 120
    ATTEMPT=$((ATTEMPT+1))
done

echo "Timeout after 90 minutes. Check status at https://console.redhat.com"
exit 1
