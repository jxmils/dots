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
parser.add_argument('--samples', type=int, default=96)
parser.add_argument('--trial-blender-version', choices=['5.1.0'])
parser.add_argument('--revision', default='v001')
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
scene.cycles.samples = 24 if args.preview else args.samples
scene.cycles.use_denoising = True
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
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .22

def material(name, color, roughness=.75):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = roughness
    return mat

CHARCOAL = (.021, .020, .021)
PINK = (.88, .20, .29)
body_mat = material('MAT_CHARCOAL_PLUSH', CHARCOAL, .91)
body_shader = body_mat.node_tree.nodes['Principled BSDF']
body_shader.inputs['Specular IOR Level'].default_value = .12
body_shader.inputs['Sheen Weight'].default_value = .25
blush = body_mat.node_tree.nodes.new('ShaderNodeVertexColor')
blush.layer_name = 'CoatColor'
body_mat.node_tree.links.new(blush.outputs['Color'], body_shader.inputs['Base Color'])
lid_mat = material('MAT_CLOSE_LYING_EYELIDS', CHARCOAL, .94)
dark_mat = material('MAT_SOFT_BROWS', (.012, .010, .015), .8)
mouth_mat = material('MAT_CLOSED_SMILE', (.005, .002, .001), .45)
mouth_mat.node_tree.nodes['Principled BSDF'].inputs['Specular IOR Level'].default_value = .2
eye_mat = material('MAT_BROWN_GLASS', (.035, .010, .003), .11)
eye_shader = eye_mat.node_tree.nodes['Principled BSDF']
eye_shader.inputs['Specular IOR Level'].default_value = .35
eye_shader.inputs['Coat Weight'].default_value = .85
eye_shader.inputs['Coat Roughness'].default_value = .06
# Continuous shader-space shading, not a high-contrast painted iris ring or
# vertex-sampled pupil edge. The whole eye remains dark coffee-brown glass.
en, el = eye_mat.node_tree.nodes, eye_mat.node_tree.links
coordinates = en.new('ShaderNodeTexCoord')
separate = en.new('ShaderNodeSeparateXYZ')
el.new(coordinates.outputs['Generated'], separate.inputs[0])
def emath(operation, a, b=0):
    node = en.new('ShaderNodeMath')
    node.operation = operation
    for index, value in enumerate([a, b]):
        if isinstance(value, (int, float)):
            node.inputs[index].default_value = value
        else:
            el.new(value, node.inputs[index])
    return node.outputs[0]
def erange(value, low, high):
    node = en.new('ShaderNodeMapRange')
    node.clamp, node.interpolation_type = True, 'SMOOTHSTEP'
    node.inputs['From Min'].default_value = low
    node.inputs['From Max'].default_value = high
    el.new(value, node.inputs['Value'])
    return node.outputs[0]
def emix(a, b, factor):
    node = en.new('ShaderNodeMixRGB')
    el.new(factor, node.inputs[0])
    for index, value in [(1, a), (2, b)]:
        if isinstance(value, tuple):
            node.inputs[index].default_value = (*value, 1)
        else:
            el.new(value, node.inputs[index])
    return node.outputs[0]
ex = emath('MULTIPLY', emath('SUBTRACT', separate.outputs['X'], .5), 2)
ez = emath('MULTIPLY', emath('SUBTRACT', separate.outputs['Z'], .5), 2)
pz = emath('SUBTRACT', ez, .19)
radial = emath('SQRT', emath('ADD', emath('MULTIPLY', ex, ex), emath('MULTIPLY', ez, ez)))
pupil = emath('SQRT', emath('ADD', emath('MULTIPLY', ex, ex), emath('MULTIPLY', pz, pz)))
warmth = erange(emath('MULTIPLY', ez, -1), -.8, .75)
brown = emix((.010, .003, .0015), (.075, .024, .008), warmth)
soft_eye = emix((.005, .0018, .001), brown, erange(pupil, .25, .72))
eye_surface = emix(soft_eye, (.008, .0025, .0012), erange(radial, .85, 1.05))
el.new(eye_surface, eye_shader.inputs['Base Color'])
el.new(eye_surface, eye_shader.inputs['Emission Color'])
eye_shader.inputs['Emission Strength'].default_value = .035

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
    z = row/(ROWS-1)*1.30
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
for polygon, z, center_v in [(body.data.polygons[-2], 0, .045), (body.data.polygons[-1], 1.30, .955)]:
    r = radius(z)
    for loop in polygon.loop_indices:
        co = body.data.vertices[body.data.loops[loop].vertex_index].co
        uv.data[loop].uv = (.5+.04*co.x/r, center_v+.04*co.y/(.76*r))
body.data.update()

def front(x, z):
    r = radius(z)
    return -.76*r*math.sqrt(max(0, 1-(x/r)**2))

def blush_amount(point):
    x, y, z = point
    amount = max(math.exp(-((x-cx)/.165)**2-((z-.49)/.105)**2) for cx in [-.48, .48])
    return amount*max(0, min(1, (-y-.25)/.16))*.86

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
    obj = sphere('ARM_'+label, (side*.87, .01, .50), (.125, .14, .215), body_mat, -side*.83)
    add_coat(obj)
    arms.append(obj)
for index, location, scale, angle in [
    (1, (-.19, .015, 1.25), (.125, .110, .140), -.65),
    (2, (-.060, .005, 1.390), (.130, .105, .205), -.40),
    (3, (.135, .010, 1.330), (.115, .105, .175), .42)]:
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

def tube(name, points, thickness, mat):
    curve = bpy.data.curves.new(name+'_CURVE', 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth, curve.bevel_resolution, curve.resolution_u = thickness, 5, 16
    curve.use_fill_caps = True
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points)-1)
    for point, co in zip(spline.bezier_points, points):
        point.co = co
        point.handle_left_type = point.handle_right_type = 'AUTO'
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
    x, z = side*.365, .695
    y = front(x, z)
    rx, ry, rz = .155, .060, .164
    eye = sphere('EYE_'+label, (x, y, z), (rx, ry, rz), eye_mat)
    attribute = eye.data.color_attributes.new(name='EyeColor', type='FLOAT_COLOR', domain='POINT')
    for vertex, color in zip(eye.data.vertices, attribute.data):
        dx, dz = (vertex.co.x-x)/rx, (vertex.co.z-z)/rz
        radial = math.sqrt(dx*dx+dz*dz)
        pupil_radius = math.sqrt(dx*dx+(dz-.17)**2)
        iris = max(0, min(1, (pupil_radius-.53)/.15))
        rim = max(0, min(1, (radial-.80)/.20))
        streak = .92+.08*math.sin(math.atan2(dz, dx)*71+radial*13)
        brown = (.150*streak, .039*streak, .007*streak)
        pupil, edge = (.0015, .0008, .0005), (.011, .004, .002)
        color.color = (*( (pupil[i]*(1-iris)+brown[i]*iris)*(1-rim)+edge[i]*rim for i in range(3)), 1)
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
                    inner = boundary*(1-closure)+seam*closure
                    zz = boundary*(1-t)+inner*t
                    yy = y-ry*math.sqrt(max(0, 1-u*u-(zz/rz)**2))-.006
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
        bz = .965+.017*math.sin(math.pi*t)-side*(t-.5)*.028
        points.append((bx, front(bx, bz)-.012, bz))
    brow = tube('EYEBROW_'+label, points, .022, dark_mat)
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
    z = .550-.045*(1-(2*t-1)**2)
    smile_points.append((x, front(x, z)-.020, z))
smile = tube('MOUTH_FIXED_CLOSED_SMILE', smile_points, .013, mouth_mat)
bind(smile)

# Hair Curves use a retained, deterministic guide groom and native interpolation.
# Deform Curves on Surface makes the groom follow the armature-deformed mesh.
hair_mat = bpy.data.materials.new('MAT_SHORT_CHARCOAL_FIBERS')
hair_mat.use_nodes = True
nodes, links = hair_mat.node_tree.nodes, hair_mat.node_tree.links
nodes.clear()
output = nodes.new('ShaderNodeOutputMaterial')
fiber = nodes.new('ShaderNodeBsdfHairPrincipled')
fiber.parametrization = 'COLOR'
fiber.inputs['Roughness'].default_value = .70
fiber.inputs['Radial Roughness'].default_value = .70
fiber.inputs['Color'].default_value = (*CHARCOAL, 1)
attr = nodes.new('ShaderNodeAttribute')
attr.attribute_name = 'FurColor'
links.new(attr.outputs['Color'], fiber.inputs['Color'])
links.new(fiber.outputs[0], output.inputs['Surface'])

def make_groom(surface, guide_count, fiber_count, seed):
    rng = random.Random(seed)
    surface.data.calc_loop_triangles()
    triangles = list(surface.data.loop_triangles)
    choices = rng.choices(triangles, weights=[tri.area for tri in triangles], k=guide_count)
    positions, uv_values, radii, colors, normals = array('f'), array('f'), array('f'), array('f'), array('f')
    uv_layer = surface.data.uv_layers.active
    for tri in choices:
        a, b, c = [surface.data.vertices[i] for i in tri.vertices]
        u, v = math.sqrt(rng.random()), rng.random()
        weights = (1-u, u*(1-v), u*v)
        point = a.co*weights[0]+b.co*weights[1]+c.co*weights[2]
        normal = (a.normal*weights[0]+b.normal*weights[1]+c.normal*weights[2]).normalized()
        normals.extend(normal)
        root_uv = sum((uv_layer.data[loop].uv*weight for loop, weight in zip(tri.loops, weights)), Vector((0, 0)))
        uv_values.extend(root_uv)
        variation = noise.noise_vector(point*17, noise_basis='PERLIN_ORIGINAL')
        flow = variation+Vector((0, 0, -.12))
        tangent = flow-normal*flow.dot(normal)
        if tangent.length < .01:
            tangent = normal.cross(Vector((1, 0, 0)))
        tangent.normalize()
        length = rng.uniform(.016, .024)
        across = normal.cross(tangent).normalized()
        for index in range(7):
            t = index/6
            curl = across*length*.22*math.sin(t*math.pi)
            positions.extend(point+normal*length*.45*t+tangent*length*.78*t+curl)
            radii.append(.00060*(1-.97*t))
            colors.extend((*coat_color(point), 1))
    data = bpy.data.hair_curves.new('GUIDES_'+surface.name)
    data.add_curves([7]*guide_count)
    data.attributes['position'].data.foreach_set('vector', positions)
    data.attributes.new('radius', 'FLOAT', 'POINT').data.foreach_set('value', radii)
    data.attributes.new('surface_uv_coordinate', 'FLOAT2', 'CURVE').data.foreach_set('vector', uv_values)
    data.attributes.new('FurColor', 'FLOAT_COLOR', 'POINT').data.foreach_set('color', colors)
    data.attributes.new('GuideNormal', 'FLOAT_VECTOR', 'CURVE').data.foreach_set('vector', normals)
    data.surface, data.surface_uv_map = surface, uv_layer.name
    data.materials.append(hair_mat)
    obj = bpy.data.objects.new('FUR_GROOM_'+surface.name, data)
    scene.collection.objects.link(obj)
    obj.parent = rig
    rest = bpy.data.objects.new('REST_SURFACE_'+surface.name, surface.data.copy())
    scene.collection.objects.link(rest)
    rest.hide_render = True
    rest.hide_set(True)
    group = bpy.data.node_groups.new('GROOM_'+surface.name, 'GeometryNodeTree')
    group.interface.new_socket(name='Geometry', in_out='INPUT', socket_type='NodeSocketGeometry')
    group.interface.new_socket(name='Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
    n, l = group.nodes, group.links
    source, target = n.new('NodeGroupInput'), n.new('NodeGroupOutput')
    info = n.new('GeometryNodeObjectInfo')
    info.inputs['Object'].default_value = rest
    distribute = n.new('GeometryNodeDistributePointsOnFaces')
    distribute.distribute_method = 'RANDOM'
    area = sum(tri.area for tri in triangles)
    distribute.inputs['Density'].default_value = fiber_count/area
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
    interpolate.inputs['Max Neighbors'].default_value = 4
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
    return obj

grooms = [make_groom(body, 6500, 165000, 7319)]
for index, obj in enumerate(arms+tufts):
    grooms.append(make_groom(obj, 1100, 18000 if obj in arms else 14000, 7320+index))

body_receivers = bpy.data.collections.new('STUDIO_LIGHT_RECEIVERS')
eye_receivers = bpy.data.collections.new('EYE_LIGHT_RECEIVERS')
for obj in list(scene.objects):
    if obj.type in {'MESH', 'CURVE', 'CURVES'} and not obj.name.startswith('REST_'):
        (eye_receivers if obj.name.startswith('EYE_') else body_receivers).objects.link(obj)

def light(name, location, energy, size, specular=0, diffuse=1, eyes=False):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size = energy, 'DISK', size
    data.specular_factor, data.diffuse_factor = specular, diffuse
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.light_linking.receiver_collection = eye_receivers if eyes else body_receivers
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, .8))-obj.location).to_track_quat('-Z', 'Y').to_euler()
    return obj

light('KEY_SOFT', (-1.5, -4, 3), 300, 5.0)
light('FILL_SOFT', (2, -3, 1.5), 180, 4.0)
light('RIM_SOFT', (1, 2.5, 3), 70, 4.0)
light('EYE_CATCHLIGHT', (2.0, -4.0, 3.8), 1000, 2.5, specular=1, diffuse=1, eyes=True)
light('EYE_SOFT_REFLECTION', (-2, -3, .6), 12, 2.0, specular=1, diffuse=.1, eyes=True)
camera_data = bpy.data.cameras.new('CAMERA_LOCKED_90MM')
camera = bpy.data.objects.new('CAMERA_LOCKED_90MM', camera_data)
scene.collection.objects.link(camera)
camera.location = (0, -7.5, 1.05)
camera.rotation_euler = (Vector((0, 0, .78))-camera.location).to_track_quat('-Z', 'Y').to_euler()
camera_data.type, camera_data.lens = 'PERSP', 90
scene.camera = camera
scene.frame_start = 1
scene.frame_end = 60
scene.frame_set(1)
bpy.context.view_layer.update()

# Structural and attachment checks are retained separately from visual approval.
report = {
    'blender': bpy.app.version_string, 'actual_3d_geometry': True,
    'reference_images_used_as_materials': False, 'render_engine': scene.render.engine,
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
scene.cycles.samples = args.samples
bpy.ops.wm.save_as_mainfile(filepath=str(model_path))
scene.render.resolution_x = scene.render.resolution_y = preview_resolution
scene.cycles.samples = 24 if args.preview else args.samples
if not args.no_render:
    scene.render.filepath = str(OUT/(f'04_previews/style-{args.revision}-preview.png' if args.preview else f'05_render_masters/style-{args.revision}-front.png'))
    bpy.ops.render.render(write_still=True)
print('DUSK_PRODUCTION_RIG_SAVED', flush=True)
