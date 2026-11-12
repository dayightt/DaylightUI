"""Download the game's own UI code that the tests run, into tests/blizzard/.

It's Blizzard's code, so it's never committed (.gitignore). Pinned to one
commit of Gethe/wow-ui-source, branch `forever`, which matches the
WoW: Forever client line for line. After a game patch: set COMMIT to the
branch's newest commit (api.github.com/repos/Gethe/wow-ui-source/commits/forever),
run this, then run the whole test suite.

    py tools/fetch_blizzard.py
"""
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


if __name__ == "__main__":
    main()
