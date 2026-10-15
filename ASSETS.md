# Assets and licences

| Asset | Files | Source | Licence |
|---|---|---|---|
| A1 Realistic muscle map (front/back, tap map, 14 muscle masks) | `assets/anatomy3d/` | Rendered in Blender from the Z-Anatomy 3D atlas (github.com/LluisV/Z-Anatomy, Lluís Vinent Juanico) by `tool/anatomy/` | **CC BY-SA 4.0** (adaptation of Z-Anatomy) |
| A2 Mini muscle chips | generated at runtime from A1 | — | as A1 |
| A3 3D exercise demonstrations (56 exercises; looping H.264 videos, ping-pong, alternating sides where needed) | `assets/exercise_video/*.mp4` | The Z-Anatomy figure rigged and posed with FormFlow's keyframes (`tool/build_exercises.py` → `assets/data/exercises.json`) by `tool/anatomy/pose_render.py`, rendered in Blender (Cycles) on a lit floor with contact shadows | **CC BY-SA 4.0** (adaptation of Z-Anatomy) |
| A4 Exercise stills / thumbnails | `assets/thumbs/*.webp` | same renders | **CC BY-SA 4.0** |
| A5 Props (dumbbells, barbell, bench, pull-up frame, wall, mat) | modelled in `pose_render.py` / drawn in `mannequin.dart` | Original | Project licence |
| A6 2D demonstrator and empty-state art | `lib/widgets/mannequin.dart`, `common.dart` | Original | Project licence |
| A7 Logo and app icons ("F" athlete monogram) | `assets/branding/`, `android/app/src/main/res/mipmap-*`, iOS AppIcon | Original, drawn by `tool/make_logo.py` | Project licence |
| A8 Animated splash background | `lib/app.dart` (`GymBackground`) | Original, drawn in code with Material icons (Apache 2.0) | Project licence |

The CC BY-SA attribution is shown in Settings → About and credits.

## Rebuilding the 3D assets

```bash
pip install bpy==5.2.2 pillow numpy          # Blender as a Python module
python3 tool/build_exercises.py               # exercise data + keyframes
python3 tool/sim_engine.py                    # check every exercise's rules against its demo
python3 -I tool/anatomy/prepare.py ...        # once: import Z-Anatomy -> body.blend
python3 -I tool/anatomy/pose_render.py -- body.blend assets/data/exercises.json out/frames 360 20 "" 1   # fast preview (3 frames each)
python3 -I tool/anatomy/pose_render.py -- body.blend assets/data/exercises.json out/frames 360 20        # final frames
python3 tool/anatomy/package_video.py out/frames assets/data/exercises.json assets 320
```

`pose_render.py` solves contacts against the real mesh: the body is grounded
on the floor or a bench, supported poses (push-ups, planks, all fours) are
rotated about the feet or knees until the hands or elbows rest on the
surface, planted hands and feet use two-bone IK, and hanging exercises hang
from a pull-up frame with posts.
