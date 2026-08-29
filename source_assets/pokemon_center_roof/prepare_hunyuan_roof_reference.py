"""Build the fitted Pokemon Center roof cage and render Hunyuan inputs.

Run from the repository root with:

    blender --background --factory-startup \
        --python source_assets/pokemon_center_roof/prepare_hunyuan_roof_reference.py

The roof is authored in final Godot meters. The reference Pokemon Center GLB
uses a 0.75 Godot import scale, so its imported Blender hierarchy is scaled by
the same amount only for the context renders.
"""

from pathlib import Path
import math

import bpy
from mathutils import Vector


SCRIPT_PATH = Path(__file__).resolve()
PROJECT_ROOT = SCRIPT_PATH.parents[2]
MODEL_PATH = (
    PROJECT_ROOT
    / "art/environments/new_bouffalant_city/reference_city_pack/models"
    / "t1_b_pokemon_center_out.glb"
)
SOURCE_DIR = SCRIPT_PATH.parent
INPUT_DIR = SOURCE_DIR / "hunyuan_input"
BLEND_PATH = SOURCE_DIR / "pokemon_center_roof_fit.blend"

IMPORT_SCALE = 0.75
WALL_TOP_HEIGHT = 4.0 * IMPORT_SCALE
BUILDING_MAX_HEIGHT = 5.9097 * IMPORT_SCALE
EAVE_BOTTOM_HEIGHT = BUILDING_MAX_HEIGHT + 0.080

# This plan uses the source model's complete 10.26 m square envelope and keeps
# its measured chamfer. The previous rim-only points stopped 0.349 m short on
# two source-space sides, visibly exposing the facade from above. Multiplying
# by the import scale yields final Godot meters.
SOURCE_FOOTPRINT = [
    (-5.130, -5.130),
    (2.488, -5.130),
    (5.130, -2.482),
    (5.130, 5.130),
    (-5.130, 5.130),
]
FOOTPRINT = [
    Vector((x * IMPORT_SCALE, y * IMPORT_SCALE))
    for x, y in SOURCE_FOOTPRINT
]


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    roughness: float,
    metallic: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    return material


def polygon_centroid(points: list[Vector]) -> Vector:
    # Area-weighted centroid keeps the roof peak centered over the asymmetric
    # triangular footprint rather than over its bounding box.
    area_twice = 0.0
    centroid = Vector((0.0, 0.0))
    for index, point in enumerate(points):
        next_point = points[(index + 1) % len(points)]
        cross = point.x * next_point.y - next_point.x * point.y
        area_twice += cross
        centroid.x += (point.x + next_point.x) * cross
        centroid.y += (point.y + next_point.y) * cross
    if abs(area_twice) <= 0.000001:
        return sum(points, Vector()) / len(points)
    return centroid / (3.0 * area_twice)


def scale_polygon(points: list[Vector], factor: float) -> list[Vector]:
    center = polygon_centroid(points)
    return [center + (point - center) * factor for point in points]


def create_extruded_polygon(
    name: str,
    points: list[Vector],
    bottom_z: float,
    top_z: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    count = len(points)
    vertices = [
        (point.x, point.y, height)
        for height in (bottom_z, top_z)
        for point in points
    ]
    faces: list[tuple[int, ...]] = []
    faces.append(tuple(reversed(range(count))))
    faces.append(tuple(range(count, count * 2)))
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, count + next_index, count + index))

    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    mesh.update()
    roof_object = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(roof_object)
    return roof_object


def create_hip_surface(
    name: str,
    outer: list[Vector],
    inner: list[Vector],
    outer_z: float,
    inner_z: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    count = len(outer)
    vertices = [
        *((point.x, point.y, outer_z) for point in outer),
        *((point.x, point.y, inner_z) for point in inner),
    ]
    faces: list[tuple[int, ...]] = []
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, count + next_index, count + index))
    faces.append(tuple(range(count, count * 2)))

    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    mesh.update()
    roof_object = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(roof_object)
    return roof_object


def create_roof_cage() -> list[bpy.types.Object]:
    ivory = make_material(
        "Roof Ivory",
        (0.72, 0.69, 0.62, 1.0),
        roughness=0.78,
    )
    red = make_material(
        "Roof Civic Red",
        (0.63, 0.018, 0.028, 1.0),
        roughness=0.58,
    )
    charcoal = make_material(
        "Roof Charcoal",
        (0.025, 0.040, 0.060, 1.0),
        roughness=0.68,
        metallic=0.05,
    )

    center = polygon_centroid(FOOTPRINT)
    # The dark drum is safely recessed behind the facade emblems. The broad
    # eave overhangs the complete building envelope, but starts above every
    # source-building vertex so it cannot cut through the red medallions.
    drum_loop = scale_polygon(FOOTPRINT, 0.70)
    eave_loop = scale_polygon(FOOTPRINT, 1.025)
    upper_loop = scale_polygon(FOOTPRINT, 0.76)
    top_loop = scale_polygon(FOOTPRINT, 0.56)
    roof_objects = [
        create_extruded_polygon(
            "RoofRecessedDrum",
            drum_loop,
            WALL_TOP_HEIGHT + 0.015,
            EAVE_BOTTOM_HEIGHT,
            charcoal,
        ),
        create_hip_surface(
            "RoofRedSoffit",
            drum_loop,
            eave_loop,
            EAVE_BOTTOM_HEIGHT,
            EAVE_BOTTOM_HEIGHT + 0.040,
            red,
        ),
        create_extruded_polygon(
            "RoofRedEave",
            eave_loop,
            EAVE_BOTTOM_HEIGHT + 0.040,
            EAVE_BOTTOM_HEIGHT + 0.180,
            red,
        ),
        create_hip_surface(
            "RoofIvoryHip",
            eave_loop,
            upper_loop,
            EAVE_BOTTOM_HEIGHT + 0.180,
            EAVE_BOTTOM_HEIGHT + 0.900,
            ivory,
        ),
        create_hip_surface(
            "RoofCharcoalCrown",
            upper_loop,
            top_loop,
            EAVE_BOTTOM_HEIGHT + 0.900,
            EAVE_BOTTOM_HEIGHT + 1.170,
            charcoal,
        ),
        create_extruded_polygon(
            "RoofIvoryTopCap",
            top_loop,
            EAVE_BOTTOM_HEIGHT + 1.170,
            EAVE_BOTTOM_HEIGHT + 1.330,
            ivory,
        ),
    ]

    # A restrained circular skylight echoes the building's round sign motifs
    # without competing with the existing red facade emblems.
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=24,
        radius=0.50,
        depth=0.22,
        location=(center.x, center.y, EAVE_BOTTOM_HEIGHT + 1.440),
    )
    skylight = bpy.context.object
    skylight.name = "RoofSkylight"
    skylight.data.materials.append(red)
    roof_objects.append(skylight)

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=24,
        radius=0.34,
        depth=0.08,
        location=(center.x, center.y, EAVE_BOTTOM_HEIGHT + 1.590),
    )
    skylight_inset = bpy.context.object
    skylight_inset.name = "RoofSkylightInset"
    skylight_inset.data.materials.append(charcoal)
    roof_objects.append(skylight_inset)

    for roof_object in roof_objects:
        roof_object["pokemon_center_roof_reference"] = True
    return roof_objects


def import_scaled_building_reference() -> list[bpy.types.Object]:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(MODEL_PATH))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    imported_set = set(imported)
    roots = [obj for obj in imported if obj.parent not in imported_set]
    for root in roots:
        root.scale = (IMPORT_SCALE, IMPORT_SCALE, IMPORT_SCALE)
        # Godot's root-scale import option scales node translations too.
        # Applying only Blender object scale shifts this particular GLB by
        # roughly 23 cm and creates a misleading fit preview.
        root.location *= IMPORT_SCALE
    for obj in imported:
        obj["pokemon_center_reference"] = True
    return imported


def look_at(camera: bpy.types.Object, target: Vector) -> None:
    camera.rotation_euler = (
        target - camera.location
    ).to_track_quat("-Z", "Y").to_euler()


def configure_render_scene() -> tuple[bpy.types.Object, bpy.types.Object]:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True

    world = bpy.data.worlds.new("RoofReferenceWorld")
    world.use_nodes = True
    scene.world = world
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.055, 0.075, 0.11, 1.0)
    background.inputs["Strength"].default_value = 0.55

    camera_data = bpy.data.cameras.new("RoofReferenceCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 10.6
    camera = bpy.data.objects.new("RoofReferenceCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera

    sun_data = bpy.data.lights.new("RoofReferenceSun", "SUN")
    sun_data.energy = 2.2
    sun_data.color = (1.0, 0.91, 0.76)
    sun = bpy.data.objects.new("RoofReferenceSun", sun_data)
    sun.rotation_euler = (
        math.radians(32.0),
        math.radians(-18.0),
        math.radians(-38.0),
    )
    scene.collection.objects.link(sun)

    fill_data = bpy.data.lights.new("RoofReferenceFill", "AREA")
    fill_data.energy = 850.0
    fill_data.shape = "DISK"
    fill_data.size = 7.0
    fill_data.color = (0.60, 0.73, 1.0)
    fill = bpy.data.objects.new("RoofReferenceFill", fill_data)
    fill.location = (-5.0, 4.0, 9.0)
    look_at(fill, Vector((0.0, 0.0, WALL_TOP_HEIGHT)))
    scene.collection.objects.link(fill)
    return camera, fill


def set_reference_visibility(show_building: bool) -> None:
    for obj in bpy.context.scene.objects:
        if obj.get("pokemon_center_reference"):
            obj.hide_render = not show_building


def render_view(
    camera: bpy.types.Object,
    name: str,
    position: tuple[float, float, float],
    target: tuple[float, float, float],
    *,
    show_building: bool,
    transparent: bool,
    resolution: int = 640,
    ortho_scale: float = 10.6,
) -> None:
    scene = bpy.context.scene
    set_reference_visibility(show_building)
    scene.render.film_transparent = transparent
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    camera.data.ortho_scale = ortho_scale
    camera.location = position
    look_at(camera, Vector(target))
    output_path = INPUT_DIR / f"{name}.png"
    scene.render.filepath = str(output_path)
    bpy.ops.render.render(write_still=True)
    print(f"Rendered {output_path}")


def main() -> None:
    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    clear_scene()
    create_roof_cage()
    import_scaled_building_reference()
    camera, _fill = configure_render_scene()

    center = polygon_centroid(FOOTPRINT)
    target = (center.x, center.y, WALL_TOP_HEIGHT + 0.22)
    render_view(
        camera,
        "front",
        (11.0, -11.0, 8.2),
        target,
        show_building=False,
        transparent=True,
    )
    render_view(
        camera,
        "left",
        (-11.0, -11.0, 8.2),
        target,
        show_building=False,
        transparent=True,
    )
    render_view(
        camera,
        "back",
        (-11.0, 11.0, 8.2),
        target,
        show_building=False,
        transparent=True,
    )
    render_view(
        camera,
        "top",
        (center.x, center.y, 16.0),
        target,
        show_building=False,
        transparent=True,
        ortho_scale=10.0,
    )
    render_view(
        camera,
        "concept_context",
        (11.5, -11.5, 8.4),
        (0.0, 0.0, 2.35),
        show_building=True,
        transparent=False,
        resolution=1024,
        ortho_scale=12.0,
    )

    set_reference_visibility(True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"Saved {BLEND_PATH}")


if __name__ == "__main__":
    main()
