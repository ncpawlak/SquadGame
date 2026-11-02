"""Add new 10-head sheets to the pool in one step.

    python add_sheets.py <sheet.webp|png|jpg> [more sheets...]

For each sheet: copy it into assets/portraits/source/ under the next free sheet number, cut the 5x2 tiles, remove the
backdrop and find landmarks, skip heads already in the pool, propose a skin group for each new head (nearest existing
group), write a review sheet, then re-bake assets/portraits/. Correct any group by editing groups_extra.json
(or tell Claude) and re-run `python bake.py`.
"""
import json
import shutil
import sys
from pathlib import Path

import cv2
import numpy as np

import bake
from cut_tiles import cut_sheet
from groups import GROUP, group
from spike import OUT, PREP, TILES, fix_edge_band, key_background, landmarker, landmarks, skin_lab

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/portraits/source"
EXTRA = Path(__file__).with_name("groups_extra.json")
GROUPS = ["dark", "brown", "asian", "light"]


def next_number() -> int:
    return max([int(p.stem) for p in SOURCE.glob("*") if p.stem.isdigit()] + [15]) + 1


def thumb(a):
    g = cv2.cvtColor(a, cv2.COLOR_BGR2GRAY)
    v = cv2.resize(g, (32, 36)).astype(np.float32).ravel()
    return (v - v.mean()) / (v.std() + 1e-6)


THUMBS = Path(__file__).with_name("work") / "thumb_cache.npz"


def existing_thumbs():
    """Duplicate-check thumbnails for every tile; only new or changed tiles are decoded (cache in work/thumb_cache.npz)."""
    cache = {}
    if THUMBS.exists():
        z = np.load(THUMBS, allow_pickle=True)
        cache = {n: (m, v) for n, m, v in zip(z["names"], z["mtimes"], z["vecs"])}
    out, fresh = {}, False
    for p in TILES.glob("*.png"):
        m = p.stat().st_mtime_ns
        if p.stem in cache and cache[p.stem][0] == m:
            out[p.stem] = cache[p.stem][1]
        else:
            out[p.stem] = thumb(cv2.imread(str(p)))
            cache[p.stem] = (m, out[p.stem])
            fresh = True
    if fresh:
        names = sorted(out)
        np.savez(THUMBS, names=np.array(names), mtimes=np.array([cache[n][0] for n in names]), vecs=np.stack([out[n] for n in names]))
    return out


def centroids():
    cs = {}
    for g in GROUPS:
        ids = [p.stem for p in PREP.glob("*.npz") if group(p.stem) == g]
        if ids:
            cs[g] = np.mean([skin_lab(i) for i in ids], axis=0)
    return cs


def main(files):
    SOURCE.mkdir(parents=True, exist_ok=True)
    lmk = landmarker()
    seen = existing_thumbs()
    cents = centroids()
    extra = json.loads(EXTRA.read_text()) if EXTRA.exists() else {}
    added = []
    for f in map(Path, files):
        n = next_number()
        dst = SOURCE / f"{n}{f.suffix.lower()}"
        shutil.copy(f, dst)
        for tid in cut_sheet(dst, n, TILES):
            tile = cv2.imread(str(TILES / f"{tid}.png"))
            t = thumb(tile)
            dup = next((o for o, v in seen.items() if float(np.dot(t, v)) / len(t) > 0.97), None)
            if dup:
                print(f"  {tid}: duplicate of {dup}, skipped")
                (TILES / f"{tid}.png").unlink()
                continue
            seen[tid] = t
            tile = fix_edge_band(tile)
            lm = landmarks(lmk, tile)
            if lm is None:
                print(f"  {tid}: no face found, skipped")
                continue
            clean, alpha = key_background(tile, lm)
            np.savez_compressed(PREP / f"{tid}.npz", bgr=clean, alpha=alpha, lm=lm)
            lab = skin_lab(tid)
            g = min(cents, key=lambda k: float(np.linalg.norm(cents[k] - lab)))
            extra[tid] = g
            GROUP[tid] = g
            added.append(tid)
        print(f"sheet {f.name} -> source/{dst.name}")
    EXTRA.write_text(json.dumps(extra, indent=1, sort_keys=True))
    if not added:
        print("no new heads")
        return
    W, H = 150, 175
    sheet = np.zeros((((len(added) + 9) // 10) * H, 10 * W, 3), np.uint8)
    for k, tid in enumerate(added):
        z = np.load(PREP / f"{tid}.npz")
        a = z["alpha"][..., None]
        comp = z["bgr"] * a + np.array([255, 0, 255]) * (1 - a)
        c = cv2.resize(comp.astype(np.uint8), (W, H), interpolation=cv2.INTER_AREA)
        cv2.putText(c, f"{tid} {group(tid)}", (3, 12), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 255), 1, cv2.LINE_AA)
        sheet[(k // 10) * H:(k // 10 + 1) * H, (k % 10) * W:(k % 10 + 1) * W] = c
    cv2.imwrite(str(OUT / "new_heads_review.png"), sheet)
    bake.main()
    print(f"added {len(added)} heads; review proposed groups in {OUT / 'new_heads_review.png'}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
