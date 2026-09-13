"""Build the editable Switch-style cover-art case in the current Blender file.

Run in Blender's Python Console with exec(compile(open(path).read(), path, 'exec')).
Only the generated collections and an untouched default startup trio are replaced.
All dimensions below are millimeters; Blender geometry is stored in meters.
"""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
MM = 0.001
W, H, D = 105.0, 170.0, 11.0
scene = bpy.context.scene


def remove_collection(collection):
    for child in list(collection.children):
        remove_collection(child)
    for obj in list(collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(collection)


for name in ("GAME CASE", "STUDIO"):
    if name in bpy.data.collections:
        remove_collection(bpy.data.collections[name])
if set(o.name for o in scene.objects) == {"Cube", "Camera", "Light"}:
    cube = bpy.data.objects["Cube"]
    if tuple(round(v, 5) for v in cube.dimensions) == (2.0, 2.0, 2.0):
        for obj in list(scene.objects):
            bpy.data.objects.remove(obj, do_unlink=True)


def collection(name, parent=None):
    result = bpy.data.collections.new(name)
    (parent.children if parent else scene.collection.children).link(result)
    return result


model = collection("GAME CASE")
shells = collection("01 • Molded clear shell", model)
inserts = collection("02 • Replaceable cover artwork", model)
details = collection("03 • Hinge, seam and latches", model)
films = collection("04 • Clear outer sleeve", model)
studio = collection("STUDIO")
root = bpy.data.objects.new("CASE • move and rotate the whole model", None)
model.objects.link(root)
root.empty_display_type = 'PLAIN_AXES'
root.empty_display_size = .018
root["Dimensions (mm)"] = "105 × 170 × 11 (approximate Switch-style proportions)"
root["Artwork"] = "Edit cover_art SVGs, export matching PNGs, then reload the three artwork images."
root["Construction"] = "Separate front and rear trays, opening seam, hinge, latches and clear sleeve. Closed display case."


def material(name, color, roughness=.3, transmission=0.0, ior=1.47):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['IOR'].default_value = ior
    bsdf.inputs['Transmission Weight'].default_value = transmission
    bsdf.inputs['Coat Weight'].default_value = 0.0 if transmission else .05
    bsdf.inputs['Coat Roughness'].default_value = .14
    if transmission:
        mat.use_raytrace_refraction = True
        mat.thickness_mode = 'SLAB'
        mat.node_tree.nodes.get('Material Output').inputs['Thickness'].default_value = .0006
    return mat


plastic = material("CASE / translucent injection-molded plastic", (.79, .825, .84), .19, .96)
polished = material("CASE / polished molded rim", (.9, .93, .94), .115, 1.0)
frosted = material("CASE / frosted internal tabs", (.66, .70, .72), .29, .42)
film = material("CASE / glossy clear sleeve", (.995, .995, .995), .075, 1.0, 1.46)
film.node_tree.nodes.get('Material Output').inputs['Thickness'].default_value = .000045
paper = material("CASE / paper edges", (.94, .935, .915), .53)
seam_mat = material("CASE / recessed seam", (.29, .32, .33), .4, .22)


def artwork(name, filename):
    mat = material(name, (.95, .95, .94), .43)
    nodes = mat.node_tree.nodes
    for node in list(nodes):
        if node.type not in {'BSDF_PRINCIPLED', 'OUTPUT_MATERIAL'}:
            nodes.remove(node)
    img = bpy.data.images.load(str(ROOT / 'cover_art' / filename), check_existing=True)
    img.name = filename
    img.filepath = '//cover_art/' + filename
    img.pack()
    tex = nodes.new('ShaderNodeTexImage')
    tex.name = 'REPLACE THIS COVER IMAGE'
    tex.label = 'Replace artwork here • UV mapped • packed'
    tex.image = img
    tex.interpolation = 'Linear'
    tex.location = (-420, 110)
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'Cover UV'
    uv.location = (-650, 110)
    mat.node_tree.links.new(uv.outputs['UV'], tex.inputs['Vector'])
    bsdf = nodes.get('Principled BSDF')
    mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Coat Weight'].default_value = .05
    return mat


front_mat = artwork("ART / FRONT • Your Game Here", 'front_cover.png')
back_mat = artwork("ART / BACK • Packaging template", 'back_cover.png')
spine_mat = artwork("ART / SPINE • Red title strip", 'spine_cover.png')


def obj_mesh(name, verts, faces, col, mat, location=(0, 0, 0), parent=root):
    mesh = bpy.data.meshes.new(name + ' mesh')
    mesh.from_pydata([tuple(v * MM for v in point) for point in verts], [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    obj.location = Vector(location) * MM
    if parent:
        obj.parent = parent
    if mat:
        mesh.materials.append(mat)
    obj['Switch case part'] = True
    return obj


def bevel(obj, width=.1, segments=3):
    mod = obj.modifiers.new('Soft molded edges', 'BEVEL')
    mod.width = width * MM
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.harden_normals = True
    normal = obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    normal.keep_sharp = True
    normal.weight = 40
    return obj


def rounded_rect(width, height, radius, steps=10):
    points = []
    for cx, cz, start in ((width/2-radius, height/2-radius, 0),
                          (-width/2+radius, height/2-radius, 90),
                          (-width/2+radius, -height/2+radius, 180),
                          (width/2-radius, -height/2+radius, 270)):
        for n in range(steps+1):
            a = math.radians(start + 90*n/steps)
            points.append((cx+radius*math.cos(a), cz+radius*math.sin(a)))
    return points


def plate(name, width, height, radius, low, high, mat=plastic, col=shells, x=0, z=85, edge=.10):
    pts = rounded_rect(width, height, radius)
    n = len(pts)
    mid = (low+high)/2
    verts = [(px, yy-mid, pz) for yy in (low, high) for px, pz in pts]
    faces = [tuple(range(n)), tuple(range(2*n-1, n-1, -1))]
    faces += [(i, n+i, n+(i+1)%n, (i+1)%n) for i in range(n)]
    obj = obj_mesh(name, verts, faces, col, mat, (x, mid, z))
    for poly in obj.data.polygons[2:]:
        poly.use_smooth = True
    if edge:
        bevel(obj, edge)
    return obj


def ring(name, width, height, radius, wall, low, high, mat=plastic, col=shells, edge=.1):
    outer = rounded_rect(width, height, radius)
    inner = rounded_rect(width-2*wall, height-2*wall, max(.15, radius-wall))
    n = len(outer)
    mid = (low+high)/2
    verts = [(px, yy-mid, pz) for pts, yy in ((outer,low),(outer,high),(inner,low),(inner,high)) for px,pz in pts]
    faces = []
    for i in range(n):
        j = (i+1)%n
        faces += [(i,n+i,n+j,j), (2*n+j,3*n+j,3*n+i,2*n+i),
                  (i,j,2*n+j,2*n+i), (n+j,n+i,3*n+i,3*n+j)]
    obj = obj_mesh(name, verts, faces, col, mat, (0,mid,85))
    for i,p in enumerate(obj.data.polygons):
        p.use_smooth = i%4 < 2
    if edge:
        bevel(obj, edge)
    return obj


def box(name, dims, loc, mat=frosted, col=details, radius=.15, parent=root):
    x,y,z = [d/2 for d in dims]
    verts = [(-x,-y,-z), (x,-y,-z), (x,y,-z), (-x,y,-z),
             (-x,-y,z), (x,-y,z), (x,y,z), (-x,y,z)]
    faces = [(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    obj = obj_mesh(name,verts,faces,col,mat,loc,parent)
    if radius:
        bevel(obj,radius)
    return obj


front_shell = plate('Shell • front face',W,H,2.0,-5.5,-4.82)
rear_shell = plate('Shell • back face',W,H,2.0,4.82,5.5)
front_rim = ring('Shell • front tray sidewalls',W,H,2.0,1.05,-4.85,-.12)
rear_rim = ring('Shell • rear tray sidewalls',W,H,2.0,1.05,.12,4.85)
ring('Seam • inner interlocking lip',103.25,168.25,1.45,.42,-.5,.65,polished,details,.06)

# A shallow, circular thumb recess crosses the opening seam on the right edge.
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=7.0*MM, depth=2.7*MM,
    location=(58.2*MM,0,85*MM), rotation=(math.pi/2,0,0))
cutter = bpy.context.object
cutter.name = 'temporary thumb notch cutter'
for target in (front_rim,rear_rim):
    boolean = target.modifiers.new('Thumb opening recess', 'BOOLEAN')
    boolean.operation = 'DIFFERENCE'
    boolean.solver = 'EXACT'
    boolean.object = cutter
    # Evaluate the cut before edge finishing.
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_move_up(modifier=boolean.name)
    bpy.ops.object.modifier_move_up(modifier=boolean.name)
    bpy.ops.object.modifier_apply(modifier=boolean.name)
bpy.data.objects.remove(cutter, do_unlink=True)

# Raised rim, fine mold lines, hinge strips and small clasp hardware.
ring('Rim • front polished perimeter',104.55,169.55,1.9,.28,-5.63,-5.48,polished,details,.035)
ring('Rim • rear polished perimeter',104.55,169.55,1.9,.28,5.48,5.63,polished,details,.035)
for yy, title in ((-3.95,'front'),(3.95,'rear')):
    box(f'Hinge • {title} living-hinge fold',(.34,.44,163.8),(-52.46,yy,85),polished,radius=.14)
for z in (19,151):
    box(f'Clasp • catch at {z} mm',(.8,1.8,5.6),(51.4,.15,z),frosted,radius=.25)
    box(f'Clasp • mating tab at {z} mm',(.65,1.5,4.0),(50.8,-.5,z),polished,radius=.16)
for z in (3.1,166.9):
    for yy in (-3.2,3.2):
        box(f'Mold detail • hinge end {z} {yy}',(1.0,1.7,1.4),(-51.5,yy,z),frosted,radius=.16)
# Subtle clear rectangular welding/retention details on the exposed bottom border.
for yy in (-5.57,5.57):
    for x in (-28,27):
        box(f'Sleeve weld • bottom {x} {yy}',(24,.12,.28),(x,yy,1.35),polished,films,.045)


def cover_panel(name, width, height, y, mat, reverse=False):
    pts = rounded_rect(width,height,.55)
    verts = [(x,0,z) for x,z in pts]
    face = tuple(reversed(range(len(pts)))) if reverse else tuple(range(len(pts)))
    obj = obj_mesh(name,verts,[face],inserts,mat,(0,y,85))
    uv = obj.data.uv_layers.new(name='Cover UV')
    for loop in obj.data.loops:
        x,_,z = obj.data.vertices[loop.vertex_index].co / MM
        uv.data[loop.index].uv = ((.5-x/width) if reverse else (.5+x/width), .5+z/height)
    obj.data.materials.append(paper)
    mod = obj.modifiers.new('Actual paper thickness • 0.05 mm', 'SOLIDIFY')
    mod.thickness = .05*MM
    mod.offset = -1
    mod.material_offset = 1
    mod.material_offset_rim = 1
    obj['Replace image'] = mat.node_tree.nodes['REPLACE THIS COVER IMAGE'].image.filepath
    return obj


cover_panel('ARTWORK • FRONT • replace front_cover.png',102.8,165,-5.565,front_mat)
cover_panel('ARTWORK • BACK • replace back_cover.png',102.8,165,5.565,back_mat,True)
spine = obj_mesh('ARTWORK • SPINE • replace spine_cover.png',
    [(0,4.85,-82.5),(0,-4.85,-82.5),(0,-4.85,82.5),(0,4.85,82.5)],[(0,1,2,3)],inserts,spine_mat,(-52.56,0,85))
uv = spine.data.uv_layers.new(name='Cover UV')
for lp in spine.data.loops:
    uv.data[lp.index].uv = [(0,0),(1,0),(1,1),(0,1)][lp.vertex_index]
mod = spine.modifiers.new('Paper thickness', 'SOLIDIFY')
mod.thickness = .05*MM
mod.offset = -1
spine['Replace image'] = '//cover_art/spine_cover.png'

# Physically separate outer film gives glancing highlights above the matte ink.
plate('Sleeve • clear film over front artwork',103.3,165.7,.75,-5.655,-5.610,film,films,edge=.009)
plate('Sleeve • clear film over back artwork',103.3,165.7,.75,5.610,5.655,film,films,edge=.009)
box('Sleeve • clear film over red spine',(.045,9.82,165.6),(-52.625,0,85),film,films,.012)

# The insert sits against the exterior of the trays; internal paper supports
# remain separate, useful when inspecting the shell from inside.
for x in (-43.5,43.5):
    for z in (17,153):
        box(f'Interior • paper support {x} {z}',(4.8,1.1,2.0),(x,-4.15,z),frosted,radius=.28)

scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.unit_settings.length_unit = 'MILLIMETERS'
scene.render.engine = 'CYCLES'
scene.eevee.use_raytracing = True
scene.eevee.ray_tracing_options.resolution_scale = '1'
scene.eevee.ray_tracing_options.screen_trace_quality = 1.0
scene.eevee.ray_tracing_options.screen_trace_thickness = .001
scene.cycles.samples = 96
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 14
scene.cycles.transmission_bounces = 10
scene.cycles.transparent_max_bounces = 12
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for device in prefs.devices:
        device.use = device.type == 'OPTIX'
    if any(d.type == 'OPTIX' for d in prefs.devices):
        scene.cycles.device = 'GPU'
except Exception:
    scene.cycles.device = 'CPU'
scene.render.resolution_x = 1500
scene.render.resolution_y = 1800
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = False
scene.render.image_settings.color_depth = '8'
scene.view_settings.view_transform = 'Khronos PBR Neutral'
scene.view_settings.look = 'None'
scene.view_settings.exposure = -1.25
world = bpy.data.worlds.new('Studio • soft neutral environment')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (.29,.32,.36,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = .35
scene.world = world

ground_mat = material('STUDIO / neutral slate',(.09,.105,.12),.65)
ground = box('Studio • seamless floor',(10000,10000,1.0),(0,0,-.70),ground_mat,studio,0,parent=None)


def aim(obj, target):
    obj.rotation_euler = (Vector(target)*MM - obj.location).to_track_quat('-Z','Y').to_euler()


def camera(name, position, target, scale):
    data = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name,data)
    studio.objects.link(obj)
    obj.location = Vector(position)*MM
    aim(obj,target)
    data.type = 'ORTHO'
    data.ortho_scale = scale*MM
    data.lens = 70
    data.clip_start = .001
    data.clip_end = 20
    data.dof.use_dof = False
    return obj


hero = camera('CAMERA • 01 Front three-quarter',(-185,-360,219),(0,0,85),218)
camera('CAMERA • 02 Back three-quarter',(-185,360,219),(0,0,85),218)
camera('CAMERA • 03 Spine and opening seam',(-380,-125,158),(0,0,85),210)
camera('CAMERA • 04 Straight front',(0,-450,85),(0,0,85),200)
camera('CAMERA • 05 Straight back',(0,450,85),(0,0,85),200)
camera('CAMERA • 06 Right clasp detail',(280,-145,135),(43,0,87),58)
scene.camera = hero


def light(name, position, target, energy, size, color, size_y=None):
    data = bpy.data.lights.new(name,'AREA')
    data.energy = energy
    data.color = color
    data.shape = 'RECTANGLE'
    data.size = size*MM
    data.size_y = (size_y or size)*MM
    obj = bpy.data.objects.new(name,data)
    studio.objects.link(obj)
    obj.location = Vector(position)*MM
    aim(obj,target)
    return obj


light('Softbox • large front key',(-140,-240,330),(0,0,80),7.0,210,(1.0,.94,.88),280)
light('Softbox • right fill',(240,-130,190),(0,0,85),4.0,160,(.86,.93,1.0),240)
light('Strip • spine rim',(-210,125,255),(0,0,90),8.0,70,(.94,.97,1.0),220)
light('Softbox • back artwork',(100,240,260),(0,0,85),6.0,180,(1.0,.97,.92),250)

# Hide the presentation rig only in the modeling viewport; it still renders.
for obj in studio.objects:
    obj.hide_set(True)
for obj in films.objects:
    if obj.name.startswith('Sleeve • clear film'):
        obj.hide_set(True)
for obj in bpy.context.view_layer.objects:
    obj.select_set(False)
bpy.context.view_layer.objects.active = front_shell
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'CONSOLE':
            area.type = 'VIEW_3D' if area.width > 600 else 'PROPERTIES'
        if area.type == 'VIEW_3D':
            space = area.spaces.active
            space.clip_start = .001
            space.clip_end = 100
            space.lens = 60
            space.shading.type = 'MATERIAL'
            space.shading.use_scene_world = False
            space.shading.use_scene_lights = False
            space.shading.studiolight_intensity = 2.5
            space.shading.studio_light = 'studio.exr'
            space.overlay.show_floor = False
            space.overlay.show_axis_x = False
            space.overlay.show_axis_y = False
            space.overlay.show_extras = False
            space.overlay.show_relationship_lines = False
            space.overlay.show_outline_selected = False
            space.region_3d.view_location = (0,0,.085)
            space.region_3d.view_rotation = hero.rotation_euler.to_quaternion()
            space.region_3d.view_distance = .31
            space.region_3d.view_perspective = 'PERSP'

for col in list(bpy.data.collections):
    if col.name == 'Collection' and not col.objects and not col.children:
        bpy.data.collections.remove(col)
readme = bpy.data.texts.get('READ ME • Case and artwork') or bpy.data.texts.new('READ ME • Case and artwork')
readme.clear()
readme.write('''SWITCH-STYLE GAME CASE / EDITABLE COVER TEMPLATE

The case is approximately 105 × 170 × 11 mm. Scene geometry is in meters,
with millimeter display units. It is a closed presentation model.

GAME CASE contains the shell halves, UV-mapped paper panels, hinge/seam
details and separate clear sleeve. Move the CASE parent empty to position
the whole asset. Parts and edge-finishing modifiers remain editable.

ARTWORK
The three packed PNG images live in cover_art alongside editable SVG sources.
Edit the SVG or substitute a PNG with the same aspect ratio, then reload the
image on the matching ART material and pack the updated image before saving.
Front/back: 2060 × 3300 pixels. Spine: 200 × 3300 pixels.
Every insert uses a full-rectangle Cover UV map. Paper backs are plain white.

PRESENTATION
STUDIO contains six cameras, four softboxes and a floor. These are hidden
only in the modeling viewport, and remain enabled for rendering. Select
the required camera in Scene properties. The default is Front three-quarter.
Cycles uses the available OptiX GPU, with denoising and transmissive plastic.
The three thin sleeve surfaces are also hidden only in the modeling viewport
to keep cover artwork sharp in Material Preview. They still render normally.

The back-cover details and RP rating are editable mockup placeholders.
The original project is preserved as pfrmca_01_before_case.blend.
''')
scene['Asset'] = 'Switch-style game case • editable reference cover template'
bpy.context.view_layer.update()
scene.render.filepath = '//previews/switch_case_front.png'
old_versions = bpy.context.preferences.filepaths.save_version
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'pfrmca_01.blend'))
bpy.context.preferences.filepaths.save_version = old_versions
report = {
    'file': bpy.data.filepath,
    'case_objects': len(model.all_objects),
    'cameras': [o.name for o in studio.objects if o.type == 'CAMERA'],
    'packed_artwork': [i.name for i in bpy.data.images if i.packed_file],
    'render_engine': scene.render.engine,
    'device': scene.cycles.device,
    'nominal_dimensions_mm': [W,D,H],
}
Path('/tmp/pfr_case_build_result.json').write_text(json.dumps(report,indent=2))
print('SWITCH CASE COMPLETE:',json.dumps(report))
