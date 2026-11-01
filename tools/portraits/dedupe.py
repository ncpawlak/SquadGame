"""List near-duplicate tiles (same head appearing on two sheets)."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

tiles = sorted(Path(sys.argv[1]).glob("*.png"))
vecs = []
for p in tiles:
    im = Image.open(p).convert("L").resize((32, 36))
    v = np.asarray(im, float).ravel()
    vecs.append((v - v.mean()) / (v.std() + 1e-6))
keep, dup = [], []
for i, p in enumerate(tiles):
    for j in keep:
        if float(np.dot(vecs[i], vecs[j])) / len(vecs[i]) > 0.97:
            dup.append((p.stem, tiles[j].stem)); break
    else:
        keep.append(i)
print("unique", len(keep), "dups", len(dup))
for a, b in dup: print(a, "=", b)
Path(sys.argv[2]).write_text("\n".join(tiles[i].stem for i in keep))
