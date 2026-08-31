"""Build the mobile-safe Pokemon Center interior environment GLB.

Run from the repository root with:

    blender --background --factory-startup \
        --python source_assets/pokemon_center_interior/create_pokemon_center_interior.py

The room is authored in final Godot meters. Its five-sided cutaway footprint
echoes the exterior building. A tiny opaque palette and one compact opaque
brick texture keep its classical masonry treatment inexpensive on mobile web.
"""

from __future__ import annotations

from pathlib import Path
import binascii
import math
import struct
import zlib

import bpy
from mathutils import Vector


SCRIPT_PATH = Path(__file__).resolve()
PROJECT_ROOT = SCRIPT_PATH.parents[2]
SOURCE_DIR = SCRIPT_PATH.parent
RUNTIME_DIR = (
    PROJECT_ROOT
    / "art/environments/new_bouffalant_city/pokemon_center_interior"
)
OUTPUT_GLB = RUNTIME_DIR / "pokemon_center_interior_environment.glb"
PALETTE_PATH = SOURCE_DIR / "pokemon_center_interior_palette.png"
BRICK_TEXTURE_PATH = SOURCE_DIR / "pokemon_center_classic_brick.png"
OUTPUT_BLEND = SOURCE_DIR / "pokemon_center_interior.blend"
PREVIEW_PATH = SOURCE_DIR / "pokemon_center_interior_preview.png"

BRICK_TILE_WIDTH_METERS = 3.20
BRICK_TILE_HEIGHT_METERS = 1.60

ROOM_FOOTPRINT = [
    (-6.0, -5.0),
    (3.0, -5.0),
    (6.0, -2.0),
    (6.0, 5.0),
    (-6.0, 5.0),
]

SWATCH_ORDER = [
    "charcoal",
    "navy",
    "cyan",
    "pale",
    "ivory",
    "red",
    "pink",
    "green",
]
SWATCH_COLORS = {
    "charcoal": (0.040, 0.022, 0.012, 1.0),
    "navy": (0.025, 0.075, 0.120, 1.0),
    "cyan": (0.055, 0.390, 0.500, 1.0),
    "pale": (0.340, 0.320, 0.270, 1.0),
    "ivory": (0.550, 0.460, 0.310, 1.0),
    "red": (0.720, 0.025, 0.045, 1.0),
    "pink": (0.950, 0.110, 0.210, 1.0),
    "green": (0.160, 0.480, 0.180, 1.0),
}
SWATCH_UV = {
    name: ((index + 0.5) / len(SWATCH_ORDER), 0.5)
    for index, name in enumerate(SWATCH_ORDER)
}


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def rotate_xy(point: tuple[float, float, float], angle: float) -> tuple[float, float, float]:
    cosine = math.cos(angle)
    sine = math.sin(angle)
    return (
        point[0] * cosine - point[1] * sine,
        point[0] * sine + point[1] * cosine,
        point[2],
    )


class MeshBuilder:
    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.swatches: list[str] = []
        self.material_kinds: list[str] = []
        self.face_uvs: list[list[tuple[float, float]] | None] = []

    def add_face(
        self,
        points: list[tuple[float, float, float]],
        swatch: str,
        material_kind: str = "palette",
        uvs: list[tuple[float, float]] | None = None,
    ) -> None:
        if uvs is not None and len(uvs) != len(points):
            raise ValueError("A face must have one UV coordinate per point")
        start = len(self.vertices)
        self.vertices.extend(points)
        self.faces.append(tuple(range(start, len(self.vertices))))
        self.swatches.append(swatch)
        self.material_kinds.append(material_kind)
        self.face_uvs.append(uvs)

    def add_box(
        self,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        swatch: str,
        rotation_z: float = 0.0,
        material_kind: str = "palette",
    ) -> None:
        half_x, half_y, half_z = (component * 0.5 for component in size)
        local = [
            (-half_x, -half_y, -half_z),
            (half_x, -half_y, -half_z),
            (half_x, half_y, -half_z),
            (-half_x, half_y, -half_z),
            (-half_x, -half_y, half_z),
            (half_x, -half_y, half_z),
            (half_x, half_y, half_z),
            (-half_x, half_y, half_z),
        ]
        points = []
        for point in local:
            rotated = rotate_xy(point, rotation_z)
            points.append(
                (
                    center[0] + rotated[0],
                    center[1] + rotated[1],
                    center[2] + rotated[2],
                )
            )
        face_specs = [
            ((0, 3, 2, 1), "horizontal"),
            ((4, 5, 6, 7), "horizontal"),
            ((0, 1, 5, 4), "x_vertical"),
            ((1, 2, 6, 5), "y_vertical"),
            ((2, 3, 7, 6), "x_vertical"),
            ((3, 0, 4, 7), "y_vertical"),
        ]
        for indices, projection in face_specs:
            face_uvs = None
            if material_kind == "brick":
                local_points = [local[index] for index in indices]
                if projection == "horizontal":
                    face_uvs = [
                        (
                            point[0] / BRICK_TILE_WIDTH_METERS,
                            point[1] / BRICK_TILE_WIDTH_METERS,
                        )
                        for point in local_points
                    ]
                elif projection == "x_vertical":
                    face_uvs = [
                        (
                            point[0] / BRICK_TILE_WIDTH_METERS,
                            point[2] / BRICK_TILE_HEIGHT_METERS,
                        )
                        for point in local_points
                    ]
                else:
                    face_uvs = [
                        (
                            point[1] / BRICK_TILE_WIDTH_METERS,
                            point[2] / BRICK_TILE_HEIGHT_METERS,
                        )
                        for point in local_points
                    ]
            self.add_face(
                [points[index] for index in indices],
                swatch,
                material_kind,
                face_uvs,
            )

    def add_plane(
        self,
        left: float,
        right: float,
        front: float,
        back: float,
        height: float,
        swatch: str,
    ) -> None:
        self.add_face(
            [
                (left, front, height),
                (right, front, height),
                (right, back, height),
                (left, back, height),
            ],
            swatch,
        )

    def add_horizontal_disc(
        self,
        center: tuple[float, float, float],
        radius: float,
        swatch: str,
        segments: int = 16,
    ) -> None:
        self.add_face(
            [
                (
                    center[0] + math.cos(math.tau * index / segments) * radius,
                    center[1] + math.sin(math.tau * index / segments) * radius,
                    center[2],
                )
                for index in range(segments)
            ],
            swatch,
        )

    def add_front_disc(
        self,
        center: tuple[float, float, float],
        radius: float,
        swatch: str,
        segments: int = 16,
    ) -> None:
        self.add_face(
            [
                (
                    center[0] + math.cos(math.tau * index / segments) * radius,
                    center[1],
                    center[2] + math.sin(math.tau * index / segments) * radius,
                )
                for index in range(segments)
            ],
            swatch,
        )

    def add_prism(
        self,
        center: tuple[float, float, float],
        bottom_radius: float,
        top_radius: float,
        height: float,
        swatch: str,
        segments: int = 8,
    ) -> None:
        bottom_height = center[2] - height * 0.5
        top_height = center[2] + height * 0.5
        bottom = []
        top = []
        for index in range(segments):
            angle = math.tau * index / segments
            bottom.append(
                (
                    center[0] + math.cos(angle) * bottom_radius,
                    center[1] + math.sin(angle) * bottom_radius,
                    bottom_height,
                )
            )
            top.append(
                (
                    center[0] + math.cos(angle) * top_radius,
                    center[1] + math.sin(angle) * top_radius,
                    top_height,
                )
            )
        self.add_face(list(reversed(bottom)), swatch)
        self.add_face(top, swatch)
        for index in range(segments):
            following = (index + 1) % segments
            self.add_face(
                [bottom[index], bottom[following], top[following], top[index]],
                swatch,
            )


def create_palette() -> bpy.types.Image:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    width = 128
    height = 16
    swatch_width = width // len(SWATCH_ORDER)
    scanlines = bytearray()

    def linear_to_srgb_byte(value: float) -> int:
        if value <= 0.0031308:
            encoded = value * 12.92
        else:
            encoded = 1.055 * value ** (1.0 / 2.4) - 0.055
        return round(clamp(encoded, 0.0, 1.0) * 255.0)

    for _y in range(height):
        scanlines.append(0)
        for x in range(width):
            color = SWATCH_COLORS[
                SWATCH_ORDER[min(len(SWATCH_ORDER) - 1, x // swatch_width)]
            ]
            scanlines.extend(linear_to_srgb_byte(channel) for channel in color)

    def png_chunk(kind: bytes, payload: bytes) -> bytes:
        checksum = binascii.crc32(kind)
        checksum = binascii.crc32(payload, checksum) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(
        png_chunk(
            b"IHDR",
            struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0),
        )
    )
    png.extend(png_chunk(b"IDAT", zlib.compress(bytes(scanlines), level=9)))
    png.extend(png_chunk(b"IEND", b""))
    PALETTE_PATH.write_bytes(png)

    image = bpy.data.images.load(str(PALETTE_PATH), check_existing=False)
    image.name = "PokemonCenterInteriorPalette"
    image.colorspace_settings.name = "sRGB"
    return image


def create_palette_material(image: bpy.types.Image) -> bpy.types.Material:
    material = bpy.data.materials.new("Pokemon Center Interior Palette")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = 0.68
    principled.inputs["Metallic"].default_value = 0.02
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "Interior Palette"
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "EXTEND"
    links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    return material


def create_brick_material() -> bpy.types.Material:
    if not BRICK_TEXTURE_PATH.is_file():
        raise FileNotFoundError(f"Missing brick texture: {BRICK_TEXTURE_PATH}")

    image = bpy.data.images.load(str(BRICK_TEXTURE_PATH), check_existing=False)
    image.name = "PokemonCenterClassicBrick"
    image.colorspace_settings.name = "sRGB"

    material = bpy.data.materials.new("Pokemon Center Classic Brick")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = 0.90
    principled.inputs["Metallic"].default_value = 0.0
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "Classic Brick Albedo"
    texture.image = image
    texture.interpolation = "Linear"
    texture.extension = "REPEAT"
    links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    return material


def add_room_shell(builder: MeshBuilder) -> None:
    builder.add_face([(x, y, 0.0) for x, y in ROOM_FOOTPRINT], "ivory")
    builder.add_face(
        [
            (-5.62, -4.62, 0.012),
            (2.84, -4.62, 0.012),
            (5.62, -1.84, 0.012),
            (5.62, 4.62, 0.012),
            (-5.62, 4.62, 0.012),
        ],
        "pale",
    )

    # Broad tile lines support navigation without relying on a noisy texture.
    for x in [-4.0, -2.0, 2.0, 4.0]:
        front = -4.45 if x <= 2.0 else -1.55
        builder.add_plane(x - 0.018, x + 0.018, front, 4.45, 0.018, "ivory")
    for y, right in [(-3.0, 4.85), (-1.0, 5.4), (1.0, 5.4), (3.0, 5.4)]:
        builder.add_plane(-5.4, right, y - 0.018, y + 0.018, 0.018, "ivory")

    # Entrance path and floor emblem establish an immediate visual route.
    builder.add_plane(-1.42, 1.42, -4.72, 2.25, 0.024, "ivory")
    builder.add_plane(-1.32, -1.20, -4.62, 2.15, 0.030, "red")
    builder.add_plane(1.20, 1.32, -4.62, 2.15, 0.030, "red")
    builder.add_horizontal_disc((0.0, 0.20, 0.034), 1.02, "red", 20)
    builder.add_horizontal_disc((0.0, 0.20, 0.040), 0.68, "ivory", 20)
    builder.add_horizontal_disc((0.0, 0.20, 0.046), 0.31, "navy", 16)
    builder.add_plane(-0.92, 0.92, 0.12, 0.28, 0.052, "navy")

    wall_height = 3.20
    builder.add_box(
        (0.0, 5.0, wall_height * 0.5),
        (12.0, 0.26, wall_height),
        "ivory",
        material_kind="brick",
    )
    builder.add_box(
        (-6.0, 0.0, wall_height * 0.5),
        (0.26, 10.0, wall_height),
        "ivory",
        material_kind="brick",
    )
    builder.add_box(
        (6.0, 1.5, wall_height * 0.5),
        (0.26, 7.0, wall_height),
        "ivory",
        material_kind="brick",
    )
    # Low cutaway front and chamfer walls preserve the existing gameplay
    # camera view while retaining the exterior building's five-sided plan.
    builder.add_box(
        (4.5, -3.5, 0.45),
        (4.25, 0.26, 0.90),
        "ivory",
        rotation_z=math.radians(45.0),
        material_kind="brick",
    )
    builder.add_box(
        (-3.8, -5.0, 0.45),
        (4.4, 0.26, 0.90),
        "ivory",
        material_kind="brick",
    )
    builder.add_box(
        (2.3, -5.0, 0.45),
        (1.4, 0.26, 0.90),
        "ivory",
        material_kind="brick",
    )

    # Dark walnut wainscot and worn limestone trim sell an older civic shell;
    # the small red rail keeps it recognizably part of the Pokemon Center.
    builder.add_box((0.0, 4.82, 0.55), (11.55, 0.08, 1.02), "charcoal")
    builder.add_box((-5.82, 0.0, 0.55), (0.08, 9.55, 1.02), "charcoal")
    builder.add_box((5.82, 1.5, 0.55), (0.08, 6.55, 1.02), "charcoal")
    builder.add_box((0.0, 4.75, 1.08), (11.60, 0.12, 0.16), "ivory")
    builder.add_box((-5.75, 0.0, 1.08), (0.12, 9.60, 0.16), "ivory")
    builder.add_box((5.75, 1.5, 1.08), (0.12, 6.60, 0.16), "ivory")
    builder.add_box((0.0, 4.67, 1.08), (11.45, 0.04, 0.055), "red")
    builder.add_box((-5.67, 0.0, 1.08), (0.04, 9.45, 0.055), "red")
    builder.add_box((5.67, 1.5, 1.08), (0.04, 6.45, 0.055), "red")
    builder.add_box((0.0, 4.82, 3.02), (11.65, 0.12, 0.18), "ivory")
    builder.add_box((-5.82, 0.0, 3.02), (0.12, 9.65, 0.18), "ivory")
    builder.add_box((5.82, 1.5, 3.02), (0.12, 6.65, 0.18), "ivory")
    builder.add_box((-3.8, -4.82, 0.92), (4.4, 0.32, 0.14), "ivory")
    builder.add_box((2.3, -4.82, 0.92), (1.4, 0.32, 0.14), "ivory")
    builder.add_box(
        (4.46, -3.46, 0.92),
        (4.12, 0.30, 0.14),
        "ivory",
        rotation_z=math.radians(45.0),
    )


def add_classical_architecture(builder: MeshBuilder) -> None:
    """Layer readable, low-poly classical masonry over the old brick shell."""
    # Shallow pilasters and oversized capitals give the brick walls civic
    # rhythm without producing new collision or expensive separate meshes.
    for x in [-5.15, -3.15, 3.15, 5.15]:
        builder.add_box((x, 4.66, 2.02), (0.26, 0.18, 1.70), "ivory")
        builder.add_box((x, 4.62, 1.20), (0.43, 0.23, 0.18), "ivory")
        builder.add_box((x, 4.62, 2.90), (0.48, 0.23, 0.20), "ivory")
    for y in [-3.55, -1.20, 1.20, 3.55]:
        builder.add_box((-5.66, y, 2.02), (0.18, 0.26, 1.70), "ivory")
        builder.add_box((-5.62, y, 1.20), (0.23, 0.43, 0.18), "ivory")
        builder.add_box((-5.62, y, 2.90), (0.23, 0.48, 0.20), "ivory")
    for y in [-0.85, 1.45, 3.75]:
        builder.add_box((5.66, y, 2.02), (0.18, 0.26, 1.70), "ivory")
        builder.add_box((5.62, y, 1.20), (0.23, 0.43, 0.18), "ivory")
        builder.add_box((5.62, y, 2.90), (0.23, 0.48, 0.20), "ivory")

    # Sparse battens imply old paneled woodwork instead of adding high-detail
    # geometry or normal maps to every wall.
    for x in [-5.05, -4.05, -3.05, 3.05, 4.05, 5.05]:
        builder.add_box((x, 4.72, 0.54), (0.055, 0.05, 0.94), "ivory")
    for y in [-3.75, -2.25, -0.75, 0.75, 2.25, 3.75]:
        builder.add_box((-5.72, y, 0.54), (0.05, 0.055, 0.94), "ivory")


def add_healing_counter(builder: MeshBuilder) -> None:
    builder.add_box((0.0, 2.75, 0.48), (7.55, 1.25, 0.96), "charcoal")
    builder.add_box((0.0, 2.10, 0.60), (7.20, 0.08, 0.64), "red")
    builder.add_box((0.0, 2.75, 1.02), (7.82, 1.42, 0.16), "ivory")
    builder.add_box((-3.50, 2.04, 0.62), (0.28, 0.10, 0.72), "pink")
    builder.add_box((3.50, 2.04, 0.62), (0.28, 0.10, 0.72), "pink")
    for x in [-2.75, -1.38, 0.0, 1.38, 2.75]:
        builder.add_box((x, 2.03, 0.58), (0.075, 0.06, 0.60), "charcoal")
        builder.add_box((x, 2.01, 0.84), (1.08, 0.04, 0.06), "charcoal")

    # Back healing console: one large screen and emblem read at gameplay scale.
    builder.add_box((0.0, 4.48, 1.75), (4.10, 0.58, 2.42), "charcoal")
    builder.add_box((0.0, 4.15, 1.70), (2.82, 0.08, 1.05), "cyan")
    builder.add_box((0.0, 4.10, 2.55), (3.55, 0.10, 0.24), "red")
    builder.add_box((-2.55, 4.55, 1.42), (0.90, 0.54, 1.72), "navy")
    builder.add_box((2.55, 4.55, 1.42), (0.90, 0.54, 1.72), "navy")
    builder.add_front_disc((0.0, 4.08, 2.66), 0.58, "red", 18)
    builder.add_front_disc((0.0, 4.05, 2.66), 0.37, "ivory", 18)
    builder.add_front_disc((0.0, 4.02, 2.66), 0.16, "red", 14)
    builder.add_box((0.0, 3.99, 2.66), (1.02, 0.04, 0.10), "red")

    # Six simplified healing pods keep the classic clinic identity without
    # transparency, particles, animation, or extra materials.
    for x in [-2.40, -1.44, -0.48, 0.48, 1.44, 2.40]:
        builder.add_prism((x, 2.60, 1.22), 0.20, 0.17, 0.28, "ivory", 8)
        builder.add_prism((x, 2.60, 1.40), 0.13, 0.09, 0.12, "pink", 8)


def add_bench(builder: MeshBuilder, y: float) -> None:
    builder.add_box((-4.48, y, 0.47), (0.82, 2.34, 0.18), "charcoal")
    builder.add_box((-4.84, y, 0.94), (0.14, 2.34, 1.00), "charcoal")
    builder.add_box((-4.43, y, 0.59), (0.66, 2.08, 0.08), "red")
    builder.add_box((-4.48, y - 0.86, 0.23), (0.55, 0.16, 0.46), "ivory")
    builder.add_box((-4.48, y + 0.86, 0.23), (0.55, 0.16, 0.46), "ivory")


def add_terminal(builder: MeshBuilder) -> None:
    builder.add_box((4.45, -0.20, 0.68), (1.18, 1.02, 1.36), "navy")
    builder.add_box((3.82, -0.20, 1.00), (0.08, 0.76, 0.58), "cyan")
    builder.add_box((4.42, -0.20, 1.44), (1.30, 1.10, 0.16), "ivory")
    builder.add_box((4.42, -0.20, 1.58), (0.62, 0.42, 0.12), "red")
    builder.add_box((4.42, -0.20, 0.10), (1.34, 1.14, 0.20), "charcoal")


def add_planter(builder: MeshBuilder, x: float, y: float) -> None:
    builder.add_prism((x, y, 0.31), 0.42, 0.32, 0.62, "red", 8)
    builder.add_prism((x, y, 0.88), 0.20, 0.48, 0.66, "green", 8)
    builder.add_prism((x, y, 1.24), 0.40, 0.10, 0.46, "green", 8)


def add_identity_details(builder: MeshBuilder) -> None:
    add_bench(builder, -1.85)
    add_bench(builder, 0.90)
    add_terminal(builder)
    add_planter(builder, -5.05, -3.70)
    add_planter(builder, 4.72, 1.72)

    # Fracture blue and Revolt red panels make the shared civic identity part
    # of the room without turning a clinic into a propaganda-heavy space.
    builder.add_box((-3.75, 4.70, 2.05), (2.10, 0.08, 1.22), "cyan")
    builder.add_box((3.75, 4.70, 2.05), (2.10, 0.08, 1.22), "red")
    builder.add_box((-3.75, 4.64, 2.05), (0.16, 0.04, 0.90), "ivory")
    builder.add_box((3.75, 4.64, 2.05), (0.90, 0.04, 0.16), "ivory")

    # Large wall lamps are visual fixtures only; the Godot scene owns the two
    # inexpensive non-shadowed local lights used for mobile compatibility.
    for x in [-3.0, 3.0]:
        builder.add_box((x, 4.62, 2.92), (1.35, 0.10, 0.16), "pale")
        builder.add_box((x, 4.68, 2.78), (0.18, 0.12, 0.30), "ivory")


def create_environment() -> bpy.types.Object:
    builder = MeshBuilder()
    add_room_shell(builder)
    add_classical_architecture(builder)
    add_healing_counter(builder)
    add_identity_details(builder)

    mesh = bpy.data.meshes.new("PokemonCenterInteriorMesh")
    mesh.from_pydata(builder.vertices, [], builder.faces)
    mesh.materials.append(create_palette_material(create_palette()))
    mesh.materials.append(create_brick_material())
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
            custom_uvs = [SWATCH_UV[swatch]] * len(polygon.loop_indices)
        for loop_index, uv in zip(polygon.loop_indices, custom_uvs, strict=True):
            uv_layer.data[loop_index].uv = uv

    environment = bpy.data.objects.new("PokemonCenterInteriorEnvironment", mesh)
    bpy.context.scene.collection.objects.link(environment)
    environment["mobile_web_asset"] = True
    environment["opaque_material_draws"] = 2
    environment["classic_brick_texture"] = True
    environment["five_sided_exterior_echo"] = True
    environment["collision_authored_in_godot_scene"] = True
    return environment


def export_environment(environment: bpy.types.Object) -> None:
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


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_preview() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = str(PREVIEW_PATH)

    world = bpy.data.worlds.new("PokemonCenterInteriorPreviewWorld")
    world.use_nodes = True
    scene.world = world
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.045, 0.075, 0.12, 1.0)
    background.inputs["Strength"].default_value = 0.75

    target = Vector((0.0, 0.2, 1.05))
    camera_data = bpy.data.cameras.new("PokemonCenterInteriorPreviewCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 15.5
    camera = bpy.data.objects.new("PokemonCenterInteriorPreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (12.8, -16.8, 12.0)
    look_at(camera, target)
    scene.camera = camera

    key_data = bpy.data.lights.new("PokemonCenterInteriorPreviewKey", "AREA")
    key_data.energy = 1350.0
    key_data.shape = "DISK"
    key_data.size = 7.0
    key = bpy.data.objects.new("PokemonCenterInteriorPreviewKey", key_data)
    scene.collection.objects.link(key)
    key.location = (-4.0, -7.0, 11.0)
    look_at(key, target)

    fill_data = bpy.data.lights.new("PokemonCenterInteriorPreviewFill", "AREA")
    fill_data.energy = 700.0
    fill_data.size = 5.0
    fill = bpy.data.objects.new("PokemonCenterInteriorPreviewFill", fill_data)
    scene.collection.objects.link(fill)
    fill.location = (6.0, 2.0, 8.0)
    look_at(fill, target)

    bpy.ops.render.render(write_still=True)


def main() -> None:
    clear_scene()
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
