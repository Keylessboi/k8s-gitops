// notmc-bridge: WebSocket -> TCP in front of Pumpkin, for the browser client.
//
// The browser client (Horizon web) opens wss://host:port/ and sends the plain
// Minecraft byte stream as binary frames. This forwards it to one fixed target
// and makes the player's identity the Authentik account:
//
//   * Traefik only sends Upgrade requests here, after forward-auth, and the
//     NetworkPolicy lets nothing else reach this pod. The account name comes
//     from the X-authentik-username header that forward-auth set.
//   * The Login Start packet is rewritten so the in-game name (and so the
//     offline UUID Pumpkin derives) is the one bound to that account, whatever
//     name the client typed. Nobody can log in as somebody else.
//   * Only protocol 777 handshakes for status, login or transfer pass.
//   * Two upstreams: the games lobby (default) and the SMP. When the server a
//     player is on sends them a Transfer packet, the bridge notes that this
//     account's NEXT connection (within ROUTE_TTL_MS) goes to the other server.
//     The client then reconnects to this same host (it follows the packet) or
//     the player re-enters the address; either way they land on the other
//     server, behind the same forward-auth, with the same bound name.
//   * Origin, per-IP and per-account limits, a frame cap, a byte-rate cap and
//     an idle timeout keep one client from hurting Pumpkin.
//
// After Login Start the stream is piped untouched (compression and anything
// else the server negotiates happen above this layer).
import { createServer } from "node:http";
import net from "node:net";
import crypto from "node:crypto";
import { WebSocketServer } from "ws";

export const PROTOCOL = 777;
const MAX_PRELOGIN = 2048; // bytes buffered before the handshake and login are parsed
const PLAY_TRANSFER_ID = 132; // clientbound play "transfer", protocol 777 (assets/packets.json)
const MAX_TRANSFER_FRAME = 600; // a Transfer packet is a short hostname and a port
const ROUTE_TTL_MS = 60_000;

// --- Minecraft framing -------------------------------------------------------

/** Reads a VarInt at `off`. Returns [value, nextOffset] or null if incomplete; throws if malformed. */
export function readVarInt(buf, off) {
  let value = 0;
  for (let i = 0; i < 5; i++) {
    if (off + i >= buf.length) return null;
    const b = buf[off + i];
    value |= (b & 0x7f) << (7 * i);
    if ((b & 0x80) === 0) return [value, off + i + 1];
  }
  throw new Error("varint too long");
}

export function writeVarInt(n) {
  const out = [];
  do {
    let b = n & 0x7f;
    n >>>= 7;
    if (n) b |= 0x80;
    out.push(b);
  } while (n);
  return Buffer.from(out);
}

/** Reads one length-prefixed packet at `off`: [packetBytesWithoutLength, nextOffset] or null. */
function readFrame(buf, off) {
  const len = readVarInt(buf, off);
  if (!len) return null;
  const [size, start] = len;
  if (size < 1 || size > MAX_PRELOGIN) throw new Error("bad frame size");
  if (start + size > buf.length) return null;
  return [buf.subarray(start, start + size), start + size];
}

/** Handshake: id 0, protocol, address string, port, next state. */
export function parseHandshake(pkt) {
  const id = readVarInt(pkt, 0);
  if (!id || id[0] !== 0) throw new Error("not a handshake");
  const proto = readVarInt(pkt, id[1]);
  const hostLen = readVarInt(pkt, proto[1]);
  if (hostLen[0] < 0 || hostLen[0] > 255 * 4) throw new Error("bad host");
  const hostEnd = hostLen[1] + hostLen[0];
  const next = readVarInt(pkt, hostEnd + 2);
  return { protocol: proto[0], nextState: next[0] };
}

/** Login Start: id 0, name (string, 16 chars), UUID (16 bytes). */
export function parseLoginStart(pkt) {
  const id = readVarInt(pkt, 0);
  if (!id || id[0] !== 0) throw new Error("not login start");
  const nameLen = readVarInt(pkt, id[1]);
  const end = nameLen[1] + nameLen[0];
  if (nameLen[0] < 1 || nameLen[0] > 16 * 4 || pkt.length !== end + 16) throw new Error("bad login start");
  return { name: pkt.subarray(nameLen[1], end).toString("utf8") };
}

export function buildLoginStart(name, uuid) {
  const nameBytes = Buffer.from(name, "utf8");
  const body = Buffer.concat([writeVarInt(0), writeVarInt(nameBytes.length), nameBytes, uuid]);
  return Buffer.concat([writeVarInt(body.length), body]);
}

/**
 * Watches the server -> client stream for a play-state Transfer packet.
 *
 * After login Pumpkin compresses packets over its threshold; shorter ones carry
 * a Data Length of 0 and are sent as they are, and a Transfer packet is always
 * short. Bigger frames are skipped without being buffered. A packet counts only
 * if its body is exactly id, host string, port (so a stray byte pattern in some
 * other frame does not).
 */
export function transferScanner(onTransfer) {
  let head = []; // length VarInt bytes so far
  let need = 0; // body bytes still to come in the current frame
  let body = null; // collected body, or null to skip it
  let lost = false; // framing no longer makes sense (a length over 3 bytes); stop looking
  const done = () => {
    if (body) {
      try {
        const dl = readVarInt(body, 0);
        const id = dl && dl[0] === 0 ? readVarInt(body, dl[1]) : null;
        if (id && id[0] === PLAY_TRANSFER_ID) {
          const hl = readVarInt(body, id[1]);
          const hostEnd = hl[1] + hl[0];
          const port = readVarInt(body, hostEnd);
          if (hl[0] > 0 && port && port[1] === body.length) {
            onTransfer(body.subarray(hl[1], hostEnd).toString("utf8"), port[0]);
          }
        }
      } catch {
        // not a Transfer packet
      }
    }
    body = null;
  };
  return (chunk) => {
    let i = 0;
    while (!lost && i < chunk.length) {
      if (need === 0) {
        const b = chunk[i++];
        head.push(b);
        if (head.length > 3) lost = true; // packets are at most 2 MiB: a 4-byte length is not framing
        else if ((b & 0x80) === 0) {
          const len = readVarInt(Buffer.from(head), 0)[0];
          head = [];
          if (len <= 0) continue;
          need = len;
          body = len <= MAX_TRANSFER_FRAME ? Buffer.alloc(0) : null;
        }
      } else {
        const take = Math.min(need, chunk.length - i);
        if (body) body = Buffer.concat([body, chunk.subarray(i, i + take)]);
        need -= take;
        i += take;
        if (need === 0) done();
      }
    }
  };
}

// --- identity ----------------------------------------------------------------

/**
 * The in-game name bound to an Authentik username: [A-Za-z0-9_], 3-16 chars.
 * A username that needed any change (or was too long) gets a short hash suffix
 * so two accounts cannot collapse into one name.
 */
export function playerName(username) {
  const clean = username.replace(/[^A-Za-z0-9_]/g, "_");
  if (clean === username && clean.length >= 3 && clean.length <= 16) return clean;
  const tag = crypto.createHash("sha256").update(username).digest("hex").slice(0, 4);
  return `${clean.slice(0, 11).padEnd(3, "_")}_${tag}`;
}

/** Vanilla's offline UUID: version-3 MD5 of "OfflinePlayer:<name>". */
export function offlineUuid(name) {
  const h = crypto.createHash("md5").update(`OfflinePlayer:${name}`).digest();
  h[6] = (h[6] & 0x0f) | 0x30;
  h[8] = (h[8] & 0x3f) | 0x80;
  return h;
}

// --- server ------------------------------------------------------------------

export function createBridge(cfg) {
  const perIp = new Map();
  const perAccount = new Map();
  const bump = (m, k, d) => {
    const n = (m.get(k) ?? 0) + d;
    if (n <= 0) m.delete(k);
    else m.set(k, n);
    return n;
  };

  // account name -> {to, until}: where that account's next login goes.
  const routes = new Map();
  const pickUpstream = (name) => {
    const r = routes.get(name);
    routes.delete(name);
    const to = r && r.until > Date.now() ? r.to : "lobby";
    return to === "smp" && cfg.smpHost ? { to, host: cfg.smpHost, port: cfg.smpPort } : { to: "lobby", host: cfg.host, port: cfg.port };
  };

  const http = createServer((req, res) => {
    // Traefik only forwards Upgrade requests; this answers the kubelet probe.
    res.writeHead(req.url === "/healthz" ? 200 : 404).end();
  });
  const wss = new WebSocketServer({
    server: http,
    maxPayload: cfg.maxFrame,
    perMessageDeflate: false,
    verifyClient: ({ req }, done) => {
      if (req.headers.origin !== cfg.origin) return done(false, 403, "origin");
      const user = req.headers["x-authentik-username"];
      if (typeof user !== "string" || !user) return done(false, 401, "no account");
      done(true);
    },
  });

  wss.on("connection", (ws, req) => {
    const user = req.headers["x-authentik-username"];
    const ip = String(req.headers["x-real-ip"] ?? req.socket.remoteAddress);
    const name = playerName(user);
    if (bump(perIp, ip, 1) > cfg.perIp || bump(perAccount, name, 1) > cfg.perAccount) {
      bump(perIp, ip, -1);
      bump(perAccount, name, -1);
      return ws.close(1013, "too many connections");
    }

    let tcp = null;
    let upstream = "lobby";
    let closed = false;
    let pre = Buffer.alloc(0);
    let handshake = null;
    let tokens = cfg.burstBytes;
    let last = Date.now();
    // Until the handshake and login are through, a short fixed deadline that
    // incoming bytes do not extend; after that, an idle timer they reset.
    let idle = setTimeout(() => finish(), cfg.preloginMs);

    const finish = () => {
      if (closed) return;
      closed = true;
      clearTimeout(idle);
      bump(perIp, ip, -1);
      bump(perAccount, name, -1);
      tcp?.destroy();
      ws.terminate();
    };

    const connect = (first, status = false) => {
      clearTimeout(idle);
      idle = setTimeout(finish, cfg.idleMs);
      const up = status ? { to: "lobby", host: cfg.host, port: cfg.port } : pickUpstream(name);
      upstream = up.to;
      tcp = net.connect({ host: up.host, port: up.port, noDelay: true });
      tcp.write(first);
      // Only players on the first server or the SMP can be sent to the other one.
      const scan = status || !cfg.smpHost
        ? null
        : transferScanner(() => routes.set(name, { to: upstream === "lobby" ? "smp" : "lobby", until: Date.now() + ROUTE_TTL_MS }));
      tcp.on("data", (d) => {
        scan?.(d);
        ws.send(d, { binary: true });
      });
      tcp.on("close", finish);
      tcp.on("error", finish);
    };

    ws.on("message", (data) => {
      const chunk = Buffer.isBuffer(data) ? data : Buffer.concat(data);
      const now = Date.now();
      tokens = Math.min(cfg.burstBytes, tokens + ((now - last) / 1000) * cfg.bytesPerSec);
      last = now;
      tokens -= chunk.length;
      if (tokens < 0) return finish();
      if (tcp) {
        clearTimeout(idle);
        idle = setTimeout(finish, cfg.idleMs);
        return tcp.write(chunk);
      }
      try {
        pre = Buffer.concat([pre, chunk]);
        if (pre.length > MAX_PRELOGIN) throw new Error("prelogin too large");
        if (!handshake) {
          const f = readFrame(pre, 0);
          if (!f) return;
          const hs = parseHandshake(f[0]);
          if (hs.protocol !== PROTOCOL || (hs.nextState < 1 || hs.nextState > 3)) throw new Error("handshake refused");
          handshake = { raw: pre.subarray(0, f[1]), state: hs.nextState };
          pre = pre.subarray(f[1]);
        }
        if (handshake.state === 1) return connect(Buffer.concat([handshake.raw, pre]), true); // status: untouched
        const f = readFrame(pre, 0);
        if (!f) return;
        parseLoginStart(f[0]); // must be well formed; the name itself is replaced
        const login = buildLoginStart(name, offlineUuid(name));
        connect(Buffer.concat([handshake.raw, login, pre.subarray(f[1])]));
      } catch {
        finish();
      }
    });
    ws.on("close", finish);
    ws.on("error", finish);
  });

  return http;
}

const env = (k, d) => process.env[k] ?? d;
export const configFromEnv = () => ({
  host: env("TARGET_HOST", "pumpkin"),
  port: Number(env("TARGET_PORT", "25565")),
  // The SMP server; leave SMP_HOST unset and transfers are not routed.
  smpHost: env("SMP_HOST", ""),
  smpPort: Number(env("SMP_PORT", "25565")),
  origin: env("ALLOWED_ORIGIN", "https://notmc.sandstorm.chat"),
  perIp: Number(env("MAX_CONN_PER_IP", "6")),
  perAccount: Number(env("MAX_CONN_PER_ACCOUNT", "2")),
  maxFrame: Number(env("MAX_FRAME_BYTES", "65536")),
  bytesPerSec: Number(env("MAX_BYTES_PER_SEC", "262144")),
  burstBytes: Number(env("BURST_BYTES", "1048576")),
  idleMs: Number(env("IDLE_MS", "90000")),
  preloginMs: Number(env("PRELOGIN_MS", "10000")),
});

if (import.meta.url === `file://${process.argv[1]}`) {
  const cfg = configFromEnv();
  const port = Number(env("LISTEN_PORT", "8080"));
  createBridge(cfg).listen(port, () => console.log(`notmc-bridge :${port} -> ${cfg.host}:${cfg.port} origin ${cfg.origin}`));
}
