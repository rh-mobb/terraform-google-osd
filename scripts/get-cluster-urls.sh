#!/bin/bash
# Output JSON with api_url and console_url from OCM for the given cluster.
# Used by Terraform external data source. Requires: ocm, jq.
# Reads cluster_name from stdin (JSON query from Terraform).
set -e
CLUSTER_NAME=$(jq -r '.cluster_name // empty' 2>/dev/null || true)
[[ -z "${CLUSTER_NAME}" ]] && echo '{"api_url":"","console_url":""}' && exit 0
CLUSTER_ID=$(ocm list clusters --no-headers --columns id,name 2>/dev/null | grep "${CLUSTER_NAME}" | awk '{print $1}' | head -1)
if [[ -z "${CLUSTER_ID}" ]]; then
  echo '{"api_url":"","console_url":""}'
  exit 0
fi
ocm get "/api/clusters_mgmt/v1/clusters/${CLUSTER_ID}" 2>/dev/null | jq -c '{api_url: (.api.url // ""), console_url: (.console.url // "")}' 2>/dev/null || echo '{"api_url":"","console_url":""}'
