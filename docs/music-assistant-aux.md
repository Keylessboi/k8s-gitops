# Aux input on a server node, played through Music Assistant

**Status: proposed. Host steps are the owner's** (policy 8.1: host configuration
of `nas` and `pve` is Z0, and agents may only describe the change).

## What the cluster part does (`apps/homeassistant`)

- Music Assistant (MA) runs in the cluster and is the Sendspin server. LAN
  clients reach it at the MetalLB address of Service
  `homeassistant/music-assistant-sendspin`, TCP 8927. The NetworkPolicy admits
  only the nas (`192.168.1.67`) and pve (`192.168.1.153`).
- MA's Subsonic provider points at Octo (`octo.downloads.svc.cluster.local:5274`).
- Home Assistant runs next to it, unpublished.

## What the host must do (not done, not verified)

The nas has a Realtek ALC897 (`card1`, "HD-Audio Generic") with analog capture
PCM devices, so a line-in jack is present at the driver level. Which jack is
line-in on that board, and whether the Vostro has a usable input, is not known
from here.

1. On the chosen node, find the capture device: `arecord -l` (the
   `alsa-utils` package is not installed on the nas today).
2. Run the Sendspin source client against the MA address, capturing that ALSA
   device. The Sendspin CLI has a source mode (`sendspin source run`, added in
   sendspin-cli; **check the exact flags with `--help` for the installed
   version**). Run it as a systemd service under a dedicated unprivileged user
   in the `audio` group.
3. In MA, enable the *Sendspin Source* plugin. The input then appears as a Live
   Input that can be played on any MA player or group. Needs MA 2.10 or newer;
   the manifest pins 2.10.9. Live inputs are 48 kHz / 16-bit stereo.
4. Set the node's mixer so Line In capture is unmuted and not clipping, and
   check that no other service on the nas holds the device.

## Limits

- Sendspin is a technical preview and the source role is new; expect changes.
- MA runs on the pod network, so it cannot discover speakers by mDNS. Add
  speakers by address, or use Sendspin players that connect to MA themselves.
  If discovery matters, the alternative is `hostNetwork` for MA, which needs a
  signed permissions-register entry.
