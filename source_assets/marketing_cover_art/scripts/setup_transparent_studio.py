"""Apply the shared Fracture/Revolt studio rig without changing model geometry.

blender --background FILE.blend --python scripts/setup_transparent_studio.py -- --save --render
Omit --save for a temporary lighting preview; --draft renders a smaller preview.
"""
import bpy
import hashlib
import json
import re
import sys
from pathlib import Path
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
scene = bpy.context.scene
project = Path(bpy.data.filepath)
root = project.parent
variant = 'revolt' if 'revolt' in project.stem.lower() else 'fracture'
studio = bpy.data.collections['STUDIO']


def model_signature():
    signature = []
    for obj in bpy.data.collections['GAME CASE'].all_objects:
        signature.append((obj.name, tuple(tuple(row) for row in obj.matrix_world)))
        if obj.type == 'MESH':
            signature.append((tuple(tuple(v.co) for v in obj.data.vertices),
                              tuple(tuple(p.vertices) for p in obj.data.polygons),
                              tuple((uv.name, tuple(tuple(loop.uv) for loop in uv.data)) for uv in obj.data.uv_layers)))
    return hashlib.sha256(repr(signature).encode()).hexdigest()


geometry_before = model_signature()
artwork_before = {image.name: hashlib.sha256(image.packed_file.data).hexdigest()
                  for image in bpy.data.images if image.packed_file}


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


# Both projects use this exact perspective camera, including sensor and framing.
hero = bpy.data.objects['CAMERA • 01 Front three-quarter']
hero.location = (-.238, -.304, .218)
aim(hero, (0, 0, .086))
hero.data.type = 'PERSP'
hero.data.lens = 80
hero.data.sensor_width = 36
hero.data.sensor_fit = 'HORIZONTAL'
hero.data.shift_x = 0
hero.data.shift_y = 0
hero.data.clip_start = .001
hero.data.clip_end = 20
hero.data.dof.use_dof = False
hero['Composition'] = 'Shared 80 mm three-quarter product view; front, spine, and top edge visible.'
scene.camera = hero

# Remove only lights from the existing presentation collection, retaining cameras.
for obj in list(studio.all_objects):
    if obj.type == 'LIGHT':
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data.users == 0:
            bpy.data.lights.remove(data)


def softbox(name, position, target, power, width, height, color, specular=1, diffuse=1):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = power
    data.color = color
    data.shape = 'RECTANGLE'
    data.size = width
    data.size_y = height
    data.specular_factor = specular
    data.diffuse_factor = diffuse
    data.transmission_factor = 1
    obj = bpy.data.objects.new(name, data)
    studio.objects.link(obj)
    obj.location = position
    aim(obj, target)
    obj['Studio purpose'] = name.split(' • ', 1)[-1]
    return obj


softbox('LIGHT • 01 Large key softbox', (-.17, -.26, .32), (0, 0, .085),
        6.5, .21, .28, (1, .97, .94), specular=.30)
softbox('LIGHT • 02 Gentle artwork fill', (.23, -.20, .24), (0, 0, .085),
        3.3, .18, .22, (.94, .97, 1), specular=.12)
softbox('LIGHT • 03 Spine edge softbox', (-.21, .10, .23), (-.048, 0, .09),
        4.2, .055, .23, (.93, .97, 1), specular=.85)
softbox('LIGHT • 04 Top rim strip', (.02, .045, .33), (0, 0, .135),
        1.4, .18, .035, (1, .98, .95), specular=.65)
softbox('LIGHT • 05 Narrow sleeve reflection', (.360, -.31, .035), (.048, -.006, .10),
        .40, .012, .29, (1, 1, 1), specular=.45, diffuse=.35)
softbox('LIGHT • 06 Back fill softbox', (.10, .25, .23), (0, 0, .09),
        3.0, .16, .22, (1, .98, .96), specular=.18)

# Preserve clear plastic and its separate polished rim. Matte ink avoids a second
# broad highlight beneath the glossy sleeve.
for material in bpy.data.materials:
    if material.name.startswith('ART /'):
        shader = material.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Roughness'].default_value = .55
        shader.inputs['Specular IOR Level'].default_value = .20
        shader.inputs['Coat Weight'].default_value = 0
film = bpy.data.materials['CASE / glossy clear sleeve'].node_tree.nodes.get('Principled BSDF')
film.inputs['Roughness'].default_value = .085
film.inputs['Transmission Weight'].default_value = 1
film.inputs['IOR'].default_value = 1.46
film.inputs['Specular IOR Level'].default_value = .50
rim = bpy.data.materials['CASE / polished molded rim'].node_tree.nodes.get('Principled BSDF')
rim.inputs['Roughness'].default_value = .14

ground = bpy.data.objects.get('Studio • seamless floor')
if ground:
    ground.hide_render = True
    ground.hide_set(True)
    ground['Studio purpose'] = 'Disabled for a completely transparent product cutout.'

world = scene.world
world.name = 'Studio • neutral ambient fill'
background = world.node_tree.nodes.get('Background')
background.inputs['Color'].default_value = (.5, .52, .56, 1)
background.inputs['Strength'].default_value = .18

scene.render.engine = 'CYCLES'
scene.cycles.samples = 160
scene.cycles.preview_samples = 32
scene.cycles.use_denoising = True
scene.cycles.use_preview_denoising = True
scene.cycles.use_adaptive_sampling = True
scene.cycles.adaptive_threshold = .008
scene.cycles.max_bounces = 16
scene.cycles.transmission_bounces = 12
scene.cycles.transparent_max_bounces = 16
scene.cycles.film_transparent_glass = True
scene.cycles.film_transparent_roughness = .35
prefs = bpy.context.preferences.addons['cycles'].preferences
try:
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for device in prefs.devices:
        device.use = device.type == 'OPTIX'
    scene.cycles.device = 'GPU' if any(d.use for d in prefs.devices) else 'CPU'
except Exception:
    scene.cycles.device = 'CPU'

scene.render.resolution_x = 2400
scene.render.resolution_y = 2880
scene.render.resolution_percentage = 100
scene.render.pixel_aspect_x = 1
scene.render.pixel_aspect_y = 1
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.color_depth = '8'
scene.render.image_settings.compression = 25
(root / 'exports').mkdir(exist_ok=True)
scene.render.filepath = f'//exports/pokemon_{variant}_box_art_transparent.png'
scene.view_settings.view_transform = 'Khronos PBR Neutral'
scene.view_settings.look = 'None'
scene.view_settings.exposure = -1.25
scene.view_settings.gamma = 1

# Keep the editor responsive; final renders use the saved Cycles studio.
for obj in studio.all_objects:
    if obj.type == 'LIGHT' or obj == hero:
        obj.hide_set(False)
for obj in bpy.data.collections['04 • Clear outer sleeve'].objects:
    if obj.name.startswith('Sleeve • clear film'):
        obj.hide_set(False)
for screen in bpy.data.screens:
    for area in screen.areas:
        for editor in area.spaces:
            if editor.type == 'IMAGE_EDITOR':
                editor.display_channels = 'COLOR_ALPHA'
        if area.type == 'VIEW_3D':
            space = area.spaces.active
            space.shading.type = 'MATERIAL'
            space.shading.use_scene_lights = True
            space.shading.use_scene_world = True
            space.shading.use_scene_lights_render = True
            space.shading.use_scene_world_render = True
            space.overlay.show_extras = False
            space.overlay.show_floor = False
            space.overlay.show_axis_x = False
            space.overlay.show_axis_y = False
            space.overlay.show_relationship_lines = False
            space.overlay.show_outline_selected = False
            space.region_3d.view_perspective = 'CAMERA'
            space.region_3d.view_camera_zoom = 0
            space.region_3d.view_camera_offset = (0, 0)
scene['Studio'] = 'Matching six-light studio and 80 mm perspective camera in both versions; clean RGBA transparency.'
scene['Reflection control'] = 'Low-specular broad artwork illumination, separate narrow sleeve highlight, polished edge lights.'

studio_readme = bpy.data.texts.get('READ ME • Transparent studio') or bpy.data.texts.new('READ ME • Transparent studio')
studio_readme.clear()
studio_readme.write('''TRANSPARENT PRODUCT STUDIO

Fracture and Revolt share exactly the same six-light rig, 80 mm perspective
camera, framing, materials, exposure, and output settings. The default camera
shows the front, spine, and top edge. Both cover images retain their original
full-frame UV mapping and packed source pixels.

F12 renders a 2400 × 2880 PNG with 8-bit RGBA alpha into the exports folder.
The filename ends in _box_art_transparent.png. Film Transparent and
transparent glass are enabled; the old floor is disabled for rendering.
Cycles uses OptiX when available, 160 samples, and denoising.

The key and fill illuminate the artwork with reduced specular contributions.
A narrow strip adds a controlled sleeve reflection, with separate rim and
spine lights retaining the clear plastic's shine. All six lights are in STUDIO.

The viewport opens in the shared camera using responsive Material Preview.
The clear sleeve is visible in the viewport as well as in final renders.
F12 uses the saved Cycles studio rig. Render Result uses Color and Alpha to
display the transparent background as a checkerboard.

scripts/setup_transparent_studio.py applies this shared setup to either file.
Existing artwork, model geometry, and alternate cameras remain editable.
''')

artwork_readme = bpy.data.texts.get('READ ME • Case and artwork')
if artwork_readme:
    content = artwork_readme.as_string()
    presentation = '''PRESENTATION
The shared studio uses six softboxes, an 80 mm perspective camera, and a fully
transparent background. The previous floor is disabled. The viewport uses
Material Preview in the shared camera view. F12 renders a
2400 × 2880 PNG with alpha. See READ ME • Transparent studio for details.
'''
    if 'PRESENTATION\n' in content:
        content = re.sub(r'PRESENTATION\n.*?(?=\nThe back-cover|\Z)', presentation, content, flags=re.S)
    else:
        content = content.replace(
            'The clear outer sleeve is hidden only in the viewport and remains visible in\n'
            'renders. STUDIO cameras and lights are also hidden only in the viewport.\n',
            presentation)
    artwork_readme.clear()
    artwork_readme.write(content)

bpy.context.view_layer.update()
assert model_signature() == geometry_before, 'Model geometry or UVs changed'
assert artwork_before == {image.name: hashlib.sha256(image.packed_file.data).hexdigest()
                          for image in bpy.data.images if image.packed_file}, 'Packed artwork changed'
if '--save' in args:
    original_save_versions = bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(project))
    bpy.context.preferences.filepaths.save_version = original_save_versions

if '--draft' in args:
    scene.render.resolution_percentage = 50
    scene.cycles.samples = 40
    scene.cycles.adaptive_threshold = .025
    scene.render.filepath = f'/tmp/pokemon_{variant}_studio_draft.png'
if '--render' in args:
    bpy.ops.render.render(write_still=True)
    print('STUDIO_RENDER=' + scene.render.filepath, flush=True)

print('STUDIO_COMPLETE=' + json.dumps({'file': str(project), 'variant': variant,
      'saved': '--save' in args, 'geometry_preserved': True, 'artwork_preserved': True,
      'transparent': scene.render.film_transparent, 'camera': hero.name}), flush=True)
