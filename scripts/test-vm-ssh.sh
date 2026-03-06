#!/bin/bash
# Test OpenShift Virtualization by creating a CentOS Stream 9 VM, injecting an SSH key,
# and verifying SSH connectivity via virtctl ssh.
#
# Requires: oc, virtctl, cluster with OpenShift Virtualization + centos-stream9 DataSource.
#
# Usage:
#   oc login <cluster-api-url>   # or ensure KUBECONFIG is set
#   ./scripts/test-vm-ssh.sh
#   ./scripts/test-vm-ssh.sh --keep-vm   # leave VM running and print virtctl command

set -e

KEEP_VM=false
[[ " ${*} " =~ " --keep-vm " ]] && KEEP_VM=true

VM_NAME="test-vm-ssh-$(date +%s)"
VM_NAMESPACE=""
SSH_KEY_DIR=""
CLEANUP_DONE=false

cleanup() {
    if [[ "${CLEANUP_DONE}" == "true" ]]; then
        return
    fi
    CLEANUP_DONE=true
    if [[ "${KEEP_VM}" == "true" ]]; then
        echo ""
        echo "VM left running. SSH key at: ${SSH_KEY_DIR}/id_ed25519"
        echo ""
        echo "virtctl ssh command:"
        echo "  virtctl ssh \"centos@vmi/${VM_NAME}\" -n ${VM_NAMESPACE} -i ${SSH_KEY_DIR}/id_ed25519 --local-ssh-opts=\"-o StrictHostKeyChecking=accept-new\""
        echo ""
        return
    fi
    echo ""
    echo "Cleaning up..."
    if [[ -n "${VM_NAMESPACE}" ]]; then
        oc delete namespace "${VM_NAMESPACE}" --wait=false --ignore-not-found=true 2>/dev/null || true
        echo "  Deleted namespace ${VM_NAMESPACE}"
    fi
    if [[ -n "${SSH_KEY_DIR}" && -d "${SSH_KEY_DIR}" ]]; then
        rm -rf "${SSH_KEY_DIR}"
        echo "  Removed temp SSH key directory"
    fi
}

trap cleanup EXIT

# Check for oc CLI and virtctl
if ! command -v oc &> /dev/null; then
    echo "ERROR: oc CLI is not installed. Please install it first."
    exit 1
fi
if ! command -v virtctl &> /dev/null; then
    echo "ERROR: virtctl is not installed. Install via: oc apply -f https://github.com/kubevirt/kubevirt/releases/latest/download/virtctl-<arch>"
    echo "  Or download virtctl from the OpenShift Console (Workloads -> Virtualization -> virtctl) for version compatibility."
    exit 1
fi

# Verify cluster access
if ! oc whoami &>/dev/null; then
    echo "ERROR: Not logged in to cluster. Run 'oc login' or set KUBECONFIG."
    exit 1
fi

# Create ephemeral SSH keypair
SSH_KEY_DIR=$(mktemp -d)
ssh-keygen -t ed25519 -f "${SSH_KEY_DIR}/id_ed25519" -N "" -C "test-vm-ssh"
echo "Generated ephemeral SSH keypair in ${SSH_KEY_DIR}"

# Read public key for cloud-init
SSH_PUBKEY=$(cat "${SSH_KEY_DIR}/id_ed25519.pub")

# Create test namespace
VM_NAMESPACE="test-vm-ssh-${RANDOM}"
echo ""
echo "Creating test namespace ${VM_NAMESPACE}..."
oc create namespace "${VM_NAMESPACE}"

# Apply VirtualMachine manifest with cloud-init injecting the SSH key
echo ""
echo "Creating VM ${VM_NAME} in ${VM_NAMESPACE}..."
oc apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${VM_NAME}
  namespace: ${VM_NAMESPACE}
  labels:
    kubevirt.io/dynamic-credentials-support: "true"
spec:
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: ${VM_NAME}
    spec:
      sourceRef:
        kind: DataSource
        name: centos-stream9
        namespace: openshift-virtualization-os-images
      storage:
        resources:
          requests:
            storage: 30Gi
  runStrategy: RerunOnFailure
  template:
    metadata:
      labels:
        kubevirt.io/domain: ${VM_NAME}
        kubevirt.io/size: small
        network.kubevirt.io/headlessService: headless
    spec:
      domain:
        cpu:
          cores: 1
          sockets: 1
          threads: 1
        devices:
          disks:
          - bootOrder: 1
            disk:
              bus: virtio
            name: rootdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - masquerade: {}
            model: virtio
            name: default
          rng: {}
        machine:
          type: pc-q35-rhel9.6.0
        memory:
          guest: 2Gi
      networks:
      - name: default
        pod: {}
      terminationGracePeriodSeconds: 180
      volumes:
      - dataVolume:
          name: ${VM_NAME}
        name: rootdisk
      - cloudInitNoCloud:
          userData: |
            #cloud-config
            user: centos
            ssh_authorized_keys:
              - "${SSH_PUBKEY}"
            chpasswd: { expire: False }
        name: cloudinitdisk
EOF

# Wait for VM Running + Ready (up to 5 minutes)
echo ""
echo "Waiting for VM to be Running and Ready (up to 5 minutes)..."
for i in $(seq 1 60); do
    STATUS=$(oc get vm "${VM_NAME}" -n "${VM_NAMESPACE}" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "")
    READY=$(oc get vm "${VM_NAME}" -n "${VM_NAMESPACE}" -o jsonpath='{.status.ready}' 2>/dev/null || echo "")
    if [[ "${STATUS}" == "Running" && "${READY}" == "true" ]]; then
        echo "VM is Running and Ready."
        break
    fi
    echo "[$(date '+%H:%M:%S')] Status: ${STATUS:-unknown}, Ready: ${READY:-false} (attempt $i/60)"
    sleep 5
done

STATUS=$(oc get vm "${VM_NAME}" -n "${VM_NAMESPACE}" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "")
READY=$(oc get vm "${VM_NAME}" -n "${VM_NAMESPACE}" -o jsonpath='{.status.ready}' 2>/dev/null || echo "")
if [[ "${STATUS}" != "Running" || "${READY}" != "true" ]]; then
    echo "ERROR: VM did not become Running/Ready in time. Status: ${STATUS}, Ready: ${READY}"
    oc get vm,vmi "${VM_NAME}" -n "${VM_NAMESPACE}" 2>/dev/null || true
    exit 1
fi

# Wait for guest agent (AgentConnected) - needed for virtctl ssh (up to 2 minutes)
echo ""
echo "Waiting for guest agent (AgentConnected) for virtctl ssh..."
for i in $(seq 1 24); do
    AGENT=$(oc get vmi "${VM_NAME}" -n "${VM_NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="AgentConnected")].status}' 2>/dev/null || echo "")
    if [[ "${AGENT}" == "True" ]]; then
        echo "Guest agent is connected."
        break
    fi
    echo "[$(date '+%H:%M:%S')] Waiting for AgentConnected... (attempt $i/24)"
    sleep 5
done

AGENT=$(oc get vmi "${VM_NAME}" -n "${VM_NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="AgentConnected")].status}' 2>/dev/null || echo "")
if [[ "${AGENT}" != "True" ]]; then
    echo "WARNING: Guest agent not connected yet. Attempting SSH anyway..."
fi

# SSH test via virtctl (use vmi/name format for KubeVirt 1.7+)
# Retry for up to 3 minutes - sshd may not be ready immediately after guest agent
echo ""
echo "Testing SSH connectivity via virtctl ssh (retrying up to 3 minutes)..."
SSH_OUTPUT=""
for i in $(seq 1 18); do
    if SSH_OUTPUT=$(virtctl ssh "centos@vmi/${VM_NAME}" -n "${VM_NAMESPACE}" -i "${SSH_KEY_DIR}/id_ed25519" --local-ssh-opts="-o StrictHostKeyChecking=accept-new" --command "hostname" 2>&1); then
        echo "SSH test succeeded. hostname: $(echo "${SSH_OUTPUT}" | tr -d '\n')"
        break
    fi
    if [[ $i -lt 18 ]]; then
        echo "[$(date '+%H:%M:%S')] SSH connection refused, retrying in 10s... (attempt $i/18)"
        sleep 10
    else
        echo "ERROR: SSH test failed after 3 minutes. Last output:"
        echo "${SSH_OUTPUT}"
        exit 1
    fi
done
echo ""
echo "======================================"
echo "VM SSH test passed successfully!"
echo "======================================"
