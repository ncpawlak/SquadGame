"""Engine v3: hand-grouped skin tones. Bald-base half-swaps (optionally with a beard bottom) + hair layer, all within one group.

    python compose.py [per_group] [seed]   # writes work/compose_best.png and work/compose_random.png
"""
import random
import sys

import cv2
import numpy as np

from groups import group
from halfswap import BAD_TILES, BALD, LAST, has_side_hair, half_swap
from spike import ALIGN, OUT, TEAMS, donors, label, layer_rgba, load, over, team_disc, warp_to

BASES = BALD + ["07_09"]
HEAD_TATTOO = {"05_07", "08_07"}   # tattoo on the scalp would leak through as "hair"
FULL_BEARD = 0.45                  # minimum beard coverage of the lower face
HAIR_BEARD = 25.0                  # max Lab distance between hair colour and beard colour
GROUPS = ["light", "dark", "brown", "asian"]

_layers = {}


def get(tid):
    if tid not in _layers:
        hair, beard, lm, cov = layer_rgba(tid)
        m = hair[1] > 0.6
        hc = np.median(cv2.cvtColor(hair[0].astype(np.uint8), cv2.COLOR_BGR2LAB)[m].astype(np.float32), axis=0) if m.sum() > 800 else None
        mb = beard[1] > 0.6
        bc = np.median(cv2.cvtColor(beard[0].astype(np.uint8), cv2.COLOR_BGR2LAB)[mb].astype(np.float32), axis=0) if mb.sum() > 300 else None
        _layers[tid] = dict(hair=hair, lm=lm, cov=cov, hc=hc, bc=bc)
    return _layers[tid]


def distortion(top, bot):
    """How hard the bottom head has to be stretched to fit the top head (0 = none)."""
    _, _, lma = load(top)
    _, _, lmb = load(bot)
    M, _ = cv2.estimateAffine2D(lmb[ALIGN], lma[ALIGN], method=cv2.LMEDS)
    s = np.linalg.svd(M[:, :2], compute_uv=False)
    return abs(s[0] / s[1] - 1) + abs(np.sqrt(s[0] * s[1]) - 1)


def render(recipe):
    top, bot, hair_id = recipe
    rgb, a, lm = half_swap(top, bot, overhang=0.16 if bot not in BASES else 0.02)
    shift = LAST["shift"]
    L = get(hair_id)
    rgb, a = over(rgb, a, *warp_to(L["hair"], L["lm"], lm, a.shape))
    return rgb, a, lm, shift


def pools(g):
    ds = [d for d in donors() if group(d) == g and d not in BAD_TILES and d not in HEAD_TATTOO and get(d)["hc"] is not None]
    bald = [b for b in BASES if group(b) == g]
    beards = [d for d in ds if get(d)["cov"] > FULL_BEARD and get(d)["bc"] is not None and not has_side_hair(d)]
    return ds, bald, beards


def candidates(rnd, g, n):
    ds, bald, beards = pools(g)
    print(f"{g}: hair donors {len(ds)}, bald bases {len(bald)}, beard bottoms {len(beards)}", flush=True)
    out = []
    while len(out) < n:
        top = rnd.choice(bald)
        if beards and rnd.random() < 0.5:
            bot = rnd.choice(beards)
            ok = [d for d in ds if np.linalg.norm(get(d)["hc"] - get(bot)["bc"]) < HAIR_BEARD]
            if not ok:
                continue
            gap = 0.3 * float(np.linalg.norm(get(rnd.choice(ok))["hc"] - get(bot)["bc"]))
            out.append((top, bot, rnd.choice(ok)))
        else:
            bot = rnd.choice([b for b in bald if b != top] or bald)
            if bot == top:
                continue
            out.append((top, bot, rnd.choice(ds)))
    return out


def score(recipe):
    top, bot, hair_id = recipe
    s = 30 * distortion(top, bot)
    half_swap(top, bot, overhang=0.16 if bot not in BASES else 0.02)
    s += 0.5 * LAST["shift"]
    if get(bot)["bc"] is not None and bot in BASES is False:
        s += 0.3 * float(np.linalg.norm(get(hair_id)["hc"] - get(bot)["bc"]))
    if bot not in BASES:
        s += 0.3 * float(np.linalg.norm(get(hair_id)["hc"] - get(bot)["bc"]))
    return s


def sheet(items, path, size=192):
    cells = []
    for i, (r, sc) in enumerate(items):
        rgb, a, lm, _ = render(r)
        kind = "beard" if r[1] not in BASES else "clean"
        cells.append(label(team_disc(rgb, a, lm, TEAMS[i % len(TEAMS)], size), f"{group(r[0])[:3]} {r[0][3:]}/{r[1]} h{r[2]} {kind} {sc:.0f}"))
    cols = 8
    rows = (len(cells) + cols - 1) // cols
    img = np.zeros((rows * size, cols * size, 3), np.uint8)
    for k, c in enumerate(cells):
        img[(k // cols) * size:(k // cols + 1) * size, (k % cols) * size:(k % cols + 1) * size] = c
    cv2.imwrite(str(OUT / path), img)
    print("wrote", path, img.shape, flush=True)


def main(per_group, seed):
    rnd = random.Random(seed)
    best, rand = [], []
    for g in GROUPS:
        pool = candidates(rnd, g, 150)
        sc = [score(r) for r in pool]
        order = np.argsort(sc)
        best += [(pool[i], sc[i]) for i in order[:per_group]]
        rand += [(pool[i], sc[i]) for i in range(per_group)]
        print(g, "score best", round(min(sc)), "median", round(float(np.median(sc))), "worst", round(max(sc)), flush=True)
    sheet(best, "compose_best.png")
    sheet(rand, "compose_random.png")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 8, int(sys.argv[2]) if len(sys.argv) > 2 else 1)
