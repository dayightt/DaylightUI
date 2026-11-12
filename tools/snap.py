"""A picture of a window of ours, drawn from the fake game: no game needed.

From the repo root:
  py tools/snap.py                      the recipes (ui, options, book, social...)
  py tools/snap.py book                 the spellbook -> tests/snaps/book.png
  py tools/snap.py options unitframes   a recipe's argument (an options page id)
  py tools/snap.py --file my.lua [arg]  your own setup (see tools/snap.lua)
  --full    the whole screen, not cropped to the window
  --boxes   every frame's outline over it, to check layout
  --gif     the opening as an animation -> tests/snaps/<name>.gif (a moment
            before, the window's glide and fade, then the recipe's play if it
            has one), 30 frames a second, the same drawing as the picture

tools/snap.lua opens it in the fake game and writes what's shown; this lays
it out the way the client does (anchors, sizes, scale, 1080p) and draws it
with our real fonts and textures (Media/). What it can't draw: the game's
own art (only Daylight UI's Media files and solid colors), atlases, models;
the game's icons (by file id) show as plain stand-in tiles. Text is measured
with the real fonts both here and in the fake game while it lays the window
out (tests/snaps/metrics.lua), so text-sized pieces sit as in game. Masks
(the angled ends) are applied.
"""
import json
import os
import re
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "snaps")
STRATA = ["WORLD", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP"]
LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 4}
DEFAULT_FONT = os.path.join(ROOT, "Media", "fonts", "Expressway.ttf")
WHITE = {"interface\\buttons\\white8x8", "interface\\buttons\\white8x8.blp"}


class Snap:
    def __init__(self, data, boxes):
        self.nodes = {n["id"]: n for n in data["nodes"]}
        self.phys = data["screen"]
        self.k = self.phys[1] / 768.0   # px per UI unit at effective scale 1
        self.rects, self.busy = {}, set()
        self.fonts, self.images = {}, {}
        self.boxes = boxes
        self.skipped = {"game art": 0, "no place": 0}
        self.children = {}
        for n in data["nodes"]:
            self.children.setdefault(n.get("parent"), []).append(n["id"])
        # A status bar's fill takes the bar's rect cut to its value.
        self.fills = {}
        for n in data["nodes"]:
            b = n.get("bar")
            if b and b.get("fill"):
                self.fills[b["fill"]] = n["id"]

    # Layout ----------------------------------------------------------
    def font(self, n):
        f = n.get("font") or [None, 12, ""]
        size = max(1, round((f[1] or 12) * (n.get("scale") or 1) * self.k))
        path = self.file(f[0], (".ttf", ".otf")) or DEFAULT_FONT
        key = (path, size)
        if key not in self.fonts:
            try:
                self.fonts[key] = ImageFont.truetype(path, size)
            except OSError:
                self.fonts[key] = ImageFont.truetype(DEFAULT_FONT, size)
        return self.fonts[key]

    def text_size(self, n):
        lines = clean(n.get("text") or "").split("\n")
        font = self.font(n)
        w = max((font.getlength("".join(t for t, _ in parse(l))) for l in lines), default=0)
        asc, desc = font.getmetrics()
        return w, (asc + desc) * len(lines)

    def rect(self, nid):
        """(left, bottom, right, top) in screen px, y up; None if it can't be placed."""
        if nid in self.rects:
            return self.rects[nid]
        n = self.nodes.get(nid)
        if not n or nid in self.busy:
            return None
        self.busy.add(nid)
        r = self._rect(n)
        self.busy.discard(nid)
        self.rects[nid] = r
        return r

    def _rect(self, n):
        if n.get("name") == "UIParent" or n.get("parent") is None and not n["points"]:
            return (0, 0, self.phys[0], self.phys[1])
        s = (n.get("scale") or 1) * self.k
        if n["id"] in self.fills:
            return self.fill_rect(self.nodes[self.fills[n["id"]]])
        parent = self.nodes.get(n.get("parent"))
        pts = n["points"]
        if not pts and parent and parent.get("scrollChild") == n["id"]:
            pr = self.rect(parent["id"])
            if not pr:
                return None
            w, h = max(0, n.get("w") or 0) * s, max(0, n.get("h") or 0) * s
            left, top = pr[0] - parent.get("hscroll", 0) * s, pr[3] + parent.get("vscroll", 0) * s
            return (left, top - h, left + w, top)
        L = R = B = T = cx = cy = None
        for p in pts:
            point, rel, relp, x, y = p
            if point == "ALL":
                rr = self.rect(rel or n.get("parent"))
                if not rr:
                    return None
                L, B, R, T = rr
                continue
            rr = self.rect(rel if rel else n.get("parent"))
            if not rr:
                return None
            ax, ay = anchor(rr, relp)
            ax, ay = ax + x * s, ay + y * s
            if "LEFT" in point:
                L = ax
            elif "RIGHT" in point:
                R = ax
            else:
                cx = ax
            if "TOP" in point:
                T = ay
            elif "BOTTOM" in point:
                B = ay
            else:
                cy = ay
        w, h = max(0, n.get("w") or 0) * s, max(0, n.get("h") or 0) * s
        if n["type"] in ("FontString",) and (not w or not h):
            tw, th = self.text_size(n)
            w = w or ((R - L) if L is not None and R is not None else tw)
            h = h or th
        if L is None and R is None and cx is None:
            return None
        if B is None and T is None and cy is None:
            return None
        if L is None:
            L = R - w if R is not None else cx - w / 2
        if R is None:
            R = L + w
        if B is None:
            B = T - h if T is not None else cy - h / 2
        if T is None:
            T = B + h
        return (L, B, R, T)

    def fill_rect(self, bar):
        r = self.rect(bar["id"])
        if not r:
            return None
        b = bar["bar"]
        span = (b["max"] - b["min"]) or 1
        t = min(1, max(0, (b["value"] - b["min"]) / span))
        L, B, R, T = r
        if b.get("orientation") == "VERTICAL":
            return (L, T - (T - B) * t, R, T) if b.get("reverse") else (L, B, R, B + (T - B) * t)
        return (R - (R - L) * t, B, R, T) if b.get("reverse") else (L, B, L + (R - L) * t, T)

    # Drawing ---------------------------------------------------------
    def file(self, path, exts=(".tga", ".png", ".blp")):
        if not isinstance(path, str):
            return None
        p = path.replace("\\", "/")
        m = re.search(r"(?i)addons/daylightui[^/]*/(.*)$", p)
        if not m:
            return None
        rel = m.group(1)
        for f in [rel] + [rel + e for e in exts]:
            full = os.path.join(ROOT, f)
            if os.path.isfile(full) and not full.lower().endswith(".blp"):
                return full
        return None

    def image(self, path):
        if path not in self.images:
            try:
                self.images[path] = Image.open(path).convert("RGBA")
            except OSError:
                self.images[path] = None
        return self.images[path]

    def box(self, r):
        """Screen rect (y up) -> image box (y down), ints."""
        L, B, R, T = r
        H = self.phys[1]
        return (round(L), round(H - T), round(R), round(H - B))

    def clip_of(self, n):
        """The clip box from every clipping frame above n (scroll frames, clipsChildren)."""
        box = None
        p = self.nodes.get(n.get("parent"))
        while p:
            if p.get("clips"):
                r = self.rect(p["id"])
                if r:
                    b = self.box(r)
                    box = b if box is None else (max(box[0], b[0]), max(box[1], b[1]), min(box[2], b[2]), min(box[3], b[3]))
            p = self.nodes.get(p.get("parent"))
        return box

    def texture(self, n, w, h):
        """The region's pixels (RGBA, w x h), or None for art we can't draw."""
        tex = n.get("texture")
        bar = self.nodes.get(self.fills.get(n["id"]))
        if bar and not tex and not n.get("color"):   # a bar's fill: the bar's texture and color
            tex = bar["bar"].get("texture")
            if not n.get("vertex") and not n.get("gradient") and bar["bar"].get("color"):
                n = dict(n, vertex=bar["bar"]["color"])
        if n.get("textureId") and not tex and not n.get("color"):
            # The game's own icon (a file id): a stand-in tile, so its place shows.
            img = Image.new("RGBA", (w, h), (92, 84, 74, 255))
            d = ImageDraw.Draw(img)
            d.rectangle((0, 0, w - 1, h // 2), fill=(118, 108, 94, 255))
            d.line((0, h - 1, w - 1, 0), fill=(140, 128, 110, 255))
            return tint(img, n["vertex"]) if n.get("vertex") else img
        if n.get("color"):
            img = Image.new("RGBA", (w, h), tuple(round(c * 255) for c in n["color"]))
        elif tex and tex.lower() in WHITE:
            img = Image.new("RGBA", (w, h), (255, 255, 255, 255))
        elif tex:
            path = self.file(tex)
            src = path and self.image(path)
            if src is None:
                self.skipped["game art"] += 1
                return None
            tc = n.get("texCoord")
            if tc and len(tc) >= 4:
                if len(tc) == 8:   # ULx, ULy, LLx, LLy, URx, URy, LRx, LRy
                    xs, ys = tc[0::2], tc[1::2]
                    tc = [min(xs), max(xs), min(ys), max(ys)]
                sw, sh = src.size
                l, r, t, b = tc[0] * sw, tc[1] * sw, tc[2] * sh, tc[3] * sh
                flipx, flipy = l > r, t > b
                crop = src.crop((round(min(l, r)), round(min(t, b)), max(round(max(l, r)), round(min(l, r)) + 1),
                                 max(round(max(t, b)), round(min(t, b)) + 1)))
                if flipx:
                    crop = crop.transpose(Image.FLIP_LEFT_RIGHT)
                if flipy:
                    crop = crop.transpose(Image.FLIP_TOP_BOTTOM)
                src = crop
            img = src.resize((w, h), Image.BILINEAR)
        else:
            return None
        if n.get("desaturated"):
            a = img.getchannel("A")
            img = img.convert("L").convert("RGBA")
            img.putalpha(a)
        g = n.get("gradient")
        if g and g[1] and g[2]:
            img = tint_gradient(img, g[0], g[1], g[2])
        elif n.get("vertex"):
            img = tint(img, n["vertex"])
        return img

    def mask(self, n, box, img):
        """Each mask's alpha over the region. Outside a mask's own rect: its edge
        pixels carried on (CLAMP, the client's default) or nothing (CLAMPTOBLACK...)."""
        from PIL import ImageChops
        for mid in n.get("masks") or []:
            m = self.nodes.get(mid)
            r = m and self.rect(mid)
            path = m and self.file(m.get("texture"))
            src = path and self.image(path)
            if not r or src is None:
                continue
            mb = self.box(r)
            mw, mh = max(1, mb[2] - mb[0]), max(1, mb[3] - mb[1])
            a = src.getchannel("A")
            ma = (a if a.getextrema() != (255, 255) else src.convert("L")).resize((mw, mh), Image.BILINEAR)
            full = clamp_place(ma, mb, box, (m.get("wrap") or "CLAMP").upper() == "CLAMP")
            img.putalpha(ImageChops.multiply(img.getchannel("A"), full))
        return img

    def draw_text(self, canvas, n, box, alpha):
        text = clean(n.get("text") or "")
        if not text.strip():
            return
        font = self.font(n)
        col = n.get("textColor") or [1, 1, 1, 1]
        w = box[2] - box[0]
        lines = []
        for para in text.split("\n"):
            lines += wrap(font, para, w) if n.get("wrap") is not False and w > 0 else [para]
        asc, desc = font.getmetrics()
        lh = asc + desc
        total = lh * len(lines)
        jv = n.get("justifyV") or "MIDDLE"
        y = box[1] if jv == "TOP" else box[3] - total if jv == "BOTTOM" else (box[1] + box[3] - total) / 2
        flags = ((n.get("font") or [None, None, ""])[2] or "").upper()
        stroke = 1 if "OUTLINE" in flags else 0
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        so = n.get("shadowOffset")
        sc = n.get("shadowColor") or [0, 0, 0, 1]
        for line in lines:
            runs = parse(line)
            lw = font.getlength("".join(t for t, _ in runs))
            jh = n.get("justifyH") or "CENTER"
            x = box[0] if jh == "LEFT" else box[2] - lw if jh == "RIGHT" else (box[0] + box[2] - lw) / 2
            for t, c in runs:
                c = c or col
                rgba = tuple(round(v * 255) for v in c[:3]) + (round(255 * (c[3] if len(c) > 3 else 1) * alpha),)
                if so and (so[0] or so[1]):
                    sh = tuple(round(v * 255) for v in sc[:3]) + (round(255 * (sc[3] if len(sc) > 3 else 1) * alpha),)
                    d.text((x + so[0] * self.k, y - so[1] * self.k), t, font=font, fill=sh)
                d.text((x, y), t, font=font, fill=rgba, stroke_width=stroke, stroke_fill=(0, 0, 0, rgba[3]))
                x += font.getlength(t)
            y += lh
        canvas.alpha_composite(layer)

    def order(self, n):
        owner = self.nodes.get(n.get("parent")) if n["type"] in ("Texture", "FontString", "MaskTexture", "Line") else n
        owner = owner or n
        strata = STRATA.index(owner.get("strata")) if owner.get("strata") in STRATA else STRATA.index("MEDIUM")
        return (strata, owner.get("level") or 0, LAYERS.get(n.get("layer") or "ARTWORK", 2), n.get("sublevel") or 0, n["id"])

    def render(self, crop_id, full):
        canvas = Image.new("RGBA", tuple(self.phys), (24, 22, 20, 255))
        drawn = [n for n in self.nodes.values() if n.get("visible") and n["type"] in ("Texture", "FontString")
                 and (n.get("alpha") or 0) > 0.01 and (n.get("layer") or "ARTWORK") != "HIGHLIGHT"]
        drawn.sort(key=self.order)
        for n in drawn:
            r = self.rect(n["id"])
            if not r:
                self.skipped["no place"] += 1
                continue
            box = self.box(r)
            w, h = box[2] - box[0], box[3] - box[1]
            if w <= 0 or h <= 0 or w > 8000 or h > 8000:
                continue
            clip = self.clip_of(n)
            if n["type"] == "FontString":
                if clip:
                    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
                    self.draw_text(layer, n, box, n.get("alpha", 1))
                    canvas.alpha_composite(cut(layer, clip))
                else:
                    self.draw_text(canvas, n, box, n.get("alpha", 1))
                continue
            img = self.texture(n, w, h)
            if img is None:
                continue
            img = self.mask(n, box, img)
            a = n.get("alpha", 1)
            if a < 1:
                img.putalpha(img.getchannel("A").point(lambda v: round(v * a)))
            layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            layer.paste(img, (box[0], box[1]))
            if clip:
                layer = cut(layer, clip)
            if (n.get("blend") or "BLEND") == "ADD":
                from PIL import ImageChops
                rgb = ImageChops.multiply(layer, Image.merge("RGBA", [layer.getchannel("A")] * 4))
                canvas = Image.alpha_composite(canvas, Image.new("RGBA", canvas.size, (0, 0, 0, 0)))
                canvas = ImageChops.add(canvas, rgb.convert("RGBA"))
            else:
                canvas.alpha_composite(layer)
        if self.boxes:
            d = ImageDraw.Draw(canvas)
            for n in self.nodes.values():
                if n.get("visible") and n["type"] not in ("Texture", "FontString", "MaskTexture"):
                    r = self.rect(n["id"])
                    if r and (r[2] - r[0]) > 1 and (r[3] - r[1]) > 1:
                        b = self.box(r)
                        d.rectangle(b, outline=(255, 0, 200, 160))
                        if n.get("name"):
                            d.text((b[0] + 2, b[1] + 1), n["name"], fill=(255, 120, 230, 220))
        if crop_id and not full:
            r = self.rect(crop_id)
            if r:
                b = self.box(r)
                m = 24
                canvas = canvas.crop((max(0, b[0] - m), max(0, b[1] - m), min(self.phys[0], b[2] + m),
                                      min(self.phys[1], b[3] + m)))
        return canvas.convert("RGB")


def clamp_place(ma, mb, box, clamp):
    """The mask ma (placed at image box mb) over the region at box: a region-sized L image."""
    w, h = box[2] - box[0], box[3] - box[1]
    out = Image.new("L", (w, h), 0)
    ox, oy = mb[0] - box[0], mb[1] - box[1]
    if not clamp:
        out.paste(ma, (ox, oy))
        return out
    mw, mh = ma.size
    # Every region pixel takes the mask pixel nearest to it (edges carried on).
    xs = [min(mw - 1, max(0, x - ox)) for x in range(w)]
    ys = [min(mh - 1, max(0, y - oy)) for y in range(h)]
    x0, x1 = xs[0], xs[-1] + 1
    y0, y1 = ys[0], ys[-1] + 1
    inner = ma.crop((x0, y0, max(x1, x0 + 1), max(y1, y0 + 1)))
    # Columns/rows before and after the mask repeat its edge.
    left = max(0, ox) if ox > 0 else 0
    top = max(0, oy) if oy > 0 else 0
    cw = inner.size[0]
    ch = inner.size[1]
    right = w - left - cw
    bottom = h - top - ch
    out.paste(inner, (left, top))
    if left > 0:
        out.paste(inner.crop((0, 0, 1, ch)).resize((left, ch)), (0, top))
    if right > 0:
        out.paste(inner.crop((cw - 1, 0, cw, ch)).resize((right, ch)), (left + cw, top))
    if top > 0:
        out.paste(out.crop((0, top, w, top + 1)).resize((w, top)), (0, 0))
    if bottom > 0:
        out.paste(out.crop((0, top + ch - 1, w, top + ch)).resize((w, bottom)), (0, top + ch))
    return out


def anchor(r, point):
    L, B, R, T = r
    x = L if "LEFT" in point else R if "RIGHT" in point else (L + R) / 2
    y = T if "TOP" in point else B if "BOTTOM" in point else (B + T) / 2
    return x, y


def tint(img, c):
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r.point(lambda v: v * c[0]), g.point(lambda v: v * c[1]),
                                b.point(lambda v: v * c[2]), a.point(lambda v: v * (c[3] if len(c) > 3 else 1))))


def tint_gradient(img, orient, a, b):
    w, h = img.size
    grad = Image.new("RGBA", (w, h))
    px = grad.load()
    vertical = (orient or "").upper() == "VERTICAL"
    for i in range(h if vertical else w):
        t = (1 - i / max(1, h - 1)) if vertical else i / max(1, w - 1)   # vertical: a = bottom, b = top
        c = tuple(round(255 * (a[k] + (b[k] - a[k]) * t)) for k in range(4))
        if vertical:
            for x in range(w):
                px[x, i] = c
        else:
            for y in range(h):
                px[i, y] = c
    from PIL import ImageChops
    return ImageChops.multiply(img, grad)


def cut(layer, clip):
    mask = Image.new("L", layer.size, 0)
    ImageDraw.Draw(mask).rectangle((clip[0], clip[1], clip[2] - 1, clip[3] - 1), fill=255)
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    out.paste(layer, (0, 0), mask)
    return out


def clean(text):
    """Game text codes out: textures and atlases (|T |A), |n new lines, || a bar."""
    text = re.sub(r"\|T.-\|t|\|T[^|]*\|t", " ", text)
    text = re.sub(r"\|A[^|]*\|a", " ", text)
    text = re.sub(r"\|H[^|]*\|h", "", text).replace("|h", "")
    return text.replace("|n", "\n").replace("||", "|")


def parse(line):
    """[(text, color or None)] from |cAARRGGBB ... |r runs."""
    runs, color, i = [], None, 0
    buf = ""
    while i < len(line):
        if line.startswith("|c", i) and re.match(r"[0-9a-fA-F]{8}", line[i + 2:i + 10]):
            if buf:
                runs.append((buf, color))
                buf = ""
            h = line[i + 2:i + 10]
            color = [int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, int(h[6:8], 16) / 255, int(h[0:2], 16) / 255]
            i += 10
        elif line.startswith("|r", i):
            if buf:
                runs.append((buf, color))
                buf = ""
            color = None
            i += 2
        else:
            buf += line[i]
            i += 1
    if buf:
        runs.append((buf, color))
    return runs


def wrap(font, para, width):
    plain = "".join(t for t, _ in parse(para))
    if font.getlength(plain) <= width + 1:
        return [para]
    words, lines, cur = para.split(" "), [], ""
    for w in words:
        test = (cur + " " + w) if cur else w
        if font.getlength("".join(t for t, _ in parse(test))) <= width + 1 or not cur:
            cur = test
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def write_metrics():
    """Every font's letter widths and line height, per point of size, for snap.lua."""
    out = ["return { default = \"expressway.ttf\", fonts = {"]
    fonts = os.path.join(ROOT, "Media", "fonts")
    for f in sorted(os.listdir(fonts)):
        if not f.lower().endswith((".ttf", ".otf")):
            continue
        try:
            font = ImageFont.truetype(os.path.join(fonts, f), 100)
        except OSError:
            continue
        asc, desc = font.getmetrics()
        widths = [font.getlength(chr(c)) / 100 for c in range(32, 127)]
        ws = ", ".join(f"[{c}] = {w:.4f}" for c, w in zip(range(32, 127), widths))
        out.append(f'  ["{f.lower()}"] = {{ a = {asc / 100:.4f}, d = {desc / 100:.4f}, avg = {sum(widths) / len(widths):.4f}, w = {{ {ws} }} }},')
    out.append("} }")
    with open(os.path.join(OUT, "metrics.lua"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(out))


def gif(folder, name, full, boxes):
    """Each frame snap.lua wrote, drawn, cropped to one box that holds the
    window in every frame (it glides), and joined into <name>.gif."""
    frames, box, last = [], None, None
    for f in sorted(os.listdir(folder)):
        with open(os.path.join(folder, f), encoding="utf-8") as fh:
            raw = fh.read()
        if raw == last:   # nothing moved this step: the same picture
            frames.append(frames[-1])
            continue
        last, data = raw, json.loads(raw)
        snap = Snap(data, boxes)
        frames.append(snap.render(None, True))
        r = data.get("crop") and snap.rect(data["crop"])
        if r and not full:
            b = snap.box(r)
            box = b if not box else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    if box:
        m, W, H = 24, frames[0].size[0], frames[0].size[1]
        box = (max(0, box[0] - m), max(0, box[1] - m), min(W, box[2] + m), min(H, box[3] + m))
        frames = [f.crop(box) for f in frames]
    path = os.path.join(OUT, name + ".gif")
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=33, loop=0, optimize=False)
    print(f"{os.path.relpath(path, ROOT)}: {len(frames)} frames, {frames[0].size[0]}x{frames[0].size[1]}")


def main():
    args = sys.argv[1:]
    full, boxes, as_gif = "--full" in args, "--boxes" in args, "--gif" in args
    rest = [a for a in args if a not in ("--full", "--boxes", "--gif")]
    os.makedirs(OUT, exist_ok=True)
    write_metrics()
    name = (rest[0] if rest[0] != "--file" else (re.search(r"([\w\-]+)\.lua$", rest[1]).group(1) if len(rest) > 1 else "custom")) if rest else None
    env = dict(os.environ)
    folder = os.path.join(OUT, f"{name}_frames")
    if as_gif and name:
        shutil.rmtree(folder, ignore_errors=True)
        os.makedirs(folder)
        env["SNAP_GIF"] = os.path.relpath(folder, ROOT).replace("\\", "/")
    run = subprocess.run(["luajit", "tools/snap.lua", *rest], cwd=ROOT, capture_output=True, text=True,
                         encoding="utf-8", errors="replace", env=env)
    print((run.stdout + run.stderr).strip()[-1500:])
    if run.returncode != 0 or not rest:
        return run.returncode or 1
    if as_gif:
        gif(folder, name, full, boxes)
        shutil.rmtree(folder, ignore_errors=True)
        return 0
    with open(os.path.join(OUT, name + ".json"), encoding="utf-8") as fh:
        data = json.load(fh)
    snap = Snap(data, boxes)
    img = snap.render(data.get("crop"), full)
    path = os.path.join(OUT, name + ".png")
    img.save(path)
    print(f"{os.path.relpath(path, ROOT)}: {img.size[0]}x{img.size[1]}"
          f" (not drawn: {snap.skipped['game art']} game art, {snap.skipped['no place']} unplaced)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
