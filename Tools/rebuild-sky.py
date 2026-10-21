"""Rebuild Sky's approved neutral model from the checked-in surface and texture.

Run with Blender through Tools/rebuild-sky.sh. This never generates new artwork
or overwrites the approved source model or preview.
"""
import argparse
from array import array
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Matrix
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'Art/Sky'


def digest(path):
    checksum = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def apply_settings(target, settings):
    for name, value in settings.items():
        setattr(target, name, value)


def coat_material(recipe):
    material = bpy.data.materials.new('Original Sky coat - front reference')
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    links = material.node_tree.links
    output = nodes.new('ShaderNodeOutputMaterial')
    image = bpy.data.images.load(str(SOURCE / recipe['file']))
    image.colorspace_settings.name = recipe['color_space']
    image.alpha_mode = recipe['alpha_mode']
    image.pack()
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = image
    texture.interpolation = recipe['interpolation']
    texture.extension = recipe['extension']
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'ReferenceProjection'
    links.new(uv.outputs['UV'], texture.inputs['Vector'])
    emission = nodes.new('ShaderNodeEmission')
    emission.inputs['Strength'].default_value = recipe['emission_strength']
    links.new(texture.outputs['Color'], emission.inputs['Color'])
    transparent = nodes.new('ShaderNodeBsdfTransparent')
    opacity = nodes.new('ShaderNodeMapRange')
    opacity.inputs['From Min'].default_value = recipe['alpha_min']
    opacity.inputs['From Max'].default_value = recipe['alpha_max']
    opacity.clamp = True
    links.new(texture.outputs['Alpha'], opacity.inputs['Value'])
    separate = nodes.new('ShaderNodeSeparateXYZ')
    links.new(uv.outputs['UV'], separate.inputs[0])
    max_x = nodes.new('ShaderNodeMath')
    max_x.operation = 'LESS_THAN'
    max_x.inputs[1].default_value = recipe['max_u']
    links.new(separate.outputs['X'], max_x.inputs[0])
    min_y = nodes.new('ShaderNodeMath')
    min_y.operation = 'GREATER_THAN'
    min_y.inputs[1].default_value = recipe['min_v']
    links.new(separate.outputs['Y'], min_y.inputs[0])
    alpha = opacity.outputs[0]
    for factor in (max_x.outputs[0], min_y.outputs[0]):
        multiply = nodes.new('ShaderNodeMath')
        multiply.operation = 'MULTIPLY'
        links.new(alpha, multiply.inputs[0])
        links.new(factor, multiply.inputs[1])
        alpha = multiply.outputs[0]
    mix = nodes.new('ShaderNodeMixShader')
    links.new(alpha, mix.inputs[0])
    links.new(transparent.outputs[0], mix.inputs[1])
    links.new(emission.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], output.inputs['Surface'])
    return material


def build_surface(recipe):
    geometry = recipe['geometry']
    depth = np.asarray(json.loads((SOURCE / 'depth.json').read_text()), dtype=np.float32)
    grid = geometry['grid']
    assert depth.shape == (grid, grid) and np.isfinite(depth).all()
    extent = geometry['image_extent']
    scale = geometry['units_per_pixel']
    vertices = []
    for i in range(grid):
        z = (geometry['bottom_y'] - i / (grid - 1) * extent) * scale + geometry['z_offset']
        for j in range(grid):
            x = (j / (grid - 1) * extent - geometry['center_x']) * scale
            vertices.append((x, float(depth[i, j]), z))
    faces = []
    for i in range(grid - 1):
        for j in range(grid - 1):
            a = i * grid + j
            faces.append((a, a + 1, a + grid + 1, a + grid))
    data = bpy.data.meshes.new('Sky reference relief')
    data.from_pydata(vertices, [], faces)
    data.update()
    surface = bpy.data.objects.new('SkyReferenceSurface', data)
    bpy.context.collection.objects.link(surface)
    surface.matrix_world = Matrix(geometry['surface_matrix'])
    for face in data.polygons:
        face.use_smooth = True
    uv = data.uv_layers.new(name='ReferenceProjection')
    indices = np.empty(len(data.loops), dtype=np.int32)
    data.loops.foreach_get('vertex_index', indices)
    points = np.asarray(vertices, dtype=np.float32)[indices]
    coordinates = np.empty((len(indices), 2), dtype=np.float32)
    width, height = recipe['texture']['dimensions']
    coordinates[:, 0] = (points[:, 0] / scale + geometry['center_x']) / width
    coordinates[:, 1] = 1 - (geometry['bottom_y'] - (points[:, 2] - geometry['z_offset']) / scale) / height
    uv.data.foreach_set('uv', coordinates.reshape(-1))
    data.materials.append(coat_material(recipe['texture']))
    return surface


def pixels(path):
    image = bpy.data.images.load(str(path), check_existing=False)
    image.colorspace_settings.name = 'Non-Color'
    values = array('f', [0]) * (image.size[0] * image.size[1] * 4)
    image.pixels.foreach_get(values)
    return np.asarray(values).reshape(image.size[1], image.size[0], 4)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT / 'build/sky-model')
    parser.add_argument('--check', action='store_true', help='Compare with the approved neutral preview')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    recipe = json.loads((SOURCE / 'look.json').read_text())
    if args.check and list(bpy.app.version) != recipe['blender_version']:
        raise RuntimeError('The approved render check requires Blender ' + '.'.join(map(str, recipe['blender_version'])))
    for name, expected in recipe['files'].items():
        if digest(SOURCE / name) != expected['sha256']:
            raise RuntimeError('Approved Sky source changed: ' + name)
    output = args.output.resolve()
    if output == SOURCE.resolve() or SOURCE.resolve() in output.parents:
        raise RuntimeError('Build into a separate output directory; approved source files are protected.')
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    apply_settings(scene.render, recipe['render'])
    apply_settings(scene.cycles, recipe['cycles'])
    scene.cycles.device = 'CPU'
    apply_settings(scene.view_settings, recipe['view'])
    apply_settings(scene.display_settings, recipe['display'])
    apply_settings(scene.render.image_settings, recipe['output'])
    scene.world = bpy.data.worlds.new('Sky studio')
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get('Background')
    background.inputs['Color'].default_value = recipe['world']['color']
    background.inputs['Strength'].default_value = recipe['world']['strength']
    surface = build_surface(recipe)
    camera_data = bpy.data.cameras.new('Sky camera')
    camera = bpy.data.objects.new('Sky camera', camera_data)
    bpy.context.collection.objects.link(camera)
    apply_settings(camera_data, {k: v for k, v in recipe['camera'].items() if k != 'matrix'})
    camera.matrix_world = Matrix(recipe['camera']['matrix'])
    scene.camera = camera
    scene['sky_look_recipe'] = 'Art/Sky/look.json'
    scene['sky_look_scope'] = 'Approved neutral front view; face rig and app integration are separate work.'
    scene.render.filepath = str(output / 'Sky.png')
    bpy.ops.wm.save_as_mainfile(filepath=str(output / 'Sky.blend'))
    bpy.ops.render.render(write_still=True)
    report = {
        'blender_version': bpy.app.version_string,
        'source_hashes_verified': True,
        'packed_texture': bool(surface.data.materials[0].node_tree.nodes.get('Image Texture').image.packed_file),
        'vertices': len(surface.data.vertices),
        'faces': len(surface.data.polygons),
        'model': 'Sky.blend', 'preview': 'Sky.png',
        'scope': 'Approved neutral front view only; not a facial animation or native-app check.',
    }
    if args.check:
        actual = pixels(output / 'Sky.png')
        expected = pixels(SOURCE / 'approved-neutral.png')
        assert actual.shape == expected.shape, 'Approved render dimensions changed'
        # RGB under zero alpha is invisible and may differ between render
        # sessions. Compare the visible color and transparency independently.
        actual = np.rint(actual * 255) / 255
        expected = np.rint(expected * 255) / 255
        difference = np.abs(actual[:, :, :3] * actual[:, :, 3:]
                            - expected[:, :, :3] * expected[:, :, 3:]) * 255
        alpha_difference = np.abs(actual[:, :, 3] - expected[:, :, 3]) * 255
        report['comparison'] = {
            'metric': 'Premultiplied visible color and alpha; invisible RGB excluded',
            'max_visible_color_difference_255': float(difference.max()),
            'mean_visible_color_difference_255': float(difference.mean()),
            'max_alpha_difference_255': float(alpha_difference.max()),
            'passed': bool(difference.max() <= 2 and alpha_difference.max() <= 1.001
                           and difference.mean() <= .25),
        }
    (output / 'look-check.json').write_text(json.dumps(report, indent=2) + '\n')
    if args.check and not report['comparison']['passed']:
        raise RuntimeError('The rebuild differs from the approved look. See ' + str(output / 'look-check.json'))
    print('SKY_REBUILT ' + json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
