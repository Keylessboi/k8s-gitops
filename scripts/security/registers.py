#!/usr/bin/env python3
"""Check, export and approve the security registers in security/registers/.

  registers.py check            schema, unique IDs, approvals, review dates
  registers.py data OUT.json    approved entries as Conftest data
  registers.py approve REGISTER ID --key PATH
                                owner only: sign one entry (needs the key's
                                touch or passphrase, which agents do not have)

An entry of an "exception" register takes effect only when its signature in
security/registers/approvals/<register>.<id>.sig verifies against a key in
security/allowed_signers. The signature covers the whole entry except its
"status" field, so any later edit voids it. CI accepts only FIDO2 keys
(sk-ssh-ed25519, sk-ecdsa) as signers unless REGISTER_ALLOW_SOFTWARE_KEYS=1,
because only a hardware key proves that a person, not an agent, signed.
Run from the repository root. Exits 1 on an error.
"""
import datetime
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

import yaml

ROOT = pathlib.Path("security")
REG = ROOT / "registers"
SIGS = REG / "approvals"
SIGNERS = ROOT / "allowed_signers"
NAMESPACE = "homelab-register"
PRINCIPAL = "owner"
HARDWARE = ("sk-ssh-ed25519@openssh.com", "sk-ecdsa-sha2-nistp256@openssh.com")

REQUIRED = {
    "publication": ["id", "ingress", "routes", "basis", "reason", "criteria", "status", "review_by"],
    "out-of-band": ["id", "item", "reason", "plan", "status", "review_by"],
    "waivers": ["id", "requirement", "scope", "reason", "compensating", "status", "review_by"],
    "permissions": ["id", "subject", "grants", "reason", "status", "review_by"],
    "accounts": ["id", "app", "type", "account", "why", "disable"],
    "keys": ["id", "key", "kept", "escrow", "rotate"],
    "data-stores": ["id", "store", "where", "class", "at_rest", "backup"],
    "zones": ["id", "zone", "paths"],
}
STATUSES = {"proposed", "approved", "rejected"}


def load():
    regs = {}
    for p in sorted(REG.glob("*.yaml")):
        doc = yaml.safe_load(p.read_text())
        regs[doc["register"]] = doc
    return regs


def payload(register, entry):
    body = {k: v for k, v in entry.items() if k != "status"}
    return json.dumps({"register": register, "entry": body}, sort_keys=True,
                      separators=(",", ":"), default=str).encode()


def signers():
    keys = []
    if SIGNERS.exists():
        for line in SIGNERS.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                keys.append(line)
    return keys


def verify(register, entry):
    # Trust mode: with no keys in allowed_signers, "approved" is taken on
    # trust (policy §10 forbids agents to set it). Add a key to turn on
    # signature checking for every approved entry.
    if not signers():
        return True, "trust mode (no signers configured)"
    sig = SIGS / f"{register}.{entry['id']}.sig"
    if not sig.exists():
        return False, "no signature"
    r = subprocess.run(["ssh-keygen", "-Y", "verify", "-f", str(SIGNERS), "-I", PRINCIPAL,
                        "-n", NAMESPACE, "-s", str(sig)], input=payload(register, entry),
                       capture_output=True)
    return r.returncode == 0, (r.stdout + r.stderr).decode().strip()


def check(regs):
    errors, warnings = [], []
    allow_soft = os.environ.get("REGISTER_ALLOW_SOFTWARE_KEYS") == "1"
    for line in signers():
        parts = line.split()
        ktype = next((p for p in parts if p.startswith(("ssh-", "sk-", "ecdsa-"))), "")
        if ktype not in HARDWARE and not allow_soft:
            errors.append(f"{SIGNERS}: {ktype or 'a key'} is not a FIDO2 key; agents could sign with it")
        if f'namespaces="{NAMESPACE}"' not in line or not line.startswith(PRINCIPAL + " "):
            errors.append(f'{SIGNERS}: each line must be: {PRINCIPAL} namespaces="{NAMESPACE}" <key>')
    today = datetime.date.today()
    for name, doc in regs.items():
        if name not in REQUIRED:
            errors.append(f"{name}: unknown register")
            continue
        ids = set()
        for e in doc.get("entries") or []:
            where = f"{name} {e.get('id', '?')}"
            missing = [k for k in REQUIRED[name] if k not in e]
            if missing:
                errors.append(f"{where}: missing {', '.join(missing)}")
            if e.get("id") in ids:
                errors.append(f"{where}: duplicate id")
            ids.add(e.get("id"))
            if doc.get("kind") != "exception":
                continue
            st = e.get("status")
            if st not in STATUSES:
                errors.append(f"{where}: status {st!r} not in {sorted(STATUSES)}")
            ok, msg = verify(name, e) if st == "approved" else (False, "")
            if st == "approved" and not ok:
                errors.append(f"{where}: says approved, but the owner signature does not verify ({msg})")
            rb = e.get("review_by")
            if st == "approved" and isinstance(rb, datetime.date) and rb < today:
                warnings.append(f"{where}: review date {rb} has passed; this is a GAP until renewed")
    for sig in SIGS.glob("*.sig") if SIGS.exists() else []:
        reg, _, eid = sig.stem.partition(".")
        if not any(e.get("id") == eid for e in (regs.get(reg, {}).get("entries") or [])):
            warnings.append(f"{sig}: no matching entry; remove it")
    return errors, warnings


def data(regs, out):
    result = {}
    for name, doc in regs.items():
        entries = doc.get("entries") or []
        if doc.get("kind") == "exception":
            entries = [e for e in entries if e.get("status") == "approved" and verify(name, e)[0]]
        result[name] = json.loads(json.dumps(entries, default=str))
    pathlib.Path(out).write_text(json.dumps({"registers": result}, indent=1, sort_keys=True))


def approve(regs, register, eid, key):
    doc = regs.get(register)
    if not doc or doc.get("kind") != "exception":
        sys.exit(f"{register}: not an exception register")
    path = next(p for p in REG.glob("*.yaml") if yaml.safe_load(p.read_text())["register"] == register)
    text = path.read_text()
    m = re.search(rf"^  - id: {re.escape(eid)}\n(?:    .*\n|      .*\n)*", text, re.M)
    if not m:
        sys.exit(f"{register} {eid}: entry not found (block style 'id:' entries only)")
    block = m.group(0)
    today = datetime.date.today().isoformat()
    block = re.sub(r"^    approved_on: .*\n", "", block, flags=re.M)
    block = re.sub(r"^(    status: )\w+\n", rf"\g<1>approved\n    approved_on: {today}\n", block, flags=re.M)
    new_text = text[:m.start()] + block + text[m.end():]
    entry = next(e for e in yaml.safe_load(new_text)["entries"] if e.get("id") == eid)
    print(json.dumps(entry, indent=1, default=str))
    if input(f"Sign {register} {eid} as shown? [y/N] ").strip().lower() != "y":
        sys.exit("not signed")
    SIGS.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=SIGS, suffix=".payload", delete=False) as f:
        f.write(payload(register, entry))
    try:
        subprocess.run(["ssh-keygen", "-Y", "sign", "-f", key, "-n", NAMESPACE, f.name], check=True)
        pathlib.Path(f.name + ".sig").replace(SIGS / f"{register}.{eid}.sig")
    finally:
        os.unlink(f.name)
    path.write_text(new_text)
    ok, msg = verify(register, entry)
    print(f"{register} {eid}: {'approved and verified' if ok else 'signed, but verification FAILED: ' + msg}")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    regs = load()
    if cmd == "check":
        errors, warnings = check(regs)
        for w in warnings:
            print(f"::warning::{w}")
        for e in errors:
            print(f"::error::{e}")
        n = sum(len(d.get("entries") or []) for d in regs.values())
        print(f"{len(regs)} registers, {n} entries; {len(errors)} error(s), {len(warnings)} warning(s)")
        sys.exit(1 if errors else 0)
    if cmd == "data":
        data(regs, sys.argv[2])
    elif cmd == "approve":
        if len(sys.argv) != 6 or sys.argv[4] != "--key":
            sys.exit("usage: registers.py approve REGISTER ID --key PATH")
        approve(regs, sys.argv[2], sys.argv[3], sys.argv[5])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
