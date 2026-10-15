"""Imports the Z-Anatomy muscular + skeletal FBX, removes label lines and
fascia, tags muscles with FormFlow groups, decimates and saves a .blend."""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from groups import group_of, is_label, SKIP_WORDS
F = sys.argv[sys.argv.index('--') + 1]
OUT = sys.argv[sys.argv.index('--') + 2]
RATIO = float(sys.argv[sys.argv.index('--') + 3]) if len(sys.argv) > sys.argv.index('--') + 3 else 0.35
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(F, 'MuscularSystem100.fbx'))
mus = {o.name for o in bpy.data.objects if o.type == 'MESH'}
bpy.ops.import_scene.fbx(filepath=os.path.join(F, 'SkeletalSystem100.fbx'))
kept, counts = 0, {}
for o in list(bpy.data.objects):
    if o.type != 'MESH':
        continue
    n = o.name.lower()
    if is_label(o.name) or len(o.data.vertices) < 40 or any(w in n for w in SKIP_WORDS):
        bpy.data.objects.remove(o)
        continue
    o['ff_kind'] = 'muscle' if o.name in mus else 'bone'
    g = group_of(o.name) if o.name in mus else None
    o['ff_group'] = g or ''
    if g:
        counts[g] = counts.get(g, 0) + 1
    if RATIO < 1 and len(o.data.polygons) > 400:
        if o.data.users > 1:
            o.data = o.data.copy()
        m = o.modifiers.new('dec', 'DECIMATE'); m.ratio = RATIO
    kept += 1
# open the abdominal wall: remove the aponeurotic front of the obliques so
# the rectus abdominis (six-pack) is visible, as on a fitness anatomy figure
import bmesh
for o in bpy.data.objects:
    if o.type == 'MESH' and 'oblique' in o.name.lower() and 'abdomin' in o.name.lower() or (o.type == 'MESH' and o.name.lower().startswith(('external oblique', 'internal oblique'))):
        if o.data.users > 1:
            o.data = o.data.copy()
        bm = bmesh.new(); bm.from_mesh(o.data)
        mw = o.matrix_world
        kill = [v for v in bm.verts if abs((mw @ v.co).x) < 0.095 and (mw @ v.co).y < -0.02]
        bmesh.ops.delete(bm, geom=kill, context='VERTS')
        bm.to_mesh(o.data); bm.free()
# apply decimation
for o in bpy.data.objects:
    if o.type == 'MESH' and o.modifiers:
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            try:
                with bpy.context.temp_override(object=o, active_object=o):
                    bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception as e:
                o.modifiers.remove(m)
for o in list(bpy.data.objects):
    if o.type == 'EMPTY' and not o.children:
        bpy.data.objects.remove(o)
print('kept', kept, 'groups', counts)
print('faces', sum(len(o.data.polygons) for o in bpy.data.objects if o.type == 'MESH'))
bpy.ops.wm.save_as_mainfile(filepath=OUT)
