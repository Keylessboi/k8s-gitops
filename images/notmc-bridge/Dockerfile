# notmc-bridge: WebSocket -> TCP in front of Pumpkin, binding the player's name
# to their Authentik account. See docs/notmc-browser-client.md.
#
# Build context is the repository root:
#   docker build -f images/notmc-bridge/Dockerfile .
#
# node:24-alpine, pinned by digest. Dependencies come from the lockfile with
# install scripts off; the runtime stage carries no npm, no shell history, and
# runs as the unprivileged `node` user.
FROM node:24-alpine@sha256:8a32c8cf649a49915a66e81e7a609223c708d0adabf288ee3f4077d765542f85 AS deps
WORKDIR /app
COPY images/notmc-bridge/package.json images/notmc-bridge/package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund

FROM node:24-alpine@sha256:8a32c8cf649a49915a66e81e7a609223c708d0adabf288ee3f4077d765542f85
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY images/notmc-bridge/package.json images/notmc-bridge/bridge.mjs ./
USER node
EXPOSE 8080
ENTRYPOINT ["node", "bridge.mjs"]
