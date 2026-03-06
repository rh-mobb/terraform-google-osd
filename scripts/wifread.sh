#!/bin/bash
# Read WIF config from OCM for Terraform state. Requires env var: WIF_CONFIG_NAME
# Outputs JSON for shell_script provider to parse.

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

# Format colon-separated lines into a JSON object that the shell provider can read
ocm gcp describe wif-config "${WIF_CONFIG_NAME}" | jq -R --slurp 'split("\n") | map(select(length>0)) | map(split(":\\s+"; "")) | map({(.[0]): .[1]}) | reduce .[] as $item ({}; . * $item)'
