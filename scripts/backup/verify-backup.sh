#!/usr/bin/env bash
# Prove the backup by reading it back. Run after backup-to-nextcloud.sh upload and
# split-upload.sh have finished, before the laptop is wiped and before revoke.
#
# Why this exists as its own file: a WebDAV size is a row the client wrote, not a
# count of bytes that reached object storage. Three files once listed at exactly
# their local byte counts and returned 503 on GET. See docs/doctor-log.md,
# 2026-10-30. Size-only comparison is used for trees because WebDAV exposes no
# hashes; every file over 1 GiB is additionally read back at head/mid/tail.
set -uo pipefail

REMOTE="nc-travis"
DEST="${REMOTE}:laptop-backup-2026-10-29"
LOG=${VERIFY_LOG:-/home/travis/backup-logs/verify.log}
WIN=65536
BIG=1073741824
fail=0

say(){ printf '[%s] %s\n' "$(date -Is)" "$*" | tee -a "$LOG"; }
mkdir -p "$(dirname "$LOG")"

spot(){ # $1 remote:path, $2 local file or "" for readability only
  local rp="$1" lf="${2:-}" size off
  if ! timeout 300 rclone cat --offset 0 --count "$WIN" "$rp" 2>/dev/null > /tmp/v.r; then
    say "  UNREADABLE $(basename "$rp")"; return 1
  fi
  if [ -z "$lf" ]; then
    say "  readable $(basename "$rp") (staged copy gone, no local reference)"
    return 0
  fi
  size=$(stat -c%s "$lf")
  for off in 0 $((size / 2)) $((size - WIN)); do
    [ "$off" -lt 0 ] && off=0
    timeout 300 rclone cat --offset "$off" --count "$WIN" "$rp" 2>/dev/null > /tmp/v.r
    dd if="$lf" bs=1 skip="$off" count="$WIN" 2>/dev/null > /tmp/v.l
    cmp -s /tmp/v.r /tmp/v.l || { say "  MISMATCH $(basename "$rp") at offset $off"; return 1; }
  done
  say "  ok $(basename "$rp") head/mid/tail match $size B"
  return 0
}

tree(){ # $1 local dir, $2 remote subdir, rest: extra rclone flags
  local src="$1" sub="$2"; shift 2
  [ -e "$src" ] || { say "SKIP missing $src"; return 0; }
  say "CHECK tree $src -> $sub"
  rclone check "$src" "$DEST/$sub" --size-only --one-way \
    --transfers 16 --checkers 32 --log-file "$LOG" --log-level INFO "$@" \
    || { say "  MISMATCH tree $src"; fail=1; }
}

parts(){ # $1 local whole file, $2 remote parts dir
  local lsize rsize n first last
  [ -e "$1" ] || { say "SKIP missing $1"; return 0; }
  lsize=$(stat -c%s "$1")
  rsize=$(timeout 300 rclone size "$DEST/$2" --json 2>/dev/null | grep -o '"bytes":[0-9]*' | cut -d: -f2)
  n=$(timeout 120 rclone lsf "$DEST/$2" 2>/dev/null | wc -l)
  say "CHECK parts $2 objects=$n local=$lsize remote_sum=${rsize:-0}"
  [ "${rsize:-0}" = "$lsize" ] || { say "  PARTS SUM MISMATCH"; fail=1; return 0; }
  first=$(timeout 120 rclone lsf "$DEST/$2" 2>/dev/null | sort | head -1)
  last=$(timeout 120 rclone lsf "$DEST/$2" 2>/dev/null | sort | tail -1)
  for p in "$first" "$last"; do
    [ -n "$p" ] || continue
    timeout 300 rclone cat --offset 0 --count "$WIN" "$DEST/$2/$p" 2>/dev/null | wc -c \
      | grep -qx "$WIN" || { say "  UNREADABLE part $p"; fail=1; }
  done
  say "  parts readable, sum matches"
}

say "=========== VERIFY START ==========="

tree "$HOME/.ssh" 01-keys-state/ssh
tree "$HOME/.gnupg" 01-keys-state/gnupg
tree "$HOME/keep-mc" 01-keys-state/keep-mc
tree "$HOME/.local/share/gajim" 01-keys-state/gajim-data
tree "$HOME/.config/gajim" 01-keys-state/gajim-config
tree "$HOME/.config/opencode" 01-keys-state/opencode
tree "$HOME/kubernetes-gitops" 02-projects/kubernetes-gitops
tree "$HOME/Hyprland-Dots" 02-projects/Hyprland-Dots
tree "$HOME/canvas-demos" 02-projects/canvas-demos
tree "$HOME/docs" 02-projects/docs
tree "$HOME/Pictures" 03-pictures
tree "$HOME/Downloads" 04-downloads
tree "$HOME/Videos/Old videos" 07-old-videos
tree "$HOME/Documents/keep" 08-keep --exclude "June 5th.zip"
tree "$HOME/Documents/migration-project" 09-migration-project

for f in "$HOME/Documents/Coding.7z" "$HOME/Documents/2tbbackup.tar.zst"; do
  [ -e "$f" ] || { say "SKIP missing $f"; continue; }
  say "CHECK file $(basename "$f")"
  spot "$DEST/06-archives/$(basename "$f")" "$f" || fail=1
done

parts "$HOME/Documents/keep/June 5th.zip" "08-keep/June 5th.zip.parts"
parts "$HOME/Documents/Old Files.7z" "06-archives/Old Files.7z.parts"

for a in Projects.tar.zst Documents-small.tar.zst Documents-git.tar.zst; do
  case "$a" in Documents-*) d=05-documents ;; *) d=02-projects ;; esac
  say "CHECK archive $a"
  spot "$DEST/$d/$a" "" || fail=1
done

if [ $fail -eq 0 ]; then
  say "VERIFY RESULT: ALL CHECKS PASSED"
else
  say "VERIFY RESULT: FAILURES PRESENT - do not wipe the laptop, do not revoke the token"
fi
exit $fail
