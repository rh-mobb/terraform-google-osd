#!/bin/bash
# Create OpenShift StorageClass for VM disk images using the Hyperdisk Balanced storage pool.
# Uses pd.csi.storage.gke.io provisioner. Run after cluster is up and hyperdisk pool exists.
#
# RWX multi-attach across zones is NOT supported - pool and nodes must be in same zone.
#
# Required env vars: STORAGE_POOL_PATH (full path, e.g. projects/my-project/zones/us-west1-a/storagePools/my-virt-pool)
#   Or: GCP_PROJECT, GCP_ZONE, STORAGE_POOL_NAME to construct the path.
#
# Usage:
#   export STORAGE_POOL_PATH="projects/my-project/zones/us-west1-a/storagePools/mycluster-virt-pool"
#   ./scripts/install-hyperdisk-storageclass.sh
#
# Or from Terraform output:
#   export STORAGE_POOL_PATH=$(terraform output -raw hyperdisk_pool_resource_path)
#   ./scripts/install-hyperdisk-storageclass.sh

set -e

STORAGE_CLASS_NAME="${STORAGE_CLASS_NAME:-hyperdisk-virt-sc}"

# Resolve storage pool path
if [[ -n "${STORAGE_POOL_PATH}" ]]; then
  POOL_PATH="${STORAGE_POOL_PATH}"
elif [[ -n "${GCP_PROJECT}" && -n "${GCP_ZONE}" && -n "${STORAGE_POOL_NAME}" ]]; then
  POOL_PATH="projects/${GCP_PROJECT}/zones/${GCP_ZONE}/storagePools/${STORAGE_POOL_NAME}"
else
  echo "ERROR: Set STORAGE_POOL_PATH, or (GCP_PROJECT, GCP_ZONE, STORAGE_POOL_NAME)"
  exit 1
fi

# Check for oc
if ! command -v oc &> /dev/null; then
  echo "ERROR: oc CLI is not installed."
  exit 1
fi

if ! oc whoami &>/dev/null; then
  echo "ERROR: Not logged in to cluster. Run 'oc login' or set KUBECONFIG."
  exit 1
fi

echo "Creating StorageClass ${STORAGE_CLASS_NAME} for OpenShift Virtualization VM disks..."
echo "Storage pool: ${POOL_PATH}"

oc apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${STORAGE_CLASS_NAME}
  annotations:
    description: "Hyperdisk Balanced for OpenShift Virtualization VM disk images"
    storageclass.kubernetes.io/is-default-class: "true"
    storageclass.kubevirt.io/is-default-virt-class: "true"
provisioner: pd.csi.storage.gke.io
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: hyperdisk-balanced
  storage-pools: ${POOL_PATH}
  provisioned-throughput-on-create: "250Mi"
  provisioned-iops-on-create: "7000"
EOF

# Remove default from standard-csi to avoid two defaults (per GCP KubeVirt storage docs)
if oc get storageclass standard-csi &>/dev/null; then
  oc annotate storageclass standard-csi storageclass.kubernetes.io/is-default-class- --overwrite 2>/dev/null || true
  echo "Removed default annotation from standard-csi."
fi

echo ""
echo "StorageClass ${STORAGE_CLASS_NAME} created and set as default."
oc get storageclass "${STORAGE_CLASS_NAME}"
