#!/bin/sh
# Create the PeerTube channels and their YouTube channel syncs in one go.
# Run it yourself (it prompts for the PeerTube root password and never prints it):
#   ! sh docs/peertube-channel-syncs.sh
# It runs inside the PeerTube pod because the public hostname is behind Authentik.
# Existing channels/syncs are reported and skipped, so it is safe to re-run.
set -eu
printf 'PeerTube root password: ' >&2
stty -echo 2>/dev/null || true
IFS= read -r PW
stty echo 2>/dev/null || true
printf '\n' >&2

JS=$(cat <<'EOF'
const B = "http://localhost:9000/api/v1";
const CH = [
  ["vsauce", "Vsauce", "@vsauce"],
  ["second_thought", "Second Thought", "@SecondThought"],
  ["benn_jordan", "Benn Jordan", "@BennJordan"],
  ["bycloud", "bycloud", "@bycloudAI"],
  ["al_jokes", "al jokes", "@aljokes"],
  ["kurzgesagt", "Kurzgesagt", "@kurzgesagt"],
  ["exurb1a", "exurb1a", "@exurb1a"],
  ["chainsfr", "ChainsFR", "@ChainsFR"],
  ["jaden_williams", "Jaden Williams", "@Officialjadenwilliams"],
  ["cgpgrey", "CGP Grey", "@CGPGrey"],
  ["veritasium", "Veritasium", "@veritasium"],
  ["3blue1brown", "3Blue1Brown", "@3blue1brown"],
  ["technology_connections", "Technology Connections", "@TechnologyConnections"],
];
const j = async (path, opts) => {
  const r = await fetch(B + path, opts);
  const t = await r.text();
  let d; try { d = JSON.parse(t); } catch { d = t; }
  return { ok: r.ok, status: r.status, d };
};
(async () => {
  const c = (await j("/oauth-clients/local")).d;
  const form = new URLSearchParams({ client_id: c.client_id, client_secret: c.client_secret,
    grant_type: "password", response_type: "code", username: "root", password: process.env.PW });
  const tok = await j("/users/token", { method: "POST", body: form });
  if (!tok.ok) { console.error("login failed:", tok.status); process.exit(1); }
  const auth = { Authorization: "Bearer " + tok.d.access_token, "Content-Type": "application/json" };
  for (const [name, display, handle] of CH) {
    let id;
    const mk = await j("/video-channels", { method: "POST", headers: auth, body: JSON.stringify({ name, displayName: display }) });
    if (mk.ok) id = mk.d.videoChannel.id;
    else {
      const ex = await j("/video-channels/" + name);
      if (!ex.ok) { console.log(name, "channel FAILED", mk.status, JSON.stringify(mk.d).slice(0, 120)); continue; }
      id = ex.d.id;
    }
    const sy = await j("/video-channel-syncs", { method: "POST", headers: auth,
      body: JSON.stringify({ externalChannelUrl: "https://www.youtube.com/" + handle, videoChannelId: id }) });
    console.log(name.padEnd(24), sy.ok ? "sync created" : "sync " + sy.status + " " + JSON.stringify(sy.d).slice(0, 100));
  }
})();
EOF
)

{ printf '%s\n' "$PW"; printf '%s\n' "$JS"; } | ssh pve "pct exec 200 -- /usr/local/bin/k3s kubectl -n peertube exec -i deploy/peertube -c peertube -- sh -c 'IFS= read -r PW; export PW; cat > /tmp/cs.js; node /tmp/cs.js; rm -f /tmp/cs.js'"
