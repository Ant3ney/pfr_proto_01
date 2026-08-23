# Modular Ground Scale Guide

Yes. Lock the project scale before making any environment assets. I measured the uploaded model.glb, and it gives us a strong reference.


## 1. Your player model’s current scale


The model’s assembled bounds are approximately:

Measurement	Size
Height	1.6675 units
Maximum width	1.0747 units
Maximum depth	0.3680 units

The width includes the character’s extended arms/rest pose, so it is not the character’s normal walking width.

Treat the model as a 1.67-meter-tall character. This is ideal because Godot’s intended 3D scale is 1 unit = 1 meter. Godot also uses Y as up and the XZ plane as the ground. Its default visible editor grid is 1×1 meter.


### Important orientation warning


The uploaded GLB contains compensating X-axis rotations and its measured long axis currently runs along Z, not Y. That suggests the hierarchy may contain an axis-conversion setup.

Your production player should eventually import into Godot with:

Position: 0, 0, 0
Rotation: 0, 0, 0
Scale:    1, 1, 1
Feet:     Y = 0
Head:     Y ≈ 1.67

Use the current file as a size reference, but clean its orientation before treating it as the permanent project ruler.


## 2. The scale system I recommend


Use this as the official scale specification for the entire project:

1 Godot unit              = 1 meter
Player height             = 1.67 meters
Fine modeling increment   = 0.25 meters
General placement snap    = 0.50 meters
Terrain base cell         = 2 × 2 meters
Standard ground module    = 4 × 4 meters
Large ground module       = 8 × 8 meters
Terrain elevation tier    = 0.50 meters
Ground slab thickness     = 0.25 meters
Modular rotation          = 90 degrees

### Why a 2-meter terrain cell?


A 2-meter square is slightly wider than the height of your player. That gives you:

Enough room for unrestricted 360-degree movement.
Clear modular measurements.
Paths that do not feel cramped with your lower third-person camera.
Dimensions that divide cleanly into 0.25, 0.5, 1, 2, 4 and 8 meters.
Easy compatibility with Godot snapping and GridMap.

Your game is not using ORAS’s strict tile movement or its more elevated camera. Your lower camera requires somewhat wider routes and more breathing room. A literal one-meter Pokémon tile would feel narrow when viewed from behind the player.


## 3. Think in three levels of modularity


### Fine increment: 0.25 meters


Use this for:

Step heights
Curbs
Small borders
Trim
Floor thickness
Minor vertical offsets

Do not make general terrain modules 0.25 meters wide. This is only your smallest measurement increment.


### Base terrain cell: 2×2 meters


This is the smallest normal ground tile.

Use it for:

Corners
Path transitions
Cliff edges
Small slopes
Special floor pieces
GridMap pieces

### Standard production module: 4×4 meters


This should become your most common environment asset.

A 4×4-meter module is made from four 2×2 cells:

┌───────────┬───────────┐
│   2×2 m   │   2×2 m   │
├───────────┼───────────┤
│   2×2 m   │   2×2 m   │
└───────────┴───────────┘

Total: 4×4 meters

It is large enough to avoid excessive object counts but still small enough to build routes, towns and interiors flexibly.

Use 8×8 and 16×16 modules only as large filler pieces after the 2×2 and 4×4 kit works correctly.


## 4. Modeling your first ground tile in Blender


Godot expects assets to be created at their real scale. Scaling them after import can create problems in physics and rendering, so the source assets should already have the correct dimensions.


### Blender scene setup


Set:

Unit System: Metric
Unit Scale: 1.000
Length: Meters

Turn on:

Increment Snapping
Absolute Grid Snap

Keep Blender’s normal Z-up orientation. The glTF exporter should perform the axis conversion for Godot.


### Create the first tile


Add a cube and enter these exact dimensions:

X: 2.00 m
Y: 2.00 m
Z: 0.25 m

Because Blender uses Z for up, set its location to:

X: 0
Y: 0
Z: -0.125

The tile will then extend downward from the ground:

Top surface:    Z = 0
Bottom surface: Z = -0.25

That is the origin convention you should use throughout the ground kit.


### Pivot convention


Place the object origin at:

X: 0
Y: 0
Z: 0

This means the pivot is:

At the center of the tile.
On the walkable surface.
Not in the geometric center of the slab.

After exporting to Godot, the walkable surface becomes local Y = 0.

This makes it easy to:

Place characters directly at terrain height.
Put props on the surface.
Raise complete terrain sections by exact increments.
Stack elevation levels without calculating half-thickness offsets.

### Apply transforms


Before export:

Ctrl + A
Apply Rotation and Scale

The object must show:

Rotation: 0, 0, 0
Scale:    1, 1, 1

Godot recommends applying transforms before export. It also recommends triangulating source meshes for predictable imported geometry.


## 5. Ground seam rules


Modularity fails when edge vertices are only visually close rather than mathematically identical.

For a 2×2-meter tile, the exterior vertices must sit exactly at:

X = -1.0 and +1.0
Y = -1.0 and +1.0 in Blender's ground plane
Z = 0 on the top surface

For a 4×4 tile:

X = -2.0 and +2.0
Y = -2.0 and +2.0

Follow these rules:

Never move seam vertices by eye.
Never bevel an edge that touches another ground tile.
Never use proportional editing near tile borders.
Never place decorative geometry across a modular boundary.
Never scale finished modules inside Godot.
Keep border normals consistent between matching modules.
Do not overlap two walkable top surfaces.
Avoid coplanar duplicate faces, which can cause flickering.

Only exposed environment edges should receive beveling or softened silhouettes.


## 6. Your first modular ground kit


Build these before making an entire route.

Asset	Dimensions	Purpose
GND_Flat_02x02_A	2×2×0.25 m	Small universal tile
GND_Flat_04x04_A	4×4×0.25 m	Standard ground module
GND_Flat_08x08_A	8×8×0.25 m	Large filler
GND_Edge_02x02_Straight	2×2 m	Exposed terrain edge
GND_Edge_02x02_OuterCorner	2×2 m	Convex corner
GND_Edge_02x02_InnerCorner	2×2 m	Concave corner
GND_Ramp_02x04_H050	2×4 m	Rises 0.5 m
GND_Stairs_02x04_H050	2×4 m	Two 0.25 m steps
GND_Cliff_02_H050	2 m wide	0.5 m terrain tier
GND_Cliff_02_H100	2 m wide	1 m terrain tier

The naming suffixes communicate the dimensions:

02x04 = 2 meters by 4 meters
H050  = 0.50-meter elevation
H100  = 1.00-meter elevation

Keep elevation changes in multiples of 0.5 meters. Smaller architectural details can use 0.25 meters, but major terrain levels should remain on the 0.5-meter system.


## 7. How to shape the geometry for an ORAS-like feel


The look should come from clean shape language, not high geometric detail.


### Keep walkable surfaces simple


Most playable ground should remain:

Flat
Broad
Easy to read
Free of small collision bumps
Broken up mainly by paths, borders, cliffs and props

Do not sculpt noisy realistic terrain into every tile. It will make movement feel uneven and move the project away from the clean Pokémon environment style.


### Exaggerate important forms


The geometry should be slightly larger and chunkier than reality:

Borders should be clearly visible.
Corners should be broad.
Ramps should be obvious.
Terrain tiers should be clean horizontal bands.
Path curves should be intentional rather than naturally irregular.
Small terrain details should not compete with characters.

### Use controlled curves


For rounded terrain corners, create dedicated corner modules. Do not randomly rotate square modules by arbitrary angles.

Normal modular rotations should be:

0°
90°
180°
270°

Create special 45-degree pieces only when a location truly needs diagonal geometry.


### Separate the ground from its walls


Do not turn every ground tile into a deep block.

Use:

Flat top modules for the walkable surface.
Separate cliff-wall or retaining-wall modules for visible sides.
Corner wall pieces where the terrain turns.

This gives you much more control over cliffs, towns, coastlines and raised platforms.


## 8. Godot snapping setup


Godot uses meters, a Y-up coordinate system and the XZ plane for horizontal movement. Its editor includes transform and rotation snapping controls.

Use these snap presets:


### Normal environment placement

Translate snap: 0.50 m
Rotation snap:  90°
Scale snap:     Irrelevant—do not scale modules

### Rapid ground assembly

Translate snap: 2.00 m
Rotation snap:  90°

### Fine architectural placement

Translate snap: 0.25 m
Rotation snap:  90° or 15°

Keep imported asset scale at:

1.0

A 2-meter Blender tile must arrive as a 2-meter Godot tile.


## 9. Using GridMap


For your strict terrain kit, a good GridMap cell size would be:

X: 2.0
Y: 0.5
Z: 2.0

That matches:

Your 2×2-meter horizontal base cell.
Your 0.5-meter terrain elevation tier.

Enable centering on X and Z, but disable Center Y so the terrain aligns to the grid floor rather than floating around the cell center. Godot’s documentation specifically says the GridMap cell size should match the meshes and recommends disabling Center Y in its example setup.

Only put the strict 2×2 pieces into this GridMap library.

Use normal snapped Node3D placement for:

4×4 and 8×8 filler meshes
Unique route sections
Organic terrain
Landmark ground pieces
Large town plazas

Do not place a 4×4 mesh into a 2×2 GridMap cell and treat it as a normal tile. It would visually occupy neighboring cells without reserving them.


## 10. Scale guide for the surrounding world


Use these as starting dimensions relative to your 1.67-meter player:

Environment feature	Suggested size
Narrow character path	2 m wide
Standard route	4 m wide
Major road or town avenue	6–8 m wide
Small plaza	8×8 m
Typical plaza	12×12 or 16×16 m
Exterior doorway	1.4–1.6 m wide
Door height	2.3–2.5 m
Building floor height	3 m
Curb	0.15 m high
Small step	0.25 m high
Terrain ledge	0.5 m high
Major terrain level	1–2 m high
Basic fence	0.9–1.1 m high
Exterior staircase	2 or 4 m wide

The environment should be mildly oversized around the player. That creates the welcoming, readable, toy-like feel associated with Pokémon environments without making the player appear miniature.


## 11. Build this greybox first


Before creating a full asset library, construct one test area containing:

A 12×12-meter flat courtyard.
A 4-meter-wide route leaving the courtyard.
A 2-meter-wide narrow path.
One 0.5-meter terrain rise.
One ramp.
One staircase.
One simple doorway.
Your player model.
Your intended gameplay camera.

Walk through it in Godot.

Check:

Does the player look correctly sized?
Does a 4-meter route feel comfortable?
Does a 2-meter path feel deliberately narrow?
Can the camera see over a 0.5-meter ledge?
Do ground seams disappear completely?
Does the player cross between modules without collision catches?
Does the world feel compact without feeling cramped?

Do not change the project’s meter scale to fix the camera. Adjust the camera, field of view and module proportions while preserving 1 unit = 1 meter. Once that greybox feels correct, the 2-meter cell and 4-meter standard module can become the permanent foundation of the environment kit.
