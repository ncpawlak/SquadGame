"""Segment each donor's hair and beard with SAM2, prompted automatically from the face landmarks.

    python sam_masks.py            # all donors -> work/sam/<id>_hair.png, <id>_beard.png
    python sam_masks.py 01_01 ...  # just these
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).parent
os.environ.setdefault("HF_HOME", str(HERE / "models/hf"))

import cv2
import numpy as np
import torch
from transformers import Sam2Model, Sam2Processor

from spike import BROWS, OVAL, SKIP_DONOR, load

MODEL_ID = "facebook/sam2.1-hiera-tiny"
OUT = HERE / "work/sam"


def pt(lm, i, dx=0.0, dy=0.0):
    return [float(lm[i][0] + dx), float(lm[i][1] + dy)]


class Segmenter:
    def __init__(self):
        self.proc = Sam2Processor.from_pretrained(MODEL_ID)
        self.model = Sam2Model.from_pretrained(MODEL_ID).eval()

    def mask(self, rgb, points, labels, box):
        box = [float(v) for v in box]
        inputs = self.proc(images=rgb, input_points=[[points]], input_labels=[[labels]], input_boxes=[[box]], return_tensors="pt")
        with torch.no_grad():
            out = self.model(**inputs, multimask_output=False)
        m = self.proc.post_process_masks(out.pred_masks.cpu(), inputs["original_sizes"])[0]
        return (m[0, 0].numpy() > 0).astype(np.uint8)


def prompts(lm, shape):
    h, w = shape[:2]
    fw = lm[454][0] - lm[234][0]
    top = lm[BROWS][:, 1].min()
    fh = lm[152][1] - top
    cx = float(lm[1][0])
    # Hair: crown and temples positive; forehead, cheeks, nose, chin and jersey negative.
    hair_pts = [pt(lm, 10, 0, -0.16 * fh), pt(lm, 10, -0.28 * fw, -0.04 * fh), pt(lm, 10, 0.28 * fw, -0.04 * fh),
                pt(lm, 9, 0, -0.02 * fh), pt(lm, 117), pt(lm, 346), pt(lm, 1), pt(lm, 152), [cx, h - 6.0]]
    hair_lab = [1, 1, 1, 0, 0, 0, 0, 0, 0]
    hair_box = [max(0.0, lm[234][0] - 0.45 * fw), max(0.0, lm[10][1] - 0.7 * fh), min(w - 1.0, lm[454][0] + 0.45 * fw), lm[2][1]]
    # Beard: chin, jaw, mustache positive; lips, nose, eyes, forehead and jersey negative.
    beard_pts = [pt(lm, 152, 0, 0.0), pt(lm, 200), pt(lm, 172, 0.02 * fw, 0), pt(lm, 397, -0.02 * fw, 0), pt(lm, 205), pt(lm, 425),
                 pt(lm, 164, 0, 0.0), pt(lm, 13), pt(lm, 1), pt(lm, 159), pt(lm, 386), pt(lm, 10), [cx, h - 6.0]]
    beard_lab = [1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0]
    beard_box = [lm[234][0] - 0.05 * fw, lm[1][1], lm[454][0] + 0.05 * fw, min(h - 1.0, lm[152][1] + 0.2 * fh)]
    return (hair_pts, hair_lab, hair_box), (beard_pts, beard_lab, beard_box)


def main(ids):
    OUT.mkdir(parents=True, exist_ok=True)
    seg = Segmenter()
    for tid in ids:
        bgr, _, lm = load(tid)
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        (hp, hl, hb), (bp, bl, bb) = prompts(lm, bgr.shape)
        if not os.environ.get("BEARD_ONLY"):
            cv2.imwrite(str(OUT / f"{tid}_hair.png"), seg.mask(rgb, hp, hl, hb) * 255)
        cv2.imwrite(str(OUT / f"{tid}_beard.png"), seg.mask(rgb, bp, bl, bb) * 255)
        print("sam", tid, flush=True)


if __name__ == "__main__":
    ids = sys.argv[1:] or [p.stem for p in sorted((HERE / "work/prep").glob("*.npz")) if p.stem not in SKIP_DONOR]
    main(ids)
