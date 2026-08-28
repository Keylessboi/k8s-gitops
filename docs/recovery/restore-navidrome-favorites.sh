#!/usr/bin/env bash
# Restore Navidrome favourites (starred tracks + albums) from the pre-rebuild
# library into the current one.
#
# WHY THIS IS NOT A DATABASE COPY
# -------------------------------
# Navidrome assigns a fresh random id to every media_file and album on each
# scan; ids are not derived from the file path or its content. Verified on this
# cluster: none of the old starred item_ids exist in the new database. Copying
# the `annotation` table therefore restores nothing - every row would point at
# an id that does not exist. Matching has to happen on metadata instead.
#
# WHAT IT DOES
# ------------
# Reads the exports next to this script, normalises artist/album/title (case,
# punctuation and bracketed suffixes like "(Remastered)" removed), finds the
# matching rows in the live database, and writes `starred` annotations for
# them. It is idempotent: annotation has unique(user_id,item_id,item_type) and
# this uses INSERT ... ON CONFLICT, so re-running only adds what is newly
# matchable.
#
# RUN IT MORE THAN ONCE. At the time of writing only ~47% of the starred
# tracks had been re-downloaded; the rest cannot be matched until they exist.
# Re-run as the library fills and it will pick up the remainder.
#
# PREREQUISITE: a Navidrome user must exist. The database starts with zero
# users and annotations are keyed by user_id, so log in through Authentik once
# (that first login auto-creates you as admin) before running this.
set -euo pipefail

HOST="${HOST:-root@100.125.108.56}"
KEY="${KEY:-$HOME/.ssh/worker_key}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKS="$HERE/navidrome-starred-tracks.tsv"
ALBUMS="$HERE/navidrome-starred-albums.tsv"
DRY="${DRY_RUN:-0}"

ssh_k() { ssh -i "$KEY" -o StrictHostKeyChecking=no "$HOST" "$@"; }
nd() { ssh_k "pct exec 200 -- kubectl exec -n navidrome \$(pct exec 200 -- kubectl get pods -n navidrome --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}') -- $*"; }

echo "== checking for a Navidrome user =="
USER_ID="$(nd sqlite3 /data/navidrome.db "'select id from user order by created_at limit 1;'" | tr -d '\r\n')"
if [ -z "$USER_ID" ]; then
  echo "  no user exists yet."
  echo "  Log in at https://navidrome.sandstorm.chat once (Authentik SSO), then re-run."
  exit 1
fi
echo "  user id: ${USER_ID:0:8}..."

echo "== pulling the current library =="
nd sqlite3 -separator "'\t'" /data/navidrome.db \
  "'select id, artist, album, title from media_file;'" > /tmp/nd_tracks.tsv
nd sqlite3 -separator "'\t'" /data/navidrome.db \
  "'select id, album_artist, name from album;'" > /tmp/nd_albums.tsv
echo "  tracks: $(wc -l < /tmp/nd_tracks.tsv)   albums: $(wc -l < /tmp/nd_albums.tsv)"

echo "== matching =="
python3 - "$TRACKS" "$ALBUMS" "$USER_ID" <<'PY' > /tmp/nd_star.sql
import re, sys
tracks_f, albums_f, user_id = sys.argv[1], sys.argv[2], sys.argv[3]

def norm(s):
    s = (s or '').strip().strip('"').lower()
    s = re.sub(r'\(.*?\)|\[.*?\]', '', s)          # (Remastered), [Deluxe] ...
    return re.sub(r'[^a-z0-9]+', '', s)

# live library, indexed two ways so a wrong album tag does not lose the match
by_full, by_at = {}, {}
for line in open('/tmp/nd_tracks.tsv', encoding='utf-8', errors='replace'):
    p = line.rstrip('\n').split('\t')
    if len(p) >= 4:
        by_full.setdefault((norm(p[1]), norm(p[2]), norm(p[3])), p[0])
        by_at.setdefault((norm(p[1]), norm(p[3])), p[0])
alb = {}
for line in open('/tmp/nd_albums.tsv', encoding='utf-8', errors='replace'):
    p = line.rstrip('\n').split('\t')
    if len(p) >= 3:
        alb.setdefault((norm(p[1]), norm(p[2])), p[0])

def emit(item_id, kind):
    print("INSERT INTO annotation (user_id,item_id,item_type,starred,starred_at,play_count,rating) "
          f"VALUES ('{user_id}','{item_id}','{kind}',1,datetime('now'),0,0) "
          "ON CONFLICT(user_id,item_id,item_type) DO UPDATE SET starred=1, "
          "starred_at=COALESCE(annotation.starred_at, datetime('now'));")

t_hit = t_miss = 0
for line in open(tracks_f, encoding='utf-8', errors='replace'):
    p = line.rstrip('\n').split('\t')
    if len(p) < 3:
        continue
    k = (norm(p[0]), norm(p[1]), norm(p[2]))
    mid = by_full.get(k) or by_at.get((norm(p[0]), norm(p[2])))
    if mid:
        emit(mid, 'media_file'); t_hit += 1
    else:
        t_miss += 1

a_hit = a_miss = 0
for line in open(albums_f, encoding='utf-8', errors='replace'):
    p = line.rstrip('\n').split('\t')
    if len(p) < 2:
        continue
    mid = alb.get((norm(p[0]), norm(p[1])))
    if mid:
        emit(mid, 'album'); a_hit += 1
    else:
        a_miss += 1

print(f"-- tracks matched {t_hit}, not yet in library {t_miss}", file=sys.stderr)
print(f"-- albums matched {a_hit}, not yet in library {a_miss}", file=sys.stderr)
PY

echo "  statements: $(grep -c '^INSERT' /tmp/nd_star.sql || echo 0)"
if [ "$DRY" = "1" ]; then
  echo "  DRY_RUN=1, nothing applied."
  exit 0
fi

echo "== applying =="
scp -q -i "$KEY" -o StrictHostKeyChecking=no /tmp/nd_star.sql "$HOST:/tmp/nd_star.sql"
ssh_k 'pct exec 200 -- sh -c "cat > /tmp/nd_star.sql" < /tmp/nd_star.sql
NP=$(pct exec 200 -- kubectl get pods -n navidrome --field-selector=status.phase=Running -o jsonpath="{.items[0].metadata.name}")
pct exec 200 -- kubectl cp /tmp/nd_star.sql navidrome/$NP:/tmp/nd_star.sql
pct exec 200 -- kubectl exec -n navidrome $NP -- sh -c "sqlite3 /data/navidrome.db < /tmp/nd_star.sql"'

echo "== result =="
nd sqlite3 /data/navidrome.db \
  "'select item_type, count(*) from annotation where starred=1 group by item_type;'"
echo "Restart Navidrome (or wait for its next refresh) if the UI still shows the old counts."
