"""Render all icons to ./out/<Id>.png (512x512) plus a labelled contact sheet.
Usage: python3 render.py            (everything)
       python3 render.py Id Id ...  (just those, sheet of those)"""
import os, sys, zlib
from multiprocessing import Pool
from PIL import Image, ImageDraw
from iconkit import Canvas
import shapes as SH
from circles import draw_circle
from items import ITEMS, SKILLS

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "out")


def render(key):
    seed = zlib.crc32(key.encode())
    if key in SKILLS:
        e = SKILLS[key]
        cv = Canvas(e["theme"], seed=seed)
        cv.backdrop(glow=0.8)
        e["draw"](cv, {})
        cv.aura(k=0.4)
    else:
        e = ITEMS[key]
        cv = Canvas(e["theme"], seed=seed)
        cv.backdrop(glow=e["glow"], embers=not e.get("boot"))
        if e.get("boot"):
            draw_circle(cv, e["boot"], k=0.85)
        for fn, kw in e["pre"]:
            fn(cv, **kw)
        getattr(SH, e["shape"])(cv, dict(e["o"]))
        cv.aura(k=0.5)
        for fn, kw in e["post"]:
            fn(cv, **kw)
    cv.finish().save(os.path.join(OUTDIR, key + ".png"), optimize=True)
    return key


def sheet(keys, path, cols=10, cell=150):
    rows = (len(keys) + cols - 1) // cols
    im = Image.new("RGB", (cols * cell, rows * (cell + 16)), (12, 10, 10))
    d = ImageDraw.Draw(im)
    for i, k in enumerate(keys):
        x, y = (i % cols) * cell, (i // cols) * (cell + 16)
        im.paste(Image.open(os.path.join(OUTDIR, k + ".png")).resize((cell - 6, cell - 6), Image.LANCZOS), (x + 3, y + 3))
        d.text((x + 4, y + cell - 1), k[:24], fill=(220, 200, 160))
    im.save(path)


ALL = list(ITEMS) + list(SKILLS)

if __name__ == "__main__":
    os.makedirs(OUTDIR, exist_ok=True)
    keys = sys.argv[1:] or ALL
    with Pool(os.cpu_count()) as p:
        for k in p.imap_unordered(render, keys):
            print("ok", k, flush=True)
    sheet(keys, os.path.join(HERE, "sheet.png"), cols=10 if len(keys) > 12 else len(keys))
