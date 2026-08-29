"""Conform a Hunyuan roof donor to the measured Pokemon Center rim.

Run from the repository root after Hunyuan generation:

    blender --background --factory-startup \
        --python source_assets/pokemon_center_roof/finalize_pokemon_center_roof.py \
        -- source_assets/pokemon_center_roof/hunyuan_output/roof_candidate_seed_731903.glb

Hunyuan supplies a small, bounded shape signature for the upper silhouette.
The mounting edge always comes from the measured building rim so generative
noise cannot cause gaps. The result is one opaque, atlas-colored mesh with no
collision, suitable for the mobile/web renderer.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import binascii
import math
import struct
import sys
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
OUTPUT_GLB = RUNTIME_DIR / "pokemon_center_roof.glb"
PALETTE_PATH = SOURCE_DIR / "pokemon_center_roof_palette.png"
OUTPUT_BLEND = SOURCE_DIR / "pokemon_center_roof_final.blend"
PREVIEW_PATH = SOURCE_DIR / "pokemon_center_roof_final_context.png"
TOP_PREVIEW_PATH = SOURCE_DIR / "pokemon_center_roof_final_top.png"

IMPORT_SCALE = 0.75
WALL_TOP_HEIGHT = 4.0 * IMPORT_SCALE
BUILDING_MAX_HEIGHT = 5.9097 * IMPORT_SCALE
EAVE_BOTTOM_HEIGHT = BUILDING_MAX_HEIGHT + 0.080
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

SWATCH_UV = {
    "red": (0.16, 0.5),
    "ivory": (0.50, 0.5),
    "charcoal": (0.84, 0.5),
}
SWATCH_COLORS = {
    "red": (0.63, 0.018, 0.028, 1.0),
    "ivory": (0.72, 0.69, 0.62, 1.0),
    "charcoal": (0.025, 0.040, 0.060, 1.0),
}


@dataclass(frozen=True)
class DonorSignature:
    seed: str
    middle_scale: float
    top_scale: float
    pitch_adjustment: float
    skylight_offset: Vector
    normalized_height: float


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((len(ordered) - 1) * fraction)))
    return ordered[index]


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def polygon_centroid(points: list[Vector]) -> Vector:
    area_twice = 0.0
    center = Vector((0.0, 0.0))
    for index, point in enumerate(points):
        following = points[(index + 1) % len(points)]
        cross = point.x * following.y - following.x * point.y
        area_twice += cross
        center.x += (point.x + following.x) * cross
        center.y += (point.y + following.y) * cross
    if abs(area_twice) <= 0.000001:
        return sum(points, Vector()) / len(points)
    return center / (3.0 * area_twice)


def scale_polygon(points: list[Vector], factor: float) -> list[Vector]:
    center = polygon_centroid(points)
    return [center + (point - center) * factor for point in points]


def load_donor_signature(candidate_path: Path) -> DonorSignature:
    if not candidate_path.is_file():
        raise FileNotFoundError(f"Hunyuan candidate not found: {candidate_path}")

    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(candidate_path))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    vertices: list[Vector] = []
    for obj in imported:
        if obj.type != "MESH":
            continue
        vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
    if len(vertices) < 16:
        raise RuntimeError(f"Hunyuan candidate has too little geometry: {candidate_path}")

    xs = [point.x for point in vertices]
    ys = [point.y for point in vertices]
    zs = [point.z for point in vertices]
    x_span = max(xs) - min(xs)
    y_span = max(ys) - min(ys)
    z_span = max(zs) - min(zs)
    horizontal_span = max(x_span, y_span, 0.000001)
    normalized_height = z_span / horizontal_span

    z_mid = percentile(zs, 0.58)
    z_top = percentile(zs, 0.82)
    middle = [point for point in vertices if point.z >= z_mid]
    top = [point for point in vertices if point.z >= z_top]

    def normalized_span(points: list[Vector]) -> float:
        span_x = max(point.x for point in points) - min(point.x for point in points)
        span_y = max(point.y for point in points) - min(point.y for point in points)
        return (span_x / max(x_span, 0.000001) + span_y / max(y_span, 0.000001)) * 0.5

    # The donor can nudge only the safe upper silhouette. These narrow clamps
    # keep the authored proportions intact even when the generated mesh has
    # floaters, a noisy back face, or exaggerated thickness.
    middle_scale = clamp(0.76 + (normalized_span(middle) - 0.62) * 0.08, 0.74, 0.80)
    top_scale = clamp(0.56 + (normalized_span(top) - 0.42) * 0.06, 0.54, 0.60)
    pitch_adjustment = clamp((normalized_height - 0.28) * 0.060, -0.030, 0.040)

    all_center = Vector((sum(xs) / len(xs), sum(ys) / len(ys)))
    top_center = Vector(
        (
            sum(point.x for point in top) / len(top),
            sum(point.y for point in top) / len(top),
        )
    )
    raw_offset = Vector(
        (
            (top_center.x - all_center.x) / max(x_span, 0.000001),
            (top_center.y - all_center.y) / max(y_span, 0.000001),
        )
    )
    skylight_offset = Vector(
        (
            clamp(raw_offset.x * 0.12, -0.045, 0.045),
            clamp(raw_offset.y * 0.12, -0.045, 0.045),
        )
    )

    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)

    seed = candidate_path.stem.removeprefix("roof_candidate_seed_")
    return DonorSignature(
        seed=seed,
        middle_scale=middle_scale,
        top_scale=top_scale,
        pitch_adjustment=pitch_adjustment,
        skylight_offset=skylight_offset,
        normalized_height=normalized_height,
    )


class MeshBuilder:
    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.swatches: list[str] = []
        self.smooth_faces: list[bool] = []

    def add_vertex(self, point: tuple[float, float, float]) -> int:
        self.vertices.append(point)
        return len(self.vertices) - 1

    def add_ring(self, points: list[Vector], height: float) -> list[int]:
        return [self.add_vertex((point.x, point.y, height)) for point in points]

    def add_circle_ring(self, center: Vector, radius: float, height: float, segments: int) -> list[int]:
        return [
            self.add_vertex(
                (
                    center.x + math.cos(math.tau * index / segments) * radius,
                    center.y + math.sin(math.tau * index / segments) * radius,
                    height,
                )
            )
            for index in range(segments)
        ]

    def add_face(self, face: tuple[int, ...], swatch: str, *, smooth: bool = False) -> None:
        self.faces.append(face)
        self.swatches.append(swatch)
        self.smooth_faces.append(smooth)

    def bridge(self, lower: list[int], upper: list[int], swatch: str, *, smooth: bool = False) -> None:
        for index in range(len(lower)):
            following = (index + 1) % len(lower)
            self.add_face(
                (lower[index], lower[following], upper[following], upper[index]),
                swatch,
                smooth=smooth,
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

    for _y in range(height):
        scanline.append(0)  # PNG filter type: None.
        for x in range(width):
            if x < 21:
                color = SWATCH_COLORS["red"]
            elif x < 43:
                color = SWATCH_COLORS["ivory"]
            else:
                color = SWATCH_COLORS["charcoal"]
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
    image.name = "PokemonCenterRoofPalette"
    image.colorspace_settings.name = "sRGB"
    return image


def create_material(image: bpy.types.Image) -> bpy.types.Material:
    material = bpy.data.materials.new("Pokemon Center Roof Palette")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = 0.72
    principled.inputs["Metallic"].default_value = 0.02
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "Roof Palette"
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "EXTEND"
    links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    return material


def create_roof(signature: DonorSignature) -> bpy.types.Object:
    builder = MeshBuilder()
    center = polygon_centroid(FOOTPRINT)
    # Keep a dark supporting drum behind the facade emblems. The broad eave
    # starts above the building's highest source vertex and overhangs the full
    # plan envelope, which guarantees coverage without crossing an emblem.
    drum = scale_polygon(FOOTPRINT, 0.70)
    eave = scale_polygon(FOOTPRINT, 1.025)
    middle = scale_polygon(FOOTPRINT, signature.middle_scale)
    top = scale_polygon(FOOTPRINT, signature.top_scale)

    drum_bottom = builder.add_ring(drum, WALL_TOP_HEIGHT + 0.015)
    drum_top = builder.add_ring(drum, EAVE_BOTTOM_HEIGHT)
    eave_bottom = builder.add_ring(eave, EAVE_BOTTOM_HEIGHT + 0.040)
    eave_top = builder.add_ring(eave, EAVE_BOTTOM_HEIGHT + 0.180)
    middle_ring = builder.add_ring(
        middle,
        EAVE_BOTTOM_HEIGHT + 0.900 + signature.pitch_adjustment,
    )
    crown_ring = builder.add_ring(
        top,
        EAVE_BOTTOM_HEIGHT + 1.170 + signature.pitch_adjustment * 0.5,
    )
    cap_ring = builder.add_ring(
        top,
        EAVE_BOTTOM_HEIGHT + 1.330 + signature.pitch_adjustment * 0.5,
    )

    builder.bridge(drum_bottom, drum_top, "charcoal")
    builder.bridge(drum_top, eave_bottom, "red")
    builder.bridge(eave_bottom, eave_top, "red")
    builder.bridge(eave_top, middle_ring, "ivory")
    builder.bridge(middle_ring, crown_ring, "charcoal")
    builder.bridge(crown_ring, cap_ring, "ivory")
    builder.add_face(tuple(cap_ring), "ivory")

    skylight_center = center + signature.skylight_offset
    segments = 20
    red_bottom = builder.add_circle_ring(
        skylight_center,
        0.50,
        EAVE_BOTTOM_HEIGHT + 1.330 + signature.pitch_adjustment * 0.5,
        segments,
    )
    red_top = builder.add_circle_ring(
        skylight_center,
        0.50,
        EAVE_BOTTOM_HEIGHT + 1.550 + signature.pitch_adjustment * 0.5,
        segments,
    )
    inset_bottom = builder.add_circle_ring(
        skylight_center,
        0.34,
        EAVE_BOTTOM_HEIGHT + 1.549 + signature.pitch_adjustment * 0.5,
        segments,
    )
    inset_top = builder.add_circle_ring(
        skylight_center,
        0.34,
        EAVE_BOTTOM_HEIGHT + 1.630 + signature.pitch_adjustment * 0.5,
        segments,
    )
    builder.bridge(red_bottom, red_top, "red", smooth=True)
    builder.bridge(red_top, inset_bottom, "red")
    builder.bridge(inset_bottom, inset_top, "charcoal", smooth=True)
    builder.add_face(tuple(inset_top), "charcoal")

    mesh = bpy.data.meshes.new("PokemonCenterRoofMesh")
    mesh.from_pydata(builder.vertices, [], builder.faces)
    mesh.materials.append(create_material(create_palette()))
    mesh.update()

    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon, swatch, use_smooth in zip(
        mesh.polygons,
        builder.swatches,
        builder.smooth_faces,
        strict=True,
    ):
        polygon.use_smooth = use_smooth
        uv = SWATCH_UV[swatch]
        for loop_index in polygon.loop_indices:
            uv_layer.data[loop_index].uv = uv

    roof = bpy.data.objects.new("PokemonCenterRoof", mesh)
    bpy.context.scene.collection.objects.link(roof)
    roof["generator"] = "Tencent Hunyuan3D-2mv donor conformed to full model envelope"
    roof["hunyuan_seed"] = signature.seed
    roof["hunyuan_normalized_height"] = round(signature.normalized_height, 6)
    roof["mobile_web_asset"] = True
    roof["collision_intentionally_omitted"] = True
    return roof


def export_roof(roof: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    roof.select_set(True)
    bpy.context.view_layer.objects.active = roof
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


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def object_world_bvh(obj: bpy.types.Object) -> BVHTree:
    mesh = obj.data
    mesh.calc_loop_triangles()
    vertices = [obj.matrix_world @ vertex.co for vertex in mesh.vertices]
    triangles = [tuple(triangle.vertices) for triangle in mesh.loop_triangles]
    return BVHTree.FromPolygons(vertices, triangles, all_triangles=True, epsilon=0.00001)


def validate_context_fit(roof: bpy.types.Object, imported: list[bpy.types.Object]) -> None:
    building_meshes = [obj for obj in imported if obj.type == "MESH"]
    building_points = [
        obj.matrix_world @ vertex.co
        for obj in building_meshes
        for vertex in obj.data.vertices
    ]
    if not building_points:
        raise RuntimeError("Imported Pokemon Center contains no mesh vertices.")

    building_min_x = min(point.x for point in building_points)
    building_max_x = max(point.x for point in building_points)
    building_min_y = min(point.y for point in building_points)
    building_max_y = max(point.y for point in building_points)
    building_max_z = max(point.z for point in building_points)
    eave = scale_polygon(FOOTPRINT, 1.025)
    if not (
        min(point.x for point in eave) <= building_min_x - 0.05
        and max(point.x for point in eave) >= building_max_x + 0.05
        and min(point.y for point in eave) <= building_min_y - 0.05
        and max(point.y for point in eave) >= building_max_y + 0.05
    ):
        raise RuntimeError(
            "Roof eave does not overhang all four building plan bounds: "
            f"building x=({building_min_x:.3f}, {building_max_x:.3f}), "
            f"y=({building_min_y:.3f}, {building_max_y:.3f})."
        )
    if EAVE_BOTTOM_HEIGHT < building_max_z + 0.05:
        raise RuntimeError(
            f"Roof eave at {EAVE_BOTTOM_HEIGHT:.3f} m does not clear the "
            f"building maximum {building_max_z:.3f} m."
        )

    roof_bvh = object_world_bvh(roof)
    intersections = sum(
        len(roof_bvh.overlap(object_world_bvh(building)))
        for building in building_meshes
    )
    if intersections:
        raise RuntimeError(
            f"Roof intersects the source building in {intersections} triangle pairs."
        )


def render_context(roof: bpy.types.Object) -> None:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(BUILDING_PATH))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    imported_set = set(imported)
    for root in (obj for obj in imported if obj.parent not in imported_set):
        root.scale = (IMPORT_SCALE, IMPORT_SCALE, IMPORT_SCALE)
        # Match Godot's root-scale import, which also scales node translation.
        root.location *= IMPORT_SCALE

    bpy.context.view_layer.update()
    validate_context_fit(roof, imported)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.film_transparent = False

    world = bpy.data.worlds.new("PokemonCenterRoofPreviewWorld")
    world.use_nodes = True
    scene.world = world
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.055, 0.075, 0.11, 1.0)
    background.inputs["Strength"].default_value = 0.55

    camera_data = bpy.data.cameras.new("PokemonCenterRoofPreviewCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 12.0
    camera = bpy.data.objects.new("PokemonCenterRoofPreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (11.5, -11.5, 8.4)
    look_at(camera, Vector((0.0, 0.0, 2.35)))
    scene.camera = camera

    sun_data = bpy.data.lights.new("PokemonCenterRoofPreviewSun", "SUN")
    sun_data.energy = 2.2
    sun_data.color = (1.0, 0.91, 0.76)
    sun = bpy.data.objects.new("PokemonCenterRoofPreviewSun", sun_data)
    sun.rotation_euler = (
        math.radians(32.0),
        math.radians(-18.0),
        math.radians(-38.0),
    )
    scene.collection.objects.link(sun)

    fill_data = bpy.data.lights.new("PokemonCenterRoofPreviewFill", "AREA")
    fill_data.energy = 850.0
    fill_data.shape = "DISK"
    fill_data.size = 7.0
    fill_data.color = (0.60, 0.73, 1.0)
    fill = bpy.data.objects.new("PokemonCenterRoofPreviewFill", fill_data)
    fill.location = (-5.0, 4.0, 9.0)
    look_at(fill, Vector((0.0, 0.0, WALL_TOP_HEIGHT)))
    scene.collection.objects.link(fill)

    roof.hide_render = False
    bpy.ops.render.render(write_still=True)

    center = polygon_centroid(FOOTPRINT)
    camera_data.ortho_scale = 9.5
    camera.location = (center.x, center.y, 16.0)
    look_at(camera, Vector((center.x, center.y, WALL_TOP_HEIGHT)))
    scene.render.filepath = str(TOP_PREVIEW_PATH)
    bpy.ops.render.render(write_still=True)


def candidate_argument() -> Path:
    if "--" not in sys.argv:
        raise RuntimeError("Pass one selected Hunyuan candidate after Blender's -- separator.")
    arguments = sys.argv[sys.argv.index("--") + 1 :]
    if len(arguments) != 1:
        raise RuntimeError("Expected exactly one Hunyuan candidate GLB path.")
    candidate = Path(arguments[0])
    if not candidate.is_absolute():
        candidate = PROJECT_ROOT / candidate
    return candidate.resolve()


def main() -> None:
    clear_scene()
    candidate = candidate_argument()
    signature = load_donor_signature(candidate)
    roof = create_roof(signature)
    bpy.context.scene["hunyuan_candidate"] = str(candidate.relative_to(PROJECT_ROOT))
    bpy.context.scene["hunyuan_seed"] = signature.seed
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    export_roof(roof)
    render_context(roof)
    triangles = sum(len(polygon.vertices) - 2 for polygon in roof.data.polygons)
    print(
        f"Exported {OUTPUT_GLB}: {len(roof.data.vertices)} vertices, "
        f"{triangles} triangles, 1 material; Hunyuan seed {signature.seed}"
    )
    print(f"Rendered {PREVIEW_PATH}")
    print(f"Rendered {TOP_PREVIEW_PATH}")


if __name__ == "__main__":
    main()
