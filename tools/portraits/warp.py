"""Landmark-driven face morphing: move anchor points (eyes, brows, nose, mouth, head width, ears) and warp the head.

    python warp.py [heads...]   # writes work/warp_test.png: original, 3 moderate and 3 strong random variants per head

Warp = moving least squares over face-landmark control points, so everything between the anchors flows smoothly.
"""
import sys

import cv2
import numpy as np

from spike import BROWS, OUT, OVAL, TEAMS, load, team_disc

L_EYE = [33, 246, 161, 160, 159, 158, 157, 173, 133, 155, 154, 153, 145, 144, 163, 7]
R_EYE = [362, 398, 384, 385, 386, 387, 388, 466, 263, 249, 390, 373, 374, 380, 381, 382]
L_BROW = [70, 63, 105, 66, 107, 55, 65, 52, 53, 46]
R_BROW = [300, 293, 334, 296, 336, 285, 295, 282, 283, 276]
NOSE = [168, 6, 197, 195, 5, 4, 1, 98, 327, 129, 358, 48, 278, 2]
NOSE_WIDE = [98, 327, 129, 358, 48, 278, 2, 1]
MOUTH = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185]

# Slider ranges at intensity 1.0 (fractions of face width fw / height fh, or of the feature's own size).
RANGES = dict(eye_x=0.05, eye_y=0.04, eye_size=0.18, brow_y=0.04, brow_size=0.20, nose_y=0.04, nose_w=0.18,
              mouth_y=0.05, mouth_w=0.15, mouth_len=0.25, head_w=0.10, ear_x=0.05, ear_y=0.06, ear_len=0.25, ear_wid=0.25)


# Approved limits (low, high) from visual review, as fractions: face width/height for positions, own size for scales.
# brow_size and the ear sliders are intentionally absent: they did not morph correctly.
LIMITS = dict(eye_x=(-0.025, 0.025), eye_y=(-0.04, 0.02), eye_size=(-0.19, 0.09), brow_y=(-0.04, 0.04), nose_y=(-0.02, 0.04),
              nose_w=(-0.18, 0.09), mouth_y=(-0.025, 0.025), mouth_w=(-0.15, 0.075), mouth_len=(-0.25, 0.35), head_w=(-0.10, 0.025))


def sample_params(rnd, strength=1.0):
    """Random slider values inside the approved limits; `strength` < 1 pulls them toward the original."""
    return {k: float(rnd.uniform(lo, hi) * strength) for k, (lo, hi) in LIMITS.items()}


def scale_about(pts, centre, sx=1.0, sy=1.0):
    out = pts - centre
    out[:, 0] *= sx
    out[:, 1] *= sy
    return out + centre


def control_points(lm, shape, p):
    """Source anchor points P and their displaced positions Q for slider values `p` (dict of floats)."""
    h, w = shape[:2]
    fw = lm[454][0] - lm[234][0]
    top = lm[BROWS][:, 1].min()
    fh = lm[152][1] - top
    cx = float(lm[1][0])
    P, Q = [], []

    def add(src, dst):
        P.append(np.asarray(src, np.float32).reshape(-1, 2))
        Q.append(np.asarray(dst, np.float32).reshape(-1, 2))

    def head_x(pts):  # head width scales everything horizontally about the face centre
        out = pts.copy()
        out[:, 0] = cx + (out[:, 0] - cx) * (1 + p["head_w"])
        return out

    # Eyes: spread, height, size.
    for ring, side in ((L_EYE, -1), (R_EYE, 1)):
        src = lm[ring]
        c = src.mean(axis=0)
        dst = scale_about(src.copy(), c, 1 + p["eye_size"], 1 + p["eye_size"]) + [side * p["eye_x"] * fw, p["eye_y"] * fh]
        add(src, head_x(dst))
    # Brows: height, length and thickness.
    for ring, side in ((L_BROW, -1), (R_BROW, 1)):
        src = lm[ring]
        c = src.mean(axis=0)
        dst = scale_about(src.copy(), c, 1 + p["brow_size"], 1 + 0.6 * p["brow_size"]) + [0, p["brow_y"] * fh]
        add(src, head_x(dst))
    # Nose: height and width.
    src = lm[NOSE]
    dst = src + [0, p["nose_y"] * fh]
    wide = np.isin(NOSE, NOSE_WIDE)
    dst[wide, 0] = cx + (src[wide, 0] - cx) * (1 + p["nose_w"])
    add(src, head_x(dst))
    # Mouth: height, width, lip height.
    src = lm[MOUTH]
    c = src.mean(axis=0)
    dst = scale_about(src.copy(), c, 1 + p["mouth_w"], 1 + p["mouth_len"]) + [0, p["mouth_y"] * fh]
    add(src, head_x(dst))
    # Head outline, plus a ring of "hair" anchors outside it so hair follows the head width.
    oval = lm[OVAL]
    centre = oval.mean(axis=0)
    add(oval, head_x(oval))
    ring = centre + (oval - centre) * 1.3
    add(ring, head_x(ring))
    # Ears (MediaPipe has none): three anchors per side just outside the jaw landmarks, with the face side pinned.
    ec_y = (top + lm[2][1]) / 2
    for side, jaw in ((-1, lm[234]), (1, lm[454])):
        ex = jaw[0] + side * 0.05 * fw
        src = np.array([[ex + side * 0.07 * fw, ec_y], [ex + side * 0.02 * fw, ec_y - 0.16 * fh], [ex + side * 0.02 * fw, ec_y + 0.16 * fh]], np.float32)
        dst = src.copy()
        dst[0, 0] = ex + (src[0, 0] - ex) * (1 + p["ear_wid"])
        dst[1:, 1] = ec_y + (src[1:, 1] - ec_y) * (1 + p["ear_len"])
        dst += [side * p["ear_x"] * fw, p["ear_y"] * fh]
        add(src, head_x(dst))
        add(np.array([jaw, jaw + [side * 0.02 * fw, -0.1 * fh]], np.float32), head_x(np.array([jaw, jaw + [side * 0.02 * fw, -0.1 * fh]], np.float32)))
    # Pins: image border (so background and the jersey stay put).
    xs, ys = np.linspace(0, w - 1, 9), np.linspace(0, h - 1, 11)
    border = np.array([[x, 0] for x in xs] + [[x, h - 1] for x in xs] + [[0, y] for y in ys[1:-1]] + [[w - 1, y] for y in ys[1:-1]], np.float32)
    add(border, border)
    return np.concatenate(P), np.concatenate(Q)


def mls_map(P, Q, shape, step=6, alpha=1.2):
    """Inverse warp field (output pixel -> source pixel) by moving least squares (affine)."""
    h, w = shape[:2]
    gx, gy = np.arange(0, w + step, step), np.arange(0, h + step, step)
    V = np.stack(np.meshgrid(gx, gy), -1).reshape(-1, 2).astype(np.float64)
    P, Q = P.astype(np.float64), Q.astype(np.float64)
    d2 = ((V[:, None, :] - Q[None]) ** 2).sum(-1) + 1e-3
    W = 1.0 / d2 ** alpha
    Ws = W.sum(1, keepdims=True)
    qs = (W[:, :, None] * Q[None]).sum(1) / Ws
    ps = (W[:, :, None] * P[None]).sum(1) / Ws
    qh, ph = Q[None] - qs[:, None], P[None] - ps[:, None]
    A = np.einsum("nk,nki,nkj->nij", W, qh, qh) + 1e-6 * np.eye(2)
    B = np.einsum("nk,nki,nkj->nij", W, qh, ph)
    M = np.linalg.solve(A, B)
    F = np.einsum("ni,nij->nj", V - qs, M) + ps
    F = F.reshape(len(gy), len(gx), 2).astype(np.float32)
    full = cv2.resize(F, (len(gx) * step, len(gy) * step), interpolation=cv2.INTER_LINEAR)[:h, :w]
    return full[..., 0], full[..., 1]


def warp_head(bgr, alpha, lm, params):
    p = {k: 0.0 for k in RANGES}
    p.update(params)
    P, Q = control_points(lm, bgr.shape, p)
    mx, my = mls_map(P, Q, bgr.shape)
    out = cv2.remap(bgr, mx, my, cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
    a = cv2.remap(alpha.astype(np.float32), mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    return out.astype(np.float32), a


def random_params(rnd, intensity):
    return {k: float(rnd.uniform(-1, 1) * r * intensity) for k, r in RANGES.items()}


def main(ids):
    import random
    rnd = random.Random(3)
    size = 168
    rows = []
    for n, tid in enumerate(ids):
        bgr, alpha, lm = load(tid)
        cells = [team_disc(bgr.astype(np.float32), alpha.astype(np.float32), lm, TEAMS[n % len(TEAMS)], size)]
        for intensity in (0.5, 0.5, 0.5, 1.0, 1.0, 1.0):
            rgb, a = warp_head(bgr, alpha, lm, random_params(rnd, intensity))
            cells.append(team_disc(rgb, a, lm, TEAMS[n % len(TEAMS)], size))
        rows.append(np.concatenate(cells, axis=1))
    cv2.imwrite(str(OUT / "warp_test.png"), np.concatenate(rows, axis=0))
    print("wrote warp_test.png")


if __name__ == "__main__":
    main(sys.argv[1:] or ["02_01", "02_02", "02_03", "02_04", "02_05"])
