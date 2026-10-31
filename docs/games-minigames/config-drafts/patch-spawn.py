import gzip, os, shutil, struct, sys

path = "/data/world/level.dat"
if not os.path.exists(path):
    print("no level.dat yet (fresh world): nothing to patch")
    sys.exit(0)
raw = gzip.open(path).read()
out = bytearray(raw)
changed = False
for name, want in (("SpawnX", 0), ("SpawnY", 64), ("SpawnZ", 0)):
    key = b"\x03" + struct.pack(">H", len(name)) + name.encode()
    if raw.count(key) != 1:
        sys.exit("unexpected level.dat layout for " + name)
    off = raw.find(key) + len(key)
    if struct.unpack(">i", raw[off:off + 4])[0] != want:
        out[off:off + 4] = struct.pack(">i", want)
        changed = True
if not changed:
    print("world spawn already 0,64,0")
    sys.exit(0)
if not os.path.exists(path + ".pre-games"):
    shutil.copy2(path, path + ".pre-games")
with gzip.open(path + ".tmp", "wb") as f:
    f.write(out)
os.replace(path + ".tmp", path)
print("world spawn set to 0,64,0")
