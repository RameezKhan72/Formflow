"""Packs the Blender frames into small looping H.264 videos and stills.

    python3 package_video.py FRAMES_DIR exercises.json ASSETS_DIR [size]

For each exercise (frames <id>_NN.png with alpha, from pose_render.py):
  exercise_video/<id>.mp4   ping-pong loop (alternating exercises play the
                            left side, then the right side), yuv420p, faststart
  thumbs/<id>.webp          still of the key position (end of the movement)
Frames are composited on the app's demo gradient so video, still and the
surrounding card match.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

FRAMES, EXJSON, ASSETS = sys.argv[1:4]
SIZE = int(sys.argv[4]) if len(sys.argv) > 4 else 320
TOP, BOTTOM = (28, 35, 80), (13, 16, 41)
os.makedirs(os.path.join(ASSETS, 'exercise_video'), exist_ok=True)
os.makedirs(os.path.join(ASSETS, 'thumbs'), exist_ok=True)


def background(size):
    t = np.linspace(0, 1, size)[:, None, None]
    col = np.array(TOP) * (1 - t) + np.array(BOTTOM) * t
    img = np.repeat(col, size, axis=1)
    # soft vignette
    y, x = np.mgrid[0:size, 0:size] / (size - 1) - 0.5
    v = np.clip(1 - (x * x + y * y) * 0.9, 0.55, 1)[..., None]
    return Image.fromarray((img * v).astype('uint8'), 'RGB').convert('RGBA')


def frames_for(eid):
    out = []
    i = 0
    while os.path.exists(os.path.join(FRAMES, '%s_%02d.png' % (eid, i))):
        out.append(os.path.join(FRAMES, '%s_%02d.png' % (eid, i)))
        i += 1
    return out


def comp(path, bg, size):
    im = Image.open(path).convert('RGBA')
    b = bg.resize(im.size)
    b.alpha_composite(im)
    return b.convert('RGB').resize((size, size), Image.LANCZOS)


data = json.load(open(EXJSON))
tot_v = tot_t = 0
for ex in data['exercises']:
    eid = ex['id']
    files = frames_for(eid)
    if not files:
        print('missing', eid)
        continue
    bg = background(512)
    kf = ex['keyframes']
    timed = ex['mode'] == 'timed'
    alt = bool(kf.get('alternate')) and not timed
    # still: key position (end of side A) for reps, the hold for timed
    n = len(files) // 2 if alt else len(files)
    still_src = files[0] if timed else files[n - 1]
    st = comp(still_src, bg, 360)
    p = os.path.join(ASSETS, 'thumbs', eid + '.webp')
    st.save(p, 'WEBP', quality=80, method=6)
    tot_t += os.path.getsize(p)
    if timed:
        continue
    sides = [files[:n], files[n:]] if alt else [files]
    seq = []
    for side in sides:
        seq += side + side[-2:0:-1]
    period = kf.get('period', 2.4)
    fps = (2 * (n - 1)) / period
    tmp = tempfile.mkdtemp()
    try:
        for i, f in enumerate(seq):
            comp(f, bg, SIZE).save(os.path.join(tmp, '%04d.png' % i))
        out = os.path.join(ASSETS, 'exercise_video', eid + '.mp4')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', '%.4f' % fps, '-i', os.path.join(tmp, '%04d.png'),
                        '-c:v', 'libx264', '-profile:v', 'main', '-level', '3.1', '-pix_fmt', 'yuv420p', '-crf', '22',
                        '-preset', 'slow', '-tune', 'animation', '-g', str(len(seq)), '-movflags', '+faststart', '-an', out],
                       check=True)
        tot_v += os.path.getsize(out)
    finally:
        shutil.rmtree(tmp)
    print(eid, len(seq), 'frames', round(fps, 1), 'fps', os.path.getsize(out) // 1024, 'KB', flush=True)
print('videos %.1f MB, stills %.1f MB' % (tot_v / 1e6, tot_t / 1e6))
