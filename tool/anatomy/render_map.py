"""Renders the realistic anatomical body map used on the Recover screen and
for the muscle chips: a shaded base image (front, back), one coverage mask
per FormFlow muscle group, and a small ID map for tap detection.

    python3 -I render_map.py -- body.blend OUT_DIR
"""
import bpy, sys, os, json, math, mathutils

args = sys.argv[sys.argv.index('--') + 1:]
BLEND, OUT = args[0], args[1]
W, H = int(args[2]) if len(args) > 2 else 720, int(args[3]) if len(args) > 3 else 1440
os.makedirs(OUT, exist_ok=True)
GROUPS = ['chest', 'abs', 'obliques', 'lats', 'traps', 'shoulders', 'biceps', 'triceps', 'forearms',
          'lower_back', 'glutes', 'quads', 'hamstrings', 'calves']

bpy.ops.wm.open_mainfile(filepath=BLEND)
scn = bpy.context.scene
meshes = [o for o in bpy.data.objects if o.type == 'MESH']

# bounds
mn = [1e9] * 3; mx = [-1e9] * 3
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ mathutils.Vector(c)
        for i in range(3):
            mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
cz = (mn[2] + mx[2]) / 2
height = (mx[2] - mn[2]) * 1.04


def body_material(name, rgb):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    b.inputs['Roughness'].default_value = 0.5
    ao = nt.nodes.new('ShaderNodeAmbientOcclusion'); ao.inputs['Distance'].default_value = 0.025
    ao.inputs['Color'].default_value = (*rgb, 1)
    mixn = nt.nodes.new('ShaderNodeMix'); mixn.data_type = 'RGBA'; mixn.blend_type = 'MULTIPLY'
    mixn.inputs['Factor'].default_value = 0.85
    mixn.inputs[6].default_value = (*rgb, 1)
    nt.links.new(ao.outputs['AO'], mixn.inputs['Factor'])
    # base * ao (darken crevices)
    gamma = nt.nodes.new('ShaderNodeMath'); gamma.operation = 'POWER'; gamma.inputs[1].default_value = 1.6
    nt.links.new(ao.outputs['AO'], gamma.inputs[0])
    mul = nt.nodes.new('ShaderNodeMix'); mul.data_type = 'RGBA'; mul.blend_type = 'MIX'
    mul.inputs[6].default_value = (rgb[0] * 0.25, rgb[1] * 0.25, rgb[2] * 0.27, 1)
    mul.inputs[7].default_value = (*rgb, 1)
    nt.links.new(gamma.outputs[0], mul.inputs['Factor'])
    nt.links.new(mul.outputs[2], b.inputs['Base Color'])
    return m


def emission(name, rgb):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    e = nt.nodes.new('ShaderNodeEmission'); e.inputs['Color'].default_value = (*rgb, 1)
    o = nt.nodes.new('ShaderNodeOutputMaterial'); nt.links.new(e.outputs[0], o.inputs[0])
    return m


def holdout():
    m = bpy.data.materials.new('holdout'); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    h = nt.nodes.new('ShaderNodeHoldout'); o = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(h.outputs[0], o.inputs[0])
    return m


def assign(fn):
    for o in meshes:
        o.data.materials.clear(); o.data.materials.append(fn(o))


cam = bpy.data.cameras.new('cam'); cam.type = 'ORTHO'; cam.ortho_scale = height
co = bpy.data.objects.new('cam', cam); scn.collection.objects.link(co); scn.camera = co
scn.render.resolution_x, scn.render.resolution_y = W, H
scn.render.film_transparent = True
scn.render.engine = 'CYCLES'; scn.cycles.device = 'CPU'
w = bpy.data.worlds.new('w'); scn.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs[0].default_value = (0.03, 0.03, 0.04, 1)
w.node_tree.nodes['Background'].inputs[1].default_value = 0.4
lights = []


def set_view(view):
    s = -1 if view == 'front' else 1
    co.location = (0, 5 * s, cz)
    co.rotation_euler = (math.radians(90), 0, 0 if view == 'front' else math.radians(180))
    for l in lights:
        bpy.data.objects.remove(l)
    lights.clear()
    for name, loc, energy, size in [('key', (-1.6, 3.0 * s, cz + 1.4), 140, 2.2), ('fill', (2.4, 3.2 * s, cz), 40, 3),
                                    ('rim1', (-1.8, -2.5 * s, cz + 1.0), 110, 1.5), ('rim2', (1.8, -2.5 * s, cz + 0.6), 90, 1.5),
                                    ('top', (0, 0, cz + 2.6), 40, 2)]:
        ld = bpy.data.lights.new(name, 'AREA'); ld.energy = energy; ld.size = size
        lo = bpy.data.objects.new(name, ld); scn.collection.objects.link(lo); lo.location = loc
        d = mathutils.Vector((0, 0, cz)) - mathutils.Vector(loc)
        lo.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        lights.append(lo)


def render(path, samples, denoise=True, view_transform='AgX', aa=True):
    scn.cycles.samples = samples; scn.cycles.use_denoising = denoise
    scn.view_settings.view_transform = view_transform
    scn.view_settings.look = 'AgX - Medium High Contrast' if view_transform == 'AgX' else 'None'
    scn.cycles.filter_width = 1.5 if aa else 0.01
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)


grey = body_material('grey', (0.72, 0.72, 0.74))
bone_m = body_material('bone', (0.66, 0.65, 0.63))
white = emission('white', (1, 1, 1))
hold = holdout()
meta = {'groups': GROUPS, 'size': [W, H], 'views': {}}
for view in ['front', 'back']:
    set_view(view)
    assign(lambda o: bone_m if o.get('ff_kind') == 'bone' else grey)
    render(f'{OUT}/body_{view}.png', 64)
    boxes = {}
    for g in GROUPS:
        assign(lambda o: white if o.get('ff_group') == g else hold)
        path = f'{OUT}/mask_{view}_{g}.png'
        render(path, 8, denoise=False, view_transform='Standard')
        boxes[g] = path
    # tiny ID map for tap detection: gray level = (group index + 1) * 16
    idm = {g: emission('id_' + g, ((i + 1) * 16 / 255.0,) * 3) for i, g in enumerate(GROUPS)}
    blk = emission('id_none', (0, 0, 0))
    assign(lambda o: idm.get(o.get('ff_group'), blk))
    scn.render.resolution_x, scn.render.resolution_y = W // 4, H // 4
    render(f'{OUT}/id_{view}.png', 1, denoise=False, view_transform='Standard', aa=False)
    scn.render.resolution_x, scn.render.resolution_y = W, H
    meta['views'][view] = True
json.dump(meta, open(f'{OUT}/meta.json', 'w'))
print('done')
