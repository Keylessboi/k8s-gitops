# Notifications

Everything that should reach a phone goes to **ntfy on travisbackupserver**,
via a **relay on the Proxmox host**. This document is mostly about why the
relay exists, because without that the setup looks like pointless indirection.

## The topology, and why it forces a relay

travisbackupserver is on `wlo1`, behind the room's WiFi router, on a
**separate `192.168.1.0/24`** — the same numbering as the cluster's LAN, a
different L2 segment. The cluster cannot route to it (`no route to host`), and
its own local subnet route shadows the tailnet route back. Verified in both
directions on 2026-09-03.

pve can reach both: it hosts LXC 200, and it reaches travisbackupserver over
Tailscale. So it relays.

```
  cluster ──192.168.1.153:9098──> homelab-ntfy-relay (pve)
                                        │
                                        └──tailscale──> ntfy (travisbackupserver:2586)
                                                          topics: homelab-alerts
                                                                  homelab-media
```

Subscribe a phone to **`http://100.81.123.74:2586`** (ntfy app → custom server)
on both topics. Nothing in this chain works until that is done — the messages
arrive and sit unread.

## The two services on pve, which are NOT the same thing

| Port | Unit | Job |
|---|---|---|
| `:9099` | `homelab-beat-receiver` | Dead man's switch. Alertmanager POSTs Watchdog every 5m; it touches a file. `homelab-beat-check.timer` alarms when that file goes stale. |
| `:9098` | `homelab-ntfy-relay` | General relay. Forwards real alerts to ntfy. |

They stay separate on purpose. 9099 must keep working when everything else is
broken, so it stays a 40-line stdlib file-toucher with no opinions. 9098 is
allowed to be cleverer because nothing depends on it to detect its own death.

Source for both is in `scripts/host/`; they are deployed to
`/usr/local/bin/` on pve with units in `/etc/systemd/system/`.

## What the relay accepts

| Request | Sent by |
|---|---|
| `POST /<topic>` + `Title`/`Priority`/`Tags` headers | Octo, ad-hoc scripts |
| `POST /<topic>?title=..&message=..&priority=..&tags=..` | Lidarr, Prowlarr, Readarr (`NtfyProxy.cs` builds the whole message into the URL and sends an empty body) |
| `POST /` with `{"topic": ...}` | anything using ntfy's JSON publish shape |
| `POST /alertmanager/<topic>` | Alertmanager — rendered one message per group, not per alert |

Topics are allow-listed in the script. It binds a LAN port with no auth, so
without the list any host on the LAN could publish to a server it otherwise
cannot reach at all.

## What is wired, and what is deliberately not

| Source | Fires on | Topic |
|---|---|---|
| Alertmanager `smart-email` | failing/hot disks, degraded array, node gone, filesystem filling, backup chain broken, MinIO drives lost | `homelab-alerts` |
| Alertmanager `heartbeat-ntfy` | Watchdog → the beat receiver (never a notification itself) | — |
| ArgoCD | `on-sync-failed`, `on-health-degraded` | `homelab-alerts` |
| Lidarr / Prowlarr / Readarr | health issue, health restored | `homelab-alerts` |
| Octo | download completed, download failed, album completed | `homelab-media` |
| `octo-artist-on-heart` | an artist was added to Lidarr | `homelab-media` |

**Not wired, having considered it:**

- ***arr on-grab / on-import.** Constant during normal operation, and with a
  mass search outstanding it would be thousands of messages. It would bury the
  health alerts sitting next to it on the same topic.
- **ArgoCD on-sync-succeeded / on-deployed.** Several a day. A topic that
  mostly carries "yes, that worked" gets muted, and takes the failures with it.
- **qBittorrent on-completion.** Same reason as on-grab; Octo already reports
  the downloads a human actually asked for.
- **Octo lossless-fallback.** With Soulseek last in the heart priority list a
  fallback is the *expected* path, not an exception.
- **Memory alerts.** The node genuinely sits near its tripwire; routing a
  permanently-true alert is how a pipeline ends up back at `null`.

## Two failures this has already had

**ntfy died silently for three hours (2026-09-04, 06:04).** A package upgrade
changed its service user from `ntfy` (987) to `_ntfy` (986), and
`/var/cache/ntfy` was still owned by the old account at mode 700, so it failed
with `FATAL unable to open database file: permission denied` and hit systemd's
start-limit. A `CacheDirectory=` drop-in now has systemd create and chown that
directory to whatever `User=` currently is, on every start, so the next
packaged-user change fixes itself instead of ending notifications.

**`smart-email` had no configs (found 2026-09-05).** The receiver was declared
with a name and nothing under it. Alertmanager accepts that and delivers
nowhere, so all seven of the routes pointed at it went into a black hole for as
long as they had existed. Checked against the live generated config, not the
source — which is the only way this class of bug is visible.

Both have the same shape as most entries in `doctor-log.md`: the component was
present, configured, and reported healthy, and did nothing.

## Verifying the chain by hand

```bash
# relay is up
curl -s http://192.168.1.153:9098/healthz

# end to end, from inside the cluster
kubectl -n lidarr exec deploy/lidarr -- \
  curl -s -o /dev/null -w '%{http_code}\n' \
  'http://192.168.1.153:9098/homelab-alerts?title=test&message=hello'

# what ntfy thinks it has done
ssh root@100.81.123.74 'journalctl -u ntfy -n 5 --no-pager'
```
A `204` from the relay means ntfy accepted it. If the phone still shows
nothing, the subscription is the problem, not the chain.
