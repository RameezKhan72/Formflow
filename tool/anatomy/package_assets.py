"""Packs the Blender renders into compact app assets.

    python3 package_assets.py MAP_DIR POSES_DIR exercises.json ASSETS_DIR

Outputs (under ASSETS_DIR):
  anatomy3d/body_front.webp, body_back.webp      shaded realistic figure
  anatomy3d/mask_<view>_<muscle>.webp            coverage masks (alpha)
  anatomy3d/id_<view>.png                        tap map (gray = (index+1)*16)
  anatomy3d/meta.json                            muscle boxes per view
  exercise_anim/<id>.webp                        looping animated WebP
  thumbs/<id>.webp                               192 px still
"""
import json
import os
import sys

from PIL import Image

MAP, POSES, EXJSON, ASSETS = sys.argv[1:5]
GROUPS = ['chest', 'abs', 'obliques', 'lats', 'traps', 'shoulders', 'biceps', 'triceps', 'forearms',
          'lower_back', 'glutes', 'quads', 'hamstrings', 'calves']
os.makedirs(f'{ASSETS}/anatomy3d', exist_ok=True)
os.makedirs(f'{ASSETS}/exercise_anim', exist_ok=True)
os.makedirs(f'{ASSETS}/thumbs', exist_ok=True)


def size(p):
    return os.path.getsize(p) / 1024


# ---- body map
meta = {'groups': GROUPS, 'views': {}}
total = 0
for view in ('front', 'back'):
    body = Image.open(f'{MAP}/body_{view}.png').convert('RGBA')
    W, H = body.size
    p = f'{ASSETS}/anatomy3d/body_{view}.webp'
    body.save(p, 'WEBP', quality=86, method=6)
    total += size(p)
    boxes = {}
    for g in GROUPS:
        m = Image.open(f'{MAP}/mask_{view}_{g}.png').convert('RGBA').getchannel('A')
        bb = m.point(lambda v: 255 if v > 60 else 0).getbbox()
        if bb is None or (bb[2] - bb[0]) * (bb[3] - bb[1]) < 40:
            continue
        boxes[g] = [bb[0] / W, bb[1] / H, bb[2] / W, bb[3] / H]
        m = m.resize((W // 2, H // 2), Image.LANCZOS)  # masks are drawn scaled; half size saves memory
        out = Image.new('RGBA', m.size, (255, 255, 255, 0))
        out.putalpha(m)
        p = f'{ASSETS}/anatomy3d/mask_{view}_{g}.webp'
        out.save(p, 'WEBP', lossless=True, method=6)
        total += size(p)
    # the ID render is sRGB-encoded; snap each pixel back to (index+1)*16
    def srgb(x):
        return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055
    codes = [(round(srgb((i + 1) * 16 / 255.0) * 255), (i + 1) * 16) for i in range(len(GROUPS))]
    lut = []
    for v in range(256):
        best = min(codes, key=lambda c: abs(c[0] - v))
        lut.append(best[1] if abs(best[0] - v) <= 6 else 0)
    idm = Image.open(f'{MAP}/id_{view}.png').convert('L').point(lut)
    p = f'{ASSETS}/anatomy3d/id_{view}.png'
    idm.save(p, optimize=True)
    total += size(p)
    meta['views'][view] = {'size': [W, H], 'boxes': boxes}
json.dump(meta, open(f'{ASSETS}/anatomy3d/meta.json', 'w'), indent=1)
print('anatomy map %.0f KB' % total)

# ---- exercise animations
data = json.load(open(EXJSON))
tot_anim = tot_th = 0
for ex in data['exercises']:
    eid = ex['id']
    frames = []
    i = 0
    while os.path.exists(f'{POSES}/{eid}_{i:02d}.png'):
        frames.append(Image.open(f'{POSES}/{eid}_{i:02d}.png').convert('RGBA'))
        i += 1
    if not frames:
        print('missing', eid)
        continue
    box = None
    for f in frames:
        bb = f.getchannel('A').point(lambda v: 255 if v > 24 else 0).getbbox()
        box = bb if box is None else (min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]), max(box[3], bb[3]))
    side = int(max(box[2] - box[0], box[3] - box[1]) * 1.08)
    cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
    crop = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)
    sq = [f.crop(crop).resize((320, 320), Image.LANCZOS) for f in frames]
    period = ex['keyframes'].get('period', 2.4)
    if len(sq) > 1:
        seq = sq + sq[-2:0:-1]
        dur = int(period * 1000 / 2 / (len(sq) - 1))
        p = f'{ASSETS}/exercise_anim/{eid}.webp'
        seq[0].save(p, 'WEBP', save_all=True, append_images=seq[1:], duration=dur, loop=0, quality=66, method=4)
    else:
        p = f'{ASSETS}/exercise_anim/{eid}.webp'
        sq[0].save(p, 'WEBP', quality=80, method=6)
    tot_anim += size(p)
    peak = frames[-1] if not ex['mode'] == 'timed' else frames[0]
    bb = peak.getchannel('A').point(lambda v: 255 if v > 24 else 0).getbbox()
    s2 = int(max(bb[2] - bb[0], bb[3] - bb[1]) * 1.06)
    c2 = ((bb[0] + bb[2]) // 2, (bb[1] + bb[3]) // 2)
    th = peak.crop((c2[0] - s2 // 2, c2[1] - s2 // 2, c2[0] - s2 // 2 + s2, c2[1] - s2 // 2 + s2)).resize((192, 192), Image.LANCZOS)
    p2 = f'{ASSETS}/thumbs/{eid}.webp'
    th.save(p2, 'WEBP', quality=82, method=6)
    tot_th += size(p2)
print('animations %.0f KB, thumbs %.0f KB' % (tot_anim, tot_th))
