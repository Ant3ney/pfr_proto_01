"""Create fitted low-poly street doors for the roofed Pokemon Center.

Run from the repository root with:

    blender --background --factory-startup \
        --python source_assets/pokemon_center_roof/create_pokemon_center_doors.py

The entrance measurements come directly from the source building's two broad
street-facing openings beneath its large red emblems. Output geometry is
authored in final Godot meters and uses one opaque palette material for
mobile/web compatibility.
"""

from __future__ import annotations

from pathlib import Path
import binascii
import struct
import zlib

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


SCRIPT_PATH = Path(__file__).resolve()
PROJECT_ROOT = SCRIPT_PATH.parents[2]
SOURCE_DIR = SCRIPT_PATH.parent
RUNTIME_DIR = (
    PROJECT_ROOT
    / "art/environments/new_bouffalant_city/pokemon_center_roof"
)
BUILDING_PATH = (
    PROJECT_ROOT
    / "art/environments/new_bouffalant_city/reference_city_pack/models"
    / "t1_b_pokemon_center_out.glb"
)
ROOF_PATH = RUNTIME_DIR / "pokemon_center_roof.glb"
OUTPUT_GLB = RUNTIME_DIR / "pokemon_center_doors.glb"
PALETTE_PATH = SOURCE_DIR / "pokemon_center_doors_palette.png"
OUTPUT_BLEND = SOURCE_DIR / "pokemon_center_doors.blend"
PREVIEW_PATH = SOURCE_DIR / "pokemon_center_doors_context.png"

IMPORT_SCALE = 0.75

# Measured from t1_b_pokemon_center_out.glb after its baked 0.75 import scale.
# Both open street facades are 3.271 m wide. The outer border deliberately
# overlaps the opening edges so no background seam can show at oblique camera
# angles. The planes remain behind the projecting columns, emblem, and trim.
SOUTH_OPENING_MIN = -2.5317 * IMPORT_SCALE
SOUTH_OPENING_MAX = 1.8298 * IMPORT_SCALE
EAST_OPENING_MIN = -1.8316 * IMPORT_SCALE
EAST_OPENING_MAX = 2.5299 * IMPORT_SCALE
FRAME_OVERLAP = 0.040
SOUTH_PLANE = -4.0458 * IMPORT_SCALE - 0.020
EAST_PLANE = 4.0405 * IMPORT_SCALE + 0.020
DOOR_BOTTOM = 0.360
DOOR_TOP = 3.070

SWATCH_UV = {
    "charcoal": (0.12, 0.5),
    "ivory": (0.38, 0.5),
    "glass": (0.64, 0.5),
    "red": (0.88, 0.5),
}
SWATCH_COLORS = {
    "charcoal": (0.020, 0.035, 0.052, 1.0),
    "ivory": (0.72, 0.69, 0.62, 1.0),
    "glass": (0.055, 0.24, 0.34, 1.0),
    "red": (0.63, 0.018, 0.028, 1.0),
}


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def facade_point(
    facade: str,
    tangent: float,
    height: float,
    normal_offset: float,
) -> tuple[float, float, float]:
    """Convert facade-local tangent/height into Blender XYZ.

    Polygon winding faces out toward the street on both facades: -Y for the
    south entrance and +X for the east entrance.
    """
    if facade == "south":
        return (tangent, SOUTH_PLANE - normal_offset, height)
    if facade == "east":
        return (EAST_PLANE + normal_offset, tangent, height)
    raise ValueError(f"Unsupported facade: {facade}")


class MeshBuilder:
    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.swatches: list[str] = []
        self.allowed_building_overlap_faces: set[int] = set()

    def add_polygon(
        self,
        facade: str,
        points: list[tuple[float, float]],
        normal_offset: float,
        swatch: str,
        allow_building_overlap: bool = False,
    ) -> None:
        start = len(self.vertices)
        self.vertices.extend(
            facade_point(facade, tangent, height, normal_offset)
            for tangent, height in points
        )
        self.faces.append(tuple(range(start, len(self.vertices))))
        self.swatches.append(swatch)
        if allow_building_overlap:
            self.allowed_building_overlap_faces.add(len(self.faces) - 1)

    def add_rectangle(
        self,
        facade: str,
        left: float,
        right: float,
        bottom: float,
        top: float,
        normal_offset: float,
        swatch: str,
        allow_building_overlap: bool = False,
    ) -> None:
        self.add_polygon(
            facade,
            [(left, bottom), (right, bottom), (right, top), (left, top)],
            normal_offset,
            swatch,
            allow_building_overlap,
        )


def create_palette() -> bpy.types.Image:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    width = 64
    height = 16
    scanline = bytearray()

    def linear_to_srgb_byte(value: float) -> int:
        if value <= 0.0031308:
            encoded = value * 12.92
        else:
            encoded = 1.055 * value ** (1.0 / 2.4) - 0.055
        return round(clamp(encoded, 0.0, 1.0) * 255.0)

    ordered = ["charcoal", "ivory", "glass", "red"]
    for _y in range(height):
        scanline.append(0)
        for x in range(width):
            color = SWATCH_COLORS[ordered[min(3, x // 16)]]
            scanline.extend(linear_to_srgb_byte(channel) for channel in color)

    def png_chunk(kind: bytes, payload: bytes) -> bytes:
        checksum = binascii.crc32(kind)
        checksum = binascii.crc32(payload, checksum) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
    png.extend(png_chunk(b"IDAT", zlib.compress(bytes(scanline), level=9)))
    png.extend(png_chunk(b"IEND", b""))
    PALETTE_PATH.write_bytes(png)

    image = bpy.data.images.load(str(PALETTE_PATH), check_existing=False)
    image.name = "PokemonCenterDoorsPalette"
    image.colorspace_settings.name = "sRGB"
    return image


def create_material(image: bpy.types.Image) -> bpy.types.Material:
    material = bpy.data.materials.new("Pokemon Center Doors Palette")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = 0.52
    principled.inputs["Metallic"].default_value = 0.04
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "Doors Palette"
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "EXTEND"
    links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    return material


def add_street_door_set(
    builder: MeshBuilder,
    facade: str,
    opening_minimum: float,
    opening_maximum: float,
) -> None:
    """Add a four-panel automatic storefront with paired center leaves."""
    left = opening_minimum - FRAME_OVERLAP
    right = opening_maximum + FRAME_OVERLAP

    builder.add_rectangle(
        facade,
        left,
        right,
        DOOR_BOTTOM,
        DOOR_TOP,
        0.000,
        "charcoal",
        allow_building_overlap=True,
    )
    builder.add_rectangle(
        facade,
        left + 0.040,
        right - 0.040,
        DOOR_BOTTOM + 0.040,
        DOOR_TOP - 0.040,
        0.006,
        "ivory",
        allow_building_overlap=True,
    )

    inner_left = left + 0.090
    inner_right = right - 0.090
    inner_bottom = DOOR_BOTTOM + 0.090
    inner_top = DOOR_TOP - 0.090
    builder.add_rectangle(
        facade,
        inner_left,
        inner_right,
        inner_bottom,
        inner_top,
        0.012,
        "glass",
    )

    width = inner_right - inner_left
    divisions = [
        inner_left + width * 0.25,
        inner_left + width * 0.50,
        inner_left + width * 0.75,
    ]
    for index, division in enumerate(divisions):
        half_width = 0.028 if index == 1 else 0.020
        builder.add_rectangle(
            facade,
            division - half_width,
            division + half_width,
            inner_bottom,
            inner_top,
            0.018,
            "charcoal",
        )

    # Separate kick plates make all four panels legible. The middle pair are
    # the automatic leaves; the outside pair are fixed sidelights.
    panel_edges = [inner_left, *divisions, inner_right]
    for index in range(4):
        builder.add_rectangle(
            facade,
            panel_edges[index] + 0.025,
            panel_edges[index + 1] - 0.025,
            inner_bottom + 0.025,
            0.720,
            0.020,
            "charcoal",
        )

    center = divisions[1]
    builder.add_rectangle(
        facade,
        divisions[0] + 0.060,
        center - 0.070,
        1.180,
        1.250,
        0.024,
        "red",
    )
    builder.add_rectangle(
        facade,
        center + 0.070,
        divisions[2] - 0.060,
        1.180,
        1.250,
        0.024,
        "red",
    )
    builder.add_rectangle(
        facade,
        center - 0.125,
        center - 0.080,
        1.380,
        1.720,
        0.027,
        "ivory",
    )
    builder.add_rectangle(
        facade,
        center + 0.080,
        center + 0.125,
        1.380,
        1.720,
        0.027,
        "ivory",
    )


def create_doors() -> bpy.types.Object:
    builder = MeshBuilder()
    add_street_door_set(
        builder,
        "south",
        SOUTH_OPENING_MIN,
        SOUTH_OPENING_MAX,
    )
    add_street_door_set(
        builder,
        "east",
        EAST_OPENING_MIN,
        EAST_OPENING_MAX,
    )

    mesh = bpy.data.meshes.new("PokemonCenterDoorsMesh")
    mesh.from_pydata(builder.vertices, [], builder.faces)
    mesh.materials.append(create_material(create_palette()))
    mesh.update()

    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon, swatch in zip(mesh.polygons, builder.swatches, strict=True):
        uv = SWATCH_UV[swatch]
        for loop_index in polygon.loop_indices:
            uv_layer.data[loop_index].uv = uv

    doors = bpy.data.objects.new("PokemonCenterDoors", mesh)
    bpy.context.scene.collection.objects.link(doors)
    doors["fit_source"] = (
        "Measured south and east street openings of t1_b_pokemon_center_out"
    )
    doors["mobile_web_asset"] = True
    doors["opaque_stylized_glass"] = True
    doors["collision_intentionally_omitted"] = True
    doors["allowed_building_overlap_faces"] = sorted(
        builder.allowed_building_overlap_faces
    )
    return doors


def export_doors(doors: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    doors.select_set(True)
    bpy.context.view_layer.objects.active = doors
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


def object_world_bvh(
    obj: bpy.types.Object,
    excluded_polygon_indices: set[int] | None = None,
) -> BVHTree:
    mesh = obj.data
    mesh.calc_loop_triangles()
    vertices = [obj.matrix_world @ vertex.co for vertex in mesh.vertices]
    excluded = excluded_polygon_indices or set()
    triangles = [
        tuple(triangle.vertices)
        for triangle in mesh.loop_triangles
        if triangle.polygon_index not in excluded
    ]
    return BVHTree.FromPolygons(vertices, triangles, all_triangles=True, epsilon=0.00001)


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_context(doors: bpy.types.Object) -> None:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(BUILDING_PATH))
    imported_building = [obj for obj in bpy.context.scene.objects if obj not in before]
    building_set = set(imported_building)
    for root in (obj for obj in imported_building if obj.parent not in building_set):
        root.scale = (IMPORT_SCALE, IMPORT_SCALE, IMPORT_SCALE)
        root.location *= IMPORT_SCALE

    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOF_PATH))
    imported_roof = [obj for obj in bpy.context.scene.objects if obj not in before]
    bpy.context.view_layer.update()

    allowed_overlap_faces = set(doors["allowed_building_overlap_faces"])
    door_bvh = object_world_bvh(doors, allowed_overlap_faces)
    intersections = sum(
        len(door_bvh.overlap(object_world_bvh(obj)))
        for obj in imported_building
        if obj.type == "MESH"
    )
    if intersections:
        raise RuntimeError(
            "Non-frame door geometry intersects the source building in "
            f"{intersections} triangle pairs."
        )

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = str(PREVIEW_PATH)

    world = bpy.data.worlds.new("PokemonCenterDoorsPreviewWorld")
    world.use_nodes = True
    scene.world = world
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.045, 0.060, 0.085, 1.0)
    background.inputs["Strength"].default_value = 0.75

    target = Vector((-0.26, -3.03, 1.45))
    camera_data = bpy.data.cameras.new("PokemonCenterDoorsPreviewCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 5.0
    camera = bpy.data.objects.new("PokemonCenterDoorsPreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (-0.26, -12.0, 2.8)
    look_at(camera, target)
    scene.camera = camera

    light_data = bpy.data.lights.new("PokemonCenterDoorsPreviewLight", "AREA")
    light_data.energy = 1100.0
    light_data.shape = "DISK"
    light_data.size = 5.0
    light = bpy.data.objects.new("PokemonCenterDoorsPreviewLight", light_data)
    scene.collection.objects.link(light)
    light.location = (-3.5, -8.0, 6.5)
    look_at(light, target)

    bpy.ops.render.render(write_still=True)


def main() -> None:
    clear_scene()
    doors = create_doors()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    export_doors(doors)
    render_context(doors)
    triangles = sum(len(polygon.vertices) - 2 for polygon in doors.data.polygons)
    print(
        f"Exported {OUTPUT_GLB}: {len(doors.data.vertices)} vertices, "
        f"{triangles} triangles, 1 opaque material"
    )
    print(f"Rendered {PREVIEW_PATH}")


if __name__ == "__main__":
    main()
