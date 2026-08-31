"""Build the east-door Pokemon Center service-annex environment.

Run from the repository root with:

    blender --background --factory-startup \
        --python source_assets/pokemon_center_annex/create_pokemon_center_annex.py

The annex shares the main clinic's compact palette and classical brick albedo,
but uses a distinct dispensary/consultation layout. It remains one mesh with
two opaque material surfaces for the mobile-web target.
"""

from __future__ import annotations

from pathlib import Path
import sys

import bpy
from mathutils import Vector


SCRIPT_PATH = Path(__file__).resolve()
PROJECT_ROOT = SCRIPT_PATH.parents[2]
SOURCE_DIR = SCRIPT_PATH.parent
MAIN_INTERIOR_SOURCE_DIR = PROJECT_ROOT / "source_assets/pokemon_center_interior"
RUNTIME_DIR = (
    PROJECT_ROOT
    / "art/environments/new_bouffalant_city/pokemon_center_annex"
)
OUTPUT_GLB = RUNTIME_DIR / "pokemon_center_annex_environment.glb"
OUTPUT_BLEND = SOURCE_DIR / "pokemon_center_annex.blend"
PREVIEW_PATH = SOURCE_DIR / "pokemon_center_annex_preview.png"

sys.path.insert(0, str(MAIN_INTERIOR_SOURCE_DIR))
import create_pokemon_center_interior as shared  # noqa: E402


ROOM_FOOTPRINT = [
    (-5.0, -4.5),
    (5.0, -4.5),
    (5.0, 4.5),
    (-5.0, 4.5),
]


def add_room_shell(builder: shared.MeshBuilder) -> None:
    builder.add_face([(x, y, 0.0) for x, y in ROOM_FOOTPRINT], "ivory")
    builder.add_plane(-4.68, 4.68, -4.18, 4.18, 0.012, "pale")

    # Broad stone tiles and a short blue service route remain legible from the
    # fixed gameplay camera without adding a floor texture or decal material.
    for x in [-3.0, -1.0, 1.0, 3.0]:
        builder.add_plane(x - 0.016, x + 0.016, -4.05, 4.05, 0.018, "ivory")
    for y in [-2.5, -0.5, 1.5, 3.5]:
        builder.add_plane(-4.55, 4.55, y - 0.016, y + 0.016, 0.018, "ivory")
    builder.add_plane(-1.18, 1.18, -4.24, 1.72, 0.024, "ivory")
    builder.add_plane(-1.08, -0.96, -4.14, 1.62, 0.030, "cyan")
    builder.add_plane(0.96, 1.08, -4.14, 1.62, 0.030, "cyan")
    builder.add_horizontal_disc((0.0, -0.25, 0.034), 0.82, "cyan", 18)
    builder.add_horizontal_disc((0.0, -0.25, 0.040), 0.52, "ivory", 18)
    builder.add_horizontal_disc((0.0, -0.25, 0.046), 0.24, "red", 14)
    builder.add_plane(-0.72, 0.72, -0.31, -0.19, 0.052, "red")

    wall_height = 3.20
    for center, size in [
        ((0.0, 4.5, wall_height * 0.5), (10.0, 0.26, wall_height)),
        ((-5.0, 0.0, wall_height * 0.5), (0.26, 9.0, wall_height)),
        ((5.0, 0.0, wall_height * 0.5), (0.26, 9.0, wall_height)),
        ((-3.1, -4.5, 0.45), (3.8, 0.26, 0.90)),
        ((3.1, -4.5, 0.45), (3.8, 0.26, 0.90)),
    ]:
        builder.add_box(center, size, "ivory", material_kind="brick")

    # Dark wood, limestone, and one narrow blue rail continue the renovated
    # civic-building language established by the main clinic.
    builder.add_box((0.0, 4.32, 0.55), (9.55, 0.08, 1.02), "charcoal")
    builder.add_box((-4.82, 0.0, 0.55), (0.08, 8.55, 1.02), "charcoal")
    builder.add_box((4.82, 0.0, 0.55), (0.08, 8.55, 1.02), "charcoal")
    builder.add_box((0.0, 4.25, 1.08), (9.60, 0.12, 0.16), "ivory")
    builder.add_box((-4.75, 0.0, 1.08), (0.12, 8.60, 0.16), "ivory")
    builder.add_box((4.75, 0.0, 1.08), (0.12, 8.60, 0.16), "ivory")
    builder.add_box((0.0, 4.17, 1.08), (9.45, 0.04, 0.055), "cyan")
    builder.add_box((-4.67, 0.0, 1.08), (0.04, 8.45, 0.055), "cyan")
    builder.add_box((4.67, 0.0, 1.08), (0.04, 8.45, 0.055), "cyan")
    builder.add_box((0.0, 4.32, 3.02), (9.65, 0.12, 0.18), "ivory")
    builder.add_box((-4.82, 0.0, 3.02), (0.12, 8.65, 0.18), "ivory")
    builder.add_box((4.82, 0.0, 3.02), (0.12, 8.65, 0.18), "ivory")
    builder.add_box((-3.1, -4.32, 0.92), (3.8, 0.32, 0.14), "ivory")
    builder.add_box((3.1, -4.32, 0.92), (3.8, 0.32, 0.14), "ivory")

    # Shallow pilasters provide classical rhythm without collision or separate
    # meshes. Their broad spacing avoids visual clutter on the smaller annex.
    for x in [-4.25, -2.35, 2.35, 4.25]:
        builder.add_box((x, 4.16, 2.03), (0.26, 0.18, 1.72), "ivory")
        builder.add_box((x, 4.12, 1.20), (0.43, 0.23, 0.18), "ivory")
        builder.add_box((x, 4.12, 2.90), (0.48, 0.23, 0.20), "ivory")
    for x in [-4.25, 4.25]:
        for y in [-3.25, -0.8, 1.65]:
            builder.add_box((x, y, 2.03), (0.22, 0.26, 1.72), "ivory")
            builder.add_box((x, y, 1.20), (0.34, 0.43, 0.18), "ivory")
            builder.add_box((x, y, 2.90), (0.38, 0.48, 0.20), "ivory")


def add_dispensary(builder: shared.MeshBuilder) -> None:
    builder.add_box((0.65, 2.58, 0.48), (7.15, 1.12, 0.96), "charcoal")
    builder.add_box((0.65, 1.98, 0.60), (6.82, 0.08, 0.64), "cyan")
    builder.add_box((0.65, 2.58, 1.02), (7.42, 1.30, 0.16), "ivory")
    builder.add_box((-2.62, 1.92, 0.62), (0.24, 0.10, 0.72), "red")
    builder.add_box((3.92, 1.92, 0.62), (0.24, 0.10, 0.72), "red")
    for x in [-1.85, -0.60, 0.65, 1.90, 3.15]:
        builder.add_box((x, 1.91, 0.58), (0.065, 0.06, 0.60), "charcoal")
        builder.add_box((x, 1.89, 0.84), (0.98, 0.04, 0.055), "charcoal")

    # An old apothecary-style timber cabinet holds clean, oversized near-future
    # medicine packages. The packages use existing palette colors only.
    builder.add_box((0.65, 4.04, 1.83), (7.18, 0.42, 2.48), "charcoal")
    for height in [1.12, 1.78, 2.44]:
        builder.add_box((0.65, 3.79, height), (6.76, 0.10, 0.11), "ivory")
    for x in [-2.15, -0.75, 0.65, 2.05, 3.45]:
        builder.add_box((x, 3.77, 1.79), (0.075, 0.08, 1.28), "ivory")
    package_colors = ["red", "cyan", "green", "pink"]
    for row, height in enumerate([1.40, 2.06, 2.70]):
        for column, x in enumerate([-2.30, -1.45, -0.60, 0.25, 1.10, 1.95, 2.80, 3.55]):
            color = package_colors[(row + column) % len(package_colors)]
            builder.add_box((x, 3.70, height), (0.46, 0.10, 0.25), color)

    builder.add_front_disc((0.65, 3.66, 2.98), 0.34, "cyan", 16)
    builder.add_front_disc((0.65, 3.63, 2.98), 0.20, "ivory", 16)
    builder.add_front_disc((0.65, 3.60, 2.98), 0.08, "red", 12)
    builder.add_box((0.65, 3.57, 2.98), (0.58, 0.04, 0.07), "red")

    # Four collection pods distinguish this service counter from the six-pod
    # healing counter in the main lobby.
    for x in [-1.30, -0.20, 0.90, 2.00]:
        builder.add_prism((x, 2.42, 1.22), 0.20, 0.17, 0.28, "ivory", 8)
        builder.add_prism((x, 2.42, 1.40), 0.13, 0.09, 0.12, "cyan", 8)


def add_consultation_area(builder: shared.MeshBuilder) -> None:
    # Walnut consultation seating with blue cushions occupies the left wall.
    builder.add_box((-4.08, -1.15, 0.47), (0.82, 2.44, 0.18), "charcoal")
    builder.add_box((-4.44, -1.15, 0.94), (0.14, 2.44, 1.00), "charcoal")
    builder.add_box((-4.03, -1.15, 0.59), (0.66, 2.16, 0.08), "cyan")
    builder.add_box((-4.08, -2.02, 0.23), (0.55, 0.16, 0.46), "ivory")
    builder.add_box((-4.08, -0.28, 0.23), (0.55, 0.16, 0.46), "ivory")
    builder.add_prism((-3.35, 0.55, 0.38), 0.52, 0.47, 0.76, "charcoal", 8)
    builder.add_prism((-3.35, 0.55, 0.79), 0.58, 0.58, 0.08, "ivory", 8)

    # A compact automated locker and standing terminal provide the annex's
    # functional near-future layer while retaining solid opaque materials.
    builder.add_box((4.16, -0.72, 0.90), (1.18, 2.20, 1.80), "navy")
    for height in [0.48, 1.02, 1.56]:
        builder.add_box((3.53, -0.72, height), (0.08, 1.82, 0.42), "cyan")
        builder.add_box((3.48, -1.18, height), (0.04, 0.06, 0.10), "red")
        builder.add_box((3.48, -0.26, height), (0.04, 0.06, 0.10), "red")
    builder.add_box((3.38, 1.08, 0.67), (1.08, 0.92, 1.34), "navy")
    builder.add_box((3.38, 0.57, 1.02), (0.82, 0.08, 0.55), "cyan")
    builder.add_box((3.38, 1.08, 1.41), (1.18, 1.02, 0.16), "ivory")
    builder.add_box((3.38, 1.08, 0.10), (1.22, 1.06, 0.20), "charcoal")

    for x in [-4.20, 4.20]:
        builder.add_prism((x, -3.55, 0.31), 0.42, 0.32, 0.62, "red", 8)
        builder.add_prism((x, -3.55, 0.88), 0.20, 0.48, 0.66, "green", 8)
        builder.add_prism((x, -3.55, 1.24), 0.40, 0.10, 0.46, "green", 8)


def create_environment() -> bpy.types.Object:
    builder = shared.MeshBuilder()
    add_room_shell(builder)
    add_dispensary(builder)
    add_consultation_area(builder)

    mesh = bpy.data.meshes.new("PokemonCenterAnnexMesh")
    mesh.from_pydata(builder.vertices, [], builder.faces)
    mesh.materials.append(shared.create_palette_material(shared.create_palette()))
    mesh.materials.append(shared.create_brick_material())
    mesh.update()

    uv_layer = mesh.uv_layers.new(name="UVMap")
    face_data = zip(
        mesh.polygons,
        builder.swatches,
        builder.material_kinds,
        builder.face_uvs,
        strict=True,
    )
    for polygon, swatch, material_kind, custom_uvs in face_data:
        polygon.material_index = 1 if material_kind == "brick" else 0
        if custom_uvs is None:
            custom_uvs = [shared.SWATCH_UV[swatch]] * len(polygon.loop_indices)
        for loop_index, uv in zip(polygon.loop_indices, custom_uvs, strict=True):
            uv_layer.data[loop_index].uv = uv

    environment = bpy.data.objects.new("PokemonCenterAnnexEnvironment", mesh)
    bpy.context.scene.collection.objects.link(environment)
    environment["mobile_web_asset"] = True
    environment["opaque_material_draws"] = 2
    environment["distinct_east_door_interior"] = True
    environment["collision_authored_in_godot_scene"] = True
    return environment


def export_environment(environment: bpy.types.Object) -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    environment.select_set(True)
    bpy.context.view_layer.objects.active = environment
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_extras=True,
    )


def render_preview() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = str(PREVIEW_PATH)

    world = bpy.data.worlds.new("PokemonCenterAnnexPreviewWorld")
    world.use_nodes = True
    scene.world = world
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.045, 0.075, 0.12, 1.0)
    background.inputs["Strength"].default_value = 0.75

    target = Vector((0.0, 0.0, 1.00))
    camera_data = bpy.data.cameras.new("PokemonCenterAnnexPreviewCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 13.8
    camera = bpy.data.objects.new("PokemonCenterAnnexPreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (11.5, -15.0, 10.8)
    shared.look_at(camera, target)
    scene.camera = camera

    key_data = bpy.data.lights.new("PokemonCenterAnnexPreviewKey", "AREA")
    key_data.energy = 1250.0
    key_data.shape = "DISK"
    key_data.size = 6.5
    key = bpy.data.objects.new("PokemonCenterAnnexPreviewKey", key_data)
    scene.collection.objects.link(key)
    key.location = (-4.0, -6.0, 10.0)
    shared.look_at(key, target)

    fill_data = bpy.data.lights.new("PokemonCenterAnnexPreviewFill", "AREA")
    fill_data.energy = 620.0
    fill_data.size = 5.0
    fill = bpy.data.objects.new("PokemonCenterAnnexPreviewFill", fill_data)
    scene.collection.objects.link(fill)
    fill.location = (5.5, 2.0, 7.5)
    shared.look_at(fill, target)

    bpy.ops.render.render(write_still=True)


def main() -> None:
    shared.clear_scene()
    environment = create_environment()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    export_environment(environment)
    render_preview()
    triangles = sum(len(polygon.vertices) - 2 for polygon in environment.data.polygons)
    print(
        f"Exported {OUTPUT_GLB}: {len(environment.data.vertices)} vertices, "
        f"{triangles} triangles, 2 opaque materials"
    )
    print(f"Rendered {PREVIEW_PATH}")


if __name__ == "__main__":
    main()
