"""Hand-made skin-tone groups (from the slashed contact sheet). Anything not listed is 'light'.

dark  = red slashes   (darkest)
brown = black slashes (medium brown / olive)
asian = green slashes (East Asian)
light = blue slashes  (light and tan)
"""
DARK = """14_02 14_10 06_07 05_09 04_06 04_02 06_01 15_06 13_07 07_01 07_07 08_02 15_02 09_08 08_08 09_01 03_09
01_02 05_02 13_03 03_02 01_10 03_05 09_03 02_08 02_02 01_08 02_10 01_04""".split()
BROWN = """06_05 07_05 13_09 06_09 07_03 14_03 14_06 15_08 09_10 14_08 05_07 04_08 08_07 03_04 13_08 02_04 03_10""".split()
ASIAN = """07_10 09_05 01_06 06_03 04_05 14_05 15_03 07_04 03_01 07_09 08_04""".split()

GROUP = {i: "dark" for i in DARK}
GROUP.update({i: "brown" for i in BROWN})
GROUP.update({i: "asian" for i in ASIAN})


import json as _json
from pathlib import Path as _Path

_EXTRA = _Path(__file__).with_name("groups_extra.json")  # heads added later (add_sheets.py); edit freely to correct a group
if _EXTRA.exists():
    GROUP.update(_json.loads(_EXTRA.read_text()))
else:
    _EXTRA.write_text("{}")


def group(tid):
    return GROUP.get(tid, "light")


def same_group(a, b):
    return group(a) == group(b)
