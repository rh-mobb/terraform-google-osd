#!/bin/bash
# Create WIF config in OCM. Requires env vars: WIF_CONFIG_NAME, GCP_PROJECT

set -e

# Validate required environment variables
for VAR in WIF_CONFIG_NAME GCP_PROJECT; do
    if [[ -z "${!VAR}" ]]; then
        echo "ERROR: Required environment variable $VAR is not set."
        exit 1
    fi
done

# Check for OCM installation
if ! command -v ocm &> /dev/null; then
    echo "ERROR: ocm CLI is not installed. Please install it first."
    exit 1
fi

# Check if WIF already exists - this script should only run on create
if ocm gcp describe wif-config "${WIF_CONFIG_NAME}" &>/dev/null; then
    echo "ERROR: WIF config ${WIF_CONFIG_NAME} already exists."
    echo "This create script should only run when the config does not exist."
    echo "If re-running terraform apply, the WIF may have been created outside terraform."
    echo "Consider: ocm gcp delete wif-config ${WIF_CONFIG_NAME} (then re-apply), or import the resource."
    exit 1
fi

echo "Creating WIF config ${WIF_CONFIG_NAME}..."
ocm gcp create wif-config --name "${WIF_CONFIG_NAME}" --project "${GCP_PROJECT}"

# Newly-created wif-configs can take some time before they are valid
# Poll verify for up to 5 minutes
echo "Waiting for WIF config to become ready (polling verify for up to 5 minutes)..."
MAX_ATTEMPTS=10
ATTEMPT=0
VERIFY_OUTPUT=""
VERIFY_EXIT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    if VERIFY_OUTPUT=$(ocm gcp verify wif-config "${WIF_CONFIG_NAME}" 2>&1); then
        echo ""
        echo "WIF config ${WIF_CONFIG_NAME} is ready!"
        exit 0
    fi
    VERIFY_EXIT=$?
    echo "[$(date '+%H:%M:%S')] Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: Verify not ready yet (exit ${VERIFY_EXIT})"
    [ $ATTEMPT -lt $MAX_ATTEMPTS ] && sleep 30
done

echo ""
echo "ERROR: WIF config ${WIF_CONFIG_NAME} did not become ready after ${MAX_ATTEMPTS} attempts"
echo "Last verify output (exit ${VERIFY_EXIT}):"
echo "---"
echo "$VERIFY_OUTPUT"
echo "---"
exit 1
