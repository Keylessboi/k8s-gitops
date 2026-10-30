#!/usr/bin/env bash
# Upload oversized single files as 8G parts (single PUT per part; the chunked
# /dav/uploads endpoint truncates bodies on this server).
# Restore: cat "NAME.part"* > NAME
set -uo pipefail
DEST_BASE="nc-travis:laptop-backup-2026-10-29"
WORK=/home/travis/.split-tmp
# Persistent on purpose: /tmp is a 9.7G tmpfs and the last reboot erased the log
# along with the evidence of which parts had actually committed.
LOG=${SPLIT_LOG:-/home/travis/backup-logs/split-upload.log}
PART=8G
WIN=65536
OPTS=(--webdav-nextcloud-chunk-size 64G --transfers 1 --retries 5
      --low-level-retries 10 --timeout 3600s --contimeout 60s
      --ignore-existing --stats 60s --stats-one-line --log-level INFO)
log(){ echo "[$(date -Is)] $*" | tee -a "$LOG"; }
mkdir -p "$WORK" "$(dirname "$LOG")"

# A WebDAV size is a row Nextcloud wrote, not a count of bytes that reached object
# storage: a PUT cut short leaves the row at the full declared size while the GET
# fails with 503 ServiceUnavailable ("file does seem to exist"). Compare a window
# at the head, the middle and the tail against the local source instead.
spotcheck(){ # $1=local file  $2=remote:path
  local lf="$1" rp="$2" size off
  size=$(stat -c%s "$lf")
  for off in 0 $((size/2)) $((size-WIN)); do
    [ "$off" -lt 0 ] && off=0
    timeout 300 rclone cat --offset "$off" --count "$WIN" "$rp" 2>/dev/null > /tmp/spot.r || return 1
    dd if="$lf" bs=1 skip="$off" count="$WIN" 2>/dev/null > /tmp/spot.l
    cmp -s /tmp/spot.r /tmp/spot.l || { log "  READBACK MISMATCH $(basename "$rp") @offset $off"; return 1; }
  done
  return 0
}

upload_split(){ # $1=src file  $2=dest dir
  local src="$1" dir="$2" base total name
  base=$(stat -c%s "$src"); name=$(basename "$src")
  log "SPLIT $name bytes=$base -> $DEST_BASE/$dir"
  rm -f "$WORK"/"$name".part* 2>/dev/null
  split -b "$PART" -d -a 3 "$src" "$WORK/$name.part" || { log "split FAILED $name"; return 1; }
  local rc=0 ok=0
  for p in "$WORK/$name".part*; do
    local pn psz got
    pn=$(basename "$p"); psz=$(stat -c%s "$p")
    rclone copyto "$p" "$DEST_BASE/$dir/$pn" "${OPTS[@]}" >>"$LOG" 2>&1 || { log "UPLOAD FAIL $pn"; rc=1; break; }
    got=$(rclone size "$DEST_BASE/$dir/$pn" --json 2>/dev/null | grep -o '"bytes":[0-9]*' | cut -d: -f2)
    if [ "${got:-0}" != "$psz" ]; then log "  SIZE MISMATCH $pn ${got:-0} != $psz"; rc=1; break; fi
    if ! spotcheck "$p" "$DEST_BASE/$dir/$pn"; then
      log "  HOLLOW $pn - deleting so the retry is not skipped by --ignore-existing"
      rclone deletefile "$DEST_BASE/$dir/$pn" >>"$LOG" 2>&1
      rc=1; break
    fi
    ok=$((ok+1)); log "  OK $pn $psz"; rm -f "$p"
  done
  log "DONE $name parts_ok=$ok total_parts=$(ls "$WORK/$name".part* 2>/dev/null | wc -l) rc=$rc"
  return $rc
}

upload_split "/home/travis/Documents/keep/June 5th.zip" "08-keep/June 5th.zip.parts"
upload_split "/home/travis/Documents/Old Files.7z"      "06-archives/Old Files.7z.parts"
log "ALL SPLIT UPLOADS FINISHED"
