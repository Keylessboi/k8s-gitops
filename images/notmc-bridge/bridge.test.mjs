import test from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import { once } from "node:events";
import WebSocket from "ws";
import {
  PROTOCOL, createBridge, configFromEnv, playerName, offlineUuid, writeVarInt, readVarInt, parseLoginStart,
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

test("wrong protocol, transfer state and garbage are dropped before reaching the server", async () => {
  const t = await setup({ preloginMs: 300 });
  for (const first of [handshake(2, 776), handshake(3), Buffer.from("GET / HTTP/1.1\r\n\r\n")]) {
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
