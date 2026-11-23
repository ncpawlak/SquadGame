"""Prepares the Pro Squad League emblem for the game.

    python tools/prep_psl_logo.py <source image> [--icon]

The source art is on a white background. This flood-fills the white that touches the image edge to transparent
(white *inside* the emblem, like the keyline and helmet, is kept), crops to the emblem, pads it to a square, and
writes assets/branding/psl_logo.png. With --icon it also points the project icon at it.
Needs Pillow:  pip install pillow
"""
import re
import sys
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "branding" / "psl_logo.png"
THRESH = 235  # a pixel counts as background white when all channels are above this


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    img = Image.open(args[0]).convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y * w + x]:
            continue
        r, g, b, _ = px[x, y]
        if min(r, g, b) < THRESH:
            continue
        seen[y * w + x] = 1
        px[x, y] = (255, 255, 255, 0)
        q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    bbox = img.getbbox()
    img = img.crop(bbox)
    side = max(img.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    if side > 1024:
        square = square.resize((1024, 1024), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    square.save(OUT)
    print("wrote", OUT, square.size)
    if "--icon" in sys.argv:
        proj = ROOT / "project.godot"
        text = proj.read_text(encoding="utf-8")
        line = 'config/icon="res://assets/branding/psl_logo.png"'
        if "config/icon=" in text:
            text = re.sub(r'config/icon=".*"', line, text)
        else:
            text = text.replace('config/features=', line + "\nconfig/features=", 1)
        proj.write_text(text, encoding="utf-8")
        print("project icon set")


if __name__ == "__main__":
    main()
