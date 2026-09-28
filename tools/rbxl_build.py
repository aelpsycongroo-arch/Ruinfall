"""Write the scripts in src/ back into a binary Roblox place (.rbxl).

    python3 tools/rbxl_build.py rainfall.rbxl src/ rainfall.rbxl

For every src/**/*.luau file (Rojo layout: Name.server.luau = Script, Name.client.luau =
LocalScript, Name.luau = ModuleScript, folder/init.luau = the folder's own script):
  * an existing script at that Explorer path gets its Source replaced;
  * a missing script is created, cloned from another script of the same class (fresh
    UniqueId / HistoryId / ScriptGuid), under its parent (which must already exist).
Everything else in the place (parts, UI, assets, other scripts) is copied byte for byte.
Changed chunks are written uncompressed, which Roblox reads fine.
"""
import os, random, struct, sys, uuid

import lz4.block
import zstandard

SUFFIX = {".server.luau": "Script", ".client.luau": "LocalScript", ".luau": "ModuleScript"}
WIDTH = {0x03: 4, 0x04: 4, 0x12: 4, 0x1B: 8, 0x1C: 4, 0x1F: 16, 0x21: 8}  # interleaved fixed-width types


# ------------------------------------------------------------------ primitives
def deinterleave(data, count, width):
    return [bytes(data[k * count + j] for k in range(width)) for j in range(count)]


def interleave(values, width):
    count = len(values)
    out = bytearray(width * count)
    for j, v in enumerate(values):
        for k in range(width):
            out[k * count + j] = v[k]
    return bytes(out)


def zz(v):  # untransform
    return (v >> 1) ^ -(v & 1)


def unzz(v):  # transform
    return (v << 1) ^ (v >> 31) if v < 0 else v << 1


def read_refs(data, count):
    acc, out = 0, []
    for raw in deinterleave(data, count, 4):
        acc += zz(int.from_bytes(raw, "big"))
        out.append(acc)
    return out


def write_refs(refs):
    prev, vals = 0, []
    for r in refs:
        d = r - prev
        prev = r
        vals.append((unzz(d) & 0xFFFFFFFF).to_bytes(4, "big"))
    return interleave(vals, 4)


def rstr(b, p):
    n, = struct.unpack_from("<I", b, p)
    return b[p + 4:p + 4 + n], p + 4 + n


def wstr(s):
    return struct.pack("<I", len(s)) + s


# ------------------------------------------------------------------ file model
class Chunk:
    def __init__(self, name, raw_header, raw, body):
        self.name, self.raw_header, self.raw, self.body = name, raw_header, raw, body
        self.dirty = False

    def encode(self):
        if not self.dirty:
            return self.raw_header + self.raw
        return self.name + struct.pack("<III", 0, len(self.body), 0) + self.body


def load(path):
    d = open(path, "rb").read()
    assert d[:8] == b"<roblox!"
    header = bytearray(d[:32])
    p, chunks = 32, []
    while p < len(d):
        name = d[p:p + 4]
        clen, ulen = struct.unpack_from("<II", d, p + 4)
        raw_header = d[p:p + 16]
        p += 16
        if clen == 0:
            raw = d[p:p + ulen]
            body = raw
            p += ulen
        else:
            raw = d[p:p + clen]
            p += clen
            body = zstandard.ZstdDecompressor().decompress(raw, max_output_size=ulen) if raw[:4] == b"\x28\xb5\x2f\xfd" \
                else lz4.block.decompress(raw, uncompressed_size=ulen)
        chunks.append(Chunk(name, raw_header, raw, bytearray(body)))
        if name == b"END\x00":
            break
    return header, chunks


class Place:
    def __init__(self, path):
        self.header, self.chunks = load(path)
        self.classes = {}  # id -> {Name, Refs, Chunk, Service}
        self.inst = {}  # ref -> {Class, Props{}, Parent}
        for c in self.chunks:
            if c.name == b"INST":
                b = c.body
                cid, = struct.unpack_from("<I", b, 0)
                name, q = rstr(b, 4)
                service = b[q]
                count, = struct.unpack_from("<I", b, q + 1)
                refs = read_refs(b[q + 5:], count)
                self.classes[cid] = dict(Name=name.decode(), Refs=refs, Chunk=c, Service=service, Tail=b[q + 5 + 4 * count:])
                for r in refs:
                    self.inst[r] = dict(Class=name.decode(), Props={}, Parent=None)
        self.props = {}  # (cid, propName) -> {Type, Values(list of raw per instance), Chunk}
        for c in self.chunks:
            if c.name == b"PROP":
                b = c.body
                cid, = struct.unpack_from("<I", b, 0)
                pname, q = rstr(b, 4)
                t = b[q]
                q += 1
                refs = self.classes[cid]["Refs"]
                n = len(refs)
                entry = dict(Type=t, Chunk=c, Name=pname.decode(), Cid=cid)
                if t == 0x01:
                    vals = []
                    for _ in range(n):
                        s, q = rstr(b, q)
                        vals.append(bytes(s))
                    entry["Values"] = vals
                    if pname in (b"Name", b"Source"):
                        for r, v in zip(refs, vals):
                            self.inst[r]["Props"][pname.decode()] = v
                elif t == 0x02:
                    entry["Values"] = [bytes([b[q + i]]) for i in range(n)]
                elif t in WIDTH:
                    entry["Values"] = deinterleave(b[q:], n, WIDTH[t])
                else:
                    entry["Values"] = None  # untouched type (we never rewrite this chunk)
                self.props[(cid, pname.decode())] = entry
            elif c.name == b"PRNT":
                b = c.body
                count, = struct.unpack_from("<I", b, 1)
                kids = read_refs(b[5:], count)
                parents = read_refs(b[5 + 4 * count:], count)
                self.prnt = dict(Chunk=c, Kids=kids, Parents=parents)
                for k, pa in zip(kids, parents):
                    self.inst[k]["Parent"] = None if pa == -1 else pa

    # ---------------------------------------------------------------- lookup
    def name(self, ref):
        return self.inst[ref]["Props"].get("Name", b"?").decode("utf-8", "replace")

    def path(self, ref):
        parts = []
        while ref is not None:
            parts.append(self.name(ref))
            ref = self.inst[ref]["Parent"]
        return "/".join(reversed(parts))

    def find(self, path):
        for ref in self.inst:
            if self.path(ref) == path:
                return ref
        return None

    def cid_of(self, class_name):
        for cid, c in self.classes.items():
            if c["Name"] == class_name:
                return cid
        return None

    # ---------------------------------------------------------------- edits
    def set_source(self, ref, source):
        cls = self.inst[ref]["Class"]
        cid = self.cid_of(cls)
        idx = self.classes[cid]["Refs"].index(ref)
        entry = self.props[(cid, "Source")]
        entry["Values"][idx] = source
        entry["Dirty"] = True
        self.inst[ref]["Props"]["Source"] = source

    def add(self, class_name, name, parent_ref, source):
        cid = self.cid_of(class_name)
        cls = self.classes[cid]
        template_index = 0
        new_ref = max(self.inst) + 1
        cls["Refs"].append(new_ref)
        cls["Dirty"] = True
        for (pcid, pname), entry in self.props.items():
            if pcid != cid:
                continue
            if entry["Values"] is None:
                raise SystemExit("cannot clone property %s.%s of type 0x%02x" % (class_name, pname, entry["Type"]))
            value = entry["Values"][template_index]
            if pname == "Name":
                value = name.encode()
            elif pname == "Source":
                value = source
            elif pname == "ScriptGuid":
                value = ("{" + str(uuid.uuid4()).upper() + "}").encode()
            elif pname in ("UniqueId", "HistoryId"):
                value = bytes(random.getrandbits(8) for _ in range(16))
            elif pname == "Disabled":
                value = b"\x00"
            entry["Values"].append(value)
            entry["Dirty"] = True
        self.inst[new_ref] = dict(Class=class_name, Props={"Name": name.encode(), "Source": source}, Parent=parent_ref)
        self.prnt["Kids"].append(new_ref)
        self.prnt["Parents"].append(parent_ref)
        self.prnt["Dirty"] = True
        count, = struct.unpack_from("<i", self.header, 20)
        struct.pack_into("<i", self.header, 20, count + 1)
        return new_ref

    # ---------------------------------------------------------------- save
    def save(self, path):
        for cid, cls in self.classes.items():
            if cls.get("Dirty"):
                c = cls["Chunk"]
                c.body = bytearray(struct.pack("<I", cid) + wstr(cls["Name"].encode()) + bytes([cls["Service"]]) +
                                   struct.pack("<I", len(cls["Refs"])) + write_refs(cls["Refs"]) +
                                   ((bytes(cls["Tail"]) + bytes(len(cls["Refs"]) - len(cls["Tail"]))) if cls["Service"] else b""))
                c.dirty = True
        for (cid, pname), entry in self.props.items():
            if entry.get("Dirty"):
                t = entry["Type"]
                if t == 0x01:
                    data = b"".join(wstr(v) for v in entry["Values"])
                elif t == 0x02:
                    data = b"".join(entry["Values"])
                else:
                    data = interleave(entry["Values"], WIDTH[t])
                c = entry["Chunk"]
                c.body = bytearray(struct.pack("<I", cid) + wstr(pname.encode()) + bytes([t]) + data)
                c.dirty = True
        if self.prnt.get("Dirty"):
            c = self.prnt["Chunk"]
            c.body = bytearray(b"\x00" + struct.pack("<I", len(self.prnt["Kids"])) + write_refs(self.prnt["Kids"]) +
                               write_refs([-1 if p is None else p for p in self.prnt["Parents"]]))
            c.dirty = True
        with open(path, "wb") as f:
            f.write(bytes(self.header))
            for c in self.chunks:
                f.write(c.encode())


# ------------------------------------------------------------------ src -> place
def scripts_in(src):
    for root, _, files in os.walk(src):
        for fn in sorted(files):
            if not fn.endswith(".luau"):
                continue
            for suffix, cls in SUFFIX.items():
                if fn.endswith(suffix):
                    stem = fn[: -len(suffix)]
                    break
            rel = os.path.relpath(os.path.join(root, fn), src).replace(os.sep, "/")
            parts = rel.split("/")[:-1]
            if stem == "init":
                path = "/".join(parts)
            else:
                path = "/".join(parts + [stem])
            yield path, cls, os.path.join(root, fn)


def build(place_in, src, place_out):
    place = Place(place_in)
    changed = added = same = 0
    pending = []
    for path, cls, file in scripts_in(src):
        source = open(file, "rb").read()
        ref = place.find(path)
        if ref is not None:
            if place.inst[ref]["Class"] != cls:
                raise SystemExit("%s is a %s in the place but %s in src" % (path, place.inst[ref]["Class"], cls))
            if place.inst[ref]["Props"].get("Source") != source:
                place.set_source(ref, source)
                changed += 1
                print("updated", path)
            else:
                same += 1
        else:
            pending.append((path, cls, source))
    for path, cls, source in pending:
        parent_path, name = path.rsplit("/", 1)
        parent = place.find(parent_path)
        if parent is None:
            raise SystemExit("parent %s of new script %s does not exist in the place" % (parent_path, path))
        place.add(cls, name, parent, source)
        added += 1
        print("added  ", path, "(" + cls + ")")
    place.save(place_out)
    print("done: %d updated, %d added, %d unchanged -> %s" % (changed, added, same, place_out))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    build(*sys.argv[1:])
