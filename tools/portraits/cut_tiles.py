"""Cut the 5x2 head-vault contact sheets into one PNG per head.

Usage: python cut_tiles.py <sheet_dir> <out_dir>
Sheets are numbered N.webp; tiles come out as NN_PP.png (sheet, position 1-10).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

COLS, ROWS = 5, 2


def content_rows(cell: np.ndarray) -> tuple[int, int]:
    """First/last row of the cell that is the blue backdrop (not the navy label strip or the card border above it)."""
    blue = cell[:, :, 2].astype(float).mean(axis=1)
    bright = np.where(blue > 90)[0]
    # Every cell starts with a ~35-row navy label strip, sometimes under a bright border line. Content begins at the
    # first bright row after the strip's first dark row.
    dark = next((y for y in range(min(80, len(blue))) if blue[y] < 75), None)
    top = int(bright[0]) if dark is None else int(next((y for y in bright if y > dark), bright[0]))
    return top, int(bright[-1]) + 1


def cut_sheet(sheet: Path, number: int, out_dir: Path) -> list[str]:
    """Cut one 5x2 sheet into tiles named NN_PP.png; returns the tile ids."""
    out_dir.mkdir(parents=True, exist_ok=True)
    img = Image.open(sheet).convert("RGB")
    arr = np.asarray(img)
    w, h = img.size
    cw, ch = w / COLS, h / ROWS
    ids = []
    for i in range(COLS * ROWS):
        r, c = divmod(i, COLS)
        x0, x1 = int(c * cw) + 3, int((c + 1) * cw) - 3
        y0, y1 = int(r * ch), int((r + 1) * ch)
        top, bot = content_rows(arr[y0:y1, x0:x1])
        img.crop((x0, y0 + top + 1, x1, y0 + bot - 1)).save(out_dir / f"{number:02d}_{i + 1:02d}.png")
        ids.append(f"{number:02d}_{i + 1:02d}")
    return ids


def main(sheet_dir: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for sheet in sorted(sheet_dir.glob("*.webp"), key=lambda p: int(p.stem)):
        img = Image.open(sheet).convert("RGB")
        arr = np.asarray(img)
        w, h = img.size
        cw, ch = w / COLS, h / ROWS
        for i in range(COLS * ROWS):
            r, c = divmod(i, COLS)
            x0, x1 = int(c * cw) + 3, int((c + 1) * cw) - 3
            y0, y1 = int(r * ch), int((r + 1) * ch)
            top, bot = content_rows(arr[y0:y1, x0:x1])
            tile = img.crop((x0, y0 + top + 1, x1, y0 + bot - 1))
            tile.save(out_dir / f"{int(sheet.stem):02d}_{i + 1:02d}.png")
        print("cut", sheet.name)


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
