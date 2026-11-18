#!/usr/bin/env python3
"""LIME-349d: join scrolled screenshots of one screen into one tall picture (the website's article, which the phone player scrolls).

usage: stitch.py out.png frame0.png frame1.png ...   (frames in scroll order; each is the same screen scrolled further by a drag)
The status bar and header at the top and the floating bar at the bottom are fixed: only the band between TOP and BOTTOM is matched. The first frame
keeps its top (status bar, header); every later frame adds only the rows that are new. Needs numpy and Pillow."""
import sys

import numpy as np
from PIL import Image

TOP, BOTTOM = 420, 2250   # in pixels of a 1206 x 2622 screenshot


def gray(im):
    return np.asarray(im.convert("L"), dtype=np.float32)


def shift_between(a, b):
    """How far the content moved up from frame a to frame b (pixels), or 0 if it did not."""
    best, best_s = None, 0
    for s in range(40, 1700, 2):
        ra, rb = a[TOP + s:BOTTOM], b[TOP:BOTTOM - s]
        if len(ra) < 250:
            break
        e = float(np.mean(np.abs(ra - rb)))
        if best is None or e < best:
            best, best_s = e, s
    return best_s if best is not None and best < 6 else 0


def main():
    out, paths = sys.argv[1], sys.argv[2:]
    frames = [Image.open(p).convert("RGB") for p in paths]
    grays = [gray(f) for f in frames]
    pieces = [np.asarray(frames[0])[:BOTTOM]]
    for k in range(1, len(frames)):
        s = shift_between(grays[k - 1], grays[k])
        print(f"frame {k}: scrolled {s}px")
        if s == 0:
            break
        pieces.append(np.asarray(frames[k])[BOTTOM - s:BOTTOM])
    tall = np.concatenate(pieces, axis=0)
    Image.fromarray(tall).save(out)
    print("tall", tall.shape)


main()
