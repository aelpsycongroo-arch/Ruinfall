"""Painterly icon toolkit (v2).

Shapes are masks drawn in a 0..100 coordinate space. Each part is lit as a rounded
volume (normals from a blurred height field), gets a thin ink outline and a coloured
back-light, and is composited over a smoky glowing backdrop. Rendered at 1024 px and
downsampled to 512 px for anti-aliasing."""
import math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = 512
K = S / 100.0

YY, XX = np.mgrid[0:S, 0:S].astype(np.float32) / S * 100.0   # 0..100 coords


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


def sat(c, k=1.3):
    m = sum(c) / 3
    return tuple(int(max(0, min(255, m + (v - m) * k))) for v in c)


# ================================================================ geometry
def tf(pts, ang=0.0, s=1.0, c=(50, 50), off=(0, 0), sx=None, sy=None):
    a = math.radians(ang)
    ca, sa = math.cos(a), math.sin(a)
    sx = s if sx is None else sx
    sy = s if sy is None else sy
    return [(c[0] + ((x - c[0]) * sx) * ca - ((y - c[1]) * sy) * sa + off[0],
             c[1] + ((x - c[0]) * sx) * sa + ((y - c[1]) * sy) * ca + off[1]) for x, y in pts]


def mirror_x(pts, cx=50):
    return [(2 * cx - x, y) for x, y in pts]


def arc_pts(cx, cy, rx, ry, a0, a1, n=48):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def bez(*p, n=24):
    """Quadratic (3 pts) or cubic (4 pts) Bezier."""
    out = []
    for i in range(n + 1):
        t = i / n
        if len(p) == 3:
            a, b, c = p
            out.append(((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * b[0] + t * t * c[0],
                        (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * b[1] + t * t * c[1]))
        else:
            a, b, c, d = p
            out.append(((1 - t) ** 3 * a[0] + 3 * (1 - t) ** 2 * t * b[0] + 3 * (1 - t) * t * t * c[0] + t ** 3 * d[0],
                        (1 - t) ** 3 * a[1] + 3 * (1 - t) ** 2 * t * b[1] + 3 * (1 - t) * t * t * c[1] + t ** 3 * d[1]))
    return out


def ribbon(spine, widths):
    """Closed outline around a polyline with per-point half widths (tapering shapes)."""
    n = len(spine)
    L, R = [], []
    for i, (x, y) in enumerate(spine):
        x2, y2 = spine[min(i + 1, n - 1)]
        x1, y1 = spine[max(i - 1, 0)]
        dx, dy = x2 - x1, y2 - y1
        d = math.hypot(dx, dy) or 1
        nx, ny = -dy / d, dx / d
        w = widths(i / (n - 1)) if callable(widths) else widths[i]
        L.append((x + nx * w, y + ny * w))
        R.append((x - nx * w, y - ny * w))
    return L + R[::-1]


# ================================================================ masks
def _new():
    return Image.new("L", (S, S), 0)


def _px(pts):
    return [(x * K, y * K) for x, y in pts]


def _arr(im):
    return np.asarray(im, dtype=np.float32) / 255.0


def M_poly(pts):
    im = _new()
    ImageDraw.Draw(im).polygon(_px(pts), fill=255)
    return _arr(im)


def M_ell(cx, cy, rx, ry=None, ang=0):
    ry = rx if ry is None else ry
    if ang:
        return M_poly(tf(arc_pts(cx, cy, rx, ry, 0, 360, 64), ang=ang, c=(cx, cy)))
    im = _new()
    ImageDraw.Draw(im).ellipse([(cx - rx) * K, (cy - ry) * K, (cx + rx) * K, (cy + ry) * K], fill=255)
    return _arr(im)


def M_line(pts, w, caps=True):
    im = _new()
    d = ImageDraw.Draw(im)
    p = _px(pts)
    d.line(p, fill=255, width=max(1, int(round(w * K))), joint="curve")
    if caps:
        r = w * K / 2
        for x, y in (p[0], p[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    return _arr(im)


def M_rect(x0, y0, x1, y1, r=0):
    im = _new()
    ImageDraw.Draw(im).rounded_rectangle([x0 * K, y0 * K, x1 * K, y1 * K], radius=r * K, fill=255)
    return _arr(im)


def M_ring(cx, cy, r, w, ry=None):
    ry = r if ry is None else ry
    return clamp01(M_ell(cx, cy, r + w / 2, ry + w / 2) - M_ell(cx, cy, r - w / 2, ry - w / 2))


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
    if r <= 0:
        return m
    im = Image.fromarray((clamp01(m) * 255).astype(np.uint8))
    return _arr(im.filter(ImageFilter.GaussianBlur(r * K)))


def blurf(m, r):
    """float blur for height fields (keeps precision)"""
    from scipy.ndimage import gaussian_filter
    return gaussian_filter(m.astype(np.float32), sigma=r * K, mode="constant", truncate=3.0)


def dilate(m, r):
    size = max(3, int(r * K) * 2 + 1)
    im = Image.fromarray((clamp01(m) * 255).astype(np.uint8))
    return _arr(im.filter(ImageFilter.MaxFilter(size)))


def rotate_mask(m, ang, c=(50, 50)):
    im = Image.fromarray((clamp01(m) * 255).astype(np.uint8))
    return _arr(im.rotate(-ang, center=(c[0] * K, c[1] * K), resample=Image.BICUBIC))


def noise(rng, cells, octaves=3):
    out = np.zeros((S, S), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = cells * (2 ** o)
        a = np.random.RandomState(rng.randint(0, 10 ** 6)).rand(n, n).astype(np.float32)
        a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC), np.float32) / 255
        out += a * amp
        tot += amp
        amp *= 0.5
    return out / tot


# ================================================================ materials
# hi, lo, spec strength, spec power
METALS = {
    "steel": ((215, 222, 235), (22, 25, 33), 0.9, 28),
    "darksteel": ((120, 125, 140), (8, 9, 12), 0.7, 24),
    "gold": ((255, 214, 120), (80, 38, 6), 0.9, 22),
    "bronze": ((225, 150, 80), (45, 20, 6), 0.6, 16),
    "silver": ((240, 245, 255), (70, 76, 92), 1.0, 30),
    "wood": ((160, 105, 60), (30, 16, 8), 0.12, 8),
    "bone": ((245, 235, 205), (95, 80, 55), 0.3, 10),
    "stone": ((150, 142, 132), (28, 25, 24), 0.08, 6),
    "dark": ((60, 52, 50), (6, 5, 5), 0.25, 12),
}


class Canvas:
    def __init__(self, theme, seed=0):
        self.theme = theme
        self.rng = random.Random(seed)
        self.img = np.zeros((S, S, 3), np.float32)
        self.sil = np.zeros((S, S), np.float32)
        self.light = np.array([-0.55, -0.7, 0.55], np.float32)
        self.light /= np.linalg.norm(self.light)

    # ---------------------------------------------------------------- compositing
    def over(self, color, alpha):
        a = clamp01(alpha)[..., None]
        c = color if isinstance(color, np.ndarray) else rgb(color)[None, None, :]
        self.img = self.img * (1 - a) + c * a

    def add(self, color, m, k=1.0):
        self.img = self.img + rgb(color)[None, None, :] * (clamp01(m) * k)[..., None]

    def glow(self, m, color, k=1.0, r=1.6, core=None):
        """emissive line/shape: wide soft halo + tight halo + hot core"""
        self.add(color, blur(m, r * 2.6), 0.7 * k)
        self.add(color, blur(m, r * 0.7), 0.9 * k)
        self.add(core or lighten(color, 0.7), m, 0.9 * k)

    # ---------------------------------------------------------------- backdrop
    def backdrop(self, glow=1.0, center=(50, 50), smoke=True, embers=True, tint=None):
        th = tint or self.theme
        rng = self.rng
        col = rgb(sat(th, 1.2))
        d = np.sqrt((XX - center[0]) ** 2 + (YY - center[1]) ** 2) / 100
        base = np.array([0.035, 0.028, 0.03], np.float32)
        wide = np.exp(-(d / 0.42) ** 2) * 0.55 * glow
        core = np.exp(-(d / 0.2) ** 2) * 0.55 * glow
        self.img = base[None, None, :] + col[None, None, :] * (wide + core)[..., None]
        if smoke:
            n = noise(rng, 4, 4)
            n2 = noise(rng, 3, 3)
            wisps = clamp01((n - 0.45) * 3.0) * np.exp(-(d / 0.55) ** 2)
            self.img += (rgb(lighten(th, 0.15)) * 0.5)[None, None, :] * wisps[..., None] * glow
            self.img *= (0.65 + 0.6 * n2)[..., None]
        if embers:
            for _ in range(22):
                x, y = rng.uniform(6, 94), rng.uniform(6, 94)
                l, w = rng.uniform(0.5, 2.2), rng.uniform(0.18, 0.4)
                m = M_line([(x, y), (x + rng.uniform(-0.6, 0.6), y - l)], w)
                self.add(lighten(th, 0.45), blur(m, 0.5), 0.8)
                self.add(lighten(th, 0.75), m, 0.7)

    # ---------------------------------------------------------------- lit part
    def part(self, m, mat="steel", color=None, round=None, outline=0.8, rim=0.9, spec=None,
             tex=0.0, streak=0.0, shadow=0.45, emissive=0.0, flat=0.0):
        """Shade mask m as a rounded volume.
        mat: metal key, or leather / cloth / gem / energy (tinted by color or theme)."""
        th = self.theme
        if mat in METALS:
            hi, lo, sp, pw = METALS[mat]
            tint = color if color is not None else th
            k = 0.4 if color is not None else 0.1
            hi, lo = mix(hi, tint, k), mix(lo, tint, k)
        elif mat == "leather":
            c = sat(color or mix(th, (90, 52, 28), 0.4), 1.25)
            hi, lo, sp, pw = lighten(c, 0.45), darken(c, 0.7), 0.2, 8
        elif mat == "cloth":
            c = color or th
            c = sat(c, 1.2)
            hi, lo, sp, pw = lighten(c, 0.35), darken(c, 0.75), 0.06, 6
        elif mat == "gem":
            c = color or th
            hi, lo, sp, pw = lighten(sat(c, 1.3), 0.5), darken(sat(c, 1.4), 0.7), 1.3, 40
            emissive = max(emissive, 0.25)
        elif mat == "energy":
            c = color or th
            hi, lo, sp, pw = lighten(c, 0.8), lighten(c, 0.1), 0.2, 8
            emissive = max(emissive, 0.6)
        else:
            raise KeyError(mat)
        if spec is not None:
            sp = spec
        if m.max() <= 0.01:
            return
        # height field from the distance to the edge: rounded rim, then (optionally) a
        # plateau.  round=None -> the whole part is one smooth curved volume.
        from scipy.ndimage import distance_transform_edt
        d = distance_transform_edt(m > 0.5).astype(np.float32) / K
        dmax = float(d.max()) or 1.0
        rr = dmax * 0.95 if round is None else min(round, dmax * 0.95)
        rr = max(rr, 0.25)
        h = np.sqrt(clamp01(d / rr)) * rr
        h = blurf(h, 0.18)
        gy, gx = np.gradient(h * K)
        nx, ny = -gx * 1.3, -gy * 1.3
        nz = np.ones_like(nx)
        inv = 1 / np.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx * inv, ny * inv, nz * inv
        L = self.light
        diff = clamp01(nx * L[0] + ny * L[1] + nz * L[2])
        diff = diff * (1 - flat) + 0.7 * flat
        # large-scale top-left -> bottom-right gradient for form
        ys, xs = np.nonzero(m > 0.5)
        if len(xs):
            x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
            g = clamp01(((XX * K - x0) / max(x1 - x0, 1) * 0.45 + (YY * K - y0) / max(y1 - y0, 1) * 0.55))
            diff = diff * (1.15 - 0.55 * g)
        diff = clamp01(diff)
        hi_a, lo_a = rgb(hi), rgb(lo)
        t = diff[..., None] ** 1.1
        col = lo_a[None, None, :] * (1 - t) + hi_a[None, None, :] * t
        # specular (Blinn)
        H = np.array([L[0], L[1], L[2] + 1.0], np.float32)
        H /= np.linalg.norm(H)
        sdot = clamp01(nx * H[0] + ny * H[1] + nz * H[2])
        col += (sdot ** pw * sp)[..., None] * rgb(lighten(hi, 0.6))[None, None, :]
        # back / rim light from lower-right in the aura colour
        if rim > 0:
            r = clamp01(nx * 0.65 + ny * 0.55 - nz * 0.1)
            col += (r ** 1.6 * rim)[..., None] * rgb(lighten(sat(th, 1.3), 0.25))[None, None, :]
        if tex > 0:
            n = noise(self.rng, 48, 2)
            col *= (1 - tex + 2 * tex * n)[..., None]
        if streak > 0:  # brushed metal
            n = np.random.RandomState(self.rng.randint(0, 10 ** 6)).rand(S // 64, S).astype(np.float32)
            n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((S, S), Image.BILINEAR), np.float32) / 255
            col *= (1 - streak + 2 * streak * n)[..., None]
        if emissive > 0:
            col += rgb(lighten(hi, 0.2))[None, None, :] * emissive * (h / (h.max() + 1e-6))[..., None]
        if shadow > 0:
            sm = blur(np.roll(np.roll(m, int(1.0 * K), 0), int(0.8 * K), 1), 1.2)
            self.over((0, 0, 0), sm * shadow)
        if outline > 0:
            self.over((4, 3, 3), dilate(m, 0.28) * outline)
        self.over(col, m)
        self.sil = np.maximum(self.sil, m)

    def gem(self, cx, cy, r, color, ry=None):
        ry = r if ry is None else ry
        m = M_ell(cx, cy, r, ry)
        self.part(m, "gem", color=color, round=r * 0.6, outline=0.9, rim=0.3, shadow=0.3)
        self.add(lighten(color, 0.3), blur(m, r * 0.8), 0.45)
        self.add((255, 255, 255), M_ell(cx - r * 0.35, cy - ry * 0.4, r * 0.28, ry * 0.2), 0.85)

    def engrave(self, pts, w=0.35, k=0.7):
        """incised line: dark groove with a light lip underneath"""
        self.over((0, 0, 0), M_line(pts, w) * k)
        self.add((255, 245, 220), M_line([(x + 0.25, y + 0.3) for x, y in pts], w * 0.6), 0.18 * k)

    def stitches(self, pts, every=2.2, w=0.35, color=(230, 210, 170)):
        acc = 0
        marks = []
        for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
            d = math.hypot(x2 - x1, y2 - y1)
            steps = max(1, int(d / 0.4))
            for i in range(steps):
                acc += d / steps
                if acc >= every:
                    acc = 0
                    t = i / steps
                    x, y = x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
                    dx, dy = (x2 - x1) / (d or 1), (y2 - y1) / (d or 1)
                    marks.append(M_line([(x - dx * 0.5, y - dy * 0.5), (x + dx * 0.5, y + dy * 0.5)], w))
        if marks:
            self.over(color, U(*marks) * 0.8)

    def aura(self, k=0.6, r=2.4, color=None):
        c = color or lighten(sat(self.theme, 1.3), 0.25)
        g = clamp01(blur(dilate(self.sil, 0.4), r) - self.sil)
        self.add(c, g, k)

    # ---------------------------------------------------------------- finishing
    def finish(self):
        img = self.img
        d = np.sqrt((XX - 50) ** 2 + (YY - 50) ** 2) / 100
        img = img * (1 - clamp01((d - 0.36) / 0.4) * 0.8)[..., None]
        img = np.clip(img, 0, None)
        hi = img > 0.72
        img[hi] = 0.72 + 0.28 * (1 - np.exp(-(img[hi] - 0.72) / 0.28))
        img = clamp01(img)
        # thin tile frame: black edge + faint bronze hairline
        b = 1.6
        edge = (XX < b) | (XX > 100 - b) | (YY < b) | (YY > 100 - b)
        img[edge] = np.array([0.03, 0.025, 0.02])
        hair = ((np.abs(XX - b) < 0.35) | (np.abs(XX - (100 - b)) < 0.35) | (np.abs(YY - b) < 0.35) | (np.abs(YY - (100 - b)) < 0.35)) & ~edge
        img[hair] = img[hair] * 0.3 + rgb((150, 110, 55)) * 0.7
        im = Image.fromarray((img * 255).astype(np.uint8), "RGB")
        return im.resize((OUT, OUT), Image.LANCZOS)
