"""Generate roof-only donor meshes with Tencent Hunyuan3D-2mv.

This script intentionally runs from an isolated Hunyuan checkout rather than
from the Godot project environment. Example:

    cd /tmp/pfr_hunyuan3d2
    .venv/bin/python \
        /path/to/project/source_assets/pokemon_center_roof/run_hunyuan_roof.py

The generated meshes are high-detail design donors. The Blender finalization
step conforms their visible form to the exact measured Pokemon Center rim and
reduces them to the project's mobile/web asset budget.
"""

from pathlib import Path
import gc
import os
import time

import torch
from PIL import Image

from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline


SCRIPT_PATH = Path(__file__).resolve()
SOURCE_DIR = SCRIPT_PATH.parent
INPUT_DIR = SOURCE_DIR / "hunyuan_input"
OUTPUT_DIR = SOURCE_DIR / "hunyuan_output"

MODEL_ID = "tencent/Hunyuan3D-2mv"
MODEL_SUBFOLDER = "hunyuan3d-dit-v2-mv-turbo"
SEEDS = (240821, 731903, 882017)


def load_views() -> dict[str, Image.Image]:
    return {
        view: Image.open(INPUT_DIR / f"{view}.png").convert("RGBA")
        for view in ("front", "left", "back")
    }


def main() -> None:
    if not torch.cuda.is_available():
        raise RuntimeError("Hunyuan roof generation requires a CUDA GPU.")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    views = load_views()
    print(
        "Loading Hunyuan3D-2mv on",
        torch.cuda.get_device_name(0),
        "with",
        round(torch.cuda.get_device_properties(0).total_memory / 1024**3, 2),
        "GiB VRAM",
    )
    # HUNYUAN_MODEL_PATH may point at a pre-staged local repository directory.
    # Staging only the SafeTensors file avoids snapshot_download fetching the
    # redundant 4.9 GB .ckpt representation as well.
    model_path = os.environ.get("HUNYUAN_MODEL_PATH", MODEL_ID)
    pipeline = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
        model_path,
        subfolder=MODEL_SUBFOLDER,
        variant="fp16",
        use_safetensors=True,
        device="cuda",
    )
    # The multiview checkpoint already contains its VAE. Retaining it avoids a
    # second model download while still enabling FlashVDM's lean decoder.
    pipeline.enable_flashvdm(topk_mode="merge", replace_vae=False)

    for seed in SEEDS:
        started = time.monotonic()
        generator = torch.Generator(device="cuda").manual_seed(seed)
        mesh = pipeline(
            image=views,
            num_inference_steps=5,
            guidance_scale=5.0,
            octree_resolution=256,
            num_chunks=8000,
            generator=generator,
            output_type="trimesh",
        )[0]
        output_path = OUTPUT_DIR / f"roof_candidate_seed_{seed}.glb"
        mesh.export(output_path)
        print(
            f"Generated {output_path} in {time.monotonic() - started:.1f}s: "
            f"{len(mesh.vertices)} vertices, {len(mesh.faces)} faces"
        )
        del mesh
        gc.collect()
        torch.cuda.empty_cache()


if __name__ == "__main__":
    main()
