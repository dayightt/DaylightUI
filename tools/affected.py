"""Runs the tests that cover what you changed, instead of guessing an area name.

From the repo root:
  py tools/affected.py              your uncommitted changes (new files too): picks the tests and runs them
  py tools/affected.py --list       only says which tests and why, runs nothing
  py tools/affected.py --since HEAD~3   what changed since that commit (and uncommitted)
  py tools/affected.py --files Book/Training.lua Threat.lua   these files only (only yours, when
                                    other sessions have changes in the same folder)

It runs what a tester would for that fix: the area's own tests and the quick
checks, never the whole suite, never the slow sweeps, and not the tests that
load every module (they cost the most and rarely see a small fix; the whole
suite has them). A shared core file (Style, Core, DB, the window
kit...) or one no test covers says so: the whole --par once, before that push.
Docs only: test_hygiene (it checks docs too).
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "tests")

# A module folder -> the stub.Load flag that loads it.
MODULE_FLAGS = {
    "DaylightUI_UnitFrames": "module", "DaylightUI_ActionBars": "actionbars", "DaylightUI_Buffs": "buffs",
    "DaylightUI_Skins": "skins", "DaylightUI_Bags": "bags", "DaylightUI_Nameplates": "nameplates",
    "DaylightUI_Tooltip": "tooltip", "DaylightUI_QoL": "qol", "DaylightUI_Chat": "chat",
    "DaylightUI_InfoPanel": "infopanel", "DaylightUI_Quests": "quests",
}
# Core windows: a folder -> the word its tests and world file are named by.
CORE_WINDOWS = {"Book": "book", "Character": "char", "Npc": "npc", "Inspect": "inspect", "Craft": "craft",
                "Lfg": "lfg", "Mail": "mail", "Social": "social", "Legacy": "legacy"}
# Core files every area draws on. A change there can break any of them, so they
# get the whole --par once before their push, never on every step.
WIDE = {"Core.lua", "DB.lua", "Pixel.lua", "Style.lua", "Motion.lua", "Tips.lua", "GameFonts.lua", "Fade.lua",
        "Movers.lua", "Gradients.lua", "Taint.lua", "Media.lua", "Locales/Locales.lua",
        "Options/Widgets.lua", "Options/Registry.lua", "Options/Theme.lua",
        "Windows/Frame.lua", "Windows/Feel.lua", "Windows/Parts.lua", "Windows/Keys.lua", "Windows/Follow.lua"}
# The fake game itself. Nearly every bug fix teaches it a rule, so it must not
# mean the whole suite: the fix's own tests prove the rule, and these prove it loads.
TEST_RIG = {"tests/stub.lua", "tests/run.lua", "tests/blizzard.lua", "tests/secret_api.lua", "tests/widget_api.lua"}
RIG_TESTS = ["test_core", "test_stub_reuse"]
# Run for any shipped Lua change: they check every file (look rules, banned
# patterns), in under 10 s together.
ALWAYS_LUA = ["test_hygiene", "test_guards"]
# test_locale draws every page in every language (37 s, the second slowest), so it
# only runs for a change to the text itself.
LOCALE_WORDS = re.compile(r"\bL\[")
SLOW = {"test_group", "test_group_sweep", "test_hostile_bg", "test_hostile_fight", "test_hostile_party",
        "test_hostile_testmode"}
# A test loading this many modules is about the whole UI, not any one area, so
# it's left to the whole suite (test_options, test_installer, test_lag...).
BROAD = 3
SKIP_DIRS = ("Media/", "screenshots/", "Libs/", "DaylightUI_Dev/", ".claude/", "tools/")


def git(*args):
    out = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                         errors="replace")
    return out.stdout


def changed_files(since):
    files = set()
    base = since or "HEAD"
    for line in git("diff", "--name-only", base).splitlines():
        files.add(line.strip())
    for line in git("ls-files", "--others", "--exclude-standard").splitlines():
        files.add(line.strip())
    return sorted(f for f in files if f)


def changed_text(since, files):
    """The added and removed lines of the changed Lua files (new files whole)."""
    lua = [f for f in files if f.endswith(".lua") and not f.startswith(SKIP_DIRS)]
    if not lua:
        return ""
    diff = git("diff", "-U0", since or "HEAD", "--", *lua)
    text = "\n".join(l for l in diff.splitlines() if l[:1] in "+-" and l[:3] not in ("+++", "---"))
    tracked = set(git("ls-files", "--", *lua).split())
    for f in lua:
        if f not in tracked:
            text += read(os.path.join(ROOT, f))
    return text


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def load_tests():
    """Each test file: its text, the world files it requires, the flags it loads."""
    names = re.findall(r'"(test_[%\w]+)"', read(os.path.join(TESTS, "run.lua")))
    worlds = {}
    for f in os.listdir(TESTS):
        if f.endswith("world.lua") or f == "hostile.lua":
            worlds[f[:-4]] = read(os.path.join(TESTS, f))
    tests = {}
    for name in names:
        text = read(os.path.join(TESTS, name + ".lua"))
        if not text:
            continue
        req = set(re.findall(r'require\("(\w+)"\)', text))
        full = text + "".join(worlds.get(r, "") for r in req)
        flags = sum(1 for flag in MODULE_FLAGS.values() if loads_flag(full, flag))
        tests[name] = {"text": text, "full": full, "requires": req, "broad": flags >= BROAD}
    return tests


def loads_flag(full, flag):
    return re.search(r"\b" + flag + r"\s*=\s*true", full) is not None


def pick(files, tests, text_changed):
    picked, wide = {}, []

    def add(test, reason, always=False):
        # The slow sweeps and the broad tests load every module, so they would match
        # every file. The whole suite runs them.
        if test in SLOW or (tests.get(test, {}).get("broad") and not always):
            return
        if test in tests and test not in picked:
            picked[test] = reason

    for f in files:
        name = os.path.basename(f)
        stem = name[:-4] if name.endswith(".lua") else name
        top = f.split("/")[0]
        if f.startswith(SKIP_DIRS) or f.startswith("docs/archive/"):
            if f.startswith("Media/"):
                add("test_media", f)
            continue
        if f.endswith(".md") or f.endswith(".pkgmeta"):
            add("test_docs", f + " (the notes are checked)")
            continue
        if f in TEST_RIG:
            for t in RIG_TESTS:
                add(t, f)
            continue
        if f in WIDE:
            wide.append(f)
            for t in ALWAYS_LUA:
                add(t, "every shipped Lua change", True)
            for t, d in tests.items():
                if f in d["text"] or t == "test_" + stem.lower():
                    add(t, f)
            continue
        if f.startswith("tests/"):
            if stem in tests:
                add(stem, f)
            elif stem in ("guards_allow",):
                add("test_guards", f)
            elif stem == "locale_keys":
                add("test_locale", f)
            else:   # a world or helper file: every test that requires it
                hits = [t for t, d in tests.items() if stem in d["requires"]]
                for t in hits:
                    add(t, f)
            continue
        if f.endswith(".toc"):
            add("test_hygiene", f)
            add("test_guards", f)
            continue
        if not f.endswith(".lua"):
            wide.append(f)
            continue
        for t in ALWAYS_LUA:
            add(t, "every shipped Lua change", True)
        if top == "Locales":
            add("test_locale", f, True)
            continue
        if name == "PatchNotes.lua":
            add("test_patchnotes", f)
            continue
        hits = []
        if top in MODULE_FLAGS:
            flag = MODULE_FLAGS[top]
            hits = [t for t, d in tests.items() if loads_flag(d["full"], flag)]
        elif top in CORE_WINDOWS:
            word = CORE_WINDOWS[top]
            hits = [t for t, d in tests.items() if word in t or (word + "world") in d["requires"]]
        # Any test naming the file itself ("Book/Training.lua", "Threat.lua")
        # or, for a core root file, its namespace (DUI.Threat).
        # A test naming the file is about it, however much else it loads.
        # The bare name counts only at the root: "Window.lua" in a test is some
        # other folder's, and Npc/Window.lua used to pull in 5 unrelated tests.
        named = False
        for t, d in tests.items():
            if f in d["text"] or ("/" not in f and name in d["text"] and len(stem) > 4):
                add(t, f, True)
                named = True
            elif "/" not in f and re.search(r"\bDUI\." + re.escape(stem) + r"\b", d["text"]):
                add(t, f, True)
                named = True
        if not hits and not named:
            wide.append(f)      # no test of its own, so only the whole suite sees it
        for t in hits:
            add(t, f)
    if text_changed:
        add("test_locale", "text in L[...] changed", True)
    return picked, wide


def main():
    args = sys.argv[1:]
    only_list = "--list" in args
    since = None
    if "--since" in args:
        i = args.index("--since")
        since = args[i + 1] if i + 1 < len(args) else None
    if "--files" in args:
        files = [a.replace("\\", "/") for a in args[args.index("--files") + 1:] if not a.startswith("--")]
    else:
        files = changed_files(since)
    if not files:
        print("Nothing changed (try --since HEAD~1 for the last commit).")
        return 0
    tests = load_tests()
    text_changed = LOCALE_WORDS.search(changed_text(since, files)) is not None
    picked, wide = pick(files, tests, text_changed)

    if not picked:
        print("No tests cover these changes (" + ", ".join(files[:6]) + ").")
    else:
        print(f"{len(picked)} test file(s) for {len(files)} changed file(s):")
        for t in sorted(picked):
            print(f"  {t:24} {picked[t]}")
    if wide:
        print("Shared, or no test of its own (" + ", ".join(wide[:6]) + (" ..." if len(wide) > 6 else "") +
              "): run the whole `luajit tests/run.lua --par` once before this push.")
    if not picked:
        return 0
    cmd = ["luajit", "tests/run.lua", "--par", "--only"] + sorted(picked)
    print("> " + " ".join(cmd))
    if only_list:
        return 0
    sys.stdout.flush()
    run = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = (run.stdout + run.stderr).strip().splitlines()
    print("\n".join(out[-30:]))
    return run.returncode


if __name__ == "__main__":
    sys.exit(main())
