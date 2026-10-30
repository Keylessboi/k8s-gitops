#!/usr/bin/env bash
# Laptop -> Nextcloud backup. Data-only (no OS/app runtime state).
# Usage: ./backup-to-nextcloud.sh upload|verify|revoke
set -uo pipefail

REMOTE="nc-travis"
DEST="${REMOTE}:laptop-backup-2026-10-29"
LOG="$HOME/nextcloud-backup.log"
UUID="93bf5393-663d-4d7d-956b-7339595dc4af"

RCLONE_OPTS=(
  --transfers 8
  --checkers 16
  --retries 5
  --low-level-retries 10
  --timeout 3600s
  --contimeout 60s
  --ignore-existing
  # The /dav/uploads/ chunking endpoint truncates chunk bodies here (cURL 26 -> S3 PutObject short read).
  # A chunk size larger than any file forces plain single PUTs, which verify byte-exact and run ~50% faster.
  --webdav-nextcloud-chunk-size 64G
  --stats 60s
  --stats-one-line
  --log-file "$LOG"
  --log-level INFO
  # Re-downloadable dependency/build trees: skip, they cost hours of small-file I/O.
  --exclude "June 5th.zip"
  --exclude "Old Files.7z"
  --exclude "**/node_modules/**"
  --exclude "/node_modules/**"
  --exclude "**/__pycache__/**"
  --exclude "/__pycache__/**"
  --exclude "**/.venv/**"
  --exclude "/.venv/**"
  --exclude "**/venv/**"
  --exclude "/venv/**"
  --exclude "**/.mypy_cache/**"
  --exclude "**/.pytest_cache/**"
  --exclude "**/.next/**"
  --exclude "**/.nuxt/**"
  --exclude "**/.turbo/**"
  --exclude "**/target/debug/**"
  --exclude "**/target/release/**"
)

say() { printf '[%s] %s\n' "$(date -Is)" "$*" | tee -a "$LOG"; }

up() { # up <source-path> <dest-subdir>
  local src="$1" sub="$2"
  if [ ! -e "$src" ]; then say "SKIP missing: $src"; return 0; fi
  say "BEGIN $src  ->  $DEST/$sub"
  rclone copy "$src" "$DEST/$sub" "${RCLONE_OPTS[@]}"
  local rc=$?
  say "END   $src  rc=$rc"
  return $rc
}

upload() {
  say "=========== BACKUP RUN START ==========="

  # 1. Irreplaceable small stuff: keys, chat, worlds, editor state
  up "$HOME/.ssh"                    "01-keys-state/ssh"
  up "$HOME/.gnupg"                  "01-keys-state/gnupg"
  up "$HOME/keep-mc"                 "01-keys-state/keep-mc"
  up "$HOME/.local/share/gajim"      "01-keys-state/gajim-data"
  up "$HOME/.config/gajim"           "01-keys-state/gajim-config"
  up "$HOME/.config/opencode"        "01-keys-state/opencode"
  up "$HOME/.config/rclone"          "01-keys-state/rclone"
  up "$HOME/.gitconfig"              "01-keys-state/misc"
  up "$HOME/.zshrc"                  "01-keys-state/misc"
  up "$HOME/.zprofile"               "01-keys-state/misc"
  up "$HOME/.ssh_history"            "01-keys-state/misc"
  up "$HOME/pw_snapshot_backup.json" "01-keys-state/misc"

  # 2. Code / projects (Projects is ~69k files -> archived, far faster than per-file WebDAV)
  up "/tmp/opencode/arch/Projects.tar.zst" "02-projects"
  up "$HOME/kubernetes-gitops"       "02-projects/kubernetes-gitops"
  up "$HOME/Hyprland-Dots"           "02-projects/Hyprland-Dots"
  up "$HOME/canvas-demos"            "02-projects/canvas-demos"
  up "$HOME/docs"                    "02-projects/docs"

  # 3. Photos
  up "$HOME/Pictures"                "03-pictures"

  # 4. Downloads
  up "$HOME/Downloads"               "04-downloads"

  # 5. Small Documents (archived: many tiny files are ruinous over WebDAV)
  up "/tmp/opencode/arch/Documents-small.tar.zst" "05-documents"
  up "/tmp/opencode/arch/Documents-git.tar.zst"   "05-documents"

  # 6. Archives
  # Old Files.7z -> split-upload.sh (8G parts); 31G single PUT duplicates work and lock-stalls
  up "$HOME/Documents/Coding.7z"         "06-archives"
  up "$HOME/Documents/2tbbackup.tar.zst" "06-archives"

  # 7. Old videos (verified-extracted copy; the .7z is redundant and skipped)
  up "$HOME/Videos/Old videos"       "07-old-videos"

  # 8. keep
  up "$HOME/Documents/keep"          "08-keep"

  # 9. migration-project (immich library, ~39k files)
  up "$HOME/Documents/migration-project" "09-migration-project"

  say "=========== BACKUP RUN FINISHED ==========="
  rclone size "$DEST" 2>&1 | tee -a "$LOG"
}

verify() {
  say "=========== VERIFY START ==========="
  local fail=0
  chk() {
    [ -e "$1" ] || return 0
    say "CHECK $1"
    rclone check "$1" "$DEST/$2" --size-only --one-way \
      --transfers 16 --checkers 32 --log-file "$LOG" --log-level INFO
    [ $? -eq 0 ] || { say "MISMATCH: $1"; fail=1; }
  }
  chk "$HOME/.ssh"            "01-keys-state/ssh"
  chk "$HOME/keep-mc"         "01-keys-state/keep-mc"
  chk "$HOME/.local/share/gajim" "01-keys-state/gajim-data"
  chk "$HOME/Pictures"        "03-pictures"
  chk "$HOME/Projects"        "02-projects/Projects"
  chk "$HOME/Downloads"       "04-downloads"
  # Old Files.7z verified by split-upload.sh (sum of 8G parts == 33414855783)
  chk "$HOME/Videos/Old videos" "07-old-videos"
  chk "$HOME/Documents/keep"  "08-keep"
  chk "$HOME/Documents/migration-project" "09-migration-project"
  if [ $fail -eq 0 ]; then say "VERIFY RESULT: ALL CHECKS PASSED"; else say "VERIFY RESULT: FAILURES PRESENT"; fi
  return $fail
}

revoke() {
  say "Revoking app password 'laptop-backup-2026-10-29'"
  local id
  id=$(kubectl -n nextcloud exec deploy/nextcloud -c nextcloud -- \
        php occ user:auth-tokens:list "$UUID" 2>/dev/null \
        | awk -F'|' '/laptop-backup-2026-10-29/ {gsub(/ /,"",$2); print $2}')
  if [ -z "$id" ]; then say "token not found"; return 1; fi
  kubectl -n nextcloud exec deploy/nextcloud -c nextcloud -- \
    php occ user:auth-tokens:delete "$UUID" "$id" 2>&1 | tee -a "$LOG"
  say "Revoked token id=$id"
  rclone config delete nc-travis 2>&1 | tee -a "$LOG"
  say "Local rclone remote 'nc-travis' removed"
}

case "${1:-upload}" in
  upload) upload ;;
  verify) verify ;;
  revoke) revoke ;;
  *) echo "usage: $0 upload|verify|revoke"; exit 2 ;;
esac
