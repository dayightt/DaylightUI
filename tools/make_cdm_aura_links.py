"""Writes DaylightUI_ActionBars/CdmAuraLinks.lua from the game client's own tables.

For each class spell (SpellClassOptions family set), the auras it puts up under
another spell id:
  - a spell it triggers that applies an aura (Arcane Concentration -> Clearcasting)
  - an aura spell with the same name (Improved Stormstrike -> its buff 1238931)

Input: four .db2 files extracted from the client (CASCExplorer, DBFilesClient):
  spelleffect.db2  spellname.db2  spellclassoptions.db2
Run after a patch that changes spells:
  python tools/make_cdm_aura_links.py <folder with the .db2 files>
"""

import os
import struct
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "DaylightUI_ActionBars", "CdmAuraLinks.lua")

# SpellEffect columns, found from known pairs in the data (Arcane Concentration
# 11213 triggers Clearcasting 12536 through aura 42).
EFF_AURA, EFF_EFFECT, EFF_TRIGGER = 0, 3, 15
APPLY_AURAS = {6, 35, 65, 128, 129}       # apply aura, to the party, raid, friend, enemy
TRIGGERS = {64}                           # trigger spell
TRIGGER_AURAS = {23, 42, 226}             # periodic trigger, proc trigger, periodic dummy trigger
SHELL_AURAS = TRIGGER_AURAS | {4}         # and dummy
WEAPON_ENCHANTS = {54, 360}               # temporary weapon enchant; 360 on the imbue casts (Rockbiter 8017)
MAX_CLASSLESS = 2
# SpellClassOptions columns: spell id, family set.
SCO_SPELL, SCO_FAMILY = 0, 2


def bits(buf, at, n):
    byte, shift = at >> 3, at & 7
    v = int.from_bytes(buf[byte:byte + ((shift + n + 7) >> 3)], "little")
    return (v >> shift) & ((1 << n) - 1)


def load(path):
    """Every readable record of a WDC5 table: dict(id, cols, parent, name_at)."""
    b = open(path, "rb").read()
    if b[:4] != b"WDC5":
        raise SystemExit("%s: not a WDC5 table" % path)
    o = 136
    rec_count, field_count, rec_size, str_size = struct.unpack_from("<4I", b, o)
    flags, id_index = struct.unpack_from("<HH", b, o + 36)
    _, _, _, fsi_size, common_size, pallet_size, section_count = struct.unpack_from("<7I", b, o + 40)
    o += 68
    sections = []
    for _ in range(section_count):
        k, off, recs, strs, _, ids, rel, _, copy = struct.unpack_from("<Q8I", b, o)
        sections.append((k, off, recs, strs, ids, rel, copy))
        o += 40
    if flags & 1:
        raise SystemExit("%s: sparse tables aren't read" % path)
    fields = [struct.unpack_from("<hH", b, o + 4 * i) for i in range(field_count)]
    o += 4 * field_count
    fsi = [struct.unpack_from("<HHIIIII", b, o + 24 * i) for i in range(fsi_size // 24)]
    o += fsi_size
    pallet = b[o:o + pallet_size]
    o += pallet_size
    common, c = [], o
    for f in fsi:
        m = {}
        if f[3] == 2:
            for k in range(f[2] // 8):
                rid, val = struct.unpack_from("<II", b, c + 8 * k)
                m[rid] = val
            c += f[2]
        common.append(m)
    o += common_size
    for s in sections:
        if s[0]:
            o += 4 + 4 * struct.unpack_from("<I", b, o)[0]

    def width(i, f):
        if f[3] == 0:
            size = (32 - fields[i][0]) // 8
            return (f[1] // 8) // size if size else 0
        return f[6] if f[3] == 4 else 1

    colpos, at, palpos, p = [], 0, [], 0
    for i, f in enumerate(fsi):
        colpos.append(at)
        at += width(i, f)
        palpos.append(p)
        if f[3] in (3, 4):
            p += f[2]

    # Strings: an offset counts from the field's place in all sections' records
    # laid end to end, into all sections' string tables laid end to end.
    all_recs = sum(s[2] for s in sections) * rec_size
    str_starts, before = [], 0
    for s in sections:
        str_starts.append((before, s[1] + s[2] * rec_size, s[3]))
        before += s[3]

    def string_at(g, field_byte, value):
        pos = g * rec_size + field_byte + value - all_recs
        for start, at_file, size in str_starts:
            if start <= pos < start + size:
                a = at_file + pos - start
                return b[a:b.index(b"\0", a)].decode("utf-8", "replace")
        return None

    rows, g = [], 0
    for key, off, recs, strs, ids_size, rel, copy in sections:
        locked = key != 0 and not any(b[off:off + 64])
        q = off + recs * rec_size + strs
        ids = struct.unpack_from("<%dI" % (ids_size // 4), b, q)
        q += ids_size
        copies = [struct.unpack_from("<II", b, q + 8 * k) for k in range(copy)]
        q += 8 * copy
        parents = {}
        if rel:
            n = struct.unpack_from("<I", b, q)[0]
            for k in range(n):
                fid, idx = struct.unpack_from("<II", b, q + 12 + 8 * k)
                parents[idx] = fid
        mine = {}
        for i in range(recs):
            if locked:
                continue
            rec = b[off + i * rec_size:off + (i + 1) * rec_size]
            cols = []
            for fi, f in enumerate(fsi):
                boff, bsize, _, kind, x1, _, x3 = f
                if kind == 0:
                    size = (32 - fields[fi][0]) // 8
                    for k in range(width(fi, f)):
                        st = boff // 8 + k * size
                        cols.append(int.from_bytes(rec[st:st + size], "little"))
                elif kind in (1, 5):
                    v = bits(rec, boff, bsize)
                    if kind == 5 and v >> (bsize - 1):
                        v -= 1 << bsize
                    cols.append(v)
                elif kind == 2:
                    cols.append(None)
                elif kind == 3:
                    cols.append(struct.unpack_from("<I", pallet, palpos[fi] + 4 * bits(rec, boff, bsize))[0])
                elif kind == 4:
                    at = palpos[fi] + 4 * bits(rec, boff, bsize) * x3
                    cols.extend(struct.unpack_from("<%dI" % x3, pallet, at))
            rid = ids[i] if ids else cols[colpos[id_index]]
            for fi, f in enumerate(fsi):
                if f[3] == 2:
                    cols[colpos[fi]] = common[fi].get(rid, f[4])
            row = dict(id=rid, cols=cols, parent=parents.get(i), g=g + i)
            mine[rid] = row
            rows.append(row)
        for new, old in copies:
            if old in mine:
                rows.append(dict(mine[old], id=new))
        g += recs
    return rows, string_at, fsi


def main(folder):
    def path(n):
        return os.path.join(folder, n + ".db2")

    name_rows, string_at, name_fsi = load(path("spellname"))
    names = {}
    for r in name_rows:
        n = string_at(r["g"], name_fsi[0][0] // 8, r["cols"][0])
        if n:
            names[r["id"]] = n
    by_name = {}
    for sid, n in names.items():
        by_name.setdefault(n, []).append(sid)

    effects = {}
    for r in load(path("spelleffect"))[0]:
        if r["parent"] is not None:
            effects.setdefault(r["parent"], []).append(r["cols"])

    family = {}
    for r in load(path("spellclassoptions"))[0]:
        family[r["cols"][SCO_SPELL]] = r["cols"][SCO_FAMILY]

    def applies_aura(sid):
        return any(c[EFF_EFFECT] in APPLY_AURAS for c in effects.get(sid, []))

    def enchants(sid):
        return any(c[EFF_EFFECT] in WEAPON_ENCHANTS for c in effects.get(sid, []))

    # A talent-style passive: every effect is a dummy or trigger aura on itself,
    # so what it does shows up as another spell (Improved Stormstrike, Poised).
    def shell(sid):
        cs = effects.get(sid, [])
        return bool(cs) and all(c[EFF_EFFECT] in APPLY_AURAS and c[EFF_AURA] in SHELL_AURAS for c in cs)

    links = {}
    for sid, fam in family.items():
        if not fam or sid not in names:
            continue
        out = set()
        for c in effects.get(sid, []):
            t = c[EFF_TRIGGER]
            if t and t != sid and applies_aura(t) and not shell(t) and (
                    c[EFF_EFFECT] in TRIGGERS or (c[EFF_EFFECT] in APPLY_AURAS and c[EFF_AURA] in TRIGGER_AURAS)):
                out.add(t)
        # A weapon imbue's name (Windfury Weapon) marks the enchant on the weapon,
        # which is no aura. Its same-name auras are procs (the extra swing's
        # attack power), so they'd light the piece only for that swing. Only the
        # class's own imbue cast counts: a rune item's enchant (Cobra Slayer) doesn't.
        imbue = any(enchants(o) and family.get(o) == fam for o in by_name.get(names[sid], []))
        if shell(sid) and not imbue:
            same = [o for o in by_name.get(names[sid], []) if o != sid and applies_aura(o) and not shell(o)]
            out.update(o for o in same if family.get(o) == fam)
            # Classless ones count only when few: NPCs share names like Lightning Shield.
            classless = [o for o in same if not family.get(o)]
            if len(classless) <= MAX_CLASSLESS:
                out.update(classless)
        if out:
            links[sid] = sorted(out)

    lines = [
        "-- Made by tools/make_cdm_aura_links.py from the game client's SpellEffect,",
        "-- SpellName and SpellClassOptions tables. Don't edit by hand: run the tool again.",
        "--",
        "-- Class spell id -> the auras it puts up under other ids: a spell it triggers",
        "-- (Arcane Concentration -> Clearcasting) or an aura of the same name (Improved",
        "-- Stormstrike -> its buff).",
        "",
        "local _, ns = ...",
        "",
        "ns.CdmAuraLinks = {",
    ]
    for sid in sorted(links):
        lines.append("    [%d] = { %s }, -- %s" % (sid, ", ".join(str(a) for a in links[sid]), names[sid]))
    lines += ["}", ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("%d class spells linked, %d aura ids -> %s" % (len(links), sum(map(len, links.values())), os.path.normpath(OUT)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
