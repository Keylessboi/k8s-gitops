# When the whole cluster is down

The 2026-09-04 outage is the worked example: pve powered off at **18:39**, and
the owner found out **3h37m later, by opening a laptop**. Nothing was broken in
a way monitoring could not see. Everything that could see it either said nothing
or had already been trained into background noise.

## What actually happened

| Time | Event |
|---|---|
| ~14:00–17:30 | `TempNasDiskHigh` / `TempNasNvmeHigh` flap ~14 times, several delivered in triplicate. `HOMELAB EDGE UNREACHABLE` fires and self-recovers at 14:53, 15:13, 15:33, 17:14. |
| 17:03, 17:37 | `App degraded: monitoring` |
| 17:43 | `ArgoCD sync failed` |
| **18:39:30** | pve powers off. Edge probe fires **one** urgent push. |
| 18:39 → 22:16 | Silence. The probe logs `edge: FAIL` every 5 min to a journal nobody reads. |
| 22:16 | New external watchdog deployed; alerts immediately. |

## The three faults, and why each one mattered

**1. Every in-band watcher shares a fate with pve.** Prometheus and Alertmanager
are in LXC 200; the ntfy relay (`:9098`) and the beat receiver (`:9099`) are on
pve itself. The dead man's switch is the trap here, because it looks like the
control that covers this: `homelab-beat-check.timer` runs *on pve*, so pve's own
death is the single failure it structurally cannot report. SESSION-HANDOFF had
already listed "pve itself dying, power cut" as uncovered. It was left uncovered.

**2. The one watcher that did see it only spoke once.** `homelab-edge-probe`
notified on `state != prev` and then never again. One push is one chance.

**3. That push was the fifth identical-looking message of the day.** Four
self-recovering `HOMELAB EDGE UNREACHABLE` alerts had already fired. A real
alert that looks exactly like four false ones is not an alert.

## What is in place now

| Watcher | Host | Sees | Blind to |
|---|---|---|---|
| `homelab-external-watchdog` | **awesomemediaserver** `.67` (the NAS) | pve by ICMP and k3s `:6443` by TCP, on the cluster's own L2 segment. Re-nags every 30 min. Fires WoL while down. | A whole-house power cut — it is in the same building. |
| `homelab-edge-probe` | **travisbackupserver** | The public path, from a different building. Re-nags every 30 min *(added 2026-09-04)*. | Anything internal; only knows "the edge answers or it does not". |

The two are complementary on purpose: the first survives the cluster dying, the
second survives the *building* dying. Neither runs on pve.

The alert path is what makes this work. Normally it is
`cluster → relay on pve → tailscale → ntfy`, i.e. **every alert about pve had to
be forwarded by pve**. awesomemediaserver reaches ntfy on travisbackupserver
directly over Tailscale (`/v1/health → {"healthy":true}`, verified 2026-09-04),
so it needs pve for nothing.

## Recovering a dead pve

Work down this list. On 2026-09-04 it ran out at step 3.

1. **Confirm it is really the host**, from a box on the cluster's segment —
   `awesomemediaserver`, not a laptop. The laptop is on travisbackupserver's
   *separate* `192.168.1.0/24` and its `.153` is a different machine entirely.
   ```sh
   ssh root@100.69.240.8 'ping -c3 192.168.1.153; ip neigh | grep 192.168.1.153'
   ```
   `INCOMPLETE` — no ARP reply on its own segment — means the NIC is dead: the
   box is powered off or hung, not merely unreachable.
2. **Wake-on-LAN.** The watchdog already does this every cycle. To force it:
   ```sh
   ssh root@100.69.240.8 'python3 -c "
   import socket
   p=b\"\\xff\"*6+bytes.fromhex(\"b07b2518d98d\")*16
   s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
   s.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1)
   s.sendto(p,(\"192.168.1.255\",9))"'
   ```
   No response means WoL is off in the BIOS, or the board has no standby power.
3. **Press the power button.** There is no remote path left: the host is a Dell
   Vostro, so **no IPMI/iDRAC**, and a LAN sweep on 2026-09-04 found only the
   router, an AP, the NAS and one appliance — **no smart plug**.

## Make step 3 unnecessary — needs someone at the machine, once

- BIOS → **AC Power Recovery = Power On**, so a power blip self-heals.
- BIOS → **Wake-on-LAN = Enabled (LAN only)**, so step 2 starts working.
- A **smart plug** on pve's socket turns a house call into a remote power cycle.
  This is the single highest-value purchase for this homelab.

## After it comes back — capture the cause before it rotates

The leading hypothesis is thermal: the disks had been alarming all day, and
`docs/adr/` records the node already at ~90% memory and swapping.

```sh
ssh root@192.168.1.153 'journalctl --list-boots | tail -5'
ssh root@192.168.1.153 'journalctl -b -1 -k --no-pager | tail -300'   # last boot's kernel log
ssh root@192.168.1.153 'journalctl -b -1 --no-pager | grep -iE "thermal|critical temp|emergency|power|oom|panic"'
ssh root@192.168.1.153 'sensors; for d in /dev/sd?; do smartctl -A $d | grep -i temp; done'
```

A clean shutdown with no shutdown request in the log is a **thermal or power
event**. A kernel `Out of memory` immediately before the gap is the memory
problem in ADR-0005 finally biting the host rather than a pod.
