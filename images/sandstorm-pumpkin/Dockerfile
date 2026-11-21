# sandstorm-pumpkin: the Pumpkin Minecraft server (Rust, MIT/GPL-3.0) plus the
# sandstorm-games plugin (lobby, TNT Run, Mob Arena) and the sandstorm-smp plugin
# (the survival server's way back to the lobby), on a ~5 MB base. One image, two
# Deployments: each one's init container copies only its own plugin directory.
#
# Build context is the repository root:
#   docker build -f images/sandstorm-pumpkin/Dockerfile .
#
# Three stages, nothing downloaded without a checksum:
#   1. plugin  compile plugins/sandstorm-games and plugins/sandstorm-smp to
#              wasm32-wasip2 (--locked)
#   2. fetch   download the pinned Pumpkin release binary, verify its sha256
#   3. final   busybox (shell for the init container) + the two artefacts
#
# Bumping Pumpkin is a deliberate commit: change PUMPKIN_TAG and PUMPKIN_SHA256
# here AND the `tag = ` of pumpkin-plugin-api in plugins/sandstorm-games/Cargo.toml
# (the plugin ABI follows the server release), then rebuild and re-pin.

FROM rust:1.98-slim AS plugin
RUN rustup target add wasm32-wasip2
WORKDIR /src
COPY plugins/sandstorm-games/ ./
RUN cargo build --release --locked --target wasm32-wasip2
COPY plugins/sandstorm-smp/ /smp/
RUN cd /smp && cargo build --release --locked --target wasm32-wasip2

FROM curlimages/curl:8.23.0@sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93 AS fetch
# Static musl build: runs on busybox, no libc to match.
ARG PUMPKIN_TAG=0.2.1%2B26.3-26.51
ARG PUMPKIN_SHA256=501c00212a268be3a1108f394d2599cee3af8504184b1d2b69d027bcf5296208
RUN curl -fsSL --retry 5 --retry-delay 5 -o /tmp/pumpkin \
      "https://github.com/Pumpkin-MC/Pumpkin/releases/download/${PUMPKIN_TAG}/pumpkin-X64-Linux-musl" \
 && echo "${PUMPKIN_SHA256}  /tmp/pumpkin" | sha256sum -c - \
 && chmod 0555 /tmp/pumpkin

FROM busybox:1.38@sha256:a46257e06c82ad85242d0d38077d0a52d9896389ca60a1a59d3463db586e5fa4
COPY --from=fetch /tmp/pumpkin /opt/pumpkin/pumpkin
COPY --from=plugin /src/target/wasm32-wasip2/release/sandstorm_games.wasm /opt/pumpkin/plugins/sandstorm_games.wasm
COPY --from=plugin /smp/target/wasm32-wasip2/release/sandstorm_smp.wasm /opt/pumpkin/smp-plugins/sandstorm_smp.wasm
# The server writes its world, logs and rewritten config into the working
# directory; the Deployment mounts a volume there.
WORKDIR /data
EXPOSE 25565
ENTRYPOINT ["/opt/pumpkin/pumpkin"]
