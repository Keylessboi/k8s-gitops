# nfs-ganesha on CT 200

These files are the live configuration on the k3s LXC (CT 200). They are kept
here because nothing else in this repo deploys them, and this service has taken
the whole cluster down **twice** by filling the root disk with its own log.

Copy them into place with:

```
pct push 200 ganesha.conf              /etc/ganesha/ganesha.conf
pct push 200 logrotate.conf            /etc/logrotate.d/ganesha
pct push 200 ganesha-logrotate.service /etc/systemd/system/ganesha-logrotate.service
pct push 200 ganesha-logrotate.timer   /etc/systemd/system/ganesha-logrotate.timer
pct exec 200 -- systemctl daemon-reload
pct exec 200 -- systemctl enable --now ganesha-logrotate.timer
pct exec 200 -- systemctl restart nfs-ganesha
```

## Two defences, because one was not enough

**1. `Enable_UDP = false`, inside the FIRST `NFS_CORE_PARAM` block.**
The UDP RPC listener spins on a malformed datagram and logs
`svc_dg_rendezvous: Bad message sa_family is 0xffff` at ~10-13 MB/s. Every
export is `Transports = TCP` and NFSv4 is TCP-only, so nothing needs it.

The placement is the whole point. This setting was originally added as a
*second* `NFS_CORE_PARAM` block at the end of the file. Ganesha keeps the first
block of a given name and ignores later duplicates, so it parsed cleanly,
changed nothing, and left the listener running — for a day, while the fix sat
in the file, in git, and in the doctor log. Verify with
`ss -lunp | grep 2049` (expect nothing) rather than by reading the config.

**2. A one-minute size check.**
`/etc/logrotate.d/ganesha` has always said `maxsize 200M`, and it has always
been useless on its own, because logrotate itself only runs **daily**. The log
reached 43 GB the first time and 72.8 GB the second, both between two runs of a
job whose config was correct.

`ganesha-logrotate.timer` runs that same config every minute against its own
state file. A size limit is only worth what the interval that checks it is
worth: at 13 MB/s a daily check permits ~1 TB, a one-minute check permits
~800 MB.
