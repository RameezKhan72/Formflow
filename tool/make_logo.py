"""Draws the FormFlow logo (original artwork) and writes every icon size.

    python3 tool/make_logo.py

Mark: an athlete in a powerful lunge drawn with thick rounded strokes, over a
flowing "form line" swoosh, on a violet-to-blue rounded square.
Outputs:
  assets/branding/logo.png            512 px app logo (rounded square)
  assets/branding/logo_mark.png       512 px white mark, transparent
  assets/branding/logo_1024.png       store / marketing size
  android/app/src/main/res/mipmap-*/ic_launcher.png (+ round)
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png (adaptive)
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
  ios/Runner/Assets.xcassets/AppIcon.appiconset/* (when ios/ exists)
To use your own logo instead, replace assets/branding/logo_1024.png and run
    python3 tool/make_logo.py --from assets/branding/logo_1024.png
"""
import json
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
S = 4096  # supersampled canvas
TOP, BOTTOM = (124, 92, 255), (40, 140, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, c1, c2, angle=35):
    import numpy as np
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    y, x = np.mgrid[0:size, 0:size] / float(size) - 0.5
    t = np.clip(x * ca + y * sa + 0.5, 0, 1)[..., None]
    arr = np.array(c1, dtype=np.float32) * (1 - t) + np.array(c2, dtype=np.float32) * t
    return Image.fromarray(arr.astype('uint8'), 'RGB')


def stroke(d, pts, w, fill=255):
    for a, b in zip(pts, pts[1:]):
        d.line([a, b], fill=fill, width=w)
    for p in pts:
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=fill)


def bezier(p0, p1, p2, n=80):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [i / n for i in range(n + 1)]]


def mark_mask(size=S):
    """White mark as an alpha mask: a bold italic "F" that is also an
    athlete (head, arms reaching forward, knee driving up, standing leg),
    with a flowing form line underneath."""
    k = size / 1024
    m = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(m)
    P = lambda x, y: (x * k, y * k)
    # head
    hx, hy, hr = 452, 178, 74
    d.ellipse([P(hx - hr, hy - hr), P(hx + hr, hy + hr)], fill=255)
    stroke(d, [P(430, 318), P(362, 812)], int(124 * k))    # stem: body + standing leg
    stroke(d, [P(430, 318), P(772, 282)], int(118 * k))    # top bar: arms reaching forward
    stroke(d, [P(398, 548), P(668, 528)], int(112 * k))    # middle bar: knee driving up
    # flowing form line
    top = bezier(P(178, 900), P(560, 780), P(902, 842))
    bot = bezier(P(196, 926), P(560, 842), P(890, 856))
    d.polygon(top + bot[::-1], fill=255)
    return m


def rounded_square(size, radius_frac=0.235):
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius_frac), fill=255)
    return m


def compose_logo(size=1024):
    bg = gradient(S, TOP, BOTTOM).convert('RGBA')
    # soft highlight in the top-left corner
    glow = Image.new('L', (S, S), 0)
    ImageDraw.Draw(glow).ellipse([-S * 0.3, -S * 0.45, S * 0.8, S * 0.55], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.08))
    bg = Image.composite(Image.new('RGBA', (S, S), (255, 255, 255, 255)), bg, glow)
    mk = mark_mask()
    # mark shadow for depth
    sh = mk.filter(ImageFilter.GaussianBlur(S * 0.012))
    sh = ImageChops.offset(sh, int(S * 0.006), int(S * 0.012)).point(lambda v: int(v * 0.35))
    bg = Image.composite(Image.new('RGBA', (S, S), (20, 10, 60, 255)), bg, sh)
    bg = Image.composite(Image.new('RGBA', (S, S), (255, 255, 255, 255)), bg, mk)
    bg.putalpha(rounded_square(S))
    return bg.resize((size, size), Image.LANCZOS)


def mark_only(size=512):
    mk = mark_mask().resize((size, size), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    out.putalpha(mk)
    return out


def full_bleed(src, size):
    """Square icon without transparency (iOS requires opaque icons)."""
    im = src.resize((size, size), Image.LANCZOS)
    flat = gradient(size, TOP, BOTTOM)
    flat.paste(im, (0, 0), im)
    return flat


def main():
    src_path = sys.argv[sys.argv.index('--from') + 1] if '--from' in sys.argv else None
    brand = os.path.join(ROOT, 'assets', 'branding')
    os.makedirs(brand, exist_ok=True)
    if src_path:
        logo = Image.open(src_path).convert('RGBA').resize((1024, 1024), Image.LANCZOS)
        mark = None
    else:
        logo = compose_logo(1024)
        mark = mark_only(512)
        logo.save(os.path.join(brand, 'logo_1024.png'))
        mark.save(os.path.join(brand, 'logo_mark.png'))
    logo.resize((512, 512), Image.LANCZOS).save(os.path.join(brand, 'logo.png'))

    # Android legacy + round icons
    res = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
    sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    for dpi, px in sizes.items():
        d = os.path.join(res, 'mipmap-' + dpi)
        os.makedirs(d, exist_ok=True)
        logo.resize((px, px), Image.LANCZOS).save(os.path.join(d, 'ic_launcher.png'))
        circ = Image.new('L', (px * 4, px * 4), 0)
        ImageDraw.Draw(circ).ellipse([0, 0, px * 4 - 1, px * 4 - 1], fill=255)
        r = full_bleed(logo, px * 4)
        r = r.convert('RGBA')
        r.putalpha(circ)
        r.resize((px, px), Image.LANCZOS).save(os.path.join(d, 'ic_launcher_round.png'))
        # adaptive foreground: 108dp canvas, mark inside the 66dp safe zone
        fpx = int(px * 108 / 48)
        fg = Image.new('RGBA', (fpx, fpx), (0, 0, 0, 0))
        m = (mark or logo).resize((int(fpx * 0.62), int(fpx * 0.62)), Image.LANCZOS)
        fg.paste(m, ((fpx - m.width) // 2, (fpx - m.height) // 2), m)
        fg.save(os.path.join(d, 'ic_launcher_foreground.png'))
    any26 = os.path.join(res, 'mipmap-anydpi-v26')
    os.makedirs(any26, exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
           '</adaptive-icon>\n')
    for n in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        open(os.path.join(any26, n), 'w').write(xml)
    dr = os.path.join(res, 'drawable')
    os.makedirs(dr, exist_ok=True)
    open(os.path.join(dr, 'ic_launcher_background.xml'), 'w').write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <gradient android:angle="315" android:startColor="#7C5CFF" android:endColor="#288CFF"/>\n'
        '</shape>\n')

    # iOS app icon set (opaque, square; iOS rounds the corners itself)
    ios = os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    if os.path.isdir(os.path.dirname(ios)):
        os.makedirs(ios, exist_ok=True)
        specs = [('iphone', '20x20', 2), ('iphone', '20x20', 3), ('iphone', '29x29', 2), ('iphone', '29x29', 3),
                 ('iphone', '40x40', 2), ('iphone', '40x40', 3), ('iphone', '60x60', 2), ('iphone', '60x60', 3),
                 ('ipad', '20x20', 1), ('ipad', '20x20', 2), ('ipad', '29x29', 1), ('ipad', '29x29', 2),
                 ('ipad', '40x40', 1), ('ipad', '40x40', 2), ('ipad', '76x76', 1), ('ipad', '76x76', 2),
                 ('ipad', '83.5x83.5', 2), ('ios-marketing', '1024x1024', 1)]
        square = full_bleed(logo, 1024)
        images = []
        for f in os.listdir(ios):
            if f.endswith('.png'):
                os.remove(os.path.join(ios, f))
        for idiom, sz, scale in specs:
            px = int(round(float(sz.split('x')[0]) * scale))
            name = 'Icon-%s@%dx.png' % (sz.split('x')[0], scale)
            square.resize((px, px), Image.LANCZOS).save(os.path.join(ios, name))
            images.append({'size': sz, 'idiom': idiom, 'filename': name, 'scale': '%dx' % scale})
        json.dump({'images': images, 'info': {'version': 1, 'author': 'xcode'}}, open(os.path.join(ios, 'Contents.json'), 'w'), indent=2)
    print('logo written')


if __name__ == '__main__':
    main()
