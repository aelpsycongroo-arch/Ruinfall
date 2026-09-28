"""Tiny painterly icon toolkit: shapes are drawn as masks in a 0..100 coordinate
space, then shaded (gradient + bevel + specular), outlined and composited over a
glowing dark backdrop. Rendered at 2x and downsampled for anti-aliasing."""
import math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024          # working resolution
OUT = 512         # exported resolution
K = S / 100.0     # 0..100 units -> pixels


def clamp01(a):
    return np.clip(a, 0.0, 1.0)


def rgb(c):
    return np.array(c, dtype=np.float32) / 255.0


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def lighten(c, t):
    return mix(c, (255, 255, 255), t)


def darken(c, t):
    return mix(c, (0, 0, 0), t)


# ---------------------------------------------------------------- geometry
def tf(pts, ang=0.0, s=1.0, c=(50, 50), off=(0, 0), sx=None, sy=None):
    """Rotate (deg) / scale points about c, then translate by off."""
    a = math.radians(ang)
    ca, sa = math.cos(a), math.sin(a)
    sx = s if sx is None else sx
    sy = s if sy is None else sy
    out = []
    for x, y in pts:
        dx, dy = (x - c[0]) * sx, (y - c[1]) * sy
        out.append((c[0] + dx * ca - dy * sa + off[0], c[1] + dx * sa + dy * ca + off[1]))
    return out


def mirror_x(pts, cx=50):
    return [(2 * cx - x, y) for x, y in pts]


def arc_pts(cx, cy, rx, ry, a0, a1, n=40):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def bezier(p0, p1, p2, n=24, p3=None):
    out = []
    for i in range(n + 1):
        t = i / n
        if p3 is None:
            x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
            y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        else:
            x = (1 - t) ** 3 * p0[0] + 3 * (1 - t) ** 2 * t * p1[0] + 3 * (1 - t) * t * t * p2[0] + t ** 3 * p3[0]
            y = (1 - t) ** 3 * p0[1] + 3 * (1 - t) ** 2 * t * p1[1] + 3 * (1 - t) * t * t * p2[1] + t ** 3 * p3[1]
        out.append((x, y))
    return out


# ---------------------------------------------------------------- masks
def _new():
    return Image.new("L", (S, S), 0)


def _px(pts):
    return [(x * K, y * K) for x, y in pts]


def M_poly(pts):
    im = _new()
    ImageDraw.Draw(im).polygon(_px(pts), fill=255)
    return np.asarray(im, dtype=np.float32) / 255.0


def M_ell(cx, cy, rx, ry=None):
    ry = rx if ry is None else ry
    im = _new()
    ImageDraw.Draw(im).ellipse([(cx - rx) * K, (cy - ry) * K, (cx + rx) * K, (cy + ry) * K], fill=255)
    return np.asarray(im, dtype=np.float32) / 255.0


def M_line(pts, w, round_caps=True):
    im = _new()
    d = ImageDraw.Draw(im)
    p = _px(pts)
    d.line(p, fill=255, width=max(1, int(w * K)), joint="curve")
    if round_caps:
        r = w * K / 2
        for x, y in (p[0], p[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    return np.asarray(im, dtype=np.float32) / 255.0


def M_rect(x0, y0, x1, y1, r=0):
    im = _new()
    ImageDraw.Draw(im).rounded_rectangle([x0 * K, y0 * K, x1 * K, y1 * K], radius=r * K, fill=255)
    return np.asarray(im, dtype=np.float32) / 255.0


def M_ring(cx, cy, r, w):
    return clamp01(M_ell(cx, cy, r + w / 2) - M_ell(cx, cy, r - w / 2))


def U(*ms):
    out = np.zeros((S, S), np.float32)
    for m in ms:
        out = np.maximum(out, m)
    return out


def SUB(a, *bs):
    for b in bs:
        a = clamp01(a - b)
    return a


def INT(a, b):
    return np.minimum(a, b)


def blur(m, r):
    im = Image.fromarray((clamp01(m) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r * K)), dtype=np.float32) / 255.0


def dilate(m, r):
    size = max(3, int(r * K) * 2 + 1)
    im = Image.fromarray((clamp01(m) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.MaxFilter(size)), dtype=np.float32) / 255.0


# ---------------------------------------------------------------- materials
MAT = {
    "steel": ((170, 178, 192), (30, 33, 42), 0.55),
    "darksteel": ((105, 110, 124), (16, 17, 22), 0.4),
    "gold": ((250, 200, 90), (95, 50, 10), 0.6),
    "bronze": ((215, 140, 70), (60, 28, 10), 0.4),
    "silver": ((210, 218, 232), (60, 66, 82), 0.7),
    "leather": None,   # tinted from theme
    "wood": ((170, 118, 70), (55, 32, 16), 0.15),
    "bone": ((245, 238, 215), (130, 115, 90), 0.3),
    "stone": ((150, 145, 140), (45, 42, 40), 0.1),
    "dark": ((70, 62, 60), (14, 12, 12), 0.2),
    "cloth": None,
    "gem": None,
    "glow": None,
}

YY, XX = np.mgrid[0:S, 0:S].astype(np.float32) / S


class Canvas:
    def __init__(self, theme, seed=0):
        self.theme = theme
        self.rng = random.Random(seed)
        self.img = np.zeros((S, S, 3), np.float32)
        self.sil = np.zeros((S, S), np.float32)   # union of all object parts (for aura)

    # ---------------------------------------------------- compositing
    def over(self, color_arr, alpha):
        a = clamp01(alpha)[..., None]
        self.img = self.img * (1 - a) + color_arr * a

    def add(self, color, m, k=1.0):
        self.img = self.img + rgb(color)[None, None, :] * (clamp01(m) * k)[..., None]

    # ---------------------------------------------------- backdrop
    def backdrop(self, glow_center=(50, 48), glow=0.75, embers=26):
        th = self.theme
        base = np.array([0.055, 0.045, 0.045], np.float32)
        d = np.sqrt((XX - glow_center[0] / 100) ** 2 + (YY - glow_center[1] / 100) ** 2)
        g = np.exp(-(d / 0.33) ** 2) * glow * 0.8
        g2 = np.exp(-(d / 0.14) ** 2) * glow * 0.45
        col = rgb(th)
        self.img = base[None, None, :] + col[None, None, :] * (g * 0.9 + g2)[..., None]
        # smoky texture
        noise = np.random.RandomState(self.rng.randint(0, 10**6)).rand(64, 64).astype(np.float32)
        n = np.asarray(Image.fromarray((noise * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC), np.float32) / 255
        n = blur(n, 1.2)
        self.img *= (0.78 + 0.44 * n)[..., None]
        # embers / motes
        for _ in range(embers):
            x, y = self.rng.uniform(8, 92), self.rng.uniform(8, 92)
            r = self.rng.uniform(0.25, 0.8)
            m = M_ell(x, y, r)
            self.add(lighten(th, 0.5), blur(m, r * 0.9), 0.9)
            self.add(lighten(th, 0.8), m, 0.6)

    # ---------------------------------------------------- shaded part
    def part(self, m, mat="steel", color=None, light=(-0.6, -0.8), outline=0.9, bevel=1.0,
             spec=None, tex=0.0, grad=1.0, shadow=True):
        th = self.theme
        if mat == "leather":
            c = color or mix(th, (92, 54, 30), 0.25)
            hi, lo, sp = lighten(c, 0.35), darken(c, 0.58), 0.12
        elif mat == "cloth":
            c = color or th
            hi, lo, sp = lighten(c, 0.15), darken(c, 0.8), 0.05
        elif mat == "gem":
            c = color or th
            hi, lo, sp = lighten(c, 0.45), darken(c, 0.6), 0.7
        elif mat == "glow":
            c = color or th
            hi, lo, sp = lighten(c, 0.6), c, 0.2
        else:
            hi, lo, sp = MAT[mat]
            tint = color if color is not None else th
            k = 0.35 if color is not None else 0.12   # metals pick up the aura colour
            hi, lo = mix(hi, tint, k), mix(lo, tint, k)
        if spec is not None:
            sp = spec
        ys, xs = np.nonzero(m > 0.5)
        if len(xs) == 0:
            return
        x0, x1, y0, y1 = xs.min() / S, xs.max() / S, ys.min() / S, ys.max() / S
        lx, ly = light
        t = ((XX - x0) / max(x1 - x0, 1e-3) * -lx + (YY - y0) / max(y1 - y0, 1e-3) * -ly)
        t = clamp01(t / (abs(lx) + abs(ly)))
        t = 0.5 + (t - 0.5) * grad
        hi_a, lo_a = rgb(hi), rgb(lo)
        col = hi_a[None, None, :] * (1 - t[..., None]) + lo_a[None, None, :] * t[..., None]
        # bevel from blurred mask gradient
        mb = blur(m, 1.4)
        gy, gx = np.gradient(mb)
        sh = -(gx * lx + gy * ly) * S / 14.0 * bevel
        col = col + np.clip(sh, 0, 1)[..., None] * 0.3 - np.clip(-sh, 0, 1)[..., None] * 0.35
        # specular band
        if sp > 0:
            band = np.exp(-((t - 0.3) / 0.045) ** 2) * sp * 0.5
            col = col + band[..., None]
        if tex > 0:
            nz = np.random.RandomState(self.rng.randint(0, 10**6)).rand(S // 8, S // 8).astype(np.float32)
            nz = np.asarray(Image.fromarray((nz * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC), np.float32) / 255
            col = col * (1 - tex + 2 * tex * nz)[..., None]
        if shadow:
            sm = blur(np.roll(np.roll(m, int(1.6 * K), 0), int(1.2 * K), 1), 1.5)
            self.over(np.zeros_like(col), sm * 0.55)
        if outline > 0:
            ol = dilate(m, 0.55)
            self.over(np.full_like(col, 0.03), ol * outline)
        self.over(col, m)
        self.sil = np.maximum(self.sil, m)

    def glowline(self, m, color, core=(255, 255, 255), r=1.6, k=1.0):
        self.add(color, blur(m, r * 2.2), 0.9 * k)
        self.add(color, blur(m, r * 0.8), 1.0 * k)
        self.add(core, m, 0.8 * k)

    def aura(self, r=3.2, k=0.8, color=None):
        c = color or lighten(self.theme, 0.2)
        g = blur(dilate(self.sil, 0.6), r) - self.sil * 0.9
        self.add(c, clamp01(g), k)

    def rim(self, k=0.55, color=None):
        """Colored rim light on silhouette edges facing away from key light."""
        c = color or lighten(self.theme, 0.35)
        mb = blur(self.sil, 0.9)
        gy, gx = np.gradient(mb)
        rimm = clamp01((gx * 0.7 + gy * 0.3) * S / 7) * self.sil
        self.add(c, rimm, k)

    # ---------------------------------------------------- finishing
    def finish(self, frame=None):
        img = self.img
        # vignette
        d = np.sqrt((XX - 0.5) ** 2 + (YY - 0.5) ** 2)
        img = img * (1 - clamp01((d - 0.38) / 0.5) * 0.75)[..., None]
        # tone map: linear up to 0.7, soft shoulder above
        img = np.clip(img, 0, None)
        hi = img > 0.7
        img[hi] = 0.7 + 0.3 * (1 - np.exp(-(img[hi] - 0.7) / 0.3))
        img = clamp01(img)
        # frame: dark bevelled border with bronze inner line
        fr = frame or (150, 110, 60)
        b = 2.2 / 100
        edge = (XX < b) | (XX > 1 - b) | (YY < b) | (YY > 1 - b)
        img[edge] = img[edge] * 0.15 + np.array([0.04, 0.035, 0.03]) * 0.85
        inner = ((np.abs(XX - b) < 0.0035) | (np.abs(XX - (1 - b)) < 0.0035) |
                 (np.abs(YY - b) < 0.0035) | (np.abs(YY - (1 - b)) < 0.0035))
        inner &= (XX > b - 0.004) & (XX < 1 - b + 0.004) & (YY > b - 0.004) & (YY < 1 - b + 0.004)
        img[inner] = rgb(fr)
        im = Image.fromarray((img * 255).astype(np.uint8), "RGB")
        return im.resize((OUT, OUT), Image.LANCZOS)


# ---------------------------------------------------------------- FX helpers
def fx_flames(cv, base_y, x0, x1, height, rng, n=7, color=(255, 120, 30)):
    for i in range(n):
        x = x0 + (x1 - x0) * (i + rng.uniform(0.1, 0.9)) / n
        h = height * rng.uniform(0.6, 1.1)
        w = (x1 - x0) / n * rng.uniform(0.7, 1.3)
        lean = rng.uniform(-4, 4)
        pts = bezier((x - w, base_y), (x - w * 0.6, base_y - h * 0.55), (x + lean, base_y - h), 12) + \
            bezier((x + lean, base_y - h), (x + w * 0.6, base_y - h * 0.55), (x + w, base_y), 12)
        m = M_poly(pts)
        cv.add(color, blur(m, 2.2), 0.8)
        cv.add(color, m, 0.7)
        inner = M_poly(tf(pts, s=0.55, c=(x, base_y)))
        cv.add((255, 230, 140), blur(inner, 0.8), 0.9)


def fx_bolt(cv, p0, p1, rng, color=(120, 190, 255), segs=7, jitter=5, w=0.9, branches=1):
    pts = [p0]
    for i in range(1, segs):
        t = i / segs
        pts.append((p0[0] + (p1[0] - p0[0]) * t + rng.uniform(-jitter, jitter),
                    p0[1] + (p1[1] - p0[1]) * t + rng.uniform(-jitter, jitter)))
    pts.append(p1)
    cv.glowline(M_line(pts, w), color, r=1.4)
    for _ in range(branches):
        j = rng.randint(1, segs - 2)
        q = pts[j]
        end = (q[0] + rng.uniform(-14, 14), q[1] + rng.uniform(4, 14))
        cv.glowline(M_line([q, ((q[0] + end[0]) / 2 + rng.uniform(-3, 3), (q[1] + end[1]) / 2), end], w * 0.6), color, r=1.0, k=0.8)


def fx_sparkles(cv, rng, n=6, color=(255, 240, 200), area=(15, 15, 85, 85), size=(1.5, 3.5)):
    for _ in range(n):
        x, y = rng.uniform(area[0], area[2]), rng.uniform(area[1], area[3])
        s = rng.uniform(*size)
        star = M_poly([(x, y - s), (x + s * 0.18, y - s * 0.18), (x + s, y), (x + s * 0.18, y + s * 0.18),
                       (x, y + s), (x - s * 0.18, y + s * 0.18), (x - s, y), (x - s * 0.18, y - s * 0.18)])
        cv.add(color, blur(star, s * 0.35), 0.8)
        cv.add((255, 255, 255), star, 0.9)


def fx_drips(cv, rng, pts, color=(110, 220, 70)):
    for x, y in pts:
        l = rng.uniform(4, 8)
        m = U(M_line([(x, y), (x, y + l)], 1.1), M_ell(x, y + l + 0.8, 1.4, 1.8))
        cv.part(m, "gem", color=color, outline=0.6, spec=0.8)
        cv.add(color, blur(m, 1.4), 0.5)


def fx_snow(cv, cx, cy, r, color=(200, 235, 255), w=0.9):
    ms = []
    for k in range(6):
        a = math.radians(k * 60 - 90)
        ex, ey = cx + r * math.cos(a), cy + r * math.sin(a)
        ms.append(M_line([(cx, cy), (ex, ey)], w))
        for f in (0.55,):
            bx, by = cx + r * f * math.cos(a), cy + r * f * math.sin(a)
            for s in (-1, 1):
                b = a + s * math.radians(40)
                ms.append(M_line([(bx, by), (bx + r * 0.3 * math.cos(b), by + r * 0.3 * math.sin(b))], w * 0.8))
    cv.glowline(U(*ms), color, r=1.0, k=0.9)


def fx_swirl(cv, cx, cy, r, color, turns=1.6, w=1.0, k=0.9):
    pts = []
    for i in range(80):
        t = i / 79
        a = t * turns * 2 * math.pi
        rr = r * (0.2 + 0.8 * t)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    cv.glowline(M_line(pts, w), color, r=1.2, k=k)
