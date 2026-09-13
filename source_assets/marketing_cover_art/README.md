# Switch-style game case

Open [pfrmca_01.blend](pfrmca_01.blend). The case uses approximate 105 × 170 × 11 mm proportions and contains separate molded shell halves, a hinge, opening seam, thumb recess, clasp details, paper inserts, and a clear outer sleeve. It is a closed presentation model; it has no opening animation or modeled cartridge.

The starting project is preserved in [pfrmca_01_before_case.blend](pfrmca_01_before_case.blend).

## Pokémon Revolt copy

Open [pokemon revolt box art.blend](<pokemon revolt box art.blend>) for the Revolt version. It contains the complete supplied Revolt front image and the spine title “POKEMON REVOLT,” retaining the itch.io spine icon. Its textures are packed into the project. The Fracture project and its artwork files remain separate.

Revolt artwork: [front PNG](cover_art/revolt_front_cover.png), [editable spine SVG](cover_art/revolt_spine_cover.svg), [spine PNG](cover_art/revolt_spine_cover.png). [Transparent studio render](exports/pokemon_revolt_box_art_transparent_80deg.png).

## Artwork

The front now uses the supplied Pokémon Fracture artwork at its original 2060 × 3300 resolution. The complete image fills the existing front UV layout without cropping or resampling and is packed into the Blender file. The case before this replacement is preserved in [pfrmca_01_before_fracture_cover.blend](pfrmca_01_before_fracture_cover.blend).

The spine uses the supplied itch.io game-case icon and the title “POKEMON FRACTURE.” The back retains its reference-style template:

| Panel | Source artwork | Blender texture |
| --- | --- | --- |
| Front | Supplied Pokémon Fracture PNG | [fracture_front_cover.png](cover_art/fracture_front_cover.png) |
| Spine | [spine_cover.svg](cover_art/spine_cover.svg) | [spine_cover.png](cover_art/spine_cover.png) |
| Back | [back_cover.svg](cover_art/back_cover.svg) | [back_cover.png](cover_art/back_cover.png) |

The original “Your Game Here” front template remains available as [SVG](cover_art/front_cover.svg) and [PNG](cover_art/front_cover.png).

The spine icon is also available as a [standalone vector](cover_art/itch_case_icon.svg), traced from the [supplied icon](cover_art/itch_case_icon_source.png). The original Switch-style spine is preserved as [SVG](cover_art/spine_cover_template.svg) and [PNG](cover_art/spine_cover_template.png).

Front and back textures are 2060 × 3300 pixels; the spine is 200 × 3300 pixels. Each artwork object has a `Cover UV` map filling the image. In Blender, select the matching `ARTWORK` object, open its `ART` material in the Shader Editor, and use the image texture node’s folder button to load replacement artwork. Then use **File → External Data → Pack Resources** and save.

The back-cover information, player counts, barcode, studio name and RP rating are template placeholders.

## Model and previews

Move the `CASE • move and rotate the whole model` parent empty to position all case parts together. The `GAME CASE` collection separates the shell, artwork, molded details, and sleeve. Edge bevels remain editable. The `STUDIO` collection has six cameras and six area lights. The old floor remains available but is disabled for rendering.

Both projects share exactly the same 80 mm perspective camera, framing, light positions and strengths, exposure, and material settings. Fracture retains its original case pose, showing the front, spine, and top edge. Revolt's entire case is rotated 80° clockwise around the vertical world Z axis (`CASE` parent Z rotation: −80°, viewed from above), with the camera and lights retained. Broad softboxes light the artwork with reduced specular contributions; a narrow sleeve reflection and separate edge lights retain the packaging shine.

Use these transparent PNG exports: [Pokémon Fracture](exports/pokemon_fracture_box_art_transparent.png), [Pokémon Revolt at 80°](exports/pokemon_revolt_box_art_transparent_80deg.png). The [previous Revolt render at 90°](exports/pokemon_revolt_box_art_transparent.png) remains available for comparison. Both projects render directly to their corresponding file in `exports/`: 2400 × 2880 PNG with standard 8-bit RGBA alpha. Film transparency and transparent glass are enabled; no floor or background is baked into the image. Both projects use Cycles, denoising, and Khronos PBR Neutral color management.

The 16-bit transparent masters are also preserved: [Fracture](previews/pokemon_fracture_studio.png), [Revolt](previews/pokemon_revolt_studio.png).

The viewport opens in the shared camera using Material Preview to keep editing responsive. F12 uses the saved Cycles studio lighting. In Blender's Render Result, **Color and Alpha** displays the transparent background as a checkerboard. The previous setups are preserved in [Fracture backup](backups/pfrmca_01_before_studio.blend) and [Revolt backup](<backups/pokemon revolt box art_before_studio.blend>).

Earlier floor-backed views remain available: [front](previews/switch_case_front.png), [back](previews/switch_case_back.png), [spine](previews/switch_case_spine.png), [Revolt front](previews/pokemon_revolt_front.png), [Revolt spine](previews/pokemon_revolt_spine.png).

## Rebuilding

[setup_transparent_studio.py](scripts/setup_transparent_studio.py) reapplies the matching lighting, materials, camera, and transparent output settings to either project while preserving geometry, UVs, and packed artwork. Run with `--save --render` after Blender's `--` argument separator to save and render; use `--draft --render` without `--save` for a temporary smaller preview.

[create_cover_template.py](scripts/create_cover_template.py) regenerates the original SVG and PNG templates using `rsvg-convert`, including the original Switch-style spine. It overwrites the template artwork files and the current spine artwork. [build_switch_case.py](scripts/build_switch_case.py) rebuilds the generated case and studio collections using the current template texture files and saves `pfrmca_01.blend`; use it only when you intend to replace edits to those generated collections. It does not apply the current Pokémon Fracture front cover. [render_previews.py](scripts/render_previews.py) renders the supplied front, back, and spine cameras without saving changes to the Blender file.
