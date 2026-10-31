#!/bin/sh
cd /tmp/mg.DHeF
docker rm -f mg-test >/dev/null 2>&1
CMDS=$(cat rcon-startup.txt)
docker run -d --name mg-test --memory 2304m -u 1000:1000 -e EULA=TRUE -e TYPE=PAPER -e VERSION=1.8.8 -e ONLINE_MODE=FALSE -e USE_NATIVE_TRANSPORT=FALSE -e MEMORY=1536M -e VIEW_DISTANCE=6 -e MAX_PLAYERS=6 -e MOTD=test -e SYNC_SKIP_NEWER_IN_DESTINATION=false -e COPY_CONFIG_DEST=/data -e "RCON_CMDS_STARTUP=$CMDS" -e "RCON_CMDS_FIRST_CONNECT=$CMDS" -v /tmp/mg.DHeF/data:/data -v /tmp/mg.DHeF/plugins:/plugins:ro -v /tmp/mg.DHeF/config:/config:ro itzg/minecraft-server:java17@sha256:a08cd9ced3e1c3f46a318af1fa393de21698afbf8746681f115dc923ba847ba5
