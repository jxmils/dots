"""Projection-length tests for the visible pile of the layered v011 groom."""
from pathlib import Path
from array import array
import bpy
import random
import math
from mathutils import Vector, noise

ROOT = Path(__file__).resolve().parents[2]
master = ROOT/'Art/Dusk/Production/02_blender/dusk_rig_v011.blend'
out = ROOT/'Art/Dusk/Production/04_previews/reviews/round-03'
out.mkdir(parents=True, exist_ok=True)
for mode, tangent_amount in [('pile-readable-width', .70)]:
    bpy.ops.wm.open_mainfile(filepath=str(master))
    scene = bpy.context.scene
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'
    prefs.get_devices()
    for device in prefs.devices:
        device.use = device.type == 'METAL'
    scene.cycles.device = 'GPU'
    scene.cycles.samples = 128
    scene.cycles.use_denoising = False
    scene.render.resolution_x = scene.render.resolution_y = 1024
    for obj in bpy.data.objects:
        if obj.type != 'CURVES' or obj.get('groom_layer') != 'pile':
            continue
        data = obj.data
        if mode == 'pile-readable-width':
            widths = array('f', [0])*len(data.points)
            data.attributes['radius'].data.foreach_get('value', widths)
            for curve in range(obj['guide_count']):
                root_width = widths[curve*7]*2.8
                for point in range(7):
                    t = point/6
                    widths[curve*7+point] = root_width*(1-.85*t**2)
            data.attributes['radius'].data.foreach_set('value', widths)
        raw = array('f', [0])*(len(data.points)*3)
        data.attributes['position'].data.foreach_get('vector', raw)
        rng = random.Random(obj['fixed_seed'])
        normals = data.attributes['GuideNormal'].data
        for index in range(obj['guide_count']):
            start = index*21
            root = Vector(raw[start:start+3])
            tip = Vector(raw[start+18:start+21])
            length = (tip-root).length
            normal = normals[index].vector.normalized()
            macro = noise.noise_vector(root*7, noise_basis='PERLIN_ORIGINAL')
            micro = noise.noise_vector(root*43+Vector((obj['fixed_seed']*.01, 0, 0)), noise_basis='PERLIN_ORIGINAL')
            flow = macro*.65+micro*.35
            tangent = flow-normal*flow.dot(normal)
            if tangent.length < .01:
                tangent = normal.cross(Vector((1, 0, 0)))
            tangent.normalize()
            across = normal.cross(tangent).normalized()
            direction = (normal*.86+tangent*tangent_amount).normalized()
            bend = rng.uniform(.10, .22)*rng.choice([-1, 1])
            phase = rng.uniform(-math.pi, math.pi)
            for point in range(7):
                t = point/6
                curl = across*length*bend*math.sin(math.pi*t)*math.cos(phase+t)
                co = root+direction*length*t+curl
                raw[start+point*3:start+point*3+3] = array('f', co)
        data.attributes['position'].data.foreach_set('vector', raw)
    scene.render.filepath = str(out/f'{mode}.png')
    bpy.ops.render.render(write_still=True)
