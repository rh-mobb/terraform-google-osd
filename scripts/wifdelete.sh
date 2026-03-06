#!/bin/bash
# Delete WIF config from OCM. Requires env var: WIF_CONFIG_NAME

set -e

# Validate required environment variables
if [[ -z "${WIF_CONFIG_NAME}" ]]; then
    echo "ERROR: Required environment variable WIF_CONFIG_NAME is not set."
    exit 1
fi

# Check for OCM installation
if ! command -v ocm &> /dev/null; then
    echo "ERROR: ocm CLI is not installed. Please install it first."
    exit 1
fi

# If WIF config doesn't exist, consider it success (already deleted)
if ! ocm gcp describe wif-config "${WIF_CONFIG_NAME}" &>/dev/null; then
    echo "WIF config ${WIF_CONFIG_NAME} does not exist - skipping delete"
    exit 0
fi

ocm gcp delete wif-config "${WIF_CONFIG_NAME}"
