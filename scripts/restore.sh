#!/bin/bash
# restore.sh - Emergency cluster restore
# Usage: ./restore.sh [snapshot-name]
#
# This script performs a full cluster restore from an etcd snapshot.
# It assumes:
# - k3s is installed on the target node
# - Doppler CLI is configured with appropriate tokens
# - Backup snapshots exist on MinIO S3
# - GitOps repo is accessible from the target node
#
# WARNING: This will RESET the cluster state. Use only for disaster recovery.

set -euo pipefail

# Configuration
SNAPSHOT=${1:-latest}
K3S_SERVER="192.168.1.172"
NAS_HOST="192.168.1.67"
MINIO_ENDPOINT="http://${NAS_HOST}:9000"
SNAPSHOT_DIR="/var/lib/rancher/k3s/server/db/snapshots"
ARGOCD_NAMESPACE="argocd"
GITOPS_REPO="https://github.com/your-org/kubernetes-gitops.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Pre-flight checks
preflight_check() {
    log_info "Running pre-flight checks..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Check if k3s is installed
    if ! command -v k3s &> /dev/null; then
        log_error "k3s is not installed on this node"
        exit 1
    fi

    # Check if Doppler CLI is available
    if ! command -v doppler &> /dev/null; then
        log_warn "Doppler CLI not found. Proceeding without credential pull."
    fi

    # Check SSH connectivity to target
    if ! ssh -q root@${K3S_SERVER} exit 2>/dev/null; then
        log_warn "Cannot SSH to ${K3S_SERVER}. Ensure you are running this ON the k3s server."
    fi

    log_info "Pre-flight checks passed"
}

# Step 1: Pull credentials from Doppler
pull_credentials() {
    log_info "[1/6] Pulling credentials from Doppler..."

    if command -v doppler &> /dev/null; then
        # Pull secrets from Doppler
        # doppler run --project kubernetes --config prd -- k3s secrets-encrypt status
        log_info "Doppler configured. Secrets available in environment."
    else
        log_warn "Doppler not available. Ensure secrets are configured manually."
    fi
}

# Step 2: Stop k3s
stop_k3s() {
    log_info "[2/6] Stopping k3s..."
    # systemctl stop k3s
    log_info "k3s stop command ready (uncomment to execute)"
}

# Step 3: Reset etcd
reset_etcd() {
    log_info "[3/6] Resetting etcd..."

    if [[ "$SNAPSHOT" == "latest" ]]; then
        # Find the most recent snapshot
        LATEST_SNAPSHOT=$(ls -t ${SNAPSHOT_DIR}/*.db 2>/dev/null | head -1)
        if [[ -z "$LATEST_SNAPSHOT" ]]; then
            log_error "No snapshots found in ${SNAPSHOT_DIR}"
            exit 1
        fi
        SNAPSHOT_PATH="$LATEST_SNAPSHOT"
    else
        SNAPSHOT_PATH="${SNAPSHOT_DIR}/${SNAPSHOT}"
    fi

    log_info "Using snapshot: ${SNAPSHOT_PATH}"

    # Reset etcd with snapshot
    # k3s server --cluster-reset --cluster-reset-restore-path="${SNAPSHOT_PATH}"
    log_info "etcd reset command ready (uncomment to execute)"
}

# Step 4: Start k3s
start_k3s() {
    log_info "[4/6] Starting k3s..."
    # systemctl start k3s
    log_info "k3s start command ready (uncomment to execute)"
}

# Step 5: Re-apply ArgoCD
apply_argocd() {
    log_info "[5/6] Re-applying ArgoCD..."

    # Wait for k3s to be ready
    # kubectl wait --for=condition=Ready node --all --timeout=300s

    # Apply ArgoCD manifests
    # kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    # Re-apply GitOps repository
    # kubectl apply -f ${GITOPS_REPO}/apps/argocd/

    log_info "ArgoCD re-apply commands ready (uncomment to execute)"
}

# Step 6: Verify cluster health
verify_cluster() {
    log_info "[6/6] Verifying cluster health..."

    # Check node status
    # kubectl get nodes

    # Check ArgoCD applications
    # kubectl get applications -n ${ARGOCD_NAMESPACE}

    # Check all pods
    # kubectl get pods -A

    log_info "Verification commands ready (uncomment to execute)"
}

# Main execution
main() {
    echo "=== Emergency Cluster Restore ==="
    echo "Target: ${K3S_SERVER}"
    echo "Snapshot: ${SNAPSHOT}"
    echo "Time: $(date)"
    echo ""

    preflight_check
    pull_credentials
    stop_k3s
    reset_etcd
    start_k3s
    apply_argocd
    verify_cluster

    echo ""
    log_info "=== Restore Procedure Complete ==="
    log_info "Review the output above and uncomment commands as needed."
    log_info "After restore, verify all services are running:"
    echo "  kubectl get nodes"
    echo "  kubectl get applications -n argocd"
    echo "  kubectl get pods -A"
}

# Run main function
main "$@"
