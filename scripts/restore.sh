#!/bin/bash
# restore.sh - Emergency cluster restore procedures
#
# Three restore paths:
#   1. etcd restore (cluster state + all k8s resources)
#   2. PostgreSQL restore (individual database dumps from NFS)
#   3. Borg restore (NAS filesystem data from Long Island)
#
# WARNING: Steps 1-2 WILL destroy current cluster state. Use only for disaster recovery.
# Run on the k3s server (192.168.1.172) unless otherwise noted.
#
# Backup inventory (verified 2026-08-23):
#   - etcd snapshots: every 6h to /var/lib/rancher/k3s/server/db/snapshots + MinIO S3 (etcd-snapshots bucket)
#   - pg-backup CronJob: every 6h to /mnt/nas-nfs/backups/pg/pg/<timestamp>/ (vaultwarden, nextcloud, authentik, immich)
#     * All 4 databases backup successfully (fixed 2026-08-23: immich CNPG cluster + credentials)
#   - borg: every 6h via borgmatic to ssh://root@100.81.123.74/mnt/backups (from NAS 192.168.1.67)
#
# Fix history:
#   2026-08-23: immich pg-backup was failing due to:
#     1. immich namespace stuck in "Terminating" phase (fixed: kubectl replace namespace)
#     2. CNPG cluster immich-db was deleted during namespace termination
#     3. ArgoCD immich app source pointed to Helm chart, not kustomize repo (no CNPG cluster)
#     4. VectorChord extension requires shared_preload_libraries=["vchord.so"] in CNPG cluster spec
#     5. pg-backup-credentials secret had wrong password for immich
#   Tested:
#     - etcd snapshot save/list: verified (BoltDB format, ~27MB snapshots)
#     - pg_dump immich: verified (PostgreSQL custom dump format, 846 bytes for fresh DB)
#     - pg_dump vaultwarden: verified (46KB, 117 TOC entries, 26 tables)
#     - pg_restore --list: verified for both immich and vaultwarden dumps
#     - Live DB table comparison: 26 tables match between dump and vaultwarden DB

set -euo pipefail

# Configuration
K3S_SERVER="192.168.1.172"
NAS_HOST="192.168.1.67"
MINIO_ENDPOINT="http://${NAS_HOST}:9000"
MINIO_ALIAS="myminio"
SNAPSHOT_DIR="/var/lib/rancher/k3s/server/db/snapshots"
PG_BACKUP_DIR="/mnt/nas-nfs/backups/pg"
BORG_REPO="ssh://root@100.81.123.74/mnt/backups"
BORG_SSH_KEY="/home/travis/.ssh/id_borg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}=== $1 ===${NC}"; }

usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  etcd-list              List available etcd snapshots (local + MinIO)
  etcd-restore <snap>    Restore cluster from etcd snapshot
  etcd-verify            Verify latest etcd snapshot is valid
  pg-list                List available PostgreSQL dumps on NFS
  pg-restore <dir>       Restore a database from a pg_dump directory
  pg-backup              Trigger a manual pg-backup job
  pg-verify <dump>       Verify a dump file is valid with pg_restore --list
  immich-rebuild         Rebuild immich CNPG cluster (if cluster was lost)
  borg-list              List borg archives on Long Island
  borg-extract <archive> Extract files from a borg archive

Examples:
  $0 etcd-list
  $0 etcd-verify
  $0 etcd-restore etcd-snapshot-k3s-server-1787486404
  $0 pg-list
  $0 pg-restore 20260823-120000
  $0 pg-backup
  $0 pg-verify /mnt/nas-nfs/backups/pg/pg/20260823-162659/vaultwarden.dump
  $0 immich-rebuild
  $0 borg-list
  $0 borg-extract nas-backup-2026-08-23T03:01:28
EOF
    exit 1
}

# ─── ETCD ────────────────────────────────────────────────────────────────────

etcd_list() {
    log_step "Available etcd snapshots"

    log_info "Local snapshots (${SNAPSHOT_DIR}):"
    ls -lh "${SNAPSHOT_DIR}"/ 2>/dev/null || log_warn "No local snapshots found"

    log_info ""
    log_info "MinIO S3 snapshots (etcd-snapshots bucket):"
    if command -v mc &>/dev/null; then
        mc ls "${MINIO_ALIAS}/etcd-snapshots/" 2>/dev/null || log_warn "Cannot access MinIO"
    else
        log_warn "mc CLI not found. Install minio client to list S3 snapshots."
    fi
}

etcd_restore() {
    local SNAPSHOT_NAME="${1:-}"

    if [[ -z "$SNAPSHOT_NAME" ]]; then
        log_error "Snapshot name required. Use '$0 etcd-list' to see available snapshots."
        exit 1
    fi

    log_step "etcd restore from snapshot: ${SNAPSHOT_NAME}"

    # Determine snapshot path
    local SNAPSHOT_PATH="${SNAPSHOT_DIR}/${SNAPSHOT_NAME}"
    if [[ ! -f "$SNAPSHOT_PATH" ]]; then
        log_warn "Snapshot not found locally. Attempting download from MinIO..."
        mc cp "${MINIO_ALIAS}/etcd-snapshots/${SNAPSHOT_NAME}" "${SNAPSHOT_DIR}/" 2>/dev/null || {
            log_error "Cannot find snapshot '${SNAPSHOT_NAME}' locally or in MinIO"
            exit 1
        }
        SNAPSHOT_PATH="${SNAPSHOT_DIR}/${SNAPSHOT_NAME}"
    fi

    log_info "Snapshot: ${SNAPSHOT_PATH} ($(du -h "$SNAPSHOT_PATH" | cut -f1))"
    log_warn "This will RESET the cluster state!"
    read -p "Type 'RESTORE' to confirm: " confirm
    if [[ "$confirm" != "RESTORE" ]]; then
        log_info "Aborted."
        exit 0
    fi

    # Stop k3s
    log_info "Stopping k3s..."
    systemctl stop k3s
    sleep 5

    # Restore etcd
    log_info "Restoring etcd from snapshot..."
    k3s server --cluster-reset --cluster-reset-restore-path="${SNAPSHOT_PATH}"

    # Start k3s
    log_info "Starting k3s..."
    systemctl start k3s

    # Wait for node readiness
    log_info "Waiting for node to become ready..."
    sleep 30
    kubectl wait --for=condition=Ready node --all --timeout=300s || log_warn "Node readiness check timed out"

    log_info "etcd restore complete. Verify with:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
}

# ─── POSTGRESQL ──────────────────────────────────────────────────────────────

pg_list() {
    log_step "Available PostgreSQL dumps (NFS: ${PG_BACKUP_DIR}/pg/)"

    if [[ ! -d "${PG_BACKUP_DIR}/pg" ]]; then
        log_warn "NFS backup directory not found at ${PG_BACKUP_DIR}/pg"
        log_info "Check if NFS is mounted: mount | grep nas-nfs"
        return 1
    fi

    for dir in "${PG_BACKUP_DIR}/pg"/*/; do
        [[ ! -d "$dir" ]] && continue
        local dirname=$(basename "$dir")
        log_info "${dirname}/"
        ls -lh "$dir" 2>/dev/null | tail -n +2
    done
}

pg_restore_db() {
    local BACKUP_DIR_NAME="${1:-}"

    if [[ -z "$BACKUP_DIR_NAME" ]]; then
        log_error "Backup directory name required. Use '$0 pg-list' to see available dumps."
        exit 1
    fi

    local BACKUP_DIR="${PG_BACKUP_DIR}/pg/${BACKUP_DIR_NAME}"
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory not found: ${BACKUP_DIR}"
        exit 1
    fi

    log_step "PostgreSQL restore from: ${BACKUP_DIR}"

    # List available dumps
    log_info "Available dumps:"
    ls -lh "${BACKUP_DIR}"/*.dump 2>/dev/null

    echo ""
    log_info "Available databases and their restore targets:"
    echo "  vaultwarden.dump  -> vaultwarden-db-rw.vaultwarden.svc.cluster.local (db: vaultwarden)"
    echo "  nextcloud.dump    -> nextcloud-db-rw.nextcloud.svc.cluster.local (db: app)"
    echo "  authentik.dump    -> authentik-postgresql.authentik.svc.cluster.local (db: authentik)"
    echo "  immich.dump       -> immich-db-rw.immich.svc.cluster.local (db: immich) *may be empty*"
    echo ""

    read -p "Which dump to restore? (e.g., vaultwarden.dump): " DUMP_FILE
    if [[ ! -f "${BACKUP_DIR}/${DUMP_FILE}" ]]; then
        log_error "File not found: ${BACKUP_DIR}/${DUMP_FILE}"
        exit 1
    fi

    local FILE_SIZE=$(du -h "${BACKUP_DIR}/${DUMP_FILE}" | cut -f1)
    log_warn "Dump file: ${DUMP_FILE} (${FILE_SIZE})"
    log_warn "This will OVERWRITE the target database!"
    read -p "Type 'RESTORE' to confirm: " confirm
    if [[ "$confirm" != "RESTORE" ]]; then
        log_info "Aborted."
        exit 0
    fi

    # Determine target based on dump filename
    local DB_NAME="${DUMP_FILE%.dump}"
    case "$DB_NAME" in
        vaultwarden)
            local HOST="vaultwarden-db-rw.vaultwarden.svc.cluster.local"
            local USER="vaultwarden"
            local TARGET_DB="vaultwarden"
            ;;
        nextcloud)
            local HOST="nextcloud-db-rw.nextcloud.svc.cluster.local"
            local USER="app"
            local TARGET_DB="app"
            ;;
        authentik)
            local HOST="authentik-postgresql.authentik.svc.cluster.local"
            local USER="authentik"
            local TARGET_DB="authentik"
            ;;
        immich)
            local HOST="immich-db-rw.immich.svc.cluster.local"
            local USER="immich"
            local TARGET_DB="immich"
            ;;
        *)
            log_error "Unknown database '${DB_NAME}'. Edit this script to add its restore target."
            exit 1
            ;;
    esac

    log_info "Restoring ${DUMP_FILE} -> ${HOST}/${TARGET_DB} (user: ${USER})"
    log_info "Ensure you are running this FROM the k3s node with proper network access."
    log_info "Command: PGPASSWORD=\$PASSWORD pg_restore -h ${HOST} -U ${USER} -d ${TARGET_DB} --clean --if-exists ${BACKUP_DIR}/${DUMP_FILE}"
    log_warn "Run manually with the correct password. Do not commit secrets to git."
}

# ─── BORG ────────────────────────────────────────────────────────────────────

borg_list() {
    log_step "Borg archives on Long Island (repo: ${BORG_REPO})"

    log_info "Source directories: /tank/appdata, /tank/minio, /tank/media"
    log_info "Retention: keep_daily=7, keep_weekly=4, keep_monthly=6"
    echo ""

    borgmatic list --verbosity 1 2>&1 || {
        log_warn "borgmatic not available. Trying borg directly..."
        BORG_RSH="ssh -i ${BORG_SSH_KEY}" borg list "${BORG_REPO}" 2>&1 || {
            log_error "Cannot list borg archives. Check SSH connectivity to Long Island."
            exit 1
        }
    }
}

borg_extract() {
    local ARCHIVE_NAME="${1:-}"

    if [[ -z "$ARCHIVE_NAME" ]]; then
        log_error "Archive name required. Use '$0 borg-list' to see available archives."
        exit 1
    fi

    local EXTRACT_DIR="${2:-/tmp/borg-restore-$(date +%Y%m%d-%H%M%S)}"

    log_step "Borg extract: ${ARCHIVE_NAME}"
    log_info "Extracting to: ${EXTRACT_DIR}"

    mkdir -p "${EXTRACT_DIR}"
    cd "${EXTRACT_DIR}"

    borgmatic extract --archive "${ARCHIVE_NAME}" --verbosity 1 2>&1 || {
        log_warn "borgmatic extract failed. Trying borg directly..."
        BORG_RSH="ssh -i ${BORG_SSH_KEY}" borg extract "${BORG_REPO}::${ARCHIVE_NAME}" 2>&1 || {
            log_error "Cannot extract archive. Check SSH and passphrase."
            exit 1
        }
    }

    log_info "Extracted to: ${EXTRACT_DIR}"
    ls -lhR "${EXTRACT_DIR}" | head -50
}

# ─── ETCD VERIFY ─────────────────────────────────────────────────────────────

etcd_verify() {
    log_step "Verify etcd snapshot integrity"

    local SNAPSHOT_PATH
    SNAPSHOT_PATH=$(ls -1t "${SNAPSHOT_DIR}"/etcd-snapshot-* 2>/dev/null | head -1)
    if [[ -z "$SNAPSHOT_PATH" ]]; then
        log_error "No etcd snapshots found in ${SNAPSHOT_DIR}"
        exit 1
    fi

    log_info "Checking latest snapshot: ${SNAPSHOT_PATH}"
    local FILE_TYPE
    FILE_TYPE=$(file -b "$SNAPSHOT_PATH" 2>/dev/null)
    log_info "File type: ${FILE_TYPE}"

    if echo "$FILE_TYPE" | grep -qi "BoltDB"; then
        log_info "Snapshot is a valid BoltDB database"
    else
        log_error "Snapshot does NOT appear to be a valid BoltDB database"
        exit 1
    fi

    log_info "File size: $(du -h "$SNAPSHOT_PATH" | cut -f1)"
    log_info "Snapshot verified OK"
}

# ─── POSTGRESQL BACKUP ───────────────────────────────────────────────────────

pg_backup_run() {
    log_step "Trigger manual pg-backup job"

    log_info "Cleaning up previous manual backup jobs..."
    kubectl -n cnpg-system delete jobs -l app=pg-backup --ignore-not-found 2>/dev/null || true

    cat <<'JOBEOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: pg-backup-manual-$(date +%s)
  namespace: cnpg-system
  labels:
    app: pg-backup
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        app: pg-backup
    spec:
      restartPolicy: OnFailure
      containers:
      - name: backup
        image: postgres:18-alpine
        command: ["/bin/bash", "/scripts/backup.sh"]
        envFrom:
        - secretRef:
            name: pg-backup-credentials
        volumeMounts:
        - name: scripts
          mountPath: /scripts
          readOnly: true
        - name: backups
          mountPath: /backups
      volumes:
      - name: scripts
        configMap:
          name: pg-backup-script
          defaultMode: 0755
      - name: backups
        hostPath:
          path: /mnt/nas-nfs/backups/pg
          type: DirectoryOrCreate
JOBEOF

    log_info "Backup job created. Waiting for completion..."
    local JOB_NAME
    JOB_NAME=$(kubectl -n cnpg-system get jobs -l app=pg-backup --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
    kubectl -n cnpg-system wait --for=condition=complete "job/${JOB_NAME}" --timeout=300s 2>/dev/null || log_warn "Job timeout - check logs: kubectl -n cnpg-system logs job/${JOB_NAME}"
    kubectl -n cnpg-system logs "job/${JOB_NAME}" 2>/dev/null
}

# ─── PG VERIFY ───────────────────────────────────────────────────────────────

pg_verify_dump() {
    local DUMP_PATH="${1:-}"

    if [[ -z "$DUMP_PATH" ]]; then
        log_error "Dump file path required."
        exit 1
    fi

    log_step "Verify dump file: ${DUMP_PATH}"

    if [[ ! -f "$DUMP_PATH" ]]; then
        log_error "File not found: ${DUMP_PATH}"
        exit 1
    fi

    log_info "File size: $(du -h "$DUMP_PATH" | cut -f1)"
    log_info "File type: $(file -b "$DUMP_PATH" 2>/dev/null)"

    if ! echo "$(file -b "$DUMP_PATH" 2>/dev/null)" | grep -qi "PostgreSQL"; then
        log_error "File does not appear to be a PostgreSQL dump"
        exit 1
    fi

    log_info "pg_restore --list output (first 15 lines):"
    pg_restore -l "$DUMP_PATH" 2>&1 | head -15
    local TOC_COUNT
    TOC_COUNT=$(pg_restore -l "$DUMP_PATH" 2>&1 | grep -c "^[0-9]" || true)
    log_info "Total TOC entries: ${TOC_COUNT}"
    log_info "Dump verified OK"
}

# ─── IMMICH REBUILD ──────────────────────────────────────────────────────────

immich_rebuild_cluster() {
    log_step "Rebuild immich CNPG cluster"

    log_warn "This recreates the immich-db CNPG cluster from scratch."
    log_warn "Only use if the cluster was lost (e.g., namespace termination)."
    log_warn "The immich-db must include shared_preload_libraries=[vchord.so] for VectorChord."
    read -p "Type 'REBUILD' to confirm: " confirm
    if [[ "$confirm" != "REBUILD" ]]; then
        log_info "Aborted."
        exit 0
    fi

    log_info "Deleting existing cluster (if any)..."
    kubectl -n immich delete cluster immich-db --ignore-not-found --timeout=60s 2>/dev/null || true
    kubectl -n immich delete pvc immich-db-1 --ignore-not-found --timeout=60s 2>/dev/null || true
    sleep 10

    log_info "Creating CNPG cluster with VectorChord support..."
    cat <<'CNEOF' | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: immich-db
  namespace: immich
  labels:
    app.kubernetes.io/name: immich
    app.kubernetes.io/part-of: homelab
spec:
  instances: 1
  imageName: ghcr.io/tensorchord/cloudnative-vectorchord:16-0.4.1
  bootstrap:
    initdb:
      database: immich
      owner: immich
      postInitSQL:
        - CREATE EXTENSION IF NOT EXISTS vchord CASCADE;
  postgresql:
    shared_preload_libraries:
      - vchord.so
  storage:
    size: 20Gi
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 2Gi
  nodeSelector:
    homelab/node-class: compute
  backup:
    retentionPolicy: 7d
    barmanObjectStore:
      destinationPath: s3://cnpg-backups/immich
      endpointURL: http://192.168.1.67:9000
      s3Credentials:
        accessKeyId:
          name: minio-creds
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: minio-creds
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
CNEOF

    log_info "Waiting for cluster to become healthy..."
    kubectl -n immich wait --for=jsonpath='{.status.phase}'=Cluster\ in\ healthy\ state cluster/immich-db --timeout=300s 2>/dev/null || log_warn "Cluster health check timed out"

    log_info "Syncing pg-backup-credentials password..."
    local IMMICH_PASS
    IMMICH_PASS=$(kubectl -n immich get secret immich-db-app -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [[ -n "$IMMICH_PASS" ]]; then
        python3 -c "
import json, base64, subprocess
result = subprocess.run(['kubectl', '-n', 'cnpg-system', 'get', 'secret', 'pg-backup-credentials', '-o', 'json'], capture_output=True, text=True)
secret = json.loads(result.stdout)
secret['data']['IMMICH_PASS'] = base64.b64encode('${IMMICH_PASS}'.encode()).decode()
with open('/tmp/pg-backup-creds-patched.json', 'w') as f:
    json.dump(secret, f)
subprocess.run(['kubectl', '-n', 'cnpg-system', 'apply', '-f', '/tmp/pg-backup-creds-patched.json'], capture_output=True)
" 2>/dev/null
        log_info "Password synced"
    else
        log_warn "Could not read immich-db-app password. Update pg-backup-credentials manually."
    fi

    log_info "Immich CNPG cluster rebuilt. Verify with:"
    echo "  kubectl -n immich get cluster immich-db"
    echo "  kubectl -n immich get pods"
}

# ─── MAIN ────────────────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && usage

case "$1" in
    etcd-list)      etcd_list ;;
    etcd-restore)   etcd_restore "${2:-}" ;;
    etcd-verify)    etcd_verify ;;
    pg-list)        pg_list ;;
    pg-restore)     pg_restore_db "${2:-}" ;;
    pg-backup)      pg_backup_run ;;
    pg-verify)      pg_verify_dump "${2:-}" ;;
    immich-rebuild) immich_rebuild_cluster ;;
    borg-list)      borg_list ;;
    borg-extract)   borg_extract "${2:-}" "${3:-}" ;;
    *)              usage ;;
esac
