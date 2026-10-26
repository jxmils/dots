"""Actual 3D reflection-card placement test, without editing the saved master."""
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
master = ROOT/'Art/Dusk/Production/02_blender/dusk_rig_v011.blend'
out = ROOT/'Art/Dusk/Production/04_previews/reviews/round-03'
out.mkdir(parents=True, exist_ok=True)
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
bpy.data.objects['EYE_CATCHLIGHT'].hide_render = True
for label in ['L', 'R']:
    eye = bpy.data.objects['EYE_'+label]
    cx = (-1 if label == 'L' else 1)*.365
    cz = .695*.92
    # Select a true mesh point in the upper-right quadrant, not an image pixel.
    vertices = [v for v in eye.data.vertices if v.normal.y < 0]
    vertex = min(vertices, key=lambda v: (v.co.x-(cx+.150*.30))**2+(v.co.z-(cz+.160*.48))**2)
    p, normal = vertex.co.copy(), vertex.normal.normalized()
    view = (scene.camera.location-p).normalized()
    reflected = (normal*(2*normal.dot(view))-view).normalized()
    data = bpy.data.lights.new('EYE_CARD_'+label, 'AREA')
    data.shape, data.size, data.energy = 'DISK', .35, 220
    data.diffuse_factor, data.specular_factor = 0, 1
    light = bpy.data.objects.new(data.name, data)
    scene.collection.objects.link(light)
    light.location = p+reflected*3.5
    light.rotation_euler = (p-light.location).to_track_quat('-Z', 'Y').to_euler()
    receivers = bpy.data.collections.new('EYE_CARD_RECEIVERS_'+label)
    receivers.objects.link(eye)
    light.light_linking.receiver_collection = receivers
    print('CARD', label, 'normal', tuple(normal), 'location', tuple(light.location), flush=True)
scene.render.filepath = str(out/'independent-3d-reflection-cards.png')
bpy.ops.render.render(write_still=True)
