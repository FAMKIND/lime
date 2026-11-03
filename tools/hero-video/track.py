"""LIME-284a4, step 2: find the white phone screen's four corners in every frame of the source video.

Works at 2048x1080 (half of the 4K source). The screen is the biggest near-white blob; the thumbs bite into its
bottom, so the corners come from lines fitted to the clean parts (left/right edges and the top edge beside the
notch), and the bottom edge from the lowest visible white. Corners are smoothed over time so they don't jitter.

    python track.py SOURCE.mp4 quads.npy
"""
import sys
import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d

W, H = 2048, 1080
RX0, RY0, RX1, RY1 = 600, 100, 1400, 1000  # where the phone lives


def screen_mask(frame):
    roi = frame[RY0:RY1, RX0:RX1]
    m = (roi.min(axis=2) > 222).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    k = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    return (lab == k)


def fit_quad(mm):
    ys, xs = np.nonzero(mm)
    top = ys.min()
    rows = np.arange(top + 70, top + 260)
    L, R = [], []
    for y in rows:
        xr = np.nonzero(mm[y])[0]
        if len(xr):
            L.append(xr.min()); R.append(xr.max())
    L, R = np.array(L), np.array(R)
    al, bl = np.polyfit(rows, L, 1)
    ar, br = np.polyfit(rows, R, 1)
    # the top edge: first white row of each column on the shoulders, away from the notch
    left_x, right_x = L.min(), R.max()
    cols = np.arange(left_x + 45, right_x - 45)
    first = np.array([np.nonzero(mm[:, c])[0].min() if mm[:, c].any() else 10**6 for c in cols])
    shoulder = first <= np.percentile(first, 20) + 6
    s, c0 = np.polyfit(cols[shoulder], first[shoulder], 1)
    # the bottom edge: the lowest white in the columns (thumbs only ever make it higher)
    last = np.array([np.nonzero(mm[:, c])[0].max() if mm[:, c].any() else -1 for c in cols])
    bottom = np.percentile(last[last > 0], 97)
    c1 = bottom - s * cols[np.argmin(np.abs(last - bottom))]

    def corner(c, a, b):  # top/bottom line y = c + s x, side line x = a y + b
        y = (c + s * b) / (1 - s * a)
        return [a * y + b, y]

    return np.array([corner(c0, al, bl), corner(c0, ar, br), corner(c1, ar, br), corner(c1, al, bl)]) + [RX0, RY0]


def main(src, out):
    cap = cv2.VideoCapture(src)
    quads = []
    while True:
        ok, f = cap.read()
        if not ok:
            break
        f = cv2.resize(f, (W, H), interpolation=cv2.INTER_AREA)
        quads.append(fit_quad(screen_mask(f)))
    q = np.array(quads)
    # a tiny median filter drops the odd frame whose thumb confuses the fit, then a gentle blur
    from scipy.signal import medfilt
    for i in range(4):
        for j in range(2):
            q[:, i, j] = medfilt(q[:, i, j], 7)
    q = gaussian_filter1d(q, 2.5, axis=0, mode="nearest")
    np.save(out, q)
    print(len(q), "frames; screen about", np.round(np.linalg.norm(q[:, 1] - q[:, 0], axis=1).mean()), "x",
          np.round(np.linalg.norm(q[:, 3] - q[:, 0], axis=1).mean()), "px")


if __name__ == "__main__":
    main(*sys.argv[1:3])
