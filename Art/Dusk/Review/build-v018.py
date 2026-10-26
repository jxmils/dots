"""Dusk production-rig trial. Run with pinned Blender 5.2.3 LTS.

All visible character parts are geometry and procedural materials. Reference
images are retained for comparison only, never projected onto the model.
No animation Actions are authored before the style-frame review.
"""
from pathlib import Path
from array import array
import argparse
import hashlib
import json
import math
import random
import sys

import bpy
from mathutils import Vector
from mathutils import noise

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'Art/Dusk/Production'
parser = argparse.ArgumentParser()
parser.add_argument('--preview', action='store_true')
parser.add_argument('--no-render', action='store_true')
parser.add_argument('--look-review', action='store_true', help='Metal render without denoising; at least 256 samples')
parser.add_argument('--samples', type=int, default=96)
parser.add_argument('--trial-blender-version', choices=['5.1.0'])
parser.add_argument('--revision', default='v001')
parser.add_argument('--eye-highlight-mode', choices=['geometry', 'lighting'], default='geometry')
parser.add_argument('--eye-fill-energy', type=float, default=220)
parser.add_argument('--fur-material', choices=['plush', 'hybrid'], default='hybrid')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
expected_version = args.trial_blender_version or '5.2.3'
assert bpy.app.version_string == expected_version, bpy.app.version_string
assert args.revision.startswith('v') and args.revision[1:].isdigit()
model_path = OUT/'02_blender'/f'dusk_rig_{args.revision}.blend'
if model_path.exists():
    raise FileExistsError(f'Preserve existing master: {model_path}; choose a new --revision')
for directory in ['02_blender', '04_previews', '05_render_masters']:
    (OUT / directory).mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
review_samples = max(256, args.samples) if args.look_review else args.samples
scene.cycles.samples = review_samples if args.look_review else (24 if args.preview else args.samples)
scene.cycles.use_denoising = not args.look_review
if args.look_review:
    preferences = bpy.context.preferences.addons['cycles'].preferences
    preferences.compute_device_type = 'METAL'
    preferences.get_devices()
    for device in preferences.devices:
        device.use = device.type == 'METAL'
    assert any(device.use for device in preferences.devices), 'Metal device unavailable'
    scene.cycles.device = 'GPU'
scene.cycles.seed = 7319
scene.cycles.use_animated_seed = False
scene.render.resolution_x = scene.render.resolution_y = 640 if args.preview else 1536
scene.render.resolution_percentage = 100
scene.render.fps = 30
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.color_depth = '16'
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = 0.0
scene.world = bpy.data.worlds.new('STUDIO_WORLD')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.86, .84, .82, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .14

def material(name, color, roughness=.75):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = roughness
    return mat

CHARCOAL = (.021, .020, .021)
PINK = (.90, .19, .24)
body_mat = material('MAT_CHARCOAL_PLUSH', CHARCOAL, .91)
body_shader = body_mat.node_tree.nodes['Principled BSDF']
body_shader.inputs['Specular IOR Level'].default_value = .12
body_shader.inputs['Sheen Weight'].default_value = .25
blush = body_mat.node_tree.nodes.new('ShaderNodeVertexColor')
blush.layer_name = 'CoatColor'
body_mat.node_tree.links.new(blush.outputs['Color'], body_shader.inputs['Base Color'])
lid_mat = material('MAT_CLOSE_LYING_EYELIDS', CHARCOAL, .94)
dark_mat = material('MAT_SOFT_BROWS', (.012, .010, .015), .8)
mouth_mat = material('MAT_CLOSED_SMILE', (.009, .0035, .0018), .75)
mouth_mat.node_tree.nodes['Principled BSDF'].inputs['Specular IOR Level'].default_value = .05
eye_mat = material('MAT_BROWN_GLASS', (.035, .010, .003), .11)
# The actual EyeTone attribute belongs to the recessed iris.
en, el = eye_mat.node_tree.nodes, eye_mat.node_tree.links
en.clear()
eye_shader = en.new('ShaderNodeBsdfPrincipled')
eye_shader.inputs['Roughness'].default_value = .11
eye_shader.inputs['Specular IOR Level'].default_value = .22
eye_shader.inputs['Coat Weight'].default_value = .20
eye_shader.inputs['Coat Roughness'].default_value = .16
eye_shader.inputs['Emission Strength'].default_value = .025
eye_tone = en.new('ShaderNodeAttribute')
eye_tone.attribute_name = 'EyeTone'
el.new(eye_tone.outputs['Color'], eye_shader.inputs['Base Color'])
el.new(eye_tone.outputs['Color'], eye_shader.inputs['Emission Color'])
eye_output = en.new('ShaderNodeOutputMaterial')
el.new(eye_shader.outputs['BSDF'], eye_output.inputs['Surface'])
eye_shader.inputs['Roughness'].default_value = .50
eye_shader.inputs['Specular IOR Level'].default_value = .12
eye_shader.inputs['Coat Weight'].default_value = 0
eye_shader.inputs['Emission Strength'].default_value = .006
cornea_mat = material('MAT_CLEAR_CORNEA', (1, 1, 1), .05)
cornea_shader = cornea_mat.node_tree.nodes['Principled BSDF']
cornea_shader.inputs['IOR'].default_value = 1.40
cornea_shader.inputs['Transmission Weight'].default_value = 1
cornea_shader.inputs['Coat Weight'].default_value = .10
cornea_shader.inputs['Coat Roughness'].default_value = .04
# A thin non-refracting varnish prevents a single open corneal sheet from
# bending camera rays outside the iris and revealing the grey body behind it.
cn, cl = cornea_mat.node_tree.nodes, cornea_mat.node_tree.links
cn.clear()
transparent = cn.new('ShaderNodeBsdfTransparent')
reflection = cn.new('ShaderNodeBsdfPrincipled')
reflection.inputs['Base Color'].default_value = (.7, .7, .7, 1)
reflection.inputs['Metallic'].default_value = 1
reflection.inputs['Roughness'].default_value = .08
fresnel = cn.new('ShaderNodeFresnel')
fresnel.inputs['IOR'].default_value = 1.40
mix = cn.new('ShaderNodeMixShader')
reflection_strength = cn.new('ShaderNodeMath')
reflection_strength.operation = 'MULTIPLY'
reflection_strength.inputs[1].default_value = .08
cl.new(fresnel.outputs['Fac'], reflection_strength.inputs[0])
cl.new(reflection_strength.outputs[0], mix.inputs[0])
cl.new(transparent.outputs[0], mix.inputs[1])
cl.new(reflection.outputs['BSDF'], mix.inputs[2])
output = cn.new('ShaderNodeOutputMaterial')
cl.new(mix.outputs[0], output.inputs['Surface'])

def mesh(name, vertices, faces, mat):
    data = bpy.data.meshes.new(name + '_MESH')
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    if mat:
        data.materials.append(mat)
    for polygon in data.polygons:
        polygon.use_smooth = True
    return obj

def sphere(name, location, scale, mat, angle=0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=40, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler.y = angle
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if mat:
        obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj

# An authored volumetric profile, not a traced contour or a textured relief.
PROFILE = [(0, .44), (.012, .59), (.045, .73), (.10, .81), (.20, .86),
           (.38, .89), (.56, .87), (.74, .81), (.91, .70), (1.06, .56),
           (1.18, .37), (1.27, .16), (1.30, .00001)]
BODY_HEIGHT = 1.30*.92*1.07
# Retain the soft planted base while lowering the dome and widening the belly.
PROFILE = [(z*.92*1.07, r*(1+.04*max(0, 1-z/1.0))) for z, r in PROFILE]

def radius(z):
    for i, ((za, ra), (zb, rb)) in enumerate(zip(PROFILE, PROFILE[1:])):
        if za <= z <= zb:
            previous, following = PROFILE[max(0, i-1)], PROFILE[min(len(PROFILE)-1, i+2)]
            ma = (rb-previous[1])/(zb-previous[0])
            mb = (following[1]-ra)/(following[0]-za)
            t = (z-za)/(zb-za)
            return max(.00001, (2*t**3-3*t*t+1)*ra + (t**3-2*t*t+t)*(zb-za)*ma
                       + (-2*t**3+3*t*t)*rb + (t**3-t*t)*(zb-za)*mb)
    return .00001

vertices, faces = [], []
ROWS, COLUMNS = 100, 128
for row in range(ROWS):
    z = row/(ROWS-1)*BODY_HEIGHT
    r = radius(z)
    for col in range(COLUMNS):
        angle = col/COLUMNS*math.tau
        vertices.append((r*math.cos(angle), .76*r*math.sin(angle), z))
for row in range(ROWS-1):
    for col in range(COLUMNS):
        a, b = row*COLUMNS+col, row*COLUMNS+(col+1)%COLUMNS
        faces.append((a, b, b+COLUMNS, a+COLUMNS))
faces.extend([tuple(reversed(range(COLUMNS))), tuple(range((ROWS-1)*COLUMNS, ROWS*COLUMNS))])
body = mesh('BODY', vertices, faces, body_mat)
uv = body.data.uv_layers.new(name='SurfaceUV')
for row in range(ROWS-1):
    for col in range(COLUMNS):
        polygon = body.data.polygons[row*COLUMNS+col]
        lower, upper = .1+.8*row/(ROWS-1), .1+.8*(row+1)/(ROWS-1)
        corners = [(col/COLUMNS, lower), ((col+1)/COLUMNS, lower),
                   ((col+1)/COLUMNS, upper), (col/COLUMNS, upper)]
        for loop, coordinate in zip(polygon.loop_indices, corners):
            uv.data[loop].uv = coordinate
for polygon, z, center_v in [(body.data.polygons[-2], 0, .045), (body.data.polygons[-1], BODY_HEIGHT, .955)]:
    r = radius(z)
    for loop in polygon.loop_indices:
        co = body.data.vertices[body.data.loops[loop].vertex_index].co
        uv.data[loop].uv = (.5+.04*co.x/r, center_v+.04*co.y/(.76*r))
body.data.update()

def front(x, z):
    r = radius(z)
    return -.76*r*math.sqrt(max(0, 1-(x/r)**2))

EYE_X, EYE_Z, EYE_RX, EYE_RZ = .365, .695*.92+.035, .145, .166
EYE_BULGE, EYE_RIM_OFFSET = .034, .003

def eye_rho(point):
    if point.y > -.30:
        return 100.0
    return min(math.hypot((point.x-side*EYE_X)/EYE_RX, (point.z-EYE_Z)/EYE_RZ) for side in [-1, 1])

def smoothstep(value):
    value = max(0, min(1, value))
    return value*value*(3-2*value)

def eye_fur_fade(point):
    return smoothstep((eye_rho(point)-1.01)/.05)

def eye_fur_length(point):
    return .30+.70*smoothstep((eye_rho(point)-1.01)/.14)

def eye_lens_y(x, z, cx):
    rho2 = ((x-cx)/EYE_RX)**2+((z-EYE_Z)/EYE_RZ)**2
    return front(x, z)-EYE_RIM_OFFSET-EYE_BULGE*max(0, 1-rho2)**2

# A controlled plush eye bed; the authored lens determines the oval aperture.
for vertex in body.data.vertices:
    if vertex.co.y < -.30:
        vertex.co.y += .008*(1-smoothstep(eye_rho(vertex.co)/1.08))
body.data.update()

def blush_amount(point):
    x, y, z = point
    amount = max(math.exp(-((x-cx)/(.165*.90))**2-((z-(.49*.92+.065))/(.105*.90))**2) for cx in [-.48, .48])
    return amount*max(0, min(1, (-y-.25)/.16))*.65

def coat_color(point):
    amount = blush_amount(point)
    return tuple(a*(1-amount)+b*amount for a, b in zip(CHARCOAL, PINK))

def add_coat(obj):
    attribute = obj.data.color_attributes.new(name='CoatColor', type='FLOAT_COLOR', domain='POINT')
    for vertex, color in zip(obj.data.vertices, attribute.data):
        color.color = (*coat_color(vertex.co), 1)

add_coat(body)
arms, tufts = [], []
for side, label in [(-1, 'L'), (1, 'R')]:
    obj = sphere('ARM_'+label, (side*.895, .01, .49), (.125*1.10, .14, .215*1.20), body_mat, -side*.55)
    add_coat(obj)
    arms.append(obj)
for index, location, scale, angle in [
    (1, (-.19, .015, 1.25-.08), (.1125, .105, .140), -.65),
    (2, (-.060, .005, 1.390-.08), (.130*.90, .105, .205*1.15), -.40),
    (3, (.135, .010, 1.330-.08), (.1035, .100, .166), .42)]:
    obj = sphere(f'TUFT_{index:02}', location, scale, body_mat, angle)
    add_coat(obj)
    tufts.append(obj)

# Actual armature with stable rest coordinates and separate body/arm/tuft controls.
data = bpy.data.armatures.new('DUSK_ARMATURE')
rig = bpy.data.objects.new('DUSK_RIG', data)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bone_specs = [
    ('CTRL_ROOT', (0, 0, 0), (0, 0, .20), None),
    ('CTRL_BODY_MOVE', (0, 0, .20), (0, 0, .45), 'CTRL_ROOT'),
    ('CTRL_BODY_TURN', (0, 0, .45), (0, 0, .70), 'CTRL_BODY_MOVE'),
    ('CTRL_BODY_SQUASH', (0, 0, 0), (0, 0, 1.25), 'CTRL_BODY_TURN'),
    ('CTRL_BODY_TOP', (0, 0, .90), (0, 0, 1.30), 'CTRL_BODY_SQUASH'),
    ('CTRL_ARM_L', (-.78, 0, .62), (-1.04, 0, .35), 'CTRL_BODY_TURN'),
    ('CTRL_ARM_R', (.78, 0, .62), (1.04, 0, .35), 'CTRL_BODY_TURN'),
    ('CTRL_TUFTS', (0, 0, 1.18), (0, 0, 1.59), 'CTRL_BODY_TOP')]
for name, head, tail, parent in bone_specs:
    bone = data.edit_bones.new(name)
    bone.head, bone.tail = head, tail
    if parent:
        bone.parent = data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
rig.show_in_front = True
data.display_type = 'STICK'
for name in ['Blink_L', 'Blink_R', 'Blink_Both', 'Eyes_Happy', 'Eyes_Sleepy', 'Brow_Worried', 'Brow_Angry']:
    rig[name] = 0.0
    rig.id_properties_ui(name).update(min=0, max=1, description='Facial control: 0 neutral, 1 full')
rig['style_status'] = 'Unapproved style-frame trial; no animation Actions yet'
rig['mouth_policy'] = 'Fixed closed smile. No tongue, open-mouth geometry or speech controls.'

def bind(obj, bone_name=None):
    rest = obj.data.attributes.get('rest_position') or obj.data.attributes.new('rest_position', 'FLOAT_VECTOR', 'POINT')
    rest.data.foreach_set('vector', array('f', (v for point in obj.data.vertices for v in point.co)))
    if bone_name:
        group = obj.vertex_groups.new(name=bone_name)
        group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    else:
        lower = obj.vertex_groups.new(name='CTRL_BODY_SQUASH')
        upper = obj.vertex_groups.new(name='CTRL_BODY_TOP')
        for vertex in obj.data.vertices:
            t = max(0, min(1, (vertex.co.z-.90)/.40))
            t = t*t*(3-2*t)
            lower.add([vertex.index], 1-t, 'REPLACE')
            upper.add([vertex.index], t, 'REPLACE')
    modifier = obj.modifiers.new('RIG_DEFORMATION', 'ARMATURE')
    modifier.object = rig
    obj.parent = rig

bind(body)
for obj, label in zip(arms, ['L', 'R']):
    bind(obj, 'CTRL_ARM_'+label)
for obj in tufts:
    bind(obj, 'CTRL_TUFTS')

def tube(name, points, thickness, mat, end_radius=.10):
    curve = bpy.data.curves.new(name+'_CURVE', 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth, curve.bevel_resolution, curve.resolution_u = thickness, 5, 16
    curve.use_fill_caps = True
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points)-1)
    for index, (point, co) in enumerate(zip(spline.bezier_points, points)):
        point.co = co
        point.handle_left_type = point.handle_right_type = 'AUTO'
        t = index/(len(points)-1)
        edge = .22
        q = t/edge if t < edge else ((1-t)/edge if t > 1-edge else 1)
        point.radius = math.sqrt(max(0, 1-(1-q)**2))
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    obj = bpy.context.object
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj

def facial_driver(key, expression, properties):
    driver = key.driver_add('value').driver
    driver.expression = expression
    for name in properties:
        variable = driver.variables.new()
        variable.name, variable.type = name, 'SINGLE_PROP'
        variable.targets[0].id = rig
        variable.targets[0].data_path = '["'+name+'"]'

for side, label in [(-1, 'L'), (1, 'R')]:
    x, z = side*EYE_X, EYE_Z
    y = front(x, z)
    rx, ry, rz = EYE_RX, EYE_BULGE, EYE_RZ
    # Closed shallow lens volume, with a designed vertical oval perimeter.
    # The back is buried in the recessed shell; the front follows its curvature.
    lens_vertices, lens_faces = [], []
    lens_rows, lens_cols = 32, 96
    for back in [False, True]:
        lens_vertices.append((x, front(x, z)+.012 if back else eye_lens_y(x, z, x), z))
        offset = len(lens_vertices)-1
        for row in range(1, lens_rows+1):
            rho = row/lens_rows
            for col in range(lens_cols):
                theta = col/lens_cols*math.tau
                xx, zz = x+rx*rho*math.cos(theta), z+rz*rho*math.sin(theta)
                yy = front(xx, zz)+.012 if back else eye_lens_y(xx, zz, x)
                lens_vertices.append((xx, yy, zz))
        for col in range(lens_cols):
            face = (offset, offset+1+col, offset+1+(col+1)%lens_cols)
            lens_faces.append(tuple(reversed(face)) if back else face)
        for row in range(lens_rows-1):
            for col in range(lens_cols):
                a = offset+1+row*lens_cols+col
                b = offset+1+row*lens_cols+(col+1)%lens_cols
                face = (a, b, b+lens_cols, a+lens_cols)
                lens_faces.append(tuple(reversed(face)) if back else face)
    rear = 1+lens_rows*lens_cols
    front_edge = 1+(lens_rows-1)*lens_cols
    back_edge = rear+front_edge
    for col in range(lens_cols):
        a, b = front_edge+col, front_edge+(col+1)%lens_cols
        c, d = back_edge+col, back_edge+(col+1)%lens_cols
        lens_faces.append((a, c, d, b))
    front_vertex_count = 1+lens_rows*lens_cols
    front_face_count = lens_rows*lens_cols
    eye = mesh('EYE_'+label, lens_vertices[:front_vertex_count], lens_faces[:front_face_count], cornea_mat)
    eye.visible_shadow = False  # Stable iris lighting without refractive caustics.
    iris_vertices = []
    for xx, yy, zz in lens_vertices[:front_vertex_count]:
        rho2 = ((xx-x)/rx)**2+((zz-z)/rz)**2
        iris_vertices.append((xx, front(xx, zz)-.0023-.020*max(0, 1-rho2)**2, zz))
    iris_surface = mesh('EYE_IRIS_'+label, iris_vertices, lens_faces[:front_face_count], eye_mat)
    bind(iris_surface)
    if args.eye_highlight_mode == 'geometry':
        # Stylized authored 3D highlight, explicitly not an optical reflection.
        # It is thinner than the eyelid's surface offset so a blink occludes it.
        highlight_mat = bpy.data.materials.get('MAT_AUTHORED_EYE_HIGHLIGHT')
        if highlight_mat is None:
            highlight_mat = bpy.data.materials.new('MAT_AUTHORED_EYE_HIGHLIGHT')
            highlight_mat.use_nodes = True
            hn, hl = highlight_mat.node_tree.nodes, highlight_mat.node_tree.links
            hn.clear()
            transparent = hn.new('ShaderNodeBsdfTransparent')
            emission = hn.new('ShaderNodeEmission')
            emission.inputs['Color'].default_value = (.98, .98, .95, 1)
            emission.inputs['Strength'].default_value = 1.05
            mask = hn.new('ShaderNodeAttribute')
            mask.attribute_name = 'HighlightMask'
            mix = hn.new('ShaderNodeMixShader')
            hl.new(mask.outputs['Fac'], mix.inputs[0])
            hl.new(transparent.outputs[0], mix.inputs[1])
            hl.new(emission.outputs[0], mix.inputs[2])
            output = hn.new('ShaderNodeOutputMaterial')
            hl.new(mix.outputs[0], output.inputs['Surface'])
        hx, hz, hr = x+rx*.35, z+rz*.44, .024
        hv, hf = [], []
        hrows, hcols = 8, 48
        for back in [False, True]:
            offset = len(hv)
            hv.append((hx, eye_lens_y(hx, hz, x)-(.0002 if back else .0011), hz))
            for row in range(1, hrows+1):
                rho = row/hrows
                for col in range(hcols):
                    theta = col/hcols*math.tau
                    xx, zz = hx+hr*rho*math.cos(theta), hz+hr*rho*math.sin(theta)
                    advance = .0002 if back else .0004+.0007*(1-rho*rho)
                    hv.append((xx, eye_lens_y(xx, zz, x)-advance, zz))
            for col in range(hcols):
                face = (offset, offset+1+col, offset+1+(col+1)%hcols)
                hf.append(tuple(reversed(face)) if back else face)
            for row in range(hrows-1):
                for col in range(hcols):
                    a, b = offset+1+row*hcols+col, offset+1+row*hcols+(col+1)%hcols
                    face = (a, b, b+hcols, a+hcols)
                    hf.append(tuple(reversed(face)) if back else face)
        rear = 1+hrows*hcols
        edge = 1+(hrows-1)*hcols
        for col in range(hcols):
            a, b = edge+col, edge+(col+1)%hcols
            hf.append((a, rear+a, rear+b, b))
        highlight = mesh('EYE_HIGHLIGHT_'+label, hv, hf, highlight_mat)
        mask_attribute = highlight.data.attributes.new('HighlightMask', 'FLOAT', 'POINT')
        for vertex, value in zip(highlight.data.vertices, mask_attribute.data):
            rho = math.hypot((vertex.co.x-hx)/hr, (vertex.co.z-hz)/hr)
            value.value = 1-smoothstep((rho-.58)/.42)
        highlight.visible_shadow = False
        highlight.visible_glossy = False
        highlight.visible_diffuse = False
        bind(highlight)
    attribute = iris_surface.data.color_attributes.new(name='EyeTone', type='FLOAT_COLOR', domain='POINT')
    for vertex, color in zip(iris_surface.data.vertices, attribute.data):
        dx, dz = (vertex.co.x-x)/rx, (vertex.co.z-z)/rz
        radial = math.sqrt(dx*dx+dz*dz)
        pupil_radius = math.hypot(dx/.92, (dz-.02)/1.02)
        pupil = (1-smoothstep((pupil_radius-.28)/(.59-.28)))*.88
        rim = smoothstep((radial-.76)/(.98-.76))
        warmth = smoothstep((-dz+.25)/1.15)
        iris_dark, iris_warm = (.004, .0012, .0006), (.110, .032, .009)
        pupil_color, rim_color = (.0008, .00025, .00015), (.0025, .0007, .00035)
        iris = tuple(iris_dark[i]*(1-warmth)+iris_warm[i]*warmth for i in range(3))
        shade = tuple(iris[i]*(1-pupil)+pupil_color[i]*pupil for i in range(3))
        color.color = (*(shade[i]*(1-rim)+rim_color[i]*rim for i in range(3)), 1)
    bind(eye)

    cols, rows = 64, 16
    def lid_vertices(closure):
        points = []
        for cap in range(2):
            for row in range(rows+1):
                t = row/rows
                for col in range(cols+1):
                    u = col/cols*2-1
                    arc = math.sqrt(max(0, 1-u*u))
                    boundary = (1 if cap == 0 else -1)*rz*arc
                    seam = -.045*arc
                    coverage = .08+(1-.08)*closure if cap == 0 else closure
                    inner = boundary*(1-coverage)+seam*coverage
                    zz = boundary*(1-t)+inner*t
                    yy = eye_lens_y(x+rx*u, z+zz, x)-.002
                    points.append((x+rx*u, yy, z+zz))
        return points
    lid_faces = []
    for cap in range(2):
        offset = cap*(cols+1)*(rows+1)
        for row in range(rows):
            for col in range(cols):
                a = offset+row*(cols+1)+col
                lid_faces.append((a, a+1, a+cols+2, a+cols+1))
    lid = mesh('EYELID_'+label, lid_vertices(.0001), lid_faces, lid_mat)
    lid.shape_key_add(name='Basis', from_mix=False)
    key = lid.shape_key_add(name='Blink_'+label, from_mix=False)
    for vertex, coordinate in zip(key.data, lid_vertices(1)):
        vertex.co = coordinate
    facial_driver(key, 'min(1, max(Blink_Both, Blink_'+label+') + Eyes_Sleepy*.5 + Eyes_Happy*.22)',
                  ['Blink_Both', 'Blink_'+label, 'Eyes_Sleepy', 'Eyes_Happy'])
    bind(lid)

    points = []
    for index in range(11):
        t = index/10
        bx = x+(t-.5)*.130
        bz = .965*.92-.005+.010*math.sin(math.pi*t)-side*(t-.5)*.014
        points.append((bx, front(bx, bz)-.012, bz))
    brow = tube('EYEBROW_'+label, points, .026, dark_mat, end_radius=.15)
    brow.shape_key_add(name='Basis', from_mix=False)
    for name, slope in [('Brow_Worried', -.35), ('Brow_Angry', .30)]:
        key = brow.shape_key_add(name=name, from_mix=False)
        for vertex in key.data:
            vertex.co.z += side*(vertex.co.x-x)*slope
        facial_driver(key, name, [name])
    bind(brow)

smile_points = []
for index in range(21):
    t = index/20
    x = (t-.5)*.225
    z = .550*.92+.035-.045*(1-(2*t-1)**2)
    smile_points.append((x, front(x, z)-.020, z))
mouth_mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.012, .0035, .0018, 1)
mouth_mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .90
mouth_mat.node_tree.nodes['Principled BSDF'].inputs['Specular IOR Level'].default_value = .03
smile_vertices, smile_faces = [], []
for index, co in enumerate(smile_points):
    t = index/(len(smile_points)-1)
    before, after = Vector(smile_points[max(0, index-1)]), Vector(smile_points[min(len(smile_points)-1, index+1)])
    tangent = after-before
    perpendicular = Vector((-tangent.z, 0, tangent.x)).normalized()
    half_width = .001725+.006325*smoothstep(min(t, 1-t)/.18)
    for back in [False, True]:
        for sign in [-1, 1]:
            x, z = co[0]+sign*perpendicular.x*half_width, co[2]+sign*perpendicular.z*half_width
            smile_vertices.append((x, front(x, z)-(.002 if back else .0035), z))
for index in range(len(smile_points)-1):
    a, b = index*4, (index+1)*4
    smile_faces.extend([(a, b, b+1, a+1), (a+2, a+3, b+3, b+2),
                        (a, a+2, b+2, b), (a+1, b+1, b+3, a+3)])
smile_faces.extend([(0, 1, 3, 2), tuple((len(smile_points)-1)*4+i for i in [0, 2, 3, 1])])
smile = mesh('MOUTH_FIXED_CLOSED_SMILE', smile_vertices, smile_faces, mouth_mat)
bind(smile)

def mouth_channel(point):
    if point.y > -.3:
        return 1
    p = Vector((point.x, point.z))
    distance = 100
    for a, b in zip(smile_points, smile_points[1:]):
        a, b = Vector((a[0], a[2])), Vector((b[0], b[2]))
        delta = b-a
        amount = max(0, min(1, (p-a).dot(delta)/delta.length_squared))
        distance = min(distance, (p-a-delta*amount).length)
    return smoothstep((distance-.010)/.018)

# Hair Curves use a retained, deterministic guide groom and native interpolation.
# Deform Curves on Surface makes the groom follow the armature-deformed mesh.
hair_materials = {}
for layer, longitudinal, radial in [('undercoat', .72, .76), ('pile', .50, .65)]:
    hair_mat = bpy.data.materials.new('MAT_CHARCOAL_FIBERS_'+layer)
    hair_mat.use_nodes = True
    nodes, links = hair_mat.node_tree.nodes, hair_mat.node_tree.links
    nodes.clear()
    output = nodes.new('ShaderNodeOutputMaterial')
    fiber = nodes.new('ShaderNodeBsdfHairPrincipled')
    fiber.parametrization = 'COLOR'
    fiber.inputs['Roughness'].default_value = longitudinal
    fiber.inputs['Radial Roughness'].default_value = radial
    fiber.inputs['Color'].default_value = (*CHARCOAL, 1)
    attr = nodes.new('ShaderNodeAttribute')
    attr.attribute_name = 'FurColor'
    links.new(attr.outputs['Color'], fiber.inputs['Color'])
    plush = nodes.new('ShaderNodeBsdfPrincipled')
    plush.inputs['Roughness'].default_value = .86 if layer == 'undercoat' else .78
    plush.inputs['Specular IOR Level'].default_value = .08 if layer == 'undercoat' else .10
    plush.inputs['Sheen Weight'].default_value = .28 if layer == 'undercoat' else .34
    plush.inputs['Sheen Roughness'].default_value = .85 if layer == 'undercoat' else .80
    lift = nodes.new('ShaderNodeMixRGB')
    lift.blend_type = 'MULTIPLY'
    lift.inputs[0].default_value = 1
    lift.inputs[2].default_value = (2.1, 2.1, 2.1, 1)
    links.new(attr.outputs['Color'], lift.inputs[1])
    links.new(lift.outputs[0], plush.inputs['Base Color'])
    plush.inputs['Sheen Tint'].default_value = (.12, .12, .12, 1)
    if args.fur_material == 'hybrid':
        mix = nodes.new('ShaderNodeMixShader')
        mix.inputs[0].default_value = .18
        links.new(plush.outputs['BSDF'], mix.inputs[1])
        links.new(fiber.outputs[0], mix.inputs[2])
        links.new(mix.outputs[0], output.inputs['Surface'])
    else:
        links.new(plush.outputs['BSDF'], output.inputs['Surface'])
    hair_materials[layer] = hair_mat

def make_groom(surface, guide_count, fiber_count, seed, layer):
    hair_mat = hair_materials[layer]
    rng = random.Random(seed)
    surface.data.calc_loop_triangles()
    triangles = list(surface.data.loop_triangles)
    triangle_weights = [tri.area for tri in triangles]
    choices = rng.choices(triangles, weights=triangle_weights, k=guide_count*2)
    positions, uv_values, radii, colors, normals = array('f'), array('f'), array('f'), array('f'), array('f')
    uv_layer = surface.data.uv_layers.active
    accepted = 0
    while accepted < guide_count:
        if not choices:
            choices = rng.choices(triangles, weights=triangle_weights, k=guide_count)
        tri = choices.pop()
        a, b, c = [surface.data.vertices[i] for i in tri.vertices]
        u, v = math.sqrt(rng.random()), rng.random()
        weights = (1-u, u*(1-v), u*v)
        point = a.co*weights[0]+b.co*weights[1]+c.co*weights[2]
        if surface.name == 'BODY' and eye_rho(point) < 1.015:
            continue
        accepted += 1
        normal = (a.normal*weights[0]+b.normal*weights[1]+c.normal*weights[2]).normalized()
        normals.extend(normal)
        root_uv = sum((uv_layer.data[loop].uv*weight for loop, weight in zip(tri.loops, weights)), Vector((0, 0)))
        uv_values.extend(root_uv)
        macro = noise.noise_vector(point*7, noise_basis='PERLIN_ORIGINAL')
        micro = noise.noise_vector(point*61+Vector((seed*.01, 0, 0)), noise_basis='PERLIN_ORIGINAL')
        flow = macro*.25+micro*.75
        tangent = flow-normal*flow.dot(normal)
        if tangent.length < .01:
            tangent = normal.cross(Vector((1, 0, 0)))
        tangent.normalize()
        if surface.name == 'BODY' and point.y < -.3 and eye_rho(point) < 1.20:
            cx = EYE_X if point.x > 0 else -EYE_X
            away = Vector((point.x-cx, 0, point.z-EYE_Z))
            away -= normal*away.dot(normal)
            if away.length > .001:
                away.normalize()
                weight = 1-smoothstep((eye_rho(point)-1.0)/.20)
                tangent = tangent*(1-weight)+away*weight
                tangent = tangent.normalized() if tangent.length > .001 else away
        face_region = surface.name == 'BODY' and point.y < -.3 and .40 < point.z < .95
        if layer == 'undercoat':
            interval = (.012, .020) if surface.name.startswith('TUFT_') else ((.007, .012) if face_region else (.009, .015))
            root_radius = rng.uniform(.00018, .00030)
            tilt = math.radians(rng.uniform(3, 10))
            direction = (normal*math.cos(tilt)+tangent*math.sin(tilt)).normalized()
            bend = rng.uniform(.02, .05)
            color_variation = rng.uniform(.94, 1.02)
            root_color, tip_color = rng.uniform(.92, .98), rng.uniform(.98, 1.04)
        else:
            interval = (.030, .044) if surface.name.startswith('TUFT_') else ((.021, .031) if face_region else (.024, .037))
            root_radius = rng.uniform(.00078, .00125)
            tilt = math.radians(rng.uniform(36, 44))
            direction = (normal*math.cos(tilt)+tangent*math.sin(tilt)).normalized()
            bend = rng.uniform(.14, .26)*rng.choice([-1, 1])
            color_variation = rng.uniform(.95, 1.05)
            root_color, tip_color = rng.uniform(.91, .98), rng.uniform(1.04, 1.10)
        length = rng.uniform(*interval)
        if surface.name == 'BODY':
            length *= eye_fur_length(point)
            if layer == 'pile':
                length *= .35+.65*mouth_channel(point)
        phase = rng.uniform(-math.pi, math.pi)
        # Keep the historical RNG draws above so material studies preserve
        # identical guide geometry; colour uses its own deterministic stream.
        strand_value = random.Random(seed*100000+accepted).uniform(.97, 1.03)
        across = normal.cross(tangent).normalized()
        for index in range(7):
            t = index/6
            curl = across*length*bend*math.sin(t*math.pi)*math.cos(phase+t)
            positions.extend(point+direction*length*t+curl)
            radii.append(root_radius*((1-.85*t*t) if layer == 'pile' else (1-.97*t)))
            colors.extend((*(value*strand_value for value in coat_color(point)), 1))
    data = bpy.data.hair_curves.new('GUIDES_'+surface.name+'_'+layer)
    data.add_curves([7]*guide_count)
    data.attributes['position'].data.foreach_set('vector', positions)
    data.attributes.new('radius', 'FLOAT', 'POINT').data.foreach_set('value', radii)
    data.attributes.new('surface_uv_coordinate', 'FLOAT2', 'CURVE').data.foreach_set('vector', uv_values)
    data.attributes.new('FurColor', 'FLOAT_COLOR', 'POINT').data.foreach_set('color', colors)
    data.attributes.new('GuideNormal', 'FLOAT_VECTOR', 'CURVE').data.foreach_set('vector', normals)
    data.surface, data.surface_uv_map = surface, uv_layer.name
    data.materials.append(hair_mat)
    obj = bpy.data.objects.new('FUR_GROOM_'+surface.name+'_'+layer, data)
    scene.collection.objects.link(obj)
    obj.visible_shadow = False  # Art-directed short plush: avoid dark root scratches.
    obj.parent = rig
    density_name = 'FurDensity_'+layer
    density = surface.data.attributes.new(density_name, 'FLOAT', 'POINT')
    for vertex, value in zip(surface.data.vertices, density.data):
        multiplier = max(.50, min(1.50, 1+.50*noise.noise(vertex.co*26, noise_basis='PERLIN_ORIGINAL'))) if layer == 'pile' else 1
        value.value = multiplier*(eye_fur_fade(vertex.co) if surface.name == 'BODY' else 1)
        if layer == 'pile' and surface.name == 'BODY':
            value.value *= .25+.75*mouth_channel(vertex.co)
    density_integral = sum(tri.area*sum(density.data[index].value for index in tri.vertices)/3 for tri in triangles)
    rest = bpy.data.objects.new('REST_SURFACE_'+surface.name+'_'+layer, surface.data.copy())
    scene.collection.objects.link(rest)
    rest.hide_render = True
    rest.hide_set(True)
    group = bpy.data.node_groups.new('GROOM_'+surface.name+'_'+layer, 'GeometryNodeTree')
    group.interface.new_socket(name='Geometry', in_out='INPUT', socket_type='NodeSocketGeometry')
    group.interface.new_socket(name='Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
    n, l = group.nodes, group.links
    source, target = n.new('NodeGroupInput'), n.new('NodeGroupOutput')
    info = n.new('GeometryNodeObjectInfo')
    info.inputs['Object'].default_value = rest
    distribute = n.new('GeometryNodeDistributePointsOnFaces')
    distribute.distribute_method = 'RANDOM'
    area = sum(tri.area for tri in triangles)
    density_field = n.new('GeometryNodeInputNamedAttribute')
    density_field.data_type = 'FLOAT'
    density_field.inputs['Name'].default_value = density_name
    density_scale = n.new('ShaderNodeMath')
    density_scale.operation = 'MULTIPLY'
    density_scale.inputs[1].default_value = fiber_count/density_integral
    l.new(density_field.outputs['Attribute'], density_scale.inputs[0])
    l.new(density_scale.outputs[0], distribute.inputs['Density'])
    distribute.inputs['Seed'].default_value = seed
    l.new(info.outputs['Geometry'], distribute.inputs['Mesh'])
    uv_attr = n.new('GeometryNodeInputNamedAttribute')
    uv_attr.data_type = 'FLOAT_VECTOR'
    uv_attr.inputs['Name'].default_value = uv_layer.name
    store = n.new('GeometryNodeStoreNamedAttribute')
    store.domain, store.data_type = 'POINT', 'FLOAT2'
    store.inputs['Name'].default_value = 'surface_uv_coordinate'
    l.new(distribute.outputs['Points'], store.inputs['Geometry'])
    l.new(uv_attr.outputs['Attribute'], store.inputs['Value'])
    interpolate = n.new('GeometryNodeInterpolateCurves')
    interpolate.inputs['Max Neighbors'].default_value = 4 if layer == 'undercoat' else 1
    guide_normal = n.new('GeometryNodeInputNamedAttribute')
    guide_normal.data_type = 'FLOAT_VECTOR'
    guide_normal.inputs['Name'].default_value = 'GuideNormal'
    l.new(guide_normal.outputs['Attribute'], interpolate.inputs['Guide Up'])
    l.new(source.outputs['Geometry'], interpolate.inputs['Guide Curves'])
    l.new(store.outputs['Geometry'], interpolate.inputs['Points'])
    l.new(distribute.outputs['Normal'], interpolate.inputs['Point Up'])
    # Interpolating guide attributes approximates their UV coordinates, which can
    # drift at seams during a turn. Attach each interpolated root to its exact
    # location on the rest surface instead of averaging guide-root UVs.
    curve_root = n.new('GeometryNodeSampleCurve')
    curve_root.mode = 'FACTOR'
    curve_root.use_all_curves = False
    curve_root.inputs['Factor'].default_value = 0
    curve_index = n.new('GeometryNodeInputIndex')
    l.new(interpolate.outputs['Curves'], curve_root.inputs['Curves'])
    l.new(curve_index.outputs['Index'], curve_root.inputs['Curve Index'])
    sample_uv = n.new('GeometryNodeSampleNearestSurface')
    sample_uv.data_type = 'FLOAT_VECTOR'
    l.new(info.outputs['Geometry'], sample_uv.inputs['Mesh'])
    l.new(uv_attr.outputs['Attribute'], sample_uv.inputs['Value'])
    l.new(curve_root.outputs['Position'], sample_uv.inputs['Sample Position'])
    attach = n.new('GeometryNodeStoreNamedAttribute')
    attach.domain, attach.data_type = 'CURVE', 'FLOAT2'
    attach.inputs['Name'].default_value = 'surface_uv_coordinate'
    l.new(interpolate.outputs['Curves'], attach.inputs['Geometry'])
    l.new(sample_uv.outputs['Value'], attach.inputs['Value'])
    deform = n.new('GeometryNodeDeformCurvesOnSurface')
    l.new(attach.outputs['Geometry'], deform.inputs['Curves'])
    set_material = n.new('GeometryNodeSetMaterial')
    set_material.inputs['Material'].default_value = hair_mat
    l.new(deform.outputs['Curves'], set_material.inputs['Geometry'])
    l.new(set_material.outputs['Geometry'], target.inputs['Geometry'])
    modifier = obj.modifiers.new('INTERPOLATE_AND_ATTACH', 'NODES')
    modifier.node_group = group
    obj['guide_count'], obj['target_fiber_count'], obj['fixed_seed'] = guide_count, fiber_count, seed
    obj['groom_layer'] = layer
    return obj

grooms = [make_groom(body, 4000, 85000, 7319, 'undercoat'),
          make_groom(body, 7000, 70000, 7399, 'pile')]
for index, obj in enumerate(arms+tufts):
    grooms.append(make_groom(obj, 450, 7000 if obj in arms else 6000, 7320+index, 'undercoat'))
    grooms.append(make_groom(obj, 300, 2600, 7400+index, 'pile'))

body_receivers = bpy.data.collections.new('STUDIO_LIGHT_RECEIVERS')
eye_receivers = bpy.data.collections.new('EYE_LIGHT_RECEIVERS')
individual_eyes = {label: bpy.data.collections.new('EYE_RECEIVER_'+label) for label in ['L', 'R']}
for obj in list(scene.objects):
    if obj.type in {'MESH', 'CURVE', 'CURVES'} and not obj.name.startswith('REST_'):
        (eye_receivers if obj.name.startswith('EYE_') else body_receivers).objects.link(obj)
        if obj.name in ['EYE_L', 'EYE_R']:
            individual_eyes[obj.name[-1]].objects.link(obj)

def light(name, location, energy, size, specular=0, diffuse=1, eyes=False, receiver=None, target=(0, 0, .8)):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size = energy, 'DISK', size
    data.specular_factor, data.diffuse_factor = specular, diffuse
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.light_linking.receiver_collection = receiver if receiver is not None else (eye_receivers if eyes else body_receivers)
    # Cycles 5.1 does not sync Light.{specular,diffuse}_factor. Explicit ray
    # visibility supplies the binary optical separation required by eye lights.
    obj.visible_glossy = specular > 0
    obj.visible_diffuse = diffuse > 0
    if eyes and specular == 0:
        obj.visible_transmission = False
    obj.location = location
    obj.rotation_euler = (Vector(target)-obj.location).to_track_quat('-Z', 'Y').to_euler()
    return obj

light('KEY_SOFT', (-1.5, -4, 3), 400, 5.0, specular=.60)
light('FILL_SOFT', (2, -3, 1.5), 160, 4.0, specular=.12, diffuse=.75)
light('RIM_SOFT', (1, 2.5, 3), 40, 4.0, specular=.40, diffuse=.25)
light('EYE_BASE_FILL', (0, -4, 2.2), args.eye_fill_energy, 4.5, specular=0, diffuse=.75, eyes=True, target=(0, 0, EYE_Z))
if args.eye_highlight_mode == 'lighting':
    for side, label in [(-1, 'L'), (1, 'R')]:
        cx = side*EYE_X
        light('EYE_GLINT_'+label, (cx+.12, -3.4, EYE_Z+.32), 120, .22,
              specular=1, diffuse=0, receiver=individual_eyes[label], target=(cx, front(cx, EYE_Z), EYE_Z))
rig['eye_highlight_policy'] = ('Authored emissive 3D highlight caps; occluded by eyelids; not optical reflections'
                               if args.eye_highlight_mode == 'geometry' else 'Light-based specular reflections')
camera_data = bpy.data.cameras.new('CAMERA_LOCKED_90MM')
camera = bpy.data.objects.new('CAMERA_LOCKED_90MM', camera_data)
scene.collection.objects.link(camera)
camera.location = (0, -7.5, 1.05)
camera.rotation_euler = (Vector((0, 0, .78))-camera.location).to_track_quat('-Z', 'Y').to_euler()
camera_data.type, camera_data.lens = 'PERSP', 90
scene.camera = camera
# A deliberately faint actual reflection card provides a broad corneal lift.
# The primary white dot is separate authored 3D geometry, documented above.
bpy.ops.mesh.primitive_plane_add(size=2, location=(.4, -3.3, 2.8))
card = bpy.context.object
card.name = 'CORNEAL_DEPTH_CARD'
card.scale = (.85, .65, 1)
card.rotation_euler = (Vector((0, 0, EYE_Z))-card.location).to_track_quat('Z', 'Y').to_euler()
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
card_mat = bpy.data.materials.new('MAT_DIM_CORNEAL_CARD')
card_mat.use_nodes = True
cn, cl = card_mat.node_tree.nodes, card_mat.node_tree.links
cn.clear()
emission = cn.new('ShaderNodeEmission')
emission.inputs['Color'].default_value = (.005, .005, .0045, 1)
emission.inputs['Strength'].default_value = 1
output = cn.new('ShaderNodeOutputMaterial')
cl.new(emission.outputs[0], output.inputs['Surface'])
card.data.materials.append(card_mat)
card.visible_camera = card.visible_diffuse = card.visible_shadow = False
card.visible_glossy = True
card.light_linking.receiver_collection = eye_receivers
scene.frame_start = 1
scene.frame_end = 60
scene.frame_set(1)
bpy.context.view_layer.update()

# Structural and attachment checks are retained separately from visual approval.
report = {
    'blender': bpy.app.version_string, 'actual_3d_geometry': True,
    'reference_images_used_as_materials': False, 'render_engine': scene.render.engine,
    'review_samples': review_samples, 'review_denoising': scene.cycles.use_denoising,
    'eye_highlight_mode': args.eye_highlight_mode,
    'eye_fill_energy': args.eye_fill_energy,
    'fur_material': args.fur_material, 'eye_layers': ['non-refracting clear varnish', 'recessed iris', 'authored feathered highlight'],
    'art_direction': {'fuzz_casts_shadows': False, 'corneal_reflection_multiplier': .08,
                      'highlight_is_authored_geometry': True},
    'master_fps': 30, 'master_png': '16-bit RGBA', 'fixed_seed': 7319,
    'controls': [bone.name for bone in data.bones],
    'facial_controls': [name for name in rig.keys() if name.startswith(('Blink', 'Eyes', 'Brow'))],
    'grooms': [{'surface': obj.data.surface.name, 'guides': obj['guide_count'],
                'target_fibers': obj['target_fiber_count']} for obj in grooms],
    'mouth_fixed_closed': True, 'actions_authored': len(bpy.data.actions),
    'style_frame_approved': False, 'app_integration': False,
    'status': 'STYLE_FRAME_REVIEW_REQUIRED_BEFORE_ANIMATION',
    'reference_sha256': hashlib.sha256((OUT/'01_design/references/approved-front.png').read_bytes()).hexdigest()
}
(OUT/f'02_blender/rig-check-{args.revision}.json').write_text(json.dumps(report, indent=2)+'\n')
# Save a production-resolution master even when making a quick preview.
preview_resolution = scene.render.resolution_x
scene.render.resolution_x = scene.render.resolution_y = 1536
scene.cycles.samples = review_samples
bpy.ops.wm.save_as_mainfile(filepath=str(model_path))
scene.render.resolution_x = scene.render.resolution_y = preview_resolution
scene.cycles.samples = review_samples if args.look_review else (24 if args.preview else args.samples)
if not args.no_render:
    scene.render.filepath = str(OUT/(f'04_previews/style-{args.revision}-preview.png' if args.preview else f'05_render_masters/style-{args.revision}-front.png'))
    bpy.ops.render.render(write_still=True)
print('DUSK_PRODUCTION_RIG_SAVED', flush=True)
