"""Poses the realistic anatomy model (Z-Anatomy, CC BY-SA 4.0) with the
exercise keyframes from assets/data/exercises.json and renders the frames of
every exercise demonstration (worked muscles in red).

    python3 -I pose_render.py -- body.blend exercises.json OUT_DIR [size] [frames] [only_ids] [preview]

Posing (v2):
* every segment is aimed in 3D: the sagittal angle from the keyframes (same
  convention as the 2D demonstrator) plus an abduction angle ("upperArmAbd",
  "thighAbd", ...) so arms and legs can move sideways;
* the pelvis follows the trunk, so lying and hinging poses look natural;
* contacts are solved against the real mesh surface: the body is grounded on
  the floor (or a bench), supported poses (push-ups, planks, quadruped) are
  rotated about the feet / knees until the hands or elbows rest on the
  surface, planted hands and feet are placed with two-bone IK, and hanging
  exercises hang from a pull-up frame with posts;
* the floor is rendered (soft spotlight floor with real contact shadows), so
  the figure never appears to float.

preview = 1 renders 3 frames per exercise with Workbench (fast) and prints
contact metrics, used to check every exercise before the final render.
"""
import bpy, sys, os, json, math, time
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import mannequin_fk as fk  # noqa: E402

args = sys.argv[sys.argv.index('--') + 1:]
BLEND, EXJSON, OUT = args[0], args[1], args[2]
SIZE = int(args[3]) if len(args) > 3 else 360
NFRAMES = int(args[4]) if len(args) > 4 else 20
ONLY = set(args[5].split(',')) if len(args) > 5 and args[5] else None
PREVIEW = len(args) > 6 and args[6] == '1'
PROF = bool(os.environ.get('FF_PROF'))
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.open_mainfile(filepath=BLEND)
scn = bpy.context.scene
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
O = {o.name: o for o in meshes}


def verts(o):
    n = len(o.data.vertices)
    a = np.empty(n * 3, dtype=np.float32)
    o.data.vertices.foreach_get('co', a)
    a = a.reshape(-1, 3)
    m = np.array(o.matrix_world)
    return a @ m[:3, :3].T + m[:3, 3]


def top(o, frac=0.05, low=False):
    v = verts(o)
    z = v[:, 2]
    zmin, zmax = z.min(), z.max()
    sel = v[z < zmin + (zmax - zmin) * frac] if low else v[z > zmax - (zmax - zmin) * frac]
    return Vector(sel.mean(axis=0))


# ---------------------------------------------------------------- landmarks
L = {}
for s in ('l', 'r'):
    fem = verts(O['Femur.' + s])
    zt = fem[:, 2].max()
    head = fem[fem[:, 2] > zt - 0.05]
    med = head[np.argsort(np.abs(head[:, 0]))[: max(5, len(head) // 3)]]
    L['hip_' + s] = Vector(med.mean(axis=0))
    L['knee_' + s] = (top(O['Femur.' + s], 0.04, low=True) + top(O['Tibia.' + s], 0.04)) / 2
    L['ankle_' + s] = Vector(verts(O['Talus.' + s]).mean(axis=0))
    cal = verts(O['Calcaneus.' + s])
    L['heel_' + s] = Vector(cal[np.argmax(cal[:, 1])])
    toes = np.concatenate([verts(o) for n, o in O.items() if 'of foot.' + s in n and 'phalanx' in n.lower()])
    L['toe_' + s] = Vector(toes[np.argmin(toes[:, 1])])
    hum = O['Humerus.' + s]
    L['shoulder_' + s] = top(hum, 0.06)
    L['elbow_' + s] = top(hum, 0.04, low=True)
    L['wrist_' + s] = (top(O['Radius.' + s], 0.04, low=True) + top(O['Ulna.' + s], 0.04, low=True)) / 2
    hand = np.concatenate([verts(o) for n, o in O.items() if 'of hand.' + s in n and 'phalanx' in n.lower()])
    L['hand_' + s] = Vector(hand[np.argmin(hand[:, 2])])
L['pelvis'] = (L['hip_l'] + L['hip_r']) / 2
L['shoulders'] = (L['shoulder_l'] + L['shoulder_r']) / 2
L['neck'] = Vector(verts(O['Vertebra C7']).mean(axis=0))
skull = np.concatenate([verts(O[n]) for n in ('Frontal bone', 'Occipital bone') if n in O])
L['head'] = Vector((0, float(skull[:, 1].mean()), float(skull[:, 2].max())))

# ---------------------------------------------------------------- armature
arm_data = bpy.data.armatures.new('rig')
arm = bpy.data.objects.new('rig', arm_data)
scn.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones
SPEC = [('root', 'pelvis', None, None), ('torso', 'pelvis', 'neck', 'root'), ('neck', 'neck', 'head', 'torso')]
for s in ('l', 'r'):
    SPEC += [('upper_' + s, 'shoulder_' + s, 'elbow_' + s, 'torso'), ('fore_' + s, 'elbow_' + s, 'wrist_' + s, 'upper_' + s),
             ('hand_' + s, 'wrist_' + s, 'hand_' + s, 'fore_' + s), ('thigh_' + s, 'hip_' + s, 'knee_' + s, 'root'),
             ('shin_' + s, 'knee_' + s, 'ankle_' + s, 'thigh_' + s), ('foot_' + s, 'ankle_' + s, 'toe_' + s, 'shin_' + s)]
for name, h, t, parent in SPEC:
    b = eb.new(name)
    b.head = L[h]
    b.tail = L[t] if t else L[h] + Vector((0, 0, 0.1))
    if parent:
        b.parent = eb[parent]
bpy.ops.object.mode_set(mode='OBJECT')
BONES = [s[0] for s in SPEC]
BI = {b: i for i, b in enumerate(BONES)}
SEG = {}
for name, h, t, _ in SPEC:
    SEG[name] = (np.array(L[h]), np.array(L[t] if t else L[h] + Vector((0, 0, 0.1))))

TORSO_WORDS = ('intercost', 'serratus', ' rib', 'vertebra', 'sternum', 'spinal', 'thorac', 'lumbar', 'lumborum', 'abdomin',
               'external oblique', 'internal oblique', 'latissimus', 'pectoral', 'trapezius', 'rhomboid', 'erector', 'iliocostal', 'longissim', 'multifid',
               'diaphragm', 'costal', 'manubrium', 'xiphoid', 'scapul', 'clavic', 'subclav', 'levator', 'splenius',
               'semispinal', 'rectus abdominis', 'pyramidal', 'linea')
PELVIS_WORDS = ('sacrum', 'coccy', 'hip bone', 'pubi', 'ilium', 'ischi', 'iliacus', 'psoas', 'piriformis',
                'obturator', 'gemell', 'quadratus femoris', 'levator ani')
HEAD_Z = L['shoulders'].z + 0.07
LEG_WORDS = ('femor', 'femur', 'vastus', 'sartor', 'gracil', 'adductor longus', 'adductor brevis', 'adductor magnus',
             'adductor minimus', 'tibi', 'fibul', 'gastroc', 'soleus', 'patell', 'calcane', 'talus', 'tars', 'of foot',
             'hallucis', 'plantar', 'gluteus', 'popliteus', 'peron', 'semitend', 'semimembr', 'tensor fasciae',
             'pectineus', 'navicular', 'cuneiform', 'cuboid', 'calcaneal', 'malleol', 'quadriceps', 'achilles')
ARM_WORDS = ('brachi', 'humer', 'radius', 'radial', 'ulna', 'carp', 'pollicis', 'of hand', 'metacarp', 'anconeus',
             'supinator', 'pronator', 'deltoid', 'triceps brachii', 'palmar', 'thenar', 'scaphoid', 'lunate', 'triquetr',
             'pisiform', 'trapezium', 'trapezoid', 'capitate', 'hamate', 'index finger', 'digiti minimi muscle of hand',
             'cubital', 'olecran', 'teres', 'infraspinat', 'supraspinat', 'subscapular', 'coracobrach')


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def candidates(o, v):
    n = o.name.lower()
    cx = float(v[:, 0].mean()); cz = float(v[:, 2].mean())
    side = 'l' if cx > 0.02 else ('r' if cx < -0.02 else None)
    if cz > HEAD_Z and abs(cx) < 0.12:
        return ['neck', 'torso']
    leg = any(w in n for w in LEG_WORDS)
    armw = any(w in n for w in ARM_WORDS)
    if side and leg and not armw:
        return ['root', 'thigh_' + side, 'shin_' + side, 'foot_' + side]
    if side and armw and not leg:
        return ['torso', 'upper_' + side, 'fore_' + side, 'hand_' + side]
    if side and not leg and not armw:
        if abs(cx) > 0.2 and cz < L['shoulders'].z - 0.1:
            return ['upper_' + side, 'fore_' + side, 'hand_' + side]
        if cz < L['pelvis'].z - 0.08:
            return ['root', 'thigh_' + side, 'shin_' + side, 'foot_' + side]
    if any(w in n for w in ('deltoid', 'teres', 'infraspinat', 'supraspinat', 'subscapular', 'coracobrach')) and side:
        return ['upper_' + side, 'torso']
    if any(w in n for w in TORSO_WORDS):
        return ['torso', 'root', 'neck'] + (['upper_' + side] if side and 'pectoral' in n else [])
    if any(w in n for w in PELVIS_WORDS):
        return ['root', 'torso'] + (['thigh_' + side] if side else ['thigh_l', 'thigh_r'])
    if side is None:
        return ['root', 'torso', 'thigh_l', 'thigh_r']
    return ['root', 'torso'] + [b for b in BONES if b.endswith('_' + side)]


rng = np.random.default_rng(7)
PTS, PBI = [], []
for o in meshes:
    if o.data.users > 1:
        o.data = o.data.copy()
    v = verts(o)
    cand = candidates(o, v)
    d = np.stack([seg_dist(v, *SEG[b]) for b in cand], axis=1)
    lname = o.name.lower()
    rigid = o.get('ff_kind') == 'bone' and any(w in lname for w in ('femur', 'tibia', 'humerus', 'radius', 'ulna', 'fibula'))
    temp = 0.002 if rigid else 0.018
    w = np.exp(-(d - d.min(axis=1, keepdims=True)) / temp)
    w /= w.sum(axis=1, keepdims=True)
    for j, b in enumerate(cand):
        idx = np.nonzero(w[:, j] > 0.01)[0]
        if len(idx) == 0:
            continue
        vg = o.vertex_groups.get(b) or o.vertex_groups.new(name=b)
        for wv in np.unique(np.round(w[idx, j], 2)):
            sel = idx[np.round(w[idx, j], 2) == wv]
            vg.add(sel.tolist(), float(wv), 'REPLACE')
    mod = o.modifiers.new('arm', 'ARMATURE'); mod.object = arm
    # surface samples (each follows its dominant bone) for contact solving
    k = min(len(v), 60)
    pick = rng.choice(len(v), k, replace=False)
    PTS.append(v[pick]); PBI.append(np.array([BI[cand[i]] for i in np.argmax(w[pick], axis=1)]))
PTS = np.concatenate(PTS); PBI = np.concatenate(PBI)

# join the ~1450 parts into one object per (kind, muscle group): renders are
# dominated by per-object overhead, joining makes every frame ~10x faster
by_group = {}
for o in (meshes if os.environ.get('FF_JOIN') else []):
    by_group.setdefault((o.get('ff_kind') or '', o.get('ff_group') or ''), []).append(o)
joined = []
for key, objs in by_group.items():
    for x in bpy.context.view_layer.objects:
        x.select_set(False)
    for x in objs:
        x.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    j = bpy.context.view_layer.objects.active
    j['ff_kind'], j['ff_group'] = key
    for extra in list(j.modifiers)[1:]:
        j.modifiers.remove(extra)
    joined.append(j)
meshes = joined or meshes
print('objects', len(meshes), 'samples', len(PTS), flush=True)
PTS_H = np.concatenate([PTS, np.ones((len(PTS), 1), dtype=np.float32)], axis=1)


def mods(on):
    for o in meshes:
        o.modifiers['arm'].show_viewport = on


mods(False)  # posing does not need deformed meshes; renders use show_render

# ---------------------------------------------------------------- materials, props
def principled(name, rgb, rough=0.5, metal=0.0, ao=True, sheen=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if 'Coat Weight' in b.inputs and sheen:
        b.inputs['Coat Weight'].default_value = sheen
        b.inputs['Coat Roughness'].default_value = 0.35
    if not ao:
        b.inputs['Base Color'].default_value = (*rgb, 1)
        return m
    a = nt.nodes.new('ShaderNodeAmbientOcclusion'); a.inputs['Distance'].default_value = 0.025
    gm = nt.nodes.new('ShaderNodeMath'); gm.operation = 'POWER'; gm.inputs[1].default_value = 1.6
    nt.links.new(a.outputs['AO'], gm.inputs[0])
    mx = nt.nodes.new('ShaderNodeMix'); mx.data_type = 'RGBA'
    mx.inputs[6].default_value = (rgb[0] * 0.25, rgb[1] * 0.25, rgb[2] * 0.27, 1)
    mx.inputs[7].default_value = (*rgb, 1)
    nt.links.new(gm.outputs[0], mx.inputs['Factor'])
    nt.links.new(mx.outputs[2], b.inputs['Base Color'])
    return m


GREY = (0.74, 0.74, 0.76)
grey = principled('grey', GREY, 0.48, sheen=0.15)
bone_m = principled('bone', (0.68, 0.67, 0.64))
RED = (0.82, 0.12, 0.08)
red_mats = [principled('red%d' % i, tuple(GREY[c] + (RED[c] - GREY[c]) * (i / 5) for c in range(3)), 0.42, sheen=0.2) for i in range(6)]
dark = principled('prop', (0.10, 0.11, 0.15), 0.35, 0.5, ao=False)
steel = principled('steel', (0.62, 0.64, 0.68), 0.22, 0.95, ao=False)
padm = principled('pad', (0.16, 0.17, 0.22), 0.6, ao=False)


def prim_cyl(name, r, depth, loc, rot, mat):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=32)
    o = bpy.context.active_object; o.name = name; o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def prim_box(name, size, loc, mat, bevel=0.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name; o.scale = size; o.data.materials.append(mat)
    if bevel:
        bm = o.modifiers.new('bevel', 'BEVEL'); bm.width = bevel; bm.segments = 3
    return o


def parent_to_bone(o, bone):
    o.parent = arm; o.parent_type = 'BONE'; o.parent_bone = bone
    pb = arm.pose.bones[bone]
    o.matrix_parent_inverse = (arm.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.length, 0))).inverted()


props = {}
for s in ('l', 'r'):
    c = (L['wrist_' + s] + L['hand_' + s]) / 2 + Vector((0, 0, 0.01))
    parts = [prim_cyl('db_bar_' + s, 0.016, 0.17, c, (0, math.radians(90), 0), steel)]
    for dx in (-0.075, 0.075):
        parts.append(prim_cyl('db_plate_%s%d' % (s, dx > 0), 0.058, 0.04, c + Vector((dx, 0, 0)), (0, math.radians(90), 0), dark))
    for p in parts:
        parent_to_bone(p, 'hand_' + s)
    props['dumbbells_' + s] = parts
# single dumbbell held in both hands at the chest (goblet squat)
gc = (L['hand_l'] + L['hand_r']) / 2
gob = [prim_cyl('gob_bar', 0.017, 0.22, gc, (0, 0, 0), steel)]
for dz in (-0.1, 0.1):
    gob.append(prim_cyl('gob_plate%d' % (dz > 0), 0.075, 0.05, gc + Vector((0, 0, dz)), (0, 0, 0), dark))
props['goblet'] = gob  # placed between the hands every frame
cb = (L['wrist_l'] + L['wrist_r']) / 2 + Vector((0, 0, -0.05))
bar = [prim_cyl('barbell_bar', 0.014, 1.6, cb, (0, math.radians(90), 0), steel)]
for dx in (-0.62, 0.62):
    bar.append(prim_cyl('barbell_plate%d' % (dx > 0), 0.225, 0.05, cb + Vector((dx, 0, 0)), (0, math.radians(90), 0), dark))
for p in bar:
    parent_to_bone(p, 'hand_l')
props['barbell'] = bar
# pull-up frame: bar on two posts standing on the floor
pull = [prim_cyl('pullbar', 0.018, 1.3, (0, 0, 0), (0, math.radians(90), 0), steel)]
pull += [prim_cyl('post%d' % i, 0.03, 1.0, (0, 0, 0), (0, 0, 0), dark) for i in range(2)]
pull += [prim_box('foot%d' % i, (0.1, 0.6, 0.04), (0, 0, 0), dark, 0.01) for i in range(2)]
props['bar'] = pull
props['bench'] = [prim_box('bench_top', (1, 1, 1), (0, 0, 0), padm, 0.02)] + \
                 [prim_box('bench_leg%d' % i, (1, 1, 1), (0, 0, 0), dark, 0.0) for i in range(2)]
props['wall'] = [prim_box('wall', (1.6, 0.08, 2.4), (0, 0, 0), principled('wallm', (0.30, 0.32, 0.40), 0.8, ao=False), 0.0)]
props['mat'] = [prim_box('yoga_mat', (0.62, 1.9, 0.008), (0, 0, 0.004), principled('matm', (0.20, 0.22, 0.42), 0.8, ao=False), 0.003)]

# soft spotlight floor: real geometry with contact shadows, fading out at the edge
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
floor = bpy.context.active_object; floor.name = 'floor'
fm = bpy.data.materials.new('floorm'); fm.use_nodes = True
nt = fm.node_tree; nt.nodes.clear()
outn = nt.nodes.new('ShaderNodeOutputMaterial')
dif = nt.nodes.new('ShaderNodeBsdfPrincipled'); dif.inputs['Base Color'].default_value = (0.035, 0.042, 0.085, 1)
dif.inputs['Roughness'].default_value = 0.55
tr = nt.nodes.new('ShaderNodeBsdfTransparent')
mix = nt.nodes.new('ShaderNodeMixShader')
tc = nt.nodes.new('ShaderNodeTexCoord')
grad = nt.nodes.new('ShaderNodeTexGradient'); grad.gradient_type = 'SPHERICAL'
ramp = nt.nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position = 0.5; ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
ramp.color_ramp.elements[1].position = 0.92; ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
nt.links.new(tc.outputs['Object'], grad.inputs['Vector'])
nt.links.new(grad.outputs['Fac'], ramp.inputs['Fac'])
nt.links.new(ramp.outputs['Color'], mix.inputs['Fac'])
nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(dif.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], outn.inputs['Surface'])
floor.data.materials.append(fm)

cam_d = bpy.data.cameras.new('cam'); cam_d.type = 'ORTHO'
cam = bpy.data.objects.new('cam', cam_d); scn.collection.objects.link(cam); scn.camera = cam
w = bpy.data.worlds.new('w'); scn.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs[0].default_value = (0.05, 0.055, 0.08, 1)
w.node_tree.nodes['Background'].inputs[1].default_value = 0.7
LIGHTS = {}
for name, loc, energy, size in [('key', (2.0, -2.2, 3.6), 150, 2.2), ('fill', (-3, -2.2, 1.6), 32, 3),
                                ('rim', (-1.5, 3, 2.8), 110, 2), ('rim2', (3, 2.5, 1.5), 50, 2)]:
    ld = bpy.data.lights.new(name, 'AREA'); ld.energy = energy; ld.size = size
    lo = bpy.data.objects.new(name, ld); scn.collection.objects.link(lo); lo.location = loc
    LIGHTS[name] = lo
scn.render.film_transparent = True
scn.render.resolution_x = scn.render.resolution_y = SIZE
if PREVIEW:
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'; scn.display.shading.color_type = 'MATERIAL'
    scn.display.shading.show_shadows = False
else:
    scn.render.engine = 'CYCLES'; scn.cycles.device = 'CPU'; scn.cycles.samples = int(os.environ.get('FF_SAMPLES', '16')); scn.cycles.use_denoising = True
    scn.view_settings.view_transform = 'AgX'; scn.view_settings.look = 'AgX - Medium High Contrast'

# ---------------------------------------------------------------- posing helpers
REST = {b.name: b.matrix_local.copy() for b in arm_data.bones}
REST_INV = {k: v.inverted() for k, v in REST.items()}
LEN = {b.name: b.length for b in arm_data.bones}
PB = arm.pose.bones


PARENT = {name: parent for name, _, _, parent in SPEC}
KIDS = {b: [c for c in BONES if PARENT[c] == b] for b in BONES}
W = {b: REST[b].copy() for b in BONES}  # posed world matrices (own FK, no depsgraph)


def subtree(b):
    out = [b]
    for c in KIDS[b]:
        out += subtree(c)
    return out


SUB = {b: subtree(b) for b in BONES}


def upd():
    bpy.context.view_layer.update()


def apply_delta(b, D):
    for d in SUB[b]:
        W[d] = D @ W[d]


def reset_pose():
    for b in BONES:
        W[b] = REST[b].copy()


def commit():
    """Write the solved pose to the armature (one depsgraph update)."""
    for b in BONES:
        p = PARENT[b]
        if p is None:
            basis = REST_INV[b] @ W[b]
        else:
            basis = (REST_INV[p] @ REST[b]).inverted() @ W[p].inverted() @ W[b]
        PB[b].matrix_basis = basis
    upd()


def sag(a):
    r = math.radians(a)
    return Vector((0.0, -math.sin(r), math.cos(r)))


def frontv(a, sgn):
    r = math.radians(a)
    return Vector((math.sin(r) * sgn, 0.0, math.cos(r)))


OUTV = {'l': Vector((1, 0, 0)), 'r': Vector((-1, 0, 0))}
FWD = Vector((0, -1, 0))


def abduct(v, s, deg):
    r = math.radians(deg)
    return (v.normalized() * math.cos(r) + OUTV[s] * math.sin(r)).normalized()


def tilt_fwd(v, deg):
    if not deg:
        return v.normalized()
    r = math.radians(deg)
    return (v.normalized() * math.cos(r) + FWD * math.sin(r)).normalized()


def yaw_out(v, s, deg):
    r = math.radians(deg if s == 'l' else -deg)
    c, sn = math.cos(r), math.sin(r)
    return Vector((v.x * c - v.y * sn, v.x * sn + v.y * c, v.z)).normalized()


def set_dir(name, target):
    m = W[name]
    cur = (m.to_3x3() @ Vector((0, 1, 0))).normalized()
    q = cur.rotation_difference(target.normalized())
    loc = m.to_translation()
    apply_delta(name, Matrix.Translation(loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-loc))


def head(name):
    return W[name].to_translation()


def tail(name):
    return W[name] @ Vector((0, LEN[name], 0))


def transform_root(M):
    apply_delta('root', M)


def points(mask=None):
    """Posed world positions of the surface samples (optionally only for some bones)."""
    Ms = np.stack([np.array(W[b] @ REST_INV[b]) for b in BONES])
    if mask is not None:
        sel = np.isin(PBI, [BI[b] for b in mask])
        P, I = PTS_H[sel], PBI[sel]
    else:
        P, I = PTS_H, PBI
    return np.einsum('nij,nj->ni', Ms[I], P)[:, :3]


HANDS = ['hand_l', 'hand_r']
FEET = ['foot_l', 'foot_r']
DEF_ABD = {'upperArm': 9, 'forearm': 6, 'thigh': 3, 'shin': 1}


FRONT_FWD = {'upperArmFwd': 6, 'forearmFwd': 8, 'thighFwd': 2, 'shinFwd': -2}


def key_default(k, front):
    base = k[:-1] if k.endswith('2') else k
    if base.endswith('Abd'):
        return DEF_ABD.get(base[:-3], 0)
    if base in FRONT_FWD:
        return FRONT_FWD[base] if front else 0
    if base == 'elbow':
        return 170
    if base == 'toeOut':
        return 10
    return 0


def angles(kf, u, swap=False):
    s0, s1 = fk.complete(kf['start']), fk.complete(kf['end'])
    front = kf.get('view') == 'front'
    keys = set(s0) | set(s1)
    keys |= {k + '2' for k in keys if k.endswith(('Abd', 'Fwd')) and not k.startswith('torso')}
    for d in (s0, s1):
        for k in sorted(keys, key=lambda x: x.endswith('2')):  # near side first
            if k in d:
                continue
            base = k[:-1] if k.endswith('2') else None
            if base and base in d:
                d[k] = d[base]  # far side mirrors the near side of the same keyframe
            else:
                d[k] = key_default(k, front)
    a = fk.lerp(s0, s1, u)
    if swap:
        b = dict(a)
        for k in list(a):
            if k.endswith('2'):
                base = k[:-1]
                b[base], b[k] = a[k], a.get(base, a[k])
        # abduction keys swap too
        for k in list(a):
            if k.endswith('Abd') and k + '2' in a:
                b[k], b[k + '2'] = a[k + '2'], a[k]
        a = b
        a['_swap'] = 1
    return a


def g(a, k, side, default):
    key = k + ('2' if side == 'r' else '')
    if key in a:
        return a[key]
    return a.get(k, default)


def pose(kf, u, swap=False):
    a = angles(kf, u, swap)
    front = kf.get('view') == 'front'
    reset_pose()
    T = frontv(a['torso'], 1) if front else sag(a['torso'])
    T = tilt_fwd(T, a.get('torsoFwd', 0))
    # pelvis follows the trunk
    R = Vector((0, 0, 1)).rotation_difference(T).to_matrix().to_4x4()
    p0 = W['root'].to_translation()
    target = Matrix.Translation(p0) @ R @ REST['root'].to_3x3().to_4x4()
    apply_delta('root', target @ W['root'].inverted())
    set_dir('torso', T)
    hd = frontv(a['torso'], 1) if front else sag(a.get('head', a['torso']))
    set_dir('neck', hd)
    for s in ('l', 'r'):
        sgn = 1 if s == 'l' else -1
        if front:
            ua = frontv(g(a, 'upperArm', s, 180), sgn); fa = frontv(g(a, 'forearm', s, 180), sgn)
            th = frontv(g(a, 'thigh', s, 0) + 180, sgn); sh = frontv(g(a, 'shin', s, 0) + 180, sgn)
            ua = tilt_fwd(ua, g(a, 'upperArmFwd', s, 6)); fa = tilt_fwd(fa, g(a, 'forearmFwd', s, 8))
            th = tilt_fwd(th, g(a, 'thighFwd', s, 2)); sh = tilt_fwd(sh, g(a, 'shinFwd', s, -2))
            ft = Vector((0, -1, -0.25)).normalized()
        else:
            ua = abduct(sag(g(a, 'upperArm', s, 180)), s, g(a, 'upperArmAbd', s, DEF_ABD['upperArm']))
            fa = abduct(sag(g(a, 'forearm', s, 180)), s, g(a, 'forearmAbd', s, DEF_ABD['forearm']))
            th = abduct(sag(g(a, 'thigh', s, 0) + 180), s, g(a, 'thighAbd', s, DEF_ABD['thigh']))
            sh = abduct(sag(g(a, 'shin', s, 0) + 180), s, g(a, 'shinAbd', s, DEF_ABD['shin']))
            ft = sag(g(a, 'foot', s, 90) + 8)
        ft = yaw_out(ft, s, g(a, 'toeOut', s, 10))
        set_dir('upper_' + s, ua)
        set_dir('fore_' + s, fa)
        hdir = kf.get('hand')
        if hdir == 'flat':
            set_dir('hand_' + s, tilt_fwd(Vector((0, 0, -1)), 85))
        elif hdir == 'fist_fwd':
            set_dir('hand_' + s, FWD + Vector((0, 0, -0.3)))
        set_dir('thigh_' + s, th)
        set_dir('shin_' + s, sh)
        set_dir('foot_' + s, ft)
    roll = a.get('bodyRoll', 0)
    if roll:
        p = head('root')
        transform_root(Matrix.Translation(p) @ Matrix.Rotation(math.radians(roll), 4, 'Y') @ Matrix.Translation(-p))
    return a


def ground_to(bones, z):
    P = points(bones)
    transform_root(Matrix.Translation((0, 0, z - float(P[:, 2].min()))))


def rotate_about(p, axis, ang):
    transform_root(Matrix.Translation(p) @ Matrix.Rotation(ang, 4, axis) @ Matrix.Translation(-p))


def ik2(upper, lower, target, pole):
    S = head(upper)
    a, b = LEN[upper], LEN[lower]
    dv = target - S
    d = max(abs(a - b) + 1e-3, min(dv.length, a + b - 1e-4))
    n = dv.normalized()
    pv = (pole - S) - n * (pole - S).dot(n)
    if pv.length < 1e-6:
        pv = Vector((0, 0, 1)) - n * n.z
    pv.normalize()
    x = (a * a - b * b + d * d) / (2 * d)
    h = math.sqrt(max(0.0, a * a - x * x))
    E = S + n * x + pv * h
    W = S + n * d
    set_dir(upper, E - S)
    set_dir(lower, W - E)


def solve_support(kf, a, sup):
    """Pivot (feet or knees) on its surface, then rotate the body about the
    pivot until the shoulders are at the height the arms need."""
    pivot = FEET if sup.get('pivot', 'toes') == 'toes' else ['shin_l', 'shin_r']
    if sup.get('pivotFoot'):
        side = sup['pivotFoot']
        if a.get('_swap'):
            side = {'l': 'r', 'r': 'l'}[side]
        pivot = ['foot_' + side]
    pz = sup.get('pivotZ', 0.0)
    rz = sup.get('reachZ', 0.0)
    ground_to(pivot, pz)
    P = points(pivot)
    low = P[P[:, 2] < P[:, 2].min() + 0.02]
    piv = Vector(low.mean(axis=0))
    ua, fa = LEN['upper_l'], LEN['fore_l']
    if sup.get('reach', 'hands') == 'hands':
        e = math.radians(a.get('elbow', 170))
        need = math.sqrt(ua * ua + fa * fa - 2 * ua * fa * math.cos(e)) * 0.985 + 0.045
    else:
        need = ua + 0.035
    axis = 'X' if sup.get('axis', 'x') == 'x' else 'Y'
    base = {b: W[b].copy() for b in BONES}
    shs = ['upper_' + sup['side']] if sup.get('side') else ['upper_l', 'upper_r']

    def sh_z(ang):
        W.update({b: m.copy() for b, m in base.items()})
        rotate_about(piv, axis, ang)
        return sum((head(b) for b in shs), Vector()).z / len(shs)

    lo, hi = math.radians(-70), math.radians(70)
    flo, fhi = sh_z(lo) - (rz + need), sh_z(hi) - (rz + need)
    if flo * fhi > 0:
        ang = lo if abs(flo) < abs(fhi) else hi
    else:
        for _ in range(28):
            mid = (lo + hi) / 2
            fm_ = sh_z(mid) - (rz + need)
            if (fm_ > 0) == (flo > 0):
                lo, flo = mid, fm_
            else:
                hi = mid
        ang = (lo + hi) / 2
    sh_z(ang)
    if PROF:
        print('support', kf.get('alternate'), 'ang %.1f need %.3f piv %s sh %.3f hip %.3f' % (
            math.degrees(ang), need, tuple(round(x, 2) for x in piv), sh_z(ang), head('thigh_l').z), flush=True)
    return rz


def plant_hands(kf, a, surface, fwd=0.0, wide=0.0, mode='hands', sides=('l', 'r')):
    for s in sides:
        S = head('upper_' + s)
        out = OUTV[s] * (wide + 0.02)
        if mode == 'hands':
            target = Vector((S.x, S.y, surface + 0.04)) + FWD * fwd + out
            pole = S + OUTV[s] * 0.35 + Vector((0, 0.4, 0)) + Vector((0, 0, 0.1))
            for _ in range(2):
                ik2('upper_' + s, 'fore_' + s, target, pole)
                set_dir('hand_' + s, tilt_fwd(Vector((0, 0, -1)), 84) + OUTV[s] * 0.08)
                hz = float(points(['hand_' + s])[:, 2].min())
                target = target + Vector((0, 0, surface - hz))
        else:  # forearms on the surface, elbows under the shoulders
            E = Vector((S.x, S.y, surface + 0.03)) + out * 0.5
            set_dir('upper_' + s, E - S)
            set_dir('fore_' + s, FWD + OUTV[s] * -0.18)
            set_dir('hand_' + s, FWD + Vector((0, 0, -0.05)))
            for _ in range(2):
                fz = float(points(['fore_' + s, 'hand_' + s])[:, 2].min())
                E = E + Vector((0, 0, surface - fz))
                set_dir('upper_' + s, E - head('upper_' + s))


def plant_feet(sides, surface, pole_fwd=True):
    for s in sides:
        A = head('foot_' + s)
        H = head('thigh_' + s)
        K = head('shin_' + s)
        target = A.copy()
        pole = K + (K - (H + A) / 2) * 2
        for _ in range(3):
            ik2('thigh_' + s, 'shin_' + s, target, pole)
            fz = float(points(['foot_' + s])[:, 2].min())
            target = target + Vector((0, 0, surface - fz))


def clear_floor(sides, margin=0.02):
    """Lift a free (swinging) leg about the hip until knee and foot clear the floor."""
    for s in sides:
        bones = ['thigh_' + s, 'shin_' + s, 'foot_' + s]
        for _ in range(40):
            dz = margin - float(points(bones)[:, 2].min())
            if dz <= 0:
                break
            hp = head('thigh_' + s)
            best = None
            for sgn in (1, -1):
                saved = {b: W[b].copy() for b in SUB['thigh_' + s]}
                apply_delta('thigh_' + s, Matrix.Translation(hp) @ Matrix.Rotation(sgn * math.radians(3), 4, 'X') @ Matrix.Translation(-hp))
                z = float(points(bones)[:, 2].min())
                W.update(saved)
                if best is None or z > best[0]:
                    best = (z, sgn)
            apply_delta('thigh_' + s, Matrix.Translation(hp) @ Matrix.Rotation(best[1] * math.radians(3), 4, 'X') @ Matrix.Translation(-hp))


def place(kf, u, swap=False, state=None):
    a = pose(kf, u, swap)
    sup = kf.get('support')
    anchor = kf.get('anchor', 'floor')
    if sup:
        rz = solve_support(kf, a, sup)
        sides = list(sup.get('plant', [sup['side']] if sup.get('side') else ['l', 'r']))
        if swap:
            sides = [{'l': 'r', 'r': 'l'}[x] for x in sides]
        plant_hands(kf, a, rz, sup.get('handFwd', 0.0), sup.get('handWide', 0.0), sup.get('reach', 'hands'), sides)
        if sup.get('clearFloor'):
            cf = list(sup['clearFloor'])
            if swap:
                cf = [{'l': 'r', 'r': 'l'}[x] for x in cf]
            clear_floor(cf)
    elif anchor == 'wrist':
        if state.get('anchor') is None:
            ground_to(FEET if kf.get('plantFeet') else None, 0.0)
        wp = (tail('fore_l') + tail('fore_r')) / 2
        if state.get('anchor') is None:
            state['anchor'] = wp.copy()
        transform_root(Matrix.Translation(state['anchor'] - wp))
        if kf.get('plantFeet'):
            plant_feet(('l', 'r'), 0.0)
    elif anchor == 'back':
        bp = (head('upper_l') + head('upper_r')) / 2
        if state.get('anchor') is None:
            ground_to(None, 0.0)
            state['anchor'] = (head('upper_l') + head('upper_r')) / 2
            bp = state['anchor']
        transform_root(Matrix.Translation(state['anchor'] - bp))
        plant_feet(('l', 'r'), 0.0)
    else:
        gb = kf.get('groundOn')
        ground_to(gb, kf.get('groundZ', 0.0)) if gb else ground_to(None, 0.0)
        if kf.get('plantFeet'):
            pf = kf['plantFeet']
            plant_feet(pf.get('sides', ('l', 'r')), pf.get('z', 0.0))
    lift = a.get('lift', 0.0)
    if lift:
        transform_root(Matrix.Translation((0, 0, lift)))
    if 'goblet' in kf.get('props', []):
        c = (tail('hand_l') + tail('hand_r') + tail('fore_l') + tail('fore_r')) / 4
        for o, dz in zip(props['goblet'], (0, -0.1, 0.1)):
            o.location = c + Vector((0, -0.03, dz))
    return a


# ---------------------------------------------------------------- props placement and checks
def bench(center, size, height):
    top, l1, l2 = props['bench']
    top.location = Vector((center.x, center.y, height - 0.04)); top.scale = (size[0], size[1], 0.08)
    for lg, dy in ((l1, -1), (l2, 1)):
        lg.location = Vector((center.x, center.y + dy * (size[1] / 2 - 0.08), (height - 0.08) / 2))
        lg.scale = (size[0] * 0.8, 0.06, height - 0.08)


def metrics(kf):
    P = points()
    zmin = float(P[:, 2].min())
    m = {'zmin': round(zmin, 3)}
    for nm, bs in (('hands', HANDS), ('feet', FEET)):
        m[nm] = round(float(points(bs)[:, 2].min()), 3)
    return m


upd()
PROP_REST = {}
for key, objs in props.items():
    for o in objs:
        if o.parent_type == 'BONE' and o.parent is arm:
            PROP_REST[o.name] = (o.parent_bone, [o.matrix_world @ Vector(c) for c in o.bound_box])


def prop_min_z(on):
    zs = []
    for key, objs in props.items():
        if key in ('bar', 'bench', 'wall', 'mat', 'goblet'):
            continue
        if not ((key.startswith('dumbbells') and 'dumbbells' in on) or key in on):
            continue
        for o in objs:
            bone, corners = PROP_REST[o.name]
            M = W[bone] @ REST_INV[bone]
            zs.append(min((M @ c).z for c in corners))
    return min(zs) if zs else None


# ---------------------------------------------------------------- render loop
data = json.load(open(EXJSON))
report = {}
for ex in data['exercises']:
    if ONLY and ex['id'] not in ONLY:
        continue
    kf = ex['keyframes']
    tot = sum(ex['muscles'].values())
    wts = {m: v / tot for m, v in ex['muscles'].items()}
    for o in meshes:
        gname = o.get('ff_group') or ''
        lvl = 0 if not gname else min(5, round(min(1.0, wts.get(gname, 0) * 2.6) * 5))
        mat = bone_m if o.get('ff_kind') == 'bone' else (red_mats[lvl] if lvl else grey)
        o.data.materials.clear(); o.data.materials.append(mat)
    on = set(kf.get('props', []))
    for key, objs in props.items():
        show = (key.startswith('dumbbells') and 'dumbbells' in on) or key in on
        for p in objs:
            p.hide_render = not show
    timed = ex['mode'] == 'timed'
    n = 1 if timed else NFRAMES
    if PREVIEW and not timed:
        n = 3
    us = [0.0] if timed else [0.5 - 0.5 * math.cos(math.pi * i / (n - 1)) for i in range(n)]
    alt = bool(kf.get('alternate')) and not timed
    seq = [(u, False) for u in us] + ([(u, True) for u in us] if alt else [])
    state = {}
    # first pass: poses, bounds, metrics
    allp = []
    mets = []
    for u, sw in seq:
        a = place(kf, u, sw, state)
        P = points()
        allp.append(P[rng.choice(len(P), 4000, replace=False)])
        m = metrics(kf)
        pm = prop_min_z(on)
        if pm is not None:
            m['props'] = round(pm, 3)
        mets.append(m)
    lift = 0.0
    if 'bar' in on:
        lift = 0.10 - min(float(p[:, 2].min()) for p in allp)  # feet hang 10 cm above the floor
    allp = np.concatenate(allp)
    allp[:, 2] += lift
    front = kf.get('view') == 'front'
    yaw = math.radians(kf.get('camYaw', -28 if front else 42))
    elev = kf.get('camElev', 0.2)
    dirv = Vector((math.sin(yaw), -math.cos(yaw), elev)).normalized()
    right = (-dirv).cross(Vector((0, 0, 1))).normalized()
    upv = right.cross(-dirv).normalized()
    extra = []
    if 'bar' in on:
        extra.append(np.array(state['anchor'] + Vector((0, 0, lift + 0.08))))
    if extra:
        allp = np.concatenate([allp, np.array(extra)])
    R_ = np.array(right); U_ = np.array(upv)
    xs = allp @ R_; ys = allp @ U_
    w_, h_ = xs.max() - xs.min(), ys.max() - ys.min()
    ext = max(w_, h_) * 1.1 + 0.12
    cxs, cys = (xs.max() + xs.min()) / 2, (ys.max() + ys.min()) / 2
    foot = allp[allp[:, 2] < 0.25]
    if len(foot) == 0:
        foot = allp
    fc = Vector((float(np.median(foot[:, 0])), float(np.median(foot[:, 1])), 0.0))
    rad = float(np.percentile(np.linalg.norm(foot[:, :2] - np.array(fc[:2]), axis=1), 98)) + 0.55
    floor.location = fc; floor.scale = (rad * 2, rad * 2, 1)
    centre3 = Vector(tuple(cxs * R_ + cys * U_))
    cam.location = centre3 + dirv * 10
    cam.rotation_euler = (-dirv).to_track_quat('-Z', 'Y').to_euler()
    cam_d.ortho_scale = ext
    cam_d.clip_end = 30
    # keep the key light above-front of the subject
    LIGHTS['key'].location = fc + Vector((2.0 * math.sin(yaw + 0.5), -2.2 * math.cos(yaw + 0.5), 3.6))
    for nm, lo in LIGHTS.items():
        lo.rotation_euler = (Vector((fc.x, fc.y, 0.8)) - lo.location).to_track_quat('-Z', 'Y').to_euler()
    # static props
    if 'bar' in on:
        bp = state['anchor'] + Vector((0, 0, lift))
        pb_, p1, p2, f1, f2 = props['bar']
        pb_.location = bp
        for post, fo, sx in ((p1, f1, -0.62), (p2, f2, 0.62)):
            post.location = Vector((bp.x + sx, bp.y, bp.z / 2)); post.scale = (1, 1, bp.z)
            fo.location = Vector((bp.x + sx, bp.y, 0.02))
    if 'bench' in on:
        bsp = kf.get('benchAt', 'hands')
        place(kf, 0.0, False, state)
        if bsp == 'hands':
            hc = (tail('fore_l') + tail('fore_r')) / 2
            hz = float(points(HANDS)[:, 2].min())
            bench(Vector((hc.x, hc.y + kf.get('benchOffset', 0.18), 0)), (0.45, 0.55), max(0.2, hz))
        elif bsp == 'feet':
            fcn = (tail('foot_l') + tail('foot_r')) / 2
            fz = float(points(FEET)[:, 2].min())
            bench(Vector((fcn.x, fcn.y + 0.05, 0)), (0.45, 0.45), max(0.2, fz))
        elif bsp == 'rear_foot':
            fcn = tail('foot_r')
            fz = float(points(['foot_r'])[:, 2].min())
            bench(Vector((0, fcn.y + 0.12, 0)), (0.5, 0.5), max(0.2, fz))
        elif bsp == 'back':
            bpnt = state['anchor']
            bench(Vector((0, bpnt.y + 0.22, 0)), (0.55, 0.5), bpnt.z - 0.07)
    if 'wall' in on:
        place(kf, 0.0, False, state)
        P = points(['torso', 'root'])
        props['wall'][0].location = Vector((0, float(P[:, 1].max()) + 0.045, 1.2))
    if 'mat' in on:
        props['mat'][0].location = Vector((fc.x, fc.y, 0.004))
        lyy = foot[:, 1]
        props['mat'][0].scale = (0.62, max(1.2, float(lyy.max() - lyy.min()) + 0.4), 0.008)
    report[ex['id']] = mets
    for i, (u, sw) in enumerate(seq):
        _t0 = time.time()
        place(kf, u, sw, state)
        _t1 = time.time()
        if lift:
            transform_root(Matrix.Translation((0, 0, lift)))
        commit()
        scn.render.filepath = os.path.join(OUT, '%s_%02d.png' % (ex['id'], i))
        bpy.ops.render.render(write_still=True)
        if PROF:
            print('timing place %.2f render %.2f' % (_t1 - _t0, time.time() - _t1), flush=True)
    print('rendered', ex['id'], json.dumps(mets), flush=True)
json.dump(report, open(os.path.join(OUT, 'report.json'), 'w'), indent=1)
print('ALL DONE')
