"""Render the case's supplied presentation cameras from the saved .blend."""
import bpy
import sys
from pathlib import Path

scene = bpy.context.scene
root = Path(bpy.data.filepath).parent
preview = root / 'previews'
preview.mkdir(exist_ok=True)
args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
draft = '--draft' in args
scene.render.resolution_percentage = 50 if draft else 100
scene.cycles.samples = 32 if draft else 96
prefs = bpy.context.preferences.addons['cycles'].preferences
try:
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == 'OPTIX'
    scene.cycles.device = 'GPU' if any(d.use for d in prefs.devices) else 'CPU'
except Exception:
    scene.cycles.device = 'CPU'
views = [('01 Front three-quarter','front'),('02 Back three-quarter','back'),('03 Spine and opening seam','spine')]
if '--detail' in args:
    views = [('06 Right clasp detail','clasp_detail')]
if '--front' in args:
    views = views[:1]
for camera, name in views:
    scene.camera = bpy.data.objects['CAMERA • ' + camera]
    scene.render.filepath = str(preview / f"{'draft_' if draft else ''}switch_case_{name}.png")
    bpy.ops.render.render(write_still=True)
    print('PREVIEW:', scene.render.filepath, flush=True)
