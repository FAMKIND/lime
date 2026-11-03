"""LIME-284a4, step 3: put lime's UI on the phone and (optionally) re-tint the backdrop.

    python composite.py SOURCE.mp4 quads.npy RECORDING.mp4 OUT.mp4 --bg a|b

- The recording (lime's scroll on a simulator) is perspective-warped into each frame's screen quad, but only where the
  original pixels are near-white, so the thumbs and the phone's notch stay on top. Shading follows the original, so
  the thumbs' shadows fall across the UI.
- --bg a keeps the pink/lavender backdrop; --bg b swaps it for lime's warm paper with a faint green glow that
  ends in #f9f8f4 at the bottom, by keying the smooth backdrop against a colour model fitted once for the whole shot.
- The last second dissolves into the first so the loop has no jump.
Output is 1920x1080, cropped around the phone.
"""
import argparse
import subprocess
import sys

import cv2
import numpy as np

W, H = 2048, 1080
CX0, CW = 25, 1920  # crop: phone centred
XFADE = 25


def lab(img):
    return cv2.cvtColor(img.astype(np.float32) / 255.0, cv2.COLOR_BGR2LAB)


def fit_backdrop(frames):
    """A cubic surface in Lab over the median of a few frames: the backdrop is a smooth gradient."""
    med = np.median(np.stack(frames), axis=0).astype(np.uint8)
    small = cv2.resize(med, (256, 135), interpolation=cv2.INTER_AREA)
    L = lab(small).reshape(-1, 3)
    yy, xx = np.mgrid[0:135, 0:256]
    x, y = (xx / 255.0).ravel(), (yy / 134.0).ravel()
    basis = np.stack([x ** i * y ** j for i in range(4) for j in range(4) if i + j <= 3], axis=1)
    w = ((y < 0.35) | (x < 0.18) | (x > 0.8)).astype(np.float32)
    for _ in range(6):
        coef = np.linalg.lstsq(basis * w[:, None], L * w[:, None], rcond=None)[0]
        err = np.linalg.norm(basis @ coef - L, axis=1)
        w = ((err < 6) & ((y < 0.6) | (x < 0.25) | (x > 0.75))).astype(np.float32)
    field = (basis @ coef).reshape(135, 256, 3).astype(np.float32)
    return cv2.resize(field, (W, H), interpolation=cv2.INTER_CUBIC)


def target_backdrop():
    """lime's warm paper with a faint green glow, ending in canvas #f9f8f4 (BGR)."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    top, bot = np.array([0xe6, 0xea, 0xec], np.float32), np.array([0xf4, 0xf8, 0xf9], np.float32)  # #ecEAe6 -> #f9f8f4
    t = (yy / (H - 1))[..., None]
    base = top * (1 - t) + bot * t
    glow = np.array([0xbe, 0xf3, 0xd4], np.float32)  # a pale lime
    g = np.exp(-(((xx - 990) / 520) ** 2 + ((yy - 470) / 420) ** 2))[..., None] * 0.55
    return base * (1 - g) + glow * g


def smoothstep(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("quads"); ap.add_argument("rec"); ap.add_argument("out")
    ap.add_argument("--bg", choices=["a", "b"], default="b")
    ap.add_argument("--ffmpeg", required=True)
    a = ap.parse_args()
    quads = np.load(a.quads)
    src, rec = cv2.VideoCapture(a.src), cv2.VideoCapture(a.rec)

    frames = []
    while True:
        ok, f = src.read()
        if not ok:
            break
        frames.append(cv2.resize(f, (W, H), interpolation=cv2.INTER_AREA))
    n = len(frames)
    recs = []
    while len(recs) < n:
        ok, r = rec.read()
        if not ok:
            recs.append(recs[-1]); continue
        r = cv2.resize(r, (298, 647), interpolation=cv2.INTER_AREA)
        # the simulator's Dynamic Island hangs below the photo's notch: paint it out with the row just under it
        r[2:44, 78:220] = r[46:47, 78:220]
        recs.append(r)
    rh, rw = recs[0].shape[:2]
    rec_corners = np.float32([[0, 0], [rw, 0], [rw, rh], [0, rh]])

    if a.bg == "b":
        field = fit_backdrop(frames[::25])
        field_bgr = cv2.cvtColor(field, cv2.COLOR_LAB2BGR) * 255.0
        target = target_backdrop()

    out_frames = []
    for i, f in enumerate(frames):
        f32 = f.astype(np.float32)
        quad = quads[i].astype(np.float32)
        # the screen: near-white pixels of the biggest bright blob (the thumbs and notch are not)
        mn = f.min(axis=2)
        white = (mn > 222).astype(np.uint8)
        nlab, lbl, st, _ = cv2.connectedComponentsWithStats(white[100:1000, 600:1400])
        k = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        blob = np.zeros((H, W), np.uint8); blob[100:1000, 600:1400] = (lbl == k)
        region = cv2.dilate(blob, np.ones((9, 9), np.uint8)).astype(np.float32)
        alpha = smoothstep(mn.astype(np.float32), 170, 232) * cv2.GaussianBlur(region, (0, 0), 1.0)

        M = cv2.getPerspectiveTransform(rec_corners, quad)
        ui = cv2.warpPerspective(recs[i], M, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE).astype(np.float32)
        ref = np.percentile(mn[blob > 0], 90)
        shade = np.clip(cv2.GaussianBlur(mn.astype(np.float32), (0, 0), 2) / ref, 0.55, 1.0)[..., None]
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        glare = (np.clip(1 - np.abs((xx - quad[0, 0]) * 0.6 + (yy - quad[0, 1]) * 0.8 - 160) / 90, 0, 1) * 5.0)[..., None]
        ui = np.clip(ui * (0.965 + 0.035 * shade) * shade ** 0.5 + glare, 0, 255)

        base = f32
        if a.bg == "b":
            d = np.linalg.norm(lab(f) - field, axis=2)
            bgw = (1 - smoothstep(d, 3.5, 9.0))[..., None]
            bgw = cv2.GaussianBlur(bgw, (0, 0), 0.8)[..., None] if bgw.ndim == 2 else cv2.GaussianBlur(bgw[..., 0], (0, 0), 0.8)[..., None]
            resid = (f32 - field_bgr) * 0.7
            # the rim of the hands carries the old lavender: warm the darker, non-backdrop pixels toward skin
            lb = lab(f)
            warm = smoothstep(80 - lb[..., 0], 2, 18) * (1 - bgw[..., 0])
            lb2 = lb.copy(); lb2[..., 2] = lb[..., 2] + warm * np.clip(10 - lb[..., 2], 0, 25) * 0.8
            lb2[..., 1] = lb[..., 1] + warm * np.clip(14 - lb[..., 1], 0, 25) * 0.25
            f32 = cv2.cvtColor(lb2.astype(np.float32), cv2.COLOR_LAB2BGR) * 255.0
            base = f32 * (1 - bgw) + (target + resid) * bgw
        comp = base * (1 - alpha[..., None]) + ui * alpha[..., None]
        out_frames.append(np.clip(comp, 0, 255).astype(np.uint8)[:, CX0:CX0 + CW, :][:1080])
        if i % 100 == 0:
            print("frame", i, "of", n, file=sys.stderr)

    # a loop with no jump: the last XFADE frames dissolve into the first ones
    m = n - XFADE
    seq = []
    for k in range(m):
        if k < XFADE:
            t = k / XFADE
            seq.append((out_frames[m + k].astype(np.float32) * (1 - t) + out_frames[k].astype(np.float32) * t).astype(np.uint8))
        else:
            seq.append(out_frames[k])
    p = subprocess.Popen([a.ffmpeg, "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{CW}x1080", "-r", "25",
                          "-i", "-", "-c:v", "libx264", "-crf", "12", "-preset", "medium", "-pix_fmt", "yuv420p", a.out], stdin=subprocess.PIPE)
    for fr in seq:
        p.stdin.write(fr.tobytes())
    p.stdin.close(); p.wait()
    cv2.imwrite(a.out.replace(".mp4", "-poster.png"), seq[XFADE + 5])


main()
