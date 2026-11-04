import test from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import { once } from "node:events";
import WebSocket from "ws";
import {
  PROTOCOL, createBridge, configFromEnv, playerName, offlineUuid, writeVarInt, readVarInt, parseLoginStart, transferScanner,
} from "./bridge.mjs";

const ORIGIN = "https://notmc.sandstorm.chat";

const str = (s) => Buffer.concat([writeVarInt(Buffer.byteLength(s)), Buffer.from(s)]);
const frame = (...parts) => {
  const body = Buffer.concat(parts);
  return Buffer.concat([writeVarInt(body.length), body]);
};
const handshake = (state, protocol = PROTOCOL) =>
  frame(writeVarInt(0), writeVarInt(protocol), str("notmc.sandstorm.chat"), Buffer.from([0x01, 0xbb]), writeVarInt(state));
const loginStart = (name) => frame(writeVarInt(0), str(name), Buffer.alloc(16, 7));

/** A fake Pumpkin that records what it receives. */
async function fakeServer() {
  const received = [];
  const server = net.createServer((s) => {
    s.on("data", (d) => received.push(d));
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return { server, received, port: server.address().port };
}

async function setup(over = {}) {
  const fake = await fakeServer();
  const cfg = { ...configFromEnv(), host: "127.0.0.1", port: fake.port, origin: ORIGIN, ...over };
  const bridge = createBridge(cfg);
  bridge.listen(0, "127.0.0.1");
  await once(bridge, "listening");
  const url = `ws://127.0.0.1:${bridge.address().port}/`;
  return {
    fake,
    url,
    close: () => {
      bridge.closeAllConnections();
      bridge.close();
      fake.server.close();
    },
  };
}

const headers = (user = "alice", origin = ORIGIN) => ({ Origin: origin, ...(user ? { "X-authentik-username": user } : {}) });
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

test("playerName keeps clean usernames and disambiguates changed ones", () => {
  assert.equal(playerName("alice"), "alice");
  assert.equal(playerName("a_b"), "a_b");
  const dotted = playerName("a.b");
  assert.notEqual(dotted, playerName("a_b"));
  assert.match(dotted, /^[A-Za-z0-9_]{3,16}$/);
  assert.match(playerName("someone.with.a.very.long.name"), /^[A-Za-z0-9_]{3,16}$/);
  assert.notEqual(playerName("a.b"), playerName("a-b"));
  assert.match(playerName("é"), /^[A-Za-z0-9_]{3,16}$/);
});

test("offlineUuid matches vanilla's for a known name", () => {
  const hex = offlineUuid("Notch").toString("hex");
  assert.equal(hex, "b50ad385829d3141a2167e7d7539ba7f");
});

test("login start is rewritten to the account's name", async () => {
  const t = await setup();
  const ws = new WebSocket(t.url, { headers: headers("alice") });
  await once(ws, "open");
  ws.send(Buffer.concat([handshake(2), loginStart("Steve")]));
  await wait(200);
  const got = Buffer.concat(t.fake.received);
  const [hsLen, hsStart] = readVarInt(got, 0);
  const rest = got.subarray(hsStart + hsLen);
  const [len, start] = readVarInt(rest, 0);
  const pkt = rest.subarray(start, start + len);
  assert.equal(parseLoginStart(pkt).name, "alice");
  assert.deepEqual(pkt.subarray(pkt.length - 16), offlineUuid("alice"));
  ws.close();
  t.close();
});

test("login split across frames still works, and the rest of the stream passes through", async () => {
  const t = await setup();
  const ws = new WebSocket(t.url, { headers: headers("bob") });
  await once(ws, "open");
  const all = Buffer.concat([handshake(2), loginStart("x")]);
  ws.send(all.subarray(0, 9));
  ws.send(all.subarray(9));
  await wait(100);
  ws.send(Buffer.from("tail"));
  await wait(200);
  assert.ok(Buffer.concat(t.fake.received).toString("latin1").endsWith("tail"));
  ws.close();
  t.close();
});

test("status requests pass through untouched", async () => {
  const t = await setup();
  const ws = new WebSocket(t.url, { headers: headers() });
  await once(ws, "open");
  const hs = handshake(1);
  const req = Buffer.from([1, 0]);
  ws.send(Buffer.concat([hs, req]));
  await wait(200);
  assert.deepEqual(Buffer.concat(t.fake.received), Buffer.concat([hs, req]));
  ws.close();
  t.close();
});

test("wrong origin and missing account are refused at the upgrade", async () => {
  const t = await setup();
  for (const h of [headers("alice", "https://evil.example"), headers(null)]) {
    const ws = new WebSocket(t.url, { headers: h });
    const [err] = await once(ws, "error");
    assert.match(err.message, /40[13]/);
  }
  t.close();
});

test("wrong protocol, unknown intent and garbage are dropped before reaching the server", async () => {
  const t = await setup({ preloginMs: 300 });
  for (const first of [handshake(2, 776), handshake(4), Buffer.from("GET / HTTP/1.1\r\n\r\n")]) {
    const ws = new WebSocket(t.url, { headers: headers() });
    await once(ws, "open");
    ws.send(first);
    await once(ws, "close");
  }
  assert.equal(t.fake.received.length, 0);
  t.close();
});

test("per-account and per-ip limits", async () => {
  const t = await setup({ perAccount: 1, perIp: 5 });
  const a = new WebSocket(t.url, { headers: headers("carol") });
  await once(a, "open");
  const b = new WebSocket(t.url, { headers: headers("carol") });
  const [code] = await once(b, "close");
  assert.equal(code, 1013);
  a.close();
  t.close();
});

test("byte-rate cap closes a flooding client", async () => {
  const t = await setup({ burstBytes: 2000, bytesPerSec: 100 });
  const ws = new WebSocket(t.url, { headers: headers() });
  await once(ws, "open");
  ws.send(handshake(1));
  for (let i = 0; i < 10; i++) ws.send(Buffer.alloc(1000, 1));
  await once(ws, "close");
  t.close();
});

test("oversized frame is rejected", async () => {
  const t = await setup({ maxFrame: 1024 });
  const ws = new WebSocket(t.url, { headers: headers() });
  await once(ws, "open");
  ws.send(Buffer.alloc(4096));
  await once(ws, "close");
  t.close();
});

// --- SMP routing ---------------------------------------------------------------

/** A clientbound play Transfer packet as Pumpkin sends it: Data Length 0, id 132, host, port. */
const transferPacket = (host = "notmc.sandstorm.chat", port = 443) =>
  frame(writeVarInt(0), writeVarInt(132), str(host), writeVarInt(port));

test("transferScanner finds a Transfer packet across chunk boundaries and between other frames", () => {
  const seen = [];
  const scan = transferScanner((h, p) => seen.push([h, p]));
  const big = frame(writeVarInt(0), writeVarInt(46), Buffer.alloc(5000, 9)); // a chunk-sized frame, skipped
  const stream = Buffer.concat([frame(writeVarInt(0), writeVarInt(45), Buffer.alloc(8)), big, transferPacket(), transferPacket("x.example", 25565)]);
  for (let i = 0; i < stream.length; i += 7) scan(stream.subarray(i, i + 7));
  assert.deepEqual(seen, [["notmc.sandstorm.chat", 443], ["x.example", 25565]]);
});

test("transferScanner ignores look-alikes", () => {
  const seen = [];
  const scan = transferScanner((h, p) => seen.push([h, p]));
  scan(frame(writeVarInt(0), writeVarInt(131), str("a"), writeVarInt(1))); // another packet id
  scan(frame(writeVarInt(5), writeVarInt(132), str("a"), writeVarInt(1))); // compressed (Data Length set)
  scan(frame(writeVarInt(0), writeVarInt(132), str("a"), writeVarInt(1), Buffer.from([0]))); // trailing bytes
  scan(frame(writeVarInt(0), writeVarInt(132), writeVarInt(50), Buffer.from("short"))); // host overruns
  assert.deepEqual(seen, []);
});

async function twoServers(over = {}) {
  const lobby = await fakeServer();
  const smp = await fakeServer();
  const cfg = {
    ...configFromEnv(), origin: ORIGIN, host: "127.0.0.1", port: lobby.port, smpHost: "127.0.0.1", smpPort: smp.port, ...over,
  };
  const bridge = createBridge(cfg);
  bridge.listen(0, "127.0.0.1");
  await once(bridge, "listening");
  const url = `ws://127.0.0.1:${bridge.address().port}/`;
  // Whatever each fake receives it answers with a Transfer packet when asked to.
  const talk = (fake) => fake.server.once("connection", (s) => s.write(transferPacket()));
  return {
    lobby, smp, url, talk,
    close: () => { bridge.closeAllConnections(); bridge.close(); lobby.server.close(); smp.server.close(); },
  };
}

const login = (ws, user = "Steve") => ws.send(Buffer.concat([handshake(2), loginStart(user)]));
async function connectAs(url, user) {
  const ws = new WebSocket(url, { headers: headers(user) });
  await once(ws, "open");
  login(ws);
  return ws;
}

test("a Transfer from the lobby sends the account's next login to the SMP, and one from the SMP sends it back", async () => {
  const t = await twoServers();
  t.talk(t.lobby);
  const a = await connectAs(t.url, "alice");
  await wait(200);
  a.close();
  assert.equal(t.smp.received.length, 0);
  t.talk(t.smp);
  const b = await connectAs(t.url, "alice");
  await wait(200);
  assert.ok(t.smp.received.length > 0, "second login reached the SMP");
  assert.equal(t.lobby.received.length, 1);
  b.close();
  await wait(100);
  const c = await connectAs(t.url, "alice");
  await wait(200);
  assert.equal(t.lobby.received.length, 2, "third login is back on the lobby");
  c.close();
  t.close();
});

test("a route applies to the account that was transferred, once, and to nobody else", async () => {
  const t = await twoServers();
  t.talk(t.lobby);
  const a = await connectAs(t.url, "alice");
  await wait(200);
  a.close();
  const other = await connectAs(t.url, "bob");
  await wait(200);
  assert.equal(t.smp.received.length, 0, "bob is unaffected");
  other.close();
  const b = await connectAs(t.url, "alice");
  await wait(200);
  assert.ok(t.smp.received.length > 0);
  b.close();
  t.close();
});

test("status pings never follow a route, and a transfer intent login works", async () => {
  const t = await twoServers();
  t.talk(t.lobby);
  const a = await connectAs(t.url, "alice");
  await wait(200);
  a.close();
  const ping = new WebSocket(t.url, { headers: headers("alice") });
  await once(ping, "open");
  ping.send(Buffer.concat([handshake(1), Buffer.from([1, 0])]));
  await wait(200);
  assert.equal(t.smp.received.length, 0);
  ping.close();
  const b = new WebSocket(t.url, { headers: headers("alice") });
  await once(b, "open");
  b.send(Buffer.concat([handshake(3), loginStart("Steve")]));
  await wait(200);
  assert.ok(t.smp.received.length > 0, "intent 3 login reached the SMP");
  b.close();
  t.close();
});

test("with no SMP configured nothing is routed", async () => {
  const t = await twoServers({ smpHost: "" });
  t.talk(t.lobby);
  const a = await connectAs(t.url, "alice");
  await wait(200);
  a.close();
  const b = await connectAs(t.url, "alice");
  await wait(200);
  assert.equal(t.smp.received.length, 0);
  b.close();
  t.close();
});
