"""Sheet of every head, pre-sorted into proposed skin-tone groups, for manual correction."""
import cv2
import numpy as np
from spike import OUT, PREP, load, skin_lab

K = 6
ids = sorted(p.stem for p in PREP.glob("*.npz"))
labs = np.array([skin_lab(i) for i in ids], np.float32)
_, lab_idx, centers = cv2.kmeans(labs, K, None, (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 100, 0.01), 10, cv2.KMEANS_PP_CENTERS)
order = np.argsort(centers[:, 0])            # group A = darkest ... F = lightest
rank = {int(g): n for n, g in enumerate(order)}
groups = {n: [] for n in range(K)}
for i, g in zip(ids, lab_idx.ravel()):
    groups[rank[int(g)]].append(i)
W, H, COLS = 104, 120, 12
rows_total = sum((len(v) + COLS - 1) // COLS for v in groups.values())
sheet = np.full((rows_total * H, COLS * W, 3), 24, np.uint8)
r = 0
for n in range(K):
    members = sorted(groups[n], key=lambda i: skin_lab(i)[0])
    print("group", "ABCDEF"[n], len(members), "L", round(float(centers[order[n]][0]) / 2.55))
    for k, i in enumerate(members):
        bgr, _, lm = load(i)
        x0 = int(lm[234][0] - 0.25 * (lm[454][0] - lm[234][0])); x1 = int(lm[454][0] + 0.25 * (lm[454][0] - lm[234][0]))
        y0 = int(lm[10][1] - 40); y1 = int(lm[152][1] + 25)
        crop = cv2.resize(bgr[max(0, y0):y1, max(0, x0):x1], (W - 4, H - 4))
        cell = sheet[(r + k // COLS) * H:(r + k // COLS + 1) * H, (k % COLS) * W:(k % COLS + 1) * W]
        cell[2:-2, 2:-2] = crop
        cv2.rectangle(cell, (0, 0), (W - 1, 14), (0, 0, 0), -1)
        cv2.putText(cell, f"{'ABCDEF'[n]} {i}", (3, 11), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 255), 1, cv2.LINE_AA)
    r += (len(members) + COLS - 1) // COLS
cv2.imwrite(str(OUT / "tone_groups.png"), sheet)
print("wrote tone_groups.png", sheet.shape)
