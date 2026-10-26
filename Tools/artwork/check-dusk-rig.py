"""Verify the open Dusk .blend structurally and under deterministic rig poses.

Run Blender -b <master.blend> --python-exit-code 1 --python this-file.
This is geometry qualification, not visual acceptance or an iPhone playback test.
"""
from pathlib import Path
from array import array
import json
import math
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

root = Path(__file__).resolve().parents[2]
rig = bpy.data.objects['DUSK_RIG']
grooms = [obj for obj in bpy.data.objects if obj.type == 'CURVES']
assert rig.type == 'ARMATURE' and len(rig.data.bones) == 8
assert not bpy.data.actions, 'Style review must precede authored animation Actions'
texture_nodes = [node for mat in bpy.data.materials if mat.use_nodes for node in mat.node_tree.nodes if node.type == 'TEX_IMAGE']
for node in texture_nodes:
    assert node.name == 'SHORT_FUR_MATERIAL_ONLY'
    assert node.image.name in {'charcoal-short-fur-v001.png', 'charcoal-short-fur-v002.png'}
    assert node.image.packed_file, 'Material texture must travel with the editable master'
    import hashlib
    expected = json.loads((root/'Art/Dusk/Production/03_textures'/Path(node.image.name).with_suffix('.json')).read_text())['sha256']
    assert hashlib.sha256(node.image.packed_file.data).hexdigest() == expected
for name in ['BODY', 'ARM_L', 'ARM_R', 'TUFT_01', 'TUFT_02', 'TUFT_03',
             'EYE_L', 'EYE_R', 'EYELID_L', 'EYELID_R', 'EYEBROW_L', 'EYEBROW_R', 'MOUTH_FIXED_CLOSED_SMILE']:
    obj = bpy.data.objects[name]
    assert all(abs(value-1) < 1e-6 for value in obj.scale), name
    assert any(mod.type == 'ARMATURE' and mod.object == rig for mod in obj.modifiers), name
    assert obj.type == 'MESH', name
for label in ['L', 'R']:
    assert 'Blink_'+label in bpy.data.objects['EYELID_'+label].data.shape_keys.key_blocks
body = bpy.data.objects['BODY']
bm = bmesh.new()
bm.from_mesh(body.data)
assert all(edge.is_manifold for edge in bm.edges)
volume = bm.calc_volume(signed=False)
assert volume > .1
bm.free()

def points(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    return [vertex.co.copy() for vertex in obj.evaluated_get(dg).data.vertices]

def update():
    rig.update_tag()
    bpy.context.view_layer.update()

rest_lid = points(bpy.data.objects['EYELID_L'])
rest_mouth = points(bpy.data.objects['MOUTH_FIXED_CLOSED_SMILE'])
for control, object_name, minimum in [('Blink_L', 'EYELID_L', .15), ('Blink_R', 'EYELID_R', .15),
        ('Blink_Both', 'EYELID_L', .15), ('Eyes_Sleepy', 'EYELID_L', .07),
        ('Eyes_Happy', 'EYELID_L', .03), ('Brow_Worried', 'EYEBROW_L', .01),
        ('Brow_Angry', 'EYEBROW_R', .01)]:
    obj = bpy.data.objects[object_name]
    neutral = points(obj)
    rig[control] = 1.0
    update()
    assert max((a-b).length for a, b in zip(neutral, points(obj))) > minimum, control
    assert max((a-b).length for a, b in zip(rest_mouth, points(bpy.data.objects['MOUTH_FIXED_CLOSED_SMILE']))) < 1e-5
    rig[control] = 0.0
    update()
    assert max((a-b).length for a, b in zip(neutral, points(obj))) < 1e-5, control

highlight_occlusion = {}
for label in ['L', 'R']:
    highlight = bpy.data.objects.get('EYE_HIGHLIGHT_'+label)
    if highlight is None:
        continue
    centre = sum((v.co for v in highlight.data.vertices), Vector())/len(highlight.data.vertices)
    direction = (centre-bpy.context.scene.camera.location).normalized()
    def camera_hit():
        hit = bpy.context.scene.ray_cast(bpy.context.evaluated_depsgraph_get(), bpy.context.scene.camera.location, direction)
        return hit[4].name if hit[0] else None
    assert camera_hit() == highlight.name, ('Neutral highlight is hidden', label, camera_hit())
    rig['Blink_Both'] = 1
    update()
    hit = camera_hit()
    assert hit == 'EYELID_'+label, ('Closed eye does not cover the highlight', label, hit)
    highlight_occlusion[label] = {'neutral': highlight.name, 'closed': hit}
    rig['Blink_Both'] = 0
    update()

def attachment():
    dg = bpy.context.evaluated_depsgraph_get()
    maximum_error, counts, mean_lengths = 0, {}, {}
    for groom in grooms:
        groom_error = 0
        data = groom.evaluated_get(dg).data
        counts[groom.name] = len(data.curves)
        assert counts[groom.name] > groom['guide_count']*2
        assert .95*groom['target_fiber_count'] < counts[groom.name] < 1.05*groom['target_fiber_count']
        assert data.attributes['surface_uv_coordinate'].domain == 'CURVE'
        expected_material = 'MAT_CHARCOAL_FIBERS_'+groom['groom_layer'] if 'groom_layer' in groom else 'MAT_SHORT_CHARCOAL_FIBERS'
        assert data.materials and data.materials[0].name == expected_material
        raw = array('f', [0.0])*(len(data.points)*3)
        data.attributes['position'].data.foreach_get('vector', raw)
        surface = groom.data.surface.evaluated_get(dg).data
        bvh = BVHTree.FromPolygons([v.co for v in surface.vertices], [list(p.vertices) for p in surface.polygons])
        lengths = []
        shading_normals = data.attributes.get('FurSurfaceNormal')
        for index in range(0, len(data.curves), max(1, len(data.curves)//160)):
            curve = data.curves[index]
            start = curve.first_point_index
            end = start+curve.points_length-1
            first = Vector(raw[start*3:start*3+3])
            last = Vector(raw[end*3:end*3+3])
            error = bvh.find_nearest(first)[3]
            if shading_normals is not None:
                shading_normal = shading_normals.data[start].vector
                assert .90 < shading_normal.length < 1.10, (groom.name, 'invalid shading normal')
                nearest_normal = bvh.find_nearest(first)[1]
                assert shading_normal.normalized().dot(nearest_normal) > .80, (groom.name, 'shading normal detached from posed surface')
            maximum_error = max(maximum_error, error)
            groom_error = max(groom_error, error)
            lengths.append((last-first).length)
        mean_lengths[groom.name] = sum(lengths)/len(lengths)
        assert .008 < mean_lengths[groom.name] < .06, mean_lengths
        print('ATTACHMENT', groom.name, groom_error, flush=True)
    assert maximum_error < .006, maximum_error
    return {'max_sampled_root_distance': maximum_error, 'evaluated_fiber_counts': counts,
            'mean_sampled_strand_lengths': mean_lengths}

checks = {'neutral': attachment()}
rest_body = points(body)
for degrees in [-25, 25]:
    rig.pose.bones['CTRL_BODY_TURN'].rotation_mode = 'XYZ'
    rig.pose.bones['CTRL_BODY_TURN'].rotation_euler.y = math.radians(degrees)
    update()
    checks['turn_'+str(degrees)] = attachment()
    assert max((a-b).length for a, b in zip(rest_body, points(body))) > .2
rig.pose.bones['CTRL_BODY_TURN'].rotation_euler.y = 0
rig.pose.bones['CTRL_BODY_SQUASH'].scale = (1.06, .94, 1.06)
update()
checks['small_squash'] = attachment()
rig.pose.bones['CTRL_BODY_SQUASH'].scale = (1, 1, 1)
rig.pose.bones['CTRL_ROOT'].location.z = .25
update()
checks['root_translation'] = attachment()
rig.pose.bones['CTRL_ROOT'].location.z = 0
update()
for name, angle in [('CTRL_ARM_L', .20), ('CTRL_ARM_R', -.20), ('CTRL_TUFTS', .08), ('CTRL_BODY_TOP', .04)]:
    bone = rig.pose.bones[name]
    bone.rotation_mode = 'XYZ'
    bone.rotation_euler.z = angle
    update()
    checks[name] = attachment()
    bone.rotation_euler.z = 0
    update()
assert max((a-b).length for a, b in zip(rest_body, points(body))) < 1e-5
out = Path(bpy.data.filepath).with_suffix('.checks.json')
out.write_text(json.dumps({'blender': bpy.app.version_string, 'status': 'PASS_STRUCTURAL_AND_SAMPLED_ATTACHMENT_CHECKS',
                           'mouth_fixed': True, 'body_closed': True, 'body_volume': volume,
                           'style_approved': False, 'animation_actions': 0,
                           'authored_highlight_occlusion': highlight_occlusion, 'poses': checks}, indent=2)+'\n')
print('DUSK_RIG_CHECKS_PASSED', out, flush=True)
