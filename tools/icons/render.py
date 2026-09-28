"""Render every icon in items.ITEMS to ./out/<Id>.png (512x512) plus a contact sheet.
Usage: python3 render.py [Id ...]"""
import os, sys, zlib
from multiprocessing import Pool
from PIL import Image, ImageDraw
from iconkit import Canvas
import shapes as SH
from items import ITEMS, FX

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "out")


def render(item_id):
    theme, shape, opts, pre, post = ITEMS[item_id]
    cv = Canvas(theme, seed=zlib.crc32(item_id.encode()))
    cv.backdrop()
    for f in pre:
        FX[f](cv, cv.rng)
    getattr(SH, shape)(cv, dict(opts))
    cv.aura()
    cv.rim()
    for f in post:
        FX[f](cv, cv.rng)
    cv.finish().save(os.path.join(OUTDIR, item_id + ".png"), optimize=True)
    return item_id


def sheet(ids, path, cols=10, cell=150):
    rows = (len(ids) + cols - 1) // cols
    im = Image.new("RGB", (cols * cell, rows * (cell + 16)), (12, 10, 10))
    d = ImageDraw.Draw(im)
    for i, k in enumerate(ids):
        x, y = (i % cols) * cell, (i // cols) * (cell + 16)
        im.paste(Image.open(os.path.join(OUTDIR, k + ".png")).resize((cell - 6, cell - 6), Image.LANCZOS), (x + 3, y + 3))
        d.text((x + 4, y + cell - 1), k[:22], fill=(220, 200, 160))
    im.save(path)


if __name__ == "__main__":
    os.makedirs(OUTDIR, exist_ok=True)
    ids = sys.argv[1:] or list(ITEMS)
    with Pool(os.cpu_count()) as p:
        for k in p.imap_unordered(render, ids):
            print("ok", k, flush=True)
    sheet(list(ITEMS) if not sys.argv[1:] else ids, os.path.join(HERE, "sheet.png"))
