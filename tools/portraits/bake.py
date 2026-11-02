"""Bake the 120 head cutouts into game assets.

    python bake.py   # -> assets/portraits/heads/<id>.webp, <id>_m.png, and assets/portraits/heads.json

<id>.webp   RGBA cutout (lossy WebP, alpha kept), WIDTH px wide
<id>_m.png  same size; R = hair+brow tint mask, G = iris recolour mask
heads.json  per head: group, image size, face centre/width, and the landmark anchors the Godot morph needs
"""
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from groups import group
from spike import BROWS, OVAL, PREP, smoothstep
from tint import EYE_COLORS, head_masks  # noqa: F401  (EYE_COLORS imported so the iris gating below matches tint.py)
from warp import L_BROW, L_EYE, MOUTH, NOSE, R_BROW, R_EYE

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/portraits/heads"
WIDTH = 256
BAKE_VERSION = 1  # bump when the output format changes, to force a full re-bake
CACHE = Path(__file__).with_name("work") / "bake_cache.json"

IRIS_L, IRIS_R = ([469, 470, 471, 472], 468), ([474, 475, 476, 477], 473)
EXTRA = [1, 2, 10, 152, 234, 454]
INDICES = sorted(set(L_EYE + R_EYE + L_BROW + R_BROW + NOSE + MOUTH + OVAL + EXTRA + BROWS))


def iris_mask(bgr, lm):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    mask = np.zeros(bgr.shape[:2], np.float32)
    for (ring, centre), eye in ((IRIS_L, L_EYE), (IRIS_R, R_EYE)):
        c = lm[centre]
        r = float(np.mean(np.linalg.norm(lm[ring] - c, axis=1)))
        disk = np.zeros_like(mask)
        cv2.circle(disk, (int(round(c[0])), int(round(c[1]))), max(1, int(round(r * 0.95))), 1.0, -1)
        lid = np.zeros_like(mask)
        cv2.fillConvexPoly(lid, cv2.convexHull(lm[eye].astype(np.int32)), 1.0)
        mask = np.maximum(mask, disk * lid)
    mask = cv2.GaussianBlur(mask, (0, 0), 0.7)
    v = hsv[..., 2]
    return mask * smoothstep(v, 45, 95) * (1 - smoothstep(v, 190, 235))


def bake_head(p, tid):
    z = np.load(p)
    bgr, alpha, lm = z["bgr"], z["alpha"], z["lm"]
    h, w = alpha.shape
    m = head_masks(tid)
    hair = np.clip(m["hair"] + m["brow"], 0, 1)
    iris = iris_mask(bgr, lm)
    rgba = np.dstack([cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB), np.clip(alpha * 255, 0, 255).astype(np.uint8)])
    nh = round(h * WIDTH / w)
    img = Image.fromarray(rgba, "RGBA").resize((WIDTH, nh), Image.LANCZOS)
    img.save(OUT / f"{tid}.webp", quality=92, method=6)
    mk = np.dstack([hair, iris, np.zeros_like(hair)])
    Image.fromarray((np.clip(mk, 0, 1) * 255).astype(np.uint8), "RGB").resize((WIDTH, nh), Image.BILINEAR).save(OUT / f"{tid}_m.png", optimize=True)
    sx = WIDTH / w
    oval = lm[OVAL]
    return dict(
        w=WIDTH, h=nh,
        cx=round(float(lm[1][0]) * sx, 2), cy=round(float(oval[:, 1].mean()) * sx, 2),
        fw=round(float(lm[454][0] - lm[234][0]) * sx, 2),
        brow_top=round(float(lm[BROWS][:, 1].min()) * sx, 2),
        pts=[[round(float(lm[i][0]) * sx, 1), round(float(lm[i][1]) * sx, 1)] for i in INDICES],
    )


def main(force=False):
    """Bake only heads that are new or whose cutout changed (cache in work/bake_cache.json); groups are always applied fresh."""
    OUT.mkdir(parents=True, exist_ok=True)
    cache = {} if force or not CACHE.exists() else json.loads(CACHE.read_text())
    heads, baked, reused = {}, 0, 0
    for p in sorted(PREP.glob("*.npz")):
        tid = p.stem
        st = p.stat()
        sig = f"{st.st_mtime_ns}:{st.st_size}:{BAKE_VERSION}"
        hit = cache.get(tid)
        if hit and hit["sig"] == sig and (OUT / f"{tid}.webp").exists() and (OUT / f"{tid}_m.png").exists():
            entry = hit["entry"]
            reused += 1
        else:
            entry = bake_head(p, tid)
            cache[tid] = dict(sig=sig, entry=entry)
            baked += 1
        heads[tid] = dict(group=group(tid), **entry)
    CACHE.write_text(json.dumps(cache, separators=(",", ":")))
    out = dict(indices=INDICES, groups=sorted({v["group"] for v in heads.values()}), heads=heads)
    (ROOT / "assets/portraits/heads.json").write_text(json.dumps(out, separators=(",", ":")))
    size = sum(f.stat().st_size for f in OUT.iterdir())
    print(f"{len(heads)} heads ({baked} baked, {reused} unchanged), {round(size / 1e6, 1)} MB images, {len(INDICES)} anchor indices")


if __name__ == "__main__":
    import sys
    main(force="--force" in sys.argv)
