"""Half-swap test: top half of one head + bottom half of another, same skin tone, feathered seam.

    python halfswap.py [N] [seed]   # writes work/halfswap_bald.png and work/halfswap_donors.png
"""
import random
import sys

import cv2
import numpy as np

from spike import (OVAL, poly_mask, ALIGN, BROWS, OUT, TEAMS, TONE_MAX, SKIP_DONOR, label, layer_rgba, load, skin_lab, smoothstep, team_disc,
                   tone_gap, donors)

BALD = ["13_02", "13_05", "13_07", "13_09"] + [f"14_{i:02d}" for i in range(1, 11)] + [f"15_{i:02d}" for i in range(3, 11)]


BAD_TILES = set()  # header-strip tiles were re-cut
LAST = {}  # diagnostics of the most recent half_swap
TONE_HS = 14.0   # stricter than TONE_MAX: halves must come from close skin tones
HAIR_HS = 25.0   # 8-bit Lab distance between the two heads' hair colours


def skin_pixels(lab, oval, S, band):
    m = (oval > 0.5) & band & (np.linalg.norm(lab - S, axis=2) < 22)
    return m


def half_swap(top_id, bot_id, cut=0.05, feather=0.07, overhang=0.02):
    ta, aa, lma = load(top_id)
    tb, ab, lmb = load(bot_id)
    h, w = aa.shape
    fh = lma[152][1] - lma[BROWS][:, 1].min()
    fw = lma[454][0] - lma[234][0]
    ycut = lma[2][1] + cut * fh
    M, _ = cv2.estimateAffine2D(lmb[ALIGN], lma[ALIGN], method=cv2.LMEDS)
    B = cv2.warpAffine(tb, M, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT)
    Ba = cv2.warpAffine(ab, M, (w, h), borderMode=cv2.BORDER_REFLECT)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)

    # Colour-match B to A on the skin right at the seam, so the two halves agree where they meet.
    labA = cv2.cvtColor(ta, cv2.COLOR_BGR2LAB).astype(np.float32)
    labB = cv2.cvtColor(B, cv2.COLOR_BGR2LAB).astype(np.float32)
    oval = poly_mask(ta.shape, lma[OVAL])
    band_a = (yy > ycut - 0.16 * fh) & (yy < ycut - 0.02 * fh)
    band_b = (yy > ycut + 0.02 * fh) & (yy < ycut + 0.16 * fh)
    ma = skin_pixels(labA, oval, skin_lab(top_id), band_a)
    mb = skin_pixels(labB, oval, skin_lab(bot_id), band_b)
    if ma.sum() > 50 and mb.sum() > 50:
        shift = labA[ma].mean(axis=0) - labB[mb].mean(axis=0)
    else:
        shift = skin_lab(top_id) - skin_lab(bot_id)
    # Shift skin fully but dark beard/hair only a little, so beards don't pick up a colour cast.
    skin_w = 1 - smoothstep(np.linalg.norm(labB - skin_lab(bot_id), axis=2), 20, 50)
    LAST['shift'] = float(np.linalg.norm(shift))
    labB = labB + shift * (0.25 + 0.75 * skin_w)[..., None]
    B = cv2.cvtColor(np.clip(labB, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR).astype(np.float32)

    # B only contributes inside the jaw outline (extended below the chin by `overhang` for beards); neck, ears and jersey stay A's.
    lower = lma[OVAL][lma[OVAL][:, 1] >= ycut - 0.04 * fh].copy()
    lower[lower[:, 1] > ycut, 1] += overhang * fh
    jaw = poly_mask(ta.shape, lower)
    jaw = cv2.dilate(jaw, np.ones((5, 5), np.uint8))
    jaw = cv2.GaussianBlur(jaw, (0, 0), 3.0)
    seam = smoothstep(yy, ycut - feather * fh, ycut + feather * fh)
    wgt = seam * jaw
    # Mix colours weighted by opacity so backdrop pixels from either head never bleed into the result.
    a = aa * (1 - wgt) + Ba * wgt
    rgb = (ta.astype(np.float32) * (aa * (1 - wgt))[..., None] + B * (Ba * wgt)[..., None]) / np.maximum(a, 1e-4)[..., None]
    return rgb, a, lma


def has_side_hair(tid):
    """True if hair hangs beside the jaw/neck, which would leak into a half-swap as stray strands."""
    bgr, alpha, lm = load(tid)
    h, w = alpha.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    fh = lm[152][1] - lm[BROWS][:, 1].min()
    fw = lm[454][0] - lm[234][0]
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    outside = poly_mask(bgr.shape, lm[OVAL], 4) < 0.5
    ear_l, ear_r = lm[234][0], lm[454][0]
    sides = ((xx > ear_l - 0.12 * fw) & (xx < ear_l + 0.04 * fw)) | ((xx > ear_r - 0.04 * fw) & (xx < ear_r + 0.12 * fw))
    zone = (yy > lm[2][1]) & (yy < lm[152][1] + 0.1 * fh) & sides
    hairy = np.linalg.norm(lab - skin_lab(tid), axis=2) > 45
    return int((zone & outside & hairy & (alpha > 0.5)).sum()) > 120


def hair_color(tid):
    (rgb, a), _, _, _ = layer_rgba(tid)
    m = a > 0.6
    return np.median(cv2.cvtColor(rgb.astype(np.uint8), cv2.COLOR_BGR2LAB)[m].astype(np.float32), axis=0) if m.sum() > 800 else None


def sheet(pairs, path, size=192):
    cells = []
    for i, (t, b) in enumerate(pairs):
        rgb, a, lm = half_swap(t, b)
        cells.append(label(team_disc(rgb, a, lm, TEAMS[i % len(TEAMS)], size), f"top {t} bot {b}"))
    cols = 6
    rows = (len(cells) + cols - 1) // cols
    img = np.zeros((rows * size, cols * size, 3), np.uint8)
    for k, c in enumerate(cells):
        img[(k // cols) * size:(k // cols + 1) * size, (k % cols) * size:(k % cols + 1) * size] = c
    cv2.imwrite(str(OUT / path), img)
    print("wrote", path)


BAD = [("09_03", "03_02"), ("03_02", "07_05"), ("08_01", "03_10"), ("06_02", "07_06"), ("05_05", "08_04"), ("04_05", "09_05"),
       ("13_08", "01_01"), ("05_10", "13_10"), ("07_07", "08_02"), ("01_08", "07_02"), ("08_01", "03_06"), ("07_05", "06_03"),
       ("06_04", "05_05"), ("01_04", "03_10"), ("09_02", "03_03"), ("03_04", "02_02"), ("08_01", "04_03"), ("01_10", "02_01"),
       ("01_03", "06_08"), ("02_05", "08_10"), ("03_04", "05_05"), ("04_08", "01_09"), ("03_02", "09_05"), ("04_05", "09_03"),
       ("13_04", "04_08"), ("06_09", "13_01"), ("01_04", "04_10"), ("05_10", "05_04"), ("06_04", "03_05"), ("04_03", "13_08")]


def main(n, seed):
    rnd = random.Random(seed)
    hc = {d: hair_color(d) for d in donors()}
    ds = [d for d in hc if hc[d] is not None and d not in BAD_TILES]
    long_hair = {d for d in ds if has_side_hair(d)}
    print('bottom donors excluded for side hair:', len(long_hair), 'of', len(ds))
    print("same pairs as the previous sheet, new blending (tone gap / hair gap):")
    for i in (6, 10, 12, 16, 22, 23, 24, 27, 29, 30):
        t, b = BAD[i - 1]
        hg = np.linalg.norm(hc[t] - hc[b]) if hc.get(t) is not None and hc.get(b) is not None else -1
        print(f"  tile {i}: {t}/{b} tone {tone_gap(t, b):.0f} hair {hg:.0f}")
    sheet(BAD, "halfswap_same_pairs.png")
    pairs = []
    while len(pairs) < n:
        t, b = rnd.sample(ds, 2)
        if b not in long_hair and tone_gap(t, b) < TONE_HS and np.linalg.norm(hc[t] - hc[b]) < HAIR_HS:
            pairs.append((t, b))
    sheet(pairs, "halfswap_gated.png")
    ok = sum(1 for t in ds for b in ds if b not in long_hair and t != b and tone_gap(t, b) < TONE_HS and np.linalg.norm(hc[t] - hc[b]) < HAIR_HS)
    print("allowed ordered pairs under the stricter gates:", ok, "of", len(ds) * (len(ds) - 1))


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 30, int(sys.argv[2]) if len(sys.argv) > 2 else 1)
