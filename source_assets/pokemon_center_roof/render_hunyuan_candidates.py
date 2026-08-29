"""Render consistent clay previews for all generated Hunyuan roof donors.

Run from the repository root:

    blender --background --factory-startup \
        --python source_assets/pokemon_center_roof/render_hunyuan_candidates.py
"""

from pathlib import Path
import math

import bpy
from mathutils import Vector


SCRIPT_PATH = Path(__file__).resolve()
OUTPUT_DIR = SCRIPT_PATH.parent / "hunyuan_output"


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def configure_scene() -> tuple[bpy.types.Object, bpy.types.Material]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False

    world = bpy.data.worlds.new("HunyuanCandidatePreviewWorld")
    world.use_nodes = True
    scene.world = world
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.035, 0.050, 0.075, 1.0)
    background.inputs["Strength"].default_value = 0.7

    camera_data = bpy.data.cameras.new("HunyuanCandidatePreviewCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2.85
    camera = bpy.data.objects.new("HunyuanCandidatePreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera

    sun_data = bpy.data.lights.new("HunyuanCandidatePreviewSun", "SUN")
    sun_data.energy = 2.6
    sun_data.color = (1.0, 0.90, 0.75)
    sun = bpy.data.objects.new("HunyuanCandidatePreviewSun", sun_data)
    sun.rotation_euler = (
        math.radians(35.0),
        math.radians(-20.0),
        math.radians(-42.0),
    )
    scene.collection.objects.link(sun)

    fill_data = bpy.data.lights.new("HunyuanCandidatePreviewFill", "AREA")
    fill_data.energy = 650.0
    fill_data.shape = "DISK"
    fill_data.size = 3.0
    fill_data.color = (0.55, 0.72, 1.0)
    fill = bpy.data.objects.new("HunyuanCandidatePreviewFill", fill_data)
    fill.location = (-2.5, 2.0, 3.0)
    look_at(fill, Vector())
    scene.collection.objects.link(fill)

    clay = bpy.data.materials.new("Hunyuan Candidate Clay")
    clay.diffuse_color = (0.68, 0.71, 0.76, 1.0)
    clay.use_nodes = True
    principled = clay.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = clay.diffuse_color
    principled.inputs["Roughness"].default_value = 0.78
    return camera, clay


def imported_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    minimum = Vector((math.inf, math.inf, math.inf))
    maximum = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            minimum = Vector((min(minimum.x, point.x), min(minimum.y, point.y), min(minimum.z, point.z)))
            maximum = Vector((max(maximum.x, point.x), max(maximum.y, point.y), max(maximum.z, point.z)))
    return minimum, maximum


def render_candidate(
    path: Path,
    camera: bpy.types.Object,
    clay: bpy.types.Material,
) -> None:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    imported_set = set(imported)
    minimum, maximum = imported_bounds(imported)
    center = (minimum + maximum) * 0.5

    container = bpy.data.objects.new(f"{path.stem}Center", None)
    bpy.context.scene.collection.objects.link(container)
    for root in (obj for obj in imported if obj.parent not in imported_set):
        root.parent = container
    container.location = -center
    for obj in imported:
        if obj.type != "MESH":
            continue
        obj.data.materials.clear()
        obj.data.materials.append(clay)

    target = Vector((0.0, 0.0, 0.0))
    camera.location = (2.6, -3.2, 2.25)
    look_at(camera, target)
    bpy.context.scene.render.filepath = str(OUTPUT_DIR / f"{path.stem}_perspective.png")
    bpy.ops.render.render(write_still=True)

    camera.location = (0.0, 0.0, 4.0)
    look_at(camera, target)
    camera.data.ortho_scale = 2.65
    bpy.context.scene.render.filepath = str(OUTPUT_DIR / f"{path.stem}_top.png")
    bpy.ops.render.render(write_still=True)
    camera.data.ortho_scale = 2.85

    bpy.data.objects.remove(container, do_unlink=True)
    for obj in imported:
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def main() -> None:
    camera, clay = configure_scene()
    candidates = sorted(OUTPUT_DIR.glob("roof_candidate_seed_*.glb"))
    if not candidates:
        raise RuntimeError(f"No Hunyuan candidates found in {OUTPUT_DIR}")
    for candidate in candidates:
        render_candidate(candidate, camera, clay)
        print(f"Rendered Hunyuan candidate previews for {candidate.name}")


if __name__ == "__main__":
    main()
