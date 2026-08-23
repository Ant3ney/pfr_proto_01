# Overworld Art Framework
## A Transferable Handheld-Era Visual and Technical Envelope

**Project:** Pokémon Fracture and Revolt  
**Scope:** Overworld presentation only  
**Excluded:** Battle art, battle models, battle environments, battle effects, battle UI, and battle animation  
**Purpose:** Extract the transferable visual-production principles of a game such as *Pokémon Omega Ruby and Alpha Sapphire* without copying its specific regional art direction

---

# 1. Purpose

This document does not define the final art style of the game.

It does not decide:

- The region’s culture
- The architectural style
- The color palette
- The shape language
- The environmental motifs
- The vegetation style
- The clothing style
- The political visual language
- The emotional tone
- The regional materials
- The decorative patterns

Those decisions should be made in a separate art-direction document later.

This document instead defines a **technical and visual envelope**. It describes how an original art style can be designed under constraints similar to those of a Nintendo 3DS-era overworld game.

The goal is not to make the game look like ORAS.

The goal is to make the game feel as though it was created under a similar production environment:

- Limited hardware
- Small screen presentation
- Low geometry budgets
- Small textures
- Simple lighting
- Limited materials
- Strong visual readability
- Carefully controlled scene density
- Heavy reliance on silhouettes and broad color shapes

A new art style can then be placed inside this framework.

---

# 2. Core Principle

The project should inherit the **limitations and production discipline**, not the specific appearance.

A useful comparison is:

> A different art team project made for the same class of hardware, using similar technical restrictions, but creating a completely different region and visual identity.

The connection should come from:

- How geometry is simplified
- How details are prioritized
- How scenes are composed
- How assets are built for a small display
- How materials are reduced
- How lighting is controlled
- How repetition is managed
- How performance limitations influence design

The connection should not come from copying:

- Buildings
- Trees
- Rocks
- Routes
- Town layouts
- Props
- Character designs
- Colors
- Cultural motifs
- Environmental themes

---

# 3. Overworld-Only Scope

This framework applies to:

- Outdoor environments
- Indoor exploration spaces
- Towns and cities
- Routes
- Roads and paths
- Terrain
- Buildings
- Vegetation
- Environmental props
- Overworld NPCs
- Overworld player characters
- Exploration animation
- Overworld lighting
- Weather
- Water
- Camera presentation
- Environmental effects
- Modular asset construction

This framework does not apply to:

- Battle character models
- Battle arenas
- Battle shaders
- Battle animation
- Battle effects
- Battle camera work
- Battle interfaces

The overworld should be treated as its own visual system.

---

# 4. What Should Be Extracted

The most useful qualities to transfer are not individual design choices. They are the methods used to make a visually appealing world under strict limitations.

## 4.1 Small-Screen Readability

The world must remain understandable when displayed at a small size.

The player should quickly recognize:

- Walkable space
- Obstacles
- Entrances
- Exits
- NPCs
- Interactive objects
- Important landmarks
- Terrain boundaries

This means objects cannot depend on fine detail.

Information should be communicated through:

- Silhouette
- Size
- Proportion
- Color grouping
- Value contrast
- Placement
- Movement
- Repetition
- Simple visual symbols

## 4.2 Deliberate Simplification

Assets should not merely be unfinished versions of realistic objects.

They should be deliberately redesigned so they remain clear with fewer polygons and smaller textures.

A simplified asset should still have:

- A clear identity
- A readable front
- A strong profile
- A limited number of important features
- A clean relationship to the ground
- An obvious scale

Simplification should remove low-value information while preserving high-value information.

## 4.3 Controlled Scene Density

The scene should not contain detail everywhere.

Instead, detail should be concentrated around:

- Important entrances
- Landmarks
- Intersections
- Story locations
- Interactive objects
- Major environmental transitions

Less important areas should remain visually quiet.

This creates hierarchy and reduces rendering cost.

## 4.4 Camera-Aware Design

Assets should be designed for the normal gameplay camera.

The final judgment of an asset should not be based only on how it looks in a modeling viewport.

The important questions are:

- Can the player identify it from the expected distance?
- Are important features visible from the usual angle?
- Does it block the camera?
- Does it merge into nearby objects?
- Does it remain readable while the player is moving?
- Does it work from multiple approach directions?

---

# 5. Technical Visual Envelope

The following principles form the basic technical envelope.

## 5.1 Geometry

Geometry should be economical and purposeful.

Prefer:

- Large simple forms
- Strong silhouettes
- Flat or gently curved surfaces
- Limited beveling
- Repeated modules
- Shared structural pieces
- Simplified back faces
- Low-detail distant models

Avoid:

- Dense subdivision
- Small modeled surface details
- Realistic edge damage
- Individual roof tiles
- Complex railings
- Excessively round objects
- Detailed object interiors that cannot be seen
- Geometry hidden from the gameplay camera

Polygon count should be spent where it changes the visible shape.

## 5.2 Texture Resolution

Textures should be designed for normal gameplay distance.

Prefer:

- Small atlases
- Shared textures
- Broad painted details
- Large material changes
- Simple gradients
- Clear graphic markings
- Limited surface variation

Avoid:

- Photographic textures
- Fine scratches
- Tiny patterns
- High-frequency noise
- Detailed brickwork
- Small text that cannot be read
- Large unique textures for minor props

Texture detail should support the geometry rather than replace it.

## 5.3 Materials

Most assets should use very few materials.

Prefer:

- One material for small props
- One or two materials for ordinary environment assets
- Shared materials across asset families
- Simple roughness values
- Limited transparency
- Limited specular response
- Consistent shader behavior

Avoid:

- Many material slots
- Complex layered shaders
- Heavy reflection
- Parallax effects
- Expensive transparency
- Per-object shader variants without a clear need

Material categories should be easy to distinguish without physically accurate rendering.

## 5.4 Lighting

Lighting should clarify form rather than simulate reality.

Prefer:

- One primary directional light
- Broad environmental fill
- Baked lighting where practical
- Simple contact grounding
- Restrained ambient occlusion
- Limited local lights
- Stable shadow direction
- Clear separation between characters and backgrounds

Avoid:

- Many dynamic shadow-casting lights
- Dense volumetric effects
- Complex reflections
- Very soft cinematic lighting everywhere
- Extremely dark scenes
- Lighting that hides navigation

## 5.5 Shadows

Shadows should be simple, readable, and stable.

Their main functions are:

- Grounding characters
- Showing elevation
- Separating overlapping objects
- Reinforcing building mass
- Clarifying stairs and edges

The project does not need perfectly realistic shadow softness or detail.

Slightly hard, simplified, or lower-resolution shadow edges are acceptable if they support the intended technical character.

## 5.6 Effects

Visual effects should be used selectively.

Prefer:

- Small particle counts
- Large readable particles
- Short effect ranges
- Simple water motion
- Limited fog
- Limited screen-space effects
- Controlled weather density

Avoid:

- Constant particle activity
- Heavy bloom
- Dense fog
- Expensive transparency
- Excessive post-processing
- Effects that reduce environmental readability

---

# 6. Modeling Principles

## 6.1 Silhouette First

Every asset should first work as a plain solid shape.

Before texturing, ask:

- Is the object recognizable?
- Is the front clear?
- Is its scale obvious?
- Does it have a distinct profile?
- Does it remain identifiable from the gameplay camera?

If the answer is no, adding texture will not solve the problem.

## 6.2 Broad Forms

Build assets from a small number of broad forms.

For example, a building may be understood through:

- Main body
- Roof
- Entrance
- Base
- One identifying feature

A tree may be understood through:

- Trunk
- Main crown
- Secondary crown
- Root or ground connection

A prop may be understood through:

- Main mass
- Support
- Handle, sign, or attachment

The number of forms should remain low.

## 6.3 Controlled Exaggeration

Some features may need to be enlarged for readability.

Common examples include:

- Doors
- Windows
- Signs
- Handles
- Roof overhangs
- Curbs
- Railings
- Steps
- Tree trunks
- Path borders
- Character hands and feet

The amount of exaggeration should be consistent across the game.

## 6.4 Limited Curvature

Curves should use only enough geometry to communicate their form.

Round objects do not need to be perfectly smooth.

Slight faceting is acceptable, especially at ordinary gameplay distance.

Curvature should be reserved for:

- Important silhouettes
- Character heads
- Large decorative forms
- Objects whose identity depends on roundness

## 6.5 Ground Contact

Every asset should clearly connect to the ground.

Use:

- Simple bases
- Foundations
- Root flares
- Contact shadows
- Slight embedded placement
- Ground color transitions

Objects should not appear to float.

---

# 7. Texture Principles

## 7.1 Broad Information

Textures should describe large information first.

Good texture information includes:

- Main color areas
- Large panels
- Large stone blocks
- Broad wood boards
- Large painted markings
- Simplified wear
- Large lighting gradients

Low-value texture information includes:

- Tiny seams
- Small cracks
- Fine grain
- Micro scratches
- Detailed dirt noise
- Subtle realistic material variation

## 7.2 Painted Depth Support

Textures may support depth with:

- Soft edge darkening
- Simple highlights
- Large ambient shadows
- Controlled gradients
- Broad color changes

These effects should remain subtle enough that they do not look like strong lighting painted onto the object from an incorrect direction.

## 7.3 Texture Reuse

Texture reuse should be a normal part of the art style.

Use shared atlases for related assets such as:

- Building pieces
- Ground materials
- Foliage
- Street props
- Indoor furniture
- Signs
- Utility objects

Reuse creates consistency and lowers rendering cost.

## 7.4 UV Simplicity

UV layouts should prioritize:

- Clean alignment
- Repeated strips
- Mirroring where acceptable
- Shared texture regions
- Predictable texel density
- Efficient atlas use

Avoid giving every hidden or minor surface unique texture space.

---

# 8. Environment Composition

## 8.1 Clear Play Space

The player should be able to see the intended travel space quickly.

Use:

- Strong path borders
- Clear changes in ground material
- Simple obstacle placement
- Consistent collision shapes
- Clear openings
- Visible route continuation

Avoid visually ambiguous boundaries.

## 8.2 Landmark Hierarchy

Each area should have a small number of dominant visual elements.

A normal area may contain:

- One primary landmark
- Several secondary anchors
- Repeated supporting assets
- Quiet background space

Not every building or prop should compete for attention.

## 8.3 Foreground, Midground, Background

Scenes should be organized into depth layers.

### Foreground

Contains immediate gameplay information:

- Player
- NPCs
- Interactive objects
- Path edges
- Obstacles

### Midground

Contains place identity:

- Buildings
- Trees
- Signs
- Bridges
- Local landmarks

### Background

Completes the world:

- Simplified terrain
- Distant buildings
- Tree masses
- Skyline shapes
- Fog barriers
- Decorative scenery

The background should not use the same detail level as the playable area.

## 8.4 Visual Rest

Some areas should remain simple.

Empty or quiet space can:

- Make landmarks stronger
- Improve navigation
- Reduce clutter
- Improve performance
- Create pacing
- Make detailed areas feel more important

Do not fill every unused space with props.

---

# 9. Terrain and Ground

## 9.1 Ground as a Large Visual Shape

The ground occupies a large part of the screen and should be treated as a graphic composition.

Use clear divisions between:

- Road
- Path
- Grass
- Soil
- Water
- Plaza
- Interior floor
- Restricted or non-walkable space

These divisions should remain visible at small scale.

## 9.2 Terrain Transitions

Prefer transitions that use shape and height.

Examples include:

- Curbs
- Edges
- Retaining walls
- Borders
- Ridges
- Drainage lines
- Raised beds
- Steps
- Broad blended strips

Avoid relying only on soft texture blending.

## 9.3 Elevation

Elevation changes should be broad and intentional.

Prefer:

- Terraces
- Wide ramps
- Clear steps
- Large slopes
- Elevated platforms
- Simple cliffs

Avoid:

- Constant small bumps
- Highly detailed natural terrain
- Unnecessary unevenness
- Slopes that interfere with character movement

---

# 10. Vegetation

This framework does not define the region’s plant species or foliage design.

It only defines the technical treatment.

## 10.1 Mass-Based Foliage

Vegetation should be built as grouped shapes.

Prefer:

- Simple tree crowns
- Large foliage clusters
- Limited leaf cards
- Shared vegetation atlases
- Strong species silhouettes
- Sparse ground plants
- Controlled placement

Avoid:

- Individual modeled leaves
- Dense transparent layers
- Realistic forest density
- Heavy foliage animation
- Fine twig geometry

## 10.2 Repetition

Vegetation should use reusable families.

Variation may come from:

- Scale
- Rotation
- Crown shape
- Trunk height
- Color tint
- Cluster arrangement

The number of unique vegetation assets should remain controlled.

## 10.3 Grass

Grass should use a combination of:

- Ground texture
- Sparse clumps
- Edge vegetation
- Specific gameplay patches
- Limited animation

Do not cover every outdoor surface with dense grass geometry.

---

# 11. Buildings

This framework does not define architectural style.

It defines how architecture should be simplified.

## 11.1 Building Structure

A building should be readable through a small number of major parts:

- Main mass
- Roof or top
- Entrance
- Base
- Windows
- One or two identifying features

## 11.2 Readable Entrances

Entrances should be:

- Large enough to see clearly
- Separated from the wall by value or color
- Positioned consistently with player navigation
- Unobstructed by props
- Designed for the gameplay camera

## 11.3 Roof and Facade Balance

Because the camera may show both roof and facade surfaces, both need clear design.

Do not place all identifying information on only one side of the building.

## 11.4 Interior Simplification

Explorable interiors should use:

- Large room zones
- Clear paths
- Few large furniture pieces
- Limited clutter
- Strong interactive-object placement
- Broad floor patterns
- Simple wall treatment

Interiors should not attempt realistic object density.

---

# 12. Props

## 12.1 Prop Categories

Props should be classified by importance.

### Gameplay Props

Objects that affect movement or interaction.

Examples:

- Doors
- Gates
- Barriers
- Signs
- Ladders
- Bridges
- Stairs

These require the clearest silhouettes.

### Identity Props

Objects that help define a location.

These should be limited and repeated consistently.

### Decorative Props

Objects that add occupation or atmosphere.

These should be sparse and low-cost.

## 12.2 Prop Economy

Before adding a prop, ask:

- Does it aid navigation?
- Does it define the location?
- Does it support storytelling?
- Does it improve scale?
- Does it fill an important compositional gap?

If not, it may not be necessary.

---

# 13. Overworld Characters

This section applies only to characters during exploration.

It does not define the final character art style.

## 13.1 Technical Character Requirements

Overworld characters should have:

- Strong head shape
- Clear torso
- Readable limbs
- Visible hands and feet
- Simple clothing masses
- Limited small accessories
- Clear front and back
- Stable silhouette during animation

## 13.2 Detail Hierarchy

Character detail should be divided by importance.

### Main Characters

May receive:

- Higher texture resolution
- More distinct hair
- More clothing layers
- Additional facial control
- Unique animation

### Important NPCs

May receive:

- Distinct silhouette
- Limited unique accessories
- Some custom animation

### Background NPCs

Should rely on:

- Shared body types
- Shared animation
- Texture variation
- Color variation
- Limited accessory swaps

## 13.3 Facial Readability

At normal exploration distance, emotion should be communicated mainly through:

- Pose
- Head movement
- Gesture
- Timing
- Character spacing
- Body orientation

Fine facial animation should not be required for basic storytelling.

---

# 14. Animation

## 14.1 Character Motion

Animation should be:

- Clear
- Responsive
- Slightly exaggerated
- Easy to read at distance
- Economical
- Built around strong poses

Avoid overly subtle realistic movement.

## 14.2 Continuous Movement

For continuous 360-degree movement, the system should support:

- Directional blending
- Smooth turning
- Idle-to-walk transitions
- Walk-to-run transitions
- Stable foot contact
- Slope handling
- Short interaction alignment

The movement should remain visually simple even if the control system is modern.

## 14.3 NPC Animation Reuse

Background NPCs should share a limited library of actions.

Examples:

- Idle
- Walk
- Look around
- Talk
- Sit
- Read
- Sweep
- Carry
- Inspect

Unique animations should be reserved for important characters and moments.

## 14.4 Environmental Animation

Environmental movement should be limited.

Use:

- Simple tree sway
- Short flag loops
- Basic water motion
- Simple doors
- Limited sign movement
- Small particle systems

Avoid making every object move.

---

# 15. Camera

## 15.1 Camera as a Constraint

The camera should be treated as part of the art pipeline.

Asset production should begin only after the camera’s normal:

- Height
- Distance
- Pitch
- Field of view
- Rotation range
- Collision behavior

have been established.

## 15.2 Guided Camera

A guided camera is preferable to a completely free camera.

Useful limitations include:

- Restricted vertical pitch
- Controlled follow distance
- Stable field of view
- Gentle rotation
- Predictable framing
- Limited camera penetration
- Carefully authored camera zones

These limitations allow the environment to be optimized for known views.

## 15.3 Lower Camera Considerations

A lower camera requires:

- Complete building facades
- Better background scenery
- Intentional horizons
- Finished undersides
- Better tree trunks
- More attention to occlusion
- Stronger side profiles
- Distant simplified assets

The lower camera should not force the game into modern open-world detail levels.

---

# 16. Performance and Asset Budgets

The following values are suggested starting points for a modern engine attempting to preserve a constrained handheld-era appearance.

They are not claims about the exact internal budgets of ORAS.

## 16.1 Suggested Geometry Ranges

| Asset type | Suggested triangle range |
|---|---:|
| Tiny prop | 20–150 |
| Small prop | 100–400 |
| Medium prop | 300–1,200 |
| Large prop | 800–2,500 |
| Small plant | 50–400 |
| Standard tree | 300–1,500 |
| Building module | 300–2,000 |
| Small building | 1,500–6,000 |
| Large building | 4,000–12,000 |
| Background NPC | 1,000–3,000 |
| Main overworld character | 2,500–6,000 |

The correct number is the lowest count that preserves the intended silhouette.

## 16.2 Suggested Texture Ranges

| Asset type | Suggested texture size |
|---|---:|
| Tiny props | Atlas region, 32–128 px |
| Small props | 128–256 px |
| Medium props | 256–512 px |
| Vegetation atlas | 256–512 px |
| Building atlas | 512–1024 px |
| Background NPC | 256–512 px |
| Main overworld character | 512–1024 px |
| Major landmark | 1024 px, larger only when justified |

## 16.3 Scene Targets

Aim for:

- Limited visible material variety
- Repeated mesh instances
- Few transparent objects
- Few dynamic lights
- Limited shadow casters
- Controlled particle counts
- Visibility ranges
- LODs
- Occlusion
- Merged static clusters where useful

Exact performance targets should be established through profiling on the weakest supported device.

---

# 17. Level of Detail

LOD should remove detail without changing identity.

## LOD 0

Full gameplay asset.

## LOD 1

Removes:

- Small trim
- Minor attachments
- Hidden geometry
- Extra foliage clusters
- Secondary surface breaks

## LOD 2

Preserves:

- Main silhouette
- Large color areas
- Major roof or top shape
- Entrance indication
- Navigation function

## Distant Form

Used for scenery that cannot be approached.

May use:

- Simplified mesh
- Billboard
- Impostor
- Background cluster
- Painted backdrop

LOD design should begin during modeling, not after the asset is finished.

---

# 18. Modular Construction

## 18.1 Shared Measurements

Modular assets should use a consistent measurement system.

Standardize:

- Wall lengths
- Floor heights
- Door sizes
- Window spacing
- Curb heights
- Road widths
- Fence spacing
- Stair dimensions
- Terrain steps
- Prop anchors

The exact dimensions should be defined in a separate scale and modularity document.

## 18.2 Asset Families

Create modular families rather than unrelated individual assets.

Examples:

- Building family
- Road family
- Fence family
- Vegetation family
- Interior family
- Utility family

The final visual style of each family can be defined later.

## 18.3 Variation

Variation should come from:

- Module arrangement
- Scale
- Color
- Texture region
- Attachments
- Signs
- Props
- Landscaping
- Orientation

Avoid producing large numbers of nearly identical unique meshes.

---

# 19. Style Slots to Define Later

The following subjects are intentionally left undefined.

They should be decided in the future art-direction document.

## Regional Identity

- Cultural references
- Historical influences
- Geographic influences
- Regional economy
- Social character

## Shape Language

- Rounded or angular
- Vertical or horizontal
- Dense or open
- Symmetrical or irregular
- Soft or rigid

## Architecture

- Roof types
- Construction materials
- Building proportions
- Window styles
- Public-space design
- Interior design

## Color

- Base palette
- Accent palette
- Environmental color
- Character color
- Institutional color
- Story progression

## Texture Style

- Flat
- Painterly
- Graphic
- Soft
- Rough
- Clean
- Patterned

## Vegetation

- Species
- Crown shapes
- Color families
- Density
- Seasonal behavior

## Props

- Local infrastructure
- Signs
- Furniture
- Transportation
- Utilities
- Decorative objects

## Character Design

- Body proportions
- Clothing
- Hair
- Accessories
- Facial style
- Cultural influence

None of these should be inferred from ORAS.

---

# 20. Transfer Process

When the final art style is defined, apply it through the following process.

## Step 1: Define the New Style

Decide:

- Cultural identity
- Shape language
- Architecture
- Palette
- Materials
- Vegetation
- Character design
- Environmental motifs

## Step 2: Reduce It to Large Forms

Translate the style into:

- Silhouettes
- Major proportions
- Large color blocks
- Repeated modules
- Limited material categories

## Step 3: Fit It to the Technical Envelope

Reduce:

- Polygon count
- Texture size
- Material count
- Transparency
- Light count
- Animation complexity
- Scene density

## Step 4: Test at Gameplay Scale

Check:

- Thumbnail readability
- Camera visibility
- Navigation
- Character separation
- Landmark recognition
- Repetition
- Performance

## Step 5: Refine Without Adding Noise

Improve assets through:

- Better silhouette
- Better proportion
- Better color grouping
- Better placement
- Better lighting
- Better animation timing

Do not automatically improve them by adding more detail.

---

# 21. Review Tests

## Silhouette Test

Can the asset be recognized as a solid shape?

## Thumbnail Test

Can the scene be understood at small size?

## Blur Test

Do paths, characters, entrances, and landmarks remain distinct?

## Neutral Material Test

Does the model still work without textures?

## Gameplay Camera Test

Are important features visible from normal play angles?

## Repetition Test

Does the asset still look acceptable when repeated?

## Density Test

Is every visible detail necessary?

## Performance Test

Is the cost appropriate for the asset’s importance?

## Style Independence Test

Is the asset following the new regional style rather than copying ORAS?

---

# 22. What to Avoid

Do not copy:

- ORAS architecture
- ORAS vegetation
- ORAS terrain shapes
- ORAS building proportions
- ORAS palettes
- ORAS route composition
- ORAS props
- ORAS town layouts
- ORAS decorative motifs

Do not replace art direction with:

- Generic low-poly assets
- Photoreal materials
- Excessive detail
- Modern high-end rendering
- Heavy post-processing
- Large empty open-world spaces
- Dense clutter
- Uncontrolled procedural generation

The project should be original in appearance and disciplined in execution.

---

# 23. Final Rule

The transferable quality is not a specific visual style.

It is the ability to create a readable, attractive, expressive overworld using limited resources.

The final game may use a completely different:

- Culture
- Palette
- Architecture
- Shape language
- Atmosphere
- Environmental identity

As long as those choices are expressed through:

- Simple geometry
- Small textures
- Few materials
- Strong silhouettes
- Clear composition
- Controlled density
- Restrained lighting
- Camera-aware design
- Consistent modular construction

The result can feel appropriate to the same technical era without looking like the same region or the same art direction.
