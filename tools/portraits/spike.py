"""Feasibility spike: cut heads out, extract hair/beard layers, composite onto bald bases.

    python spike.py prep                # tiles -> cutouts + landmarks (work/prep/*.npz)
    python spike.py layers              # debug sheet of extracted hair/beard layers
    python spike.py combos [N] [seed]   # N composites on team-coloured discs
"""
import json
import random
import sys
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision

HERE = Path(__file__).parent
TILES, PREP, OUT = HERE / "work/tiles", HERE / "work/prep", HERE / "work"
MODEL = HERE / "models/face_landmarker.task"

OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149,
        150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109]
LIPS = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185]
BROWS = [70, 63, 105, 66, 107, 300, 293, 334, 296, 336]
ALIGN = [33, 263, 1, 61, 291, 152, 234, 454]
BASES = ["14_01", "14_02", "14_05", "14_08", "15_05", "15_09", "13_05", "15_04", "14_04", "15_07"]
SKIP_DONOR = set(BASES) | {f"14_{i:02d}" for i in range(1, 11)} | {f"15_{i:02d}" for i in range(1, 11)} | {
    "13_02", "13_05", "13_07", "13_09", "09_07"}
TEAMS = [(176, 40, 48), (30, 110, 70), (236, 170, 30), (90, 60, 150), (20, 130, 170), (230, 110, 40)]


def landmarker():
    opts = vision.FaceLandmarkerOptions(base_options=mpt.BaseOptions(model_asset_path=str(MODEL)), num_faces=1,
                                        min_face_detection_confidence=0.2, min_face_presence_confidence=0.2)
    return vision.FaceLandmarker.create_from_options(opts)


def landmarks(lmk, bgr):
    res = lmk.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)))
    if not res.face_landmarks:
        return None
    h, w = bgr.shape[:2]
    return np.array([[p.x * w, p.y * h] for p in res.face_landmarks[0]], np.float32)


def poly_mask(shape, pts, grow=0):
    m = np.zeros(shape[:2], np.uint8)
    cv2.fillPoly(m, [pts.astype(np.int32)], 255)
    if grow:
        m = cv2.dilate(m, np.ones((2 * grow + 1,) * 2, np.uint8)) if grow > 0 else cv2.erode(m, np.ones((-2 * grow + 1,) * 2, np.uint8))
    return m.astype(np.float32) / 255.0


def key_background(bgr, lm):
    """Soft foreground alpha from the blue backdrop, plus blue-fringe despill along the edge."""
    b, g, r = [bgr[..., i].astype(np.float32) for i in range(3)]
    bd = b - np.maximum(r, g)
    # Measure this tile's own backdrop from its side margins (the face never reaches them). Bright-backdrop sheets keep the
    # original fixed thresholds; dark navy sheets scale to the measured blueness, and black hair is told apart by having none.
    h0, w0 = bd.shape
    margin = np.concatenate([bd[: int(0.7 * h0), 2:14], bd[: int(0.7 * h0), -14:-2]], axis=1)
    bdb = float(np.percentile(margin, 80))  # upper quartile: hair or dreads reaching the edge only lower the blueness
    if bdb >= 60.0:
        a = np.clip(1.0 - (bd - 15.0) / 35.0, 0, 1)
        a = np.maximum(a, np.clip((85.0 - b) / 25.0, 0, 1))  # very dark pixels are hair, not backdrop
    else:
        a = np.clip(1.0 - (bd - 0.45 * bdb) / (0.45 * bdb), 0, 1)
    a = np.maximum(a, poly_mask(bgr.shape, lm[OVAL], -4))  # never punch holes in the face (blue eyes)
    solid = (a > 0.5).astype(np.uint8)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(solid, connectivity=8)
    keep = np.zeros(n, bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] > 250
    # Only pieces connected to the face survive; leftover swoosh fragments elsewhere are backdrop.
    face_hit = np.unique(lab[poly_mask(bgr.shape, lm[OVAL], -6) > 0.5])
    keep &= np.isin(np.arange(n), face_hit)
    a = a * keep[lab]
    a = cv2.erode(a, np.ones((3, 3), np.uint8))
    edge = cv2.dilate((a > 0.02).astype(np.uint8), np.ones((9, 9), np.uint8)) - cv2.erode((a > 0.98).astype(np.uint8), np.ones((9, 9), np.uint8))
    band = np.clip(edge, 0, 1).astype(bool)
    out = bgr.copy().astype(np.float32)
    cap = np.maximum(r, g)
    out[..., 0] = np.where(band, np.minimum(b, cap), b)
    return np.clip(out, 0, 255).astype(np.uint8), np.clip(a, 0, 1)


def fix_edge_band(bgr):
    """Replace the dark vertical card-border band near the left edge with the column beside it."""
    blue = bgr[:, :, 0].astype(float).mean(axis=0)
    dark = [i for i in range(2, 30) if blue[i] < 100]
    if dark:
        lo, hi = dark[0], dark[-1]
        bgr = bgr.copy()
        bgr[:, lo:hi + 1] = bgr[:, hi + 2:hi + 3]
    return bgr


def prep() -> None:
    PREP.mkdir(parents=True, exist_ok=True)
    lmk = landmarker()
    uniq = (OUT / "unique.txt").read_text().split()
    miss = []
    for tid in uniq:
        bgr = fix_edge_band(cv2.imread(str(TILES / f"{tid}.png")))
        lm = landmarks(lmk, bgr)
        if lm is None:
            miss.append(tid)
            continue
        clean, alpha = key_background(bgr, lm)
        np.savez_compressed(PREP / f"{tid}.npz", bgr=clean, alpha=alpha, lm=lm)
    print("prepped", len(uniq) - len(miss), "no face:", miss)


def load(tid):
    z = np.load(PREP / f"{tid}.npz")
    return z["bgr"], z["alpha"], z["lm"]


def smoothstep(x, e0, e1):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def extract_layers(bgr, alpha, lm, sam_beard=None):
    """Return (hair_alpha, beard_alpha, skin_bgr) for a donor head. Colours are un-mixed from the donor skin."""
    h, w = bgr.shape[:2]
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    S = np.median(np.concatenate([lab[int(y) - 7:int(y) + 8, int(x) - 7:int(x) + 8].reshape(-1, 3) for x, y in (lm[117], lm[346])]), axis=0)
    skin_bgr = cv2.cvtColor(np.uint8([[S]]), cv2.COLOR_LAB2BGR)[0, 0].astype(np.float32)
    dist = np.linalg.norm(lab - S, axis=2)
    soft = smoothstep(dist, 25, 60)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    oval = poly_mask(bgr.shape, lm[OVAL])
    face_w = lm[454][0] - lm[234][0]
    y_brow = lm[BROWS][:, 1].min() - 6
    y_nose = lm[1][1]
    y_sub = lm[2][1] + 3
    y_chin = lm[152][1]

    # Beard: lower face inside the oval (minus nose and lips), plus a short strip below the chin.
    nose = np.zeros((h, w), np.float32)
    cv2.circle(nose, (int(lm[1][0]), int(lm[1][1])), int(face_w * 0.11), 1.0, -1)
    lips = poly_mask(bgr.shape, lm[LIPS], 2)
    jaw_x = (xx > lm[234][0] + face_w * 0.08) & (xx < lm[454][0] - face_w * 0.08)
    low_oval = lm[OVAL].copy()
    low_oval[low_oval[:, 1] > y_nose, 1] += 0.15 * (y_chin - y_brow)  # beards overhang the chin and jaw
    region = poly_mask(bgr.shape, low_oval) * (yy > y_nose) * (1 - nose) * (1 - lips)
    # Only solid hair: far from skin AND clearly darker than it. Skin shadows and light stubble are dropped.
    beard_soft = smoothstep(dist, 55, 95) * smoothstep(S[0] - lab[..., 0], 35, 60)
    raw = (region * beard_soft * alpha > 0.35).astype(np.uint8)
    raw = cv2.morphologyEx(raw, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab_cc, stats, _ = cv2.connectedComponentsWithStats(raw, connectivity=8)
    keep = np.zeros(n, bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] > 350
    solid = (keep[lab_cc]).astype(np.float32)
    solid = cv2.morphologyEx(solid, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    beard = cv2.GaussianBlur(solid, (0, 0), 1.2) * region
    if sam_beard is not None:
        # Full beards: trust SAM2's outline. Goatees/stubble/clean faces (SAM2 grabs bare skin) keep the strict colour mask.
        m = (sam_beard > 0).astype(np.float32)
        dark = (S[0] - lab[..., 0]) > 40
        if float((m * region * dark).sum() / max((m * region).sum(), 1)) > 0.55:
            m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
            soft_region = cv2.GaussianBlur(region, (0, 0), 3.0)
            beard = cv2.GaussianBlur(m, (0, 0), 1.2) * soft_region * smoothstep(dist, 35, 65) * alpha
    # Hair: scalp/forehead, plus hair outside the face oval above the nose and long hair beside the jaw.
    outside = (1 - poly_mask(bgr.shape, lm[OVAL], 3)) * alpha
    white = (lab[..., 0] > 190) & (np.linalg.norm(lab[..., 1:] - 128, axis=2) < 14)
    top = (yy < y_brow) * 1.0
    ears = ((yy >= y_brow) & (yy < y_sub)) * soft
    sides = ((yy >= y_sub) & ~jaw_x & (yy < y_chin + 20)) * soft * (~white)
    hair_out = outside * np.maximum(top, np.maximum(ears, sides))
    forehead = oval * (yy < y_brow) * smoothstep(dist, 45, 90)
    hair = np.clip(np.maximum(hair_out, forehead) - beard * 0.0, 0, 1)
    hair = cv2.GaussianBlur(hair, (0, 0), 1.0)
    # A bald donor leaves near-zero hair; drop speckle.
    hair[hair < 0.06] = 0
    beard[beard < 0.06] = 0
    coverage = float((beard > 0.5).sum() / max(region.sum(), 1))
    return hair, beard, skin_bgr, coverage


def unmix(bgr, a, skin_bgr):
    """Foreground colour such that compositing over any skin reproduces the donor look."""
    c = bgr.astype(np.float32)
    aa = np.maximum(a, 0.25)[..., None]
    return np.clip((c - (1 - a[..., None]) * skin_bgr) / aa, 0, 255)


def layer_rgba(tid):
    bgr, alpha, lm = load(tid)
    sp = HERE / "work/sam" / f"{tid}_beard.png"
    sam = cv2.imread(str(sp), 0) if sp.exists() else None
    hair, beard, skin, cov = extract_layers(bgr, alpha, lm, sam)
    return (unmix(bgr, hair, skin), hair), (unmix(bgr, beard, skin), beard), lm, cov


def over(dst_rgb, dst_a, src_rgb, src_a):
    a = src_a + dst_a * (1 - src_a)
    rgb = (src_rgb * src_a[..., None] + dst_rgb * (dst_a * (1 - src_a))[..., None]) / np.maximum(a, 1e-4)[..., None]
    return rgb, a


def warp_to(layer, src_lm, dst_lm, size):
    rgb, a = layer
    M, _ = cv2.estimateAffine2D(src_lm[ALIGN], dst_lm[ALIGN], method=cv2.LMEDS)
    wh = (size[1], size[0])
    return (cv2.warpAffine(rgb, M, wh, flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE),
            np.clip(cv2.warpAffine(a, M, wh, flags=cv2.INTER_CUBIC), 0, 1))


def compose_head(base_id, hair_id, beard_id):
    bgr, alpha, lm = load(base_id)
    rgb, a = bgr.astype(np.float32), alpha.astype(np.float32)
    if beard_id:
        _, beard, bl, _ = layer_rgba(beard_id)
        rgb, a = over(rgb, a, *warp_to(beard, bl, lm, bgr.shape))
    if hair_id:
        hair, _, hl, _ = layer_rgba(hair_id)
        rgb, a = over(rgb, a, *warp_to(hair, hl, lm, bgr.shape))
    return rgb, a, lm


def team_disc(rgb, a, lm, team, size=256):
    pad_t, pad_s = 40, 36
    h, w = a.shape
    canvas_w, canvas_h = w + 2 * pad_s, h + pad_t
    side = max(canvas_w, canvas_h)
    yy, xx = np.mgrid[0:side, 0:side].astype(np.float32)
    d = np.hypot(xx - side / 2, yy - side * 0.45) / (side * 0.62)
    col = np.array(team[::-1], np.float32)
    bg = col[None, None] * (1.12 - 0.55 * np.clip(d, 0, 1))[..., None]
    # Tint the white jersey to the team colour (lower part of the frame only).
    lab = cv2.cvtColor(np.clip(rgb, 0, 255).astype(np.uint8), cv2.COLOR_BGR2LAB).astype(np.float32)
    white = smoothstep(lab[..., 0], 150, 200) * (1 - smoothstep(np.linalg.norm(lab[..., 1:] - 128, axis=2), 8, 18))
    white *= (np.mgrid[0:h, 0:w][0] > lm[152][1] + 0.12 * (lm[152][1] - lm[10][1]))
    tint = (lab[..., 0] / 255.0 * 1.25)[..., None] * col[None, None] * 0.9
    rgb = rgb * (1 - white[..., None]) + np.clip(tint, 0, 255) * white[..., None]
    full_rgb = np.zeros((side, side, 3), np.float32)
    full_a = np.zeros((side, side), np.float32)
    x0 = (side - w) // 2
    full_rgb[pad_t:pad_t + h, x0:x0 + w] = rgb
    full_a[pad_t:pad_t + h, x0:x0 + w] = a
    out = bg * (1 - full_a[..., None]) + full_rgb * full_a[..., None]
    out = cv2.resize(out, (size, size), interpolation=cv2.INTER_AREA)
    circle = np.zeros((size, size), np.float32)
    cv2.circle(circle, (size // 2, size // 2), int(size * 0.485), 1.0, -1, cv2.LINE_AA)
    ring = np.full((size, size, 3), 40, np.float32)
    out = out * circle[..., None] + 24 * (1 - circle[..., None])
    return np.clip(out, 0, 255).astype(np.uint8)


def label(img, text):
    cv2.putText(img, text, (4, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (0, 255, 255), 1, cv2.LINE_AA)
    return img


_SKIN = {}


_SKIN_FILE = HERE / "work" / "skin_cache.json"
_SKIN_DISK = None


def _skin_disk():
    global _SKIN_DISK
    if _SKIN_DISK is None:
        _SKIN_DISK = json.loads(_SKIN_FILE.read_text()) if _SKIN_FILE.exists() else {}
        import atexit
        atexit.register(lambda: _SKIN_FILE.write_text(json.dumps(_SKIN_DISK)))
    return _SKIN_DISK


def skin_lab(tid):
    """Median upper-cheek colour (8-bit Lab) of a head; the basis for skin-tone matching. Cached on disk per cutout."""
    if tid not in _SKIN:
        st = (PREP / f"{tid}.npz").stat()
        sig = f"{st.st_mtime_ns}:{st.st_size}"
        disk = _skin_disk()
        if tid in disk and disk[tid][0] == sig:
            _SKIN[tid] = np.array(disk[tid][1], np.float32)
        else:
            bgr, _, lm = load(tid)
            lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
            px = np.concatenate([lab[int(y) - 7:int(y) + 8, int(x) - 7:int(x) + 8].reshape(-1, 3) for x, y in (lm[117], lm[346])])
            _SKIN[tid] = np.median(px, axis=0)
            disk[tid] = [sig, [float(v) for v in _SKIN[tid]]]
    return _SKIN[tid]


TONE_MAX = 22.0  # 8-bit Lab distance; ~9 CIE L units. Layers only go onto bases at least this close in skin tone.


def tone_gap(a, b):
    return float(np.linalg.norm(skin_lab(a) - skin_lab(b)))


def donors():
    ids = [p.stem for p in sorted(PREP.glob("*.npz"))]
    return [i for i in ids if i not in SKIP_DONOR]


def debug_layers() -> None:
    ids = donors()[:60:3]
    tiles = []
    for tid in ids:
        (hrgb, ha), (brgb, ba), lm, _ = layer_rgba(tid)
        bgr, _, _ = load(tid)
        chk = (np.indices(ha.shape).sum(0) // 12 % 2 * 40 + 100).astype(np.float32)[..., None].repeat(3, 2)
        hv = hrgb * ha[..., None] + chk * (1 - ha[..., None])
        bv = brgb * ba[..., None] + chk * (1 - ba[..., None])
        row = np.concatenate([bgr, hv, bv], axis=1)
        tiles.append(label(cv2.resize(np.clip(row, 0, 255).astype(np.uint8), (520, 200), interpolation=cv2.INTER_AREA), tid))
    cols = 3
    h, w = tiles[0].shape[:2]
    rows = (len(tiles) + cols - 1) // cols
    sheet = np.zeros((rows * h, cols * w, 3), np.uint8)
    for k, t in enumerate(tiles):
        sheet[(k // cols) * h:(k // cols + 1) * h, (k % cols) * w:(k % cols + 1) * w] = t[:h, :w]
    cv2.imwrite(str(OUT / "debug_layers.png"), sheet)
    print("wrote debug_layers.png", sheet.shape)


def combos(n: int, seed: int) -> None:
    rnd = random.Random(seed)
    ds = donors()
    beard_ds = [d for d in ds if layer_rgba(d)[3] > 0.28]
    print("beard donors:", len(beard_ds), "of", len(ds))
    size = 192
    cells = []
    for b in BASES:
        print(b, "L", round(float(skin_lab(b)[0]) / 2.55), "compatible hair donors:", sum(tone_gap(b, d) < TONE_MAX for d in ds),
              "beard donors:", sum(tone_gap(b, d) < TONE_MAX for d in beard_ds))
    for i in range(n):
        base = BASES[i % len(BASES)]
        hair = rnd.choice([d for d in ds if tone_gap(base, d) < TONE_MAX])
        beard = rnd.choice([d for d in beard_ds if tone_gap(base, d) < TONE_MAX])
        rgb, a, lm = compose_head(base, hair, beard if rnd.random() < 0.7 else None)
        disc = team_disc(rgb, a, lm, TEAMS[i % len(TEAMS)], size)
        cells.append(label(disc, f"b{base} h{hair} d{beard}"))
    cols = 6
    rows = (n + cols - 1) // cols
    sheet = np.zeros((rows * size, cols * size, 3), np.uint8)
    for k, c in enumerate(cells):
        sheet[(k // cols) * size:(k // cols + 1) * size, (k % cols) * size:(k % cols + 1) * size] = c
    cv2.imwrite(str(OUT / "combos.png"), sheet)
    small = np.concatenate([np.concatenate([cv2.resize(c, (64, 64), interpolation=cv2.INTER_AREA) for c in cells[r * cols:(r + 1) * cols]], axis=1) for r in range(rows)], axis=0)
    cv2.imwrite(str(OUT / "combos_64px.png"), small)
    print("wrote combos.png", sheet.shape)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "prep":
        prep()
    elif cmd == "layers":
        debug_layers()
    elif cmd == "combos":
        combos(int(sys.argv[2]) if len(sys.argv) > 2 else 30, int(sys.argv[3]) if len(sys.argv) > 3 else 1)
