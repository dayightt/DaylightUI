"""Download the game's own UI code that the tests run, into tests/blizzard/.

It's Blizzard's code, so it's never committed (.gitignore). Pinned to one
commit of Gethe/wow-ui-source, branch `forever`, which matches the
WoW: Forever client line for line. After a game patch: set COMMIT to the
branch's newest commit (api.github.com/repos/Gethe/wow-ui-source/commits/forever),
run this, then run the whole test suite.

    py tools/fetch_blizzard.py

It also writes tests/blizzard/CooldownSets.lua: the game's Cooldown Manager
catalogue (which spells each class's rows hold), from wago.tools' tables for
WoW: Forever. The tables are kept in tools/bin/wago/ (git-ignored) and only
downloaded when missing; delete that folder after a game patch.
"""
import csv
import json
import os
import subprocess
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor

COMMIT = "e3ecc27b64d30fdc735a3f6579b866858f9f9df1"   # the pinned commit on the forever branch
REPO = "Gethe/wow-ui-source"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "blizzard")
FILES = [
    "Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua",
]
# The game's Cooldown Manager and the shared code it runs on (tests/cdmworld.lua
# loads them in this order).
BASE = "Interface/AddOns/Blizzard_SharedXMLBase/"
FILES += [BASE + name + ".lua" for name in (
    "Mixin", "TableUtil", "FunctionUtil", "EnumUtil", "Flags", "MathUtil", "SecureTypes", "ProxyUtil",
    "FrameUtil", "Pools", "CallbackRegistry", "GlobalCallbackRegistry", "CvarUtil", "AnchorUtil")]
FILES += [
    "Interface/AddOns/Blizzard_SharedXML/GridLayoutUtil.lua",
    "Interface/AddOns/Blizzard_SharedXML/LayoutFrame.lua",
    "Interface/AddOns/Blizzard_SharedXML/LayoutFrame.xml",
    "Interface/AddOns/Blizzard_FrameXMLUtil/Cooldown.lua",
    "Interface/AddOns/Blizzard_VisualAlerts/VisualAlertTarget.lua",
    "Interface/AddOns/Blizzard_ManagedFrameSystem/Shared/ManagedFrameSystem.lua",
]
VIEWER = "Interface/AddOns/Blizzard_CooldownViewer/"
FILES += [VIEWER + name for name in (
    "CooldownViewerSettingsConstants.lua", "CooldownViewerUtil.lua", "CooldownViewerSecure.lua",
    "CooldownViewerVisualAlertTarget.lua", "CooldownViewerAlert.lua", "CooldownViewerItemData.lua",
    "CooldownViewer.lua", "CooldownViewer.xml")]
# wago.tools tables (product wowf) behind tests/blizzard/CooldownSets.lua.
WAGO_URL = "https://wago.tools/db2/%s/csv?product=wowf"
WAGO_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin", "wago")
WAGO = ["CooldownSetSpell", "CooldownSetLinkedSpell", "SpellEffect", "SpellName"]
# SpellEffect.Effect values that make something which casts for you: a summon
# (28), a game object (50, 76, 104-107: traps), a pet (56), a totem (87-90).
SUMMON_EFFECTS = {28, 50, 56, 76, 87, 88, 89, 90, 104, 105, 106, 107}
# Every widget type's methods, for the stricter fake game (tests/widget_api.lua).
DOC_DIR = "Interface/AddOns/Blizzard_APIDocumentationGenerated/"


def is_widget_doc(name):
    """Widget types' method lists: Simple* (frames, textures, ...), FrameAPI*
    (Cooldown, GameTooltip, NamePlate, ...) and *FrameAPIDocumentation (Minimap)."""
    return name.endswith(".lua") and (name.startswith("Simple") or name.startswith("FrameAPI")
                                      or name.endswith("FrameAPIDocumentation.lua"))


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "DaylightUI-tests"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def download(paths, out):
    """Each path's file into out (several at once), and out/FILES.txt listing them."""
    os.makedirs(out, exist_ok=True)

    def one(p):
        name = os.path.basename(p)
        with open(os.path.join(out, name), "wb") as f:
            f.write(get(f"https://raw.githubusercontent.com/{REPO}/{COMMIT}/{p}"))
        return name

    with ThreadPoolExecutor(max_workers=16) as pool:
        names = list(pool.map(one, paths))
    with open(os.path.join(out, "FILES.txt"), "w") as f:
        f.write("\n".join(names) + "\n")
    return names


def tree_paths():
    """Every file path in the pinned commit. Cloud sessions can't reach
    api.github.com, so then git lists the tree (no file contents downloaded)."""
    try:
        tree = json.loads(get(f"https://api.github.com/repos/{REPO}/git/trees/{COMMIT}?recursive=1"))
        return [item["path"] for item in tree["tree"]]
    except Exception:
        tmp = tempfile.mkdtemp()
        git = lambda *a: subprocess.run(["git", "-C", tmp, *a], check=True, capture_output=True, text=True).stdout
        git("init", "-q")
        git("fetch", "-q", "--depth", "1", "--filter=blob:none", f"https://github.com/{REPO}.git", COMMIT)
        return git("ls-tree", "-r", "--name-only", "FETCH_HEAD").splitlines()


def wago(name):
    """One wago.tools table as rows, downloaded once into tools/bin/wago/."""
    path = os.path.join(WAGO_DIR, name + ".csv")
    if not os.path.exists(path):
        os.makedirs(WAGO_DIR, exist_ok=True)
        with open(path, "wb") as f:
            f.write(get(WAGO_URL % name))
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def cooldown_sets(out):
    """tests/blizzard/CooldownSets.lua: every row of the Cooldown Manager catalogue
    with its linked spells, the spell's name, whether the spell itself puts an
    aura on something (aura) and only ever on the caster (selfAura), which of
    its linked spells do (linkAuras), and whether it makes a totem, trap or
    other summon (summons), whose auras aren't cast by the player."""
    links, names, auras, summons, leads = {}, {}, {}, set(), {}
    for r in wago("CooldownSetLinkedSpell"):
        links.setdefault(r["CooldownSetSpellID"], []).append(int(r["SpellID"]))
    for r in wago("SpellName"):
        names[r["ID"]] = r["Name_lang"]
    for r in wago("SpellEffect"):
        if int(r["EffectAura"]) > 0:
            auras.setdefault(r["SpellID"], []).append(int(r["ImplicitTarget_0"]))
        if int(r["Effect"]) in SUMMON_EFFECTS:
            summons.add(r["SpellID"])
        # A spell that only teaches or triggers another (Mana Spring Totem's row).
        if int(r["Effect"]) in (36, 64) and int(r["EffectTriggerSpell"]) > 0:
            leads.setdefault(r["SpellID"], []).append(r["EffectTriggerSpell"])
    rows = sorted(wago("CooldownSetSpell"), key=lambda r: int(r["ID"]))
    lines = ["-- Made by tools/fetch_blizzard.py from wago.tools (product wowf). Not committed.", "return {"]
    for r in rows:
        targets = auras.get(r["SpellID"])
        name = names.get(r["SpellID"], "").replace("\\", "\\\\").replace('"', '\\"')
        fields = [
            "id = %d" % int(r["ID"]), "set = %d" % int(r["CooldownSetID"]), "spell = %d" % int(r["SpellID"]),
            "category = %d" % int(r["Category"]), "flags = %d" % int(r["Flags"]), "order = %d" % int(r["OrderIndex"]),
            "spellCategory = %d" % int(r["SpellCategoryID"]), "equipSlot = %d" % int(r["EquipSlot"]),
            'name = "%s"' % name,
            "aura = %s" % ("true" if targets else "false"),
            "selfAura = %s" % ("true" if targets and all(t == 1 for t in targets) else "false"),
            "links = { %s }" % ", ".join(str(i) for i in links.get(r["ID"], [])),
            "linkAuras = { %s }" % ", ".join(str(i) for i in links.get(r["ID"], []) if str(i) in auras),
            "summons = %s" % ("true" if r["SpellID"] in summons
                              or any(t in summons for t in leads.get(r["SpellID"], [])) else "false"),
        ]
        lines.append("    { " + ", ".join(fields) + " },")
    lines.append("}")
    with open(os.path.join(out, "CooldownSets.lua"), "w", encoding="utf-8", newline=chr(10)) as f:
        f.write(chr(10).join(lines) + chr(10))
    return len(rows)


def main():
    paths, api = list(FILES), []
    for p in tree_paths():
        name = os.path.basename(p)
        if p.startswith(DOC_DIR) and name.endswith(".lua"):
            (paths if is_widget_doc(name) else api).append(p)
    names = download(paths, OUT)
    # Every other API doc (global functions, events, structures): which values
    # the client makes secret, for the fake game (tests/secret_api.lua).
    api_names = download(api, os.path.join(OUT, "api"))
    with open(os.path.join(OUT, "SOURCE.txt"), "w") as f:
        f.write(f"{REPO}@{COMMIT}\n")
    print(f"tests/blizzard: {len(names)} files, api/: {len(api_names)} files, from {REPO}@{COMMIT[:7]}")
    print(f"tests/blizzard/CooldownSets.lua: {cooldown_sets(OUT)} rows of the Cooldown Manager catalogue")


if __name__ == "__main__":
    main()
