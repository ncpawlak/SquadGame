"""Cheap variety on top of the morph: mirror flip, hair/beard/brow tint, eye colour, small skin tint.

    python tint.py   # writes work/variants.png: per head, the original then 8 random full variants
"""
import random

import cv2
import numpy as np

from spike import BROWS, OUT, TEAMS, landmarker, landmarks, layer_rgba, load, smoothstep, team_disc
from warp import L_BROW, L_EYE, R_BROW, R_EYE, sample_params, warp_head

# Hair/beard/brow tints as 8-bit Lab deltas (L, a, b). Texture is kept; only the colour moves.
HAIR_TINTS = {
    "keep": (0, 0, 0),
    "darker": (-32, 0, -3),
    "lighter": (26, 0, 9),
    "warmer": (-4, 9, 13),
    "ash": (10, -2, -2),
}
# Iris colours as OpenCV (hue 0-179, saturation 0-255).
EYE_COLORS = {"brown": (12, 150), "hazel": (22, 140), "green": (55, 110), "blue": (105, 120), "gray": (100, 30)}

_lmk = None
_masks = {}


def lmk():
    global _lmk
    if _lmk is None:
        _lmk = landmarker()
    return _lmk


def head_masks(tid):
    """Soft masks (hair+beard, brows) for a head; cached."""
    if tid not in _masks:
        (_, hair), (_, beard), lm, cov = layer_rgba(tid)
        beard = beard if cov > 0.3 else beard * 0   # clean-shaven faces: the 'beard' mask is just skin shadow
        bgr, alpha, _ = load(tid)
        lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
        S = np.median(np.concatenate([lab[int(y) - 6:int(y) + 7, int(x) - 6:int(x) + 7].reshape(-1, 3) for x, y in (lm[117], lm[346])]), axis=0)
        brow = np.zeros(alpha.shape, np.float32)
        for ring in (L_BROW, R_BROW):
            cv2.fillConvexPoly(brow, cv2.convexHull(lm[ring].astype(np.int32)), 1.0)
        brow = cv2.GaussianBlur(brow, (0, 0), 1.2) * smoothstep(np.linalg.norm(lab - S, axis=2), 25, 55)
        skin = (1 - np.clip(hair + beard + brow, 0, 1)) * alpha * (1 - smoothstep(np.linalg.norm(lab - S, axis=2), 30, 60))
        _masks[tid] = dict(hair=smoothstep(np.maximum(hair, beard), 0.5, 0.85) * smoothstep(np.linalg.norm(lab - S, axis=2), 15, 40), brow=brow, skin=skin)
    return _masks[tid]


def tint_hair(bgr, m, delta):
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    w = np.clip(m["hair"] + m["brow"], 0, 1)[..., None]
    lab = lab + w * np.array(delta, np.float32)
    return cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)


def tint_skin(bgr, m, delta):
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    lab = lab + m["skin"][..., None] * np.array(delta, np.float32)
    return cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)


def recolor_eyes(bgr, lm, colour):
    hue, sat = EYE_COLORS[colour]
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    mask = np.zeros(bgr.shape[:2], np.float32)
    for centre, ring, eye in ((468, [469, 470, 471, 472], L_EYE), (473, [474, 475, 476, 477], R_EYE)):
        c = lm[centre]
        r = float(np.mean(np.linalg.norm(lm[ring] - c, axis=1)))
        disk = np.zeros_like(mask)
        cv2.circle(disk, (int(round(c[0])), int(round(c[1]))), max(1, int(round(r * 0.95))), 1.0, -1)
        lid = np.zeros_like(mask)
        cv2.fillConvexPoly(lid, cv2.convexHull(lm[eye].astype(np.int32)), 1.0)
        mask = np.maximum(mask, disk * lid)
    mask = cv2.GaussianBlur(mask, (0, 0), 0.7)
    v = hsv[..., 2]
    iris = smoothstep(v, 45, 95) * (1 - smoothstep(v, 190, 235))  # leave the pupil and the highlight alone
    w = mask * iris
    hsv[..., 0] = hsv[..., 0] * (1 - w) + hue * w
    hsv[..., 1] = hsv[..., 1] * (1 - w) + (hsv[..., 1] * 0.35 + sat * 0.65) * w
    return cv2.cvtColor(np.clip(hsv, 0, 255).astype(np.uint8), cv2.COLOR_HSV2BGR)


def flip_head(bgr, alpha, masks):
    """Mirror a head, re-detecting landmarks so left/right anchors stay correct."""
    b, a = np.ascontiguousarray(bgr[:, ::-1]), np.ascontiguousarray(alpha[:, ::-1])
    m = {k: np.ascontiguousarray(v[:, ::-1]) for k, v in masks.items()}
    return b, a, m, landmarks(lmk(), b)


def variant(tid, rnd, flip=None, tint=None, eyes=None, skin=False, morph=True):
    """One fully randomised variant of head `tid` (any piece can be forced via the arguments)."""
    bgr, alpha, lm = load(tid)
    m = head_masks(tid)
    if (rnd.random() < 0.5) if flip is None else flip:
        bgr, alpha, m, lm2 = flip_head(bgr, alpha, m)
        lm = lm2 if lm2 is not None else lm
    name = tint or rnd.choice(list(HAIR_TINTS))
    d = np.array(HAIR_TINTS[name], np.float32) * rnd.uniform(0.7, 1.0)
    bgr = tint_hair(bgr, m, d)
    if skin:
        bgr = tint_skin(bgr, m, (rnd.uniform(-3, 3), rnd.uniform(-1.2, 1.2), rnd.uniform(-2, 2)))
    bgr = recolor_eyes(bgr, lm, eyes or rnd.choice(list(EYE_COLORS)))
    a = alpha.astype(np.float32)
    if morph:
        out, a = warp_head(bgr, alpha, lm, sample_params(rnd))
    else:
        out = bgr.astype(np.float32)
    return out, a, lm


def main():
    size = 160
    rows = []
    for n, tid in enumerate(["14_01", "02_03", "02_04", "02_02", "05_03", "03_06"]):
        rnd = random.Random(500 + n)
        bgr, alpha, lm = load(tid)
        cells = [team_disc(bgr.astype(np.float32), alpha.astype(np.float32), lm, TEAMS[n % 6], size)]
        for _ in range(8):
            rgb, a, l = variant(tid, rnd)
            cells.append(team_disc(rgb, a, l, TEAMS[n % 6], size))
        rows.append(np.concatenate(cells, 1))
    cv2.imwrite(str(OUT / "variants.png"), np.concatenate(rows, 0))
    print("wrote variants.png")


if __name__ == "__main__":
    main()
