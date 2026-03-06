#!/bin/bash
# Install OpenShift Virtualization (Red Hat OpenShift, not OKD) - operator + HyperConverged CR.
# Run manually after the OSD cluster is ready. Requires: oc CLI, cluster-admin login.
#
# Uses redhat-operators (OpenShift) - NOT the community OKD operators.
#
# Usage:
#   oc login <cluster-api-url>   # or ensure KUBECONFIG is set
#   ./scripts/install-openshift-virt.sh

set -e

# Check for oc CLI and jq
if ! command -v oc &> /dev/null; then
    echo "ERROR: oc CLI is not installed. Please install it first."
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required for patching. Please install it first."
    exit 1
fi

# Verify cluster access
if ! oc whoami &>/dev/null; then
    echo "ERROR: Not logged in to cluster. Run 'oc login' or set KUBECONFIG."
    exit 1
fi

# Step 1: Install the operator (Namespace, OperatorGroup, Subscription) if not already present
if oc get subscription hco-operatorhub -n openshift-cnv &>/dev/null; then
    echo "Subscription hco-operatorhub already exists, skipping operator install."
else
    echo ""
    echo "======================================"
    echo "Installing OpenShift Virtualization operator..."
    echo "======================================"
    oc apply -f - <<'OPERATOR_EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
    - openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hco-operatorhub
  namespace: openshift-cnv
spec:
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  name: kubevirt-hyperconverged
  channel: "stable"
  installPlanApproval: Automatic
OPERATOR_EOF
fi

# Step 2: Wait for operator CSV to succeed
echo ""
echo "Waiting for operator to be ready (up to 10 minutes)..."
for i in {1..60}; do
    if oc get csv -n openshift-cnv -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q 'Succeeded'; then
        echo "Operator CSV is Succeeded."
        break
    fi
    echo "[$(date '+%H:%M:%S')] Waiting for CSV... (attempt $i/60)"
    sleep 10
done

if ! oc get csv -n openshift-cnv -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q 'Succeeded'; then
    echo "ERROR: Operator did not reach Succeeded phase in time."
    oc get csv -n openshift-cnv 2>/dev/null || true
    exit 1
fi

# Step 2b: Wait for HyperConverged CRD to be installed (operator installs CRDs; may lag behind CSV Succeeded)
echo ""
echo "Waiting for HyperConverged CRD to be installed..."
for i in {1..30}; do
    if oc get crd hyperconvergeds.hco.kubevirt.io &>/dev/null; then
        echo "HyperConverged CRD is installed."
        break
    fi
    echo "[$(date '+%H:%M:%S')] Waiting for CRD... (attempt $i/30)"
    sleep 10
done
if ! oc get crd hyperconvergeds.hco.kubevirt.io &>/dev/null; then
    echo "ERROR: HyperConverged CRD did not appear in time."
    oc get crd | grep -E 'kubevirt|hco' || true
    exit 1
fi

# Step 2c: Wait for webhook endpoints to be ready (avoids "no endpoints available" on CR creation)
echo ""
echo "Waiting for hco-webhook-service endpoints (up to 5 minutes)..."
for i in {1..30}; do
    EP_COUNT=$(oc get endpoints hco-webhook-service -n openshift-cnv -o jsonpath='{.subsets[*].addresses}' 2>/dev/null | jq -s 'add | length' 2>/dev/null)
    if [[ -n "${EP_COUNT}" && "${EP_COUNT}" -ge 1 ]]; then
        echo "Webhook service has ${EP_COUNT} endpoint(s) ready."
        break
    fi
    echo "[$(date '+%H:%M:%S')] Waiting for webhook endpoints... (attempt $i/30)"
    sleep 10
done
if ! oc get endpoints hco-webhook-service -n openshift-cnv -o jsonpath='{.subsets[*].addresses}' 2>/dev/null | jq -s 'add | length' 2>/dev/null | grep -qE '^[1-9]'; then
    echo "WARNING: Webhook endpoints not ready; CR creation may fail."
fi

# Step 3: Create HyperConverged CR if not already present
if oc get hco kubevirt-hyperconverged -n openshift-cnv &>/dev/null; then
    echo "HyperConverged kubevirt-hyperconverged already exists."
else
    echo ""
    echo "======================================"
    echo "Creating HyperConverged resource..."
    echo "======================================"
    for attempt in {1..6}; do
        if oc apply -f - <<'HCO_EOF'
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec: {}
HCO_EOF
        then
            break
        fi
        echo "[$(date '+%H:%M:%S')] HyperConverged creation failed (attempt $attempt/6), retrying in 15s..."
        sleep 15
    done
    if ! oc get hco kubevirt-hyperconverged -n openshift-cnv &>/dev/null; then
        echo "ERROR: Failed to create HyperConverged resource after retries."
        exit 1
    fi
fi

# Step 4: Patch dataImportCronTemplates to add accessModes: [ReadWriteOnce] to each storage
# Wait for HCO resource, then for status.dataImportCronTemplates with >= 5 items, then extract, add storage, patch into spec
echo ""
echo "Waiting for HyperConverged resource..."
for wait in {1..60}; do
    if oc get hco kubevirt-hyperconverged -n openshift-cnv &>/dev/null; then
        echo "HyperConverged resource exists."
        break
    fi
    echo "[$(date '+%H:%M:%S')] Waiting for HyperConverged... (attempt $wait/60)"
    sleep 10
done
if ! oc get hco kubevirt-hyperconverged -n openshift-cnv &>/dev/null; then
    echo "ERROR: HyperConverged resource not found after 10 minutes."
    exit 1
fi

echo ""
echo "Waiting for status.dataImportCronTemplates (at least 5 items)..."
for wait in {1..60}; do
    COUNT=$(oc get hco kubevirt-hyperconverged -n openshift-cnv -o json 2>/dev/null | jq '(.status.dataImportCronTemplates // []) | length' 2>/dev/null)
    if [[ -n "${COUNT}" && "${COUNT}" -ge 5 ]]; then
        echo "Found ${COUNT} dataImportCronTemplates in status."
        break
    fi
    echo "[$(date '+%H:%M:%S')] Waiting for dataImportCronTemplates... (${COUNT:-0}/5, attempt $wait/60)"
    sleep 10
done
COUNT=$(oc get hco kubevirt-hyperconverged -n openshift-cnv -o json 2>/dev/null | jq '(.status.dataImportCronTemplates // []) | length' 2>/dev/null)
if [[ -z "${COUNT}" || "${COUNT}" -lt 5 ]]; then
    echo "WARNING: Only ${COUNT:-0} dataImportCronTemplates in status (need 5). Patch skipped; Step 6 StorageProfile will apply RWO."
else
    echo ""
    echo "Patching HyperConverged spec.dataImportCronTemplates with storage.accessModes..."
    PATCH_JSON=$(oc get hco kubevirt-hyperconverged -n openshift-cnv -o json 2>/dev/null | jq -c '{
      spec: {
        dataImportCronTemplates: [
          (.status.dataImportCronTemplates // [])[] |
          .spec.template.spec.storage += {"accessModes": ["ReadWriteOnce"]} |
          del(.spec.template.status) |
          del(.status)
        ]
      }
    }' 2>/dev/null)
    if [[ -n "${PATCH_JSON}" && "${PATCH_JSON}" != '{"spec":{"dataImportCronTemplates":[]}}' ]]; then
        TEMPLATE_COUNT=$(echo "${PATCH_JSON}" | jq '.spec.dataImportCronTemplates | length' 2>/dev/null || echo "0")
        echo "Patching ${TEMPLATE_COUNT} dataImportCronTemplate(s)..."
        if oc patch hco kubevirt-hyperconverged -n openshift-cnv --type=merge -p="${PATCH_JSON}" 2>/dev/null; then
            echo "Applied accessModes patch (merge)."
        else
            echo "WARNING: Merge patch failed; Step 6 StorageProfile will apply RWO at CDI layer."
            oc patch hco kubevirt-hyperconverged -n openshift-cnv --type=merge -p="${PATCH_JSON}" 2>/dev/null || true
        fi
    else
        echo "WARNING: Could not build patch JSON."
    fi
fi

# Step 5: Wait for HyperConverged to be available
echo ""
echo "Waiting for OpenShift Virtualization to be ready (up to 15 minutes)..."
for i in {1..90}; do
    if oc get hco -n openshift-cnv kubevirt-hyperconverged -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q 'True'; then
        echo ""
        echo "======================================"
        echo "OpenShift Virtualization is ready!"
        echo "======================================"
        oc get pods -n openshift-cnv
        break
    fi
    echo "[$(date '+%H:%M:%S')] Waiting for HyperConverged... (attempt $i/90)"
    sleep 10
done

if ! oc get hco -n openshift-cnv kubevirt-hyperconverged -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q 'True'; then
    echo "ERROR: HyperConverged did not become Available in time."
    oc get hco -n openshift-cnv 2>/dev/null || true
    oc get pods -n openshift-cnv 2>/dev/null || true
    exit 1
fi

# Step 5b: Apply VolumeSnapshotClass with snapshot-type: images (4.21.x only; 4.22+ provisions it automatically)
# Enables unlimited restores per hour for golden images; see https://github.com/noamasu/docs/tree/main/gcp
OCP_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+' || echo "0.0")
if [[ "${OCP_VERSION}" == "4.21" ]] && ! oc get volumesnapshotclass csi-gce-pd-vsc-images &>/dev/null; then
    echo ""
    echo "Applying VolumeSnapshotClass csi-gce-pd-vsc-images (snapshot-type: images) for 4.21.x..."
    oc apply -f https://raw.githubusercontent.com/openshift/gcp-pd-csi-driver-operator/main/assets/volumesnapshotclass_images.yaml 2>/dev/null && echo "  VolumeSnapshotClass applied." || echo "  WARNING: Could not apply VolumeSnapshotClass (may already exist or network issue)."
fi

# Step 6: Patch StorageProfiles with accessModes [ReadWriteOnce]
# CDI uses StorageProfile claimPropertySets when DataVolumes omit accessModes.
# DataImportCron templates use 30Gi (above 4 GB minimum). For smaller PVCs, ensure >= 4Gi.
# See https://github.com/noamasu/docs/tree/main/gcp
echo ""
echo "Patching StorageProfiles with accessModes ReadWriteOnce..."
STORAGE_PROFILE_PATCH='{"spec":{"claimPropertySets":[{"accessModes":["ReadWriteOnce"],"volumeMode":"Filesystem"}]}}'
DEFAULT_SC=$(oc get storageclass -o json 2>/dev/null | jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true") | .metadata.name' | head -1)
for sc in ${DEFAULT_SC} hyperdisk-virt-sc; do
    [[ -z "${sc}" ]] && continue
    if oc get storageprofile "${sc}" &>/dev/null; then
        if oc patch storageprofile "${sc}" --type=merge -p="${STORAGE_PROFILE_PATCH}" 2>/dev/null; then
            echo "  Patched StorageProfile ${sc}"
        fi
    fi
done

exit 0
