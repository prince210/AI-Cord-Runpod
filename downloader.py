import os
import subprocess
import logging
from pathlib import Path
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ModelDownloader")

def get_comfy_models_dir() -> Path:
    """Dynamically discover ComfyUI models directory inside the container."""
    for path in [Path("/workspace/ComfyUI/models"), Path("/comfyui/models"), Path("./models")]:
        if path.exists():
            logger.info(f"Discovered ComfyUI models directory: {path}")
            return path
    logger.warning("Could not discover ComfyUI models directory. Defaulting to /comfyui/models")
    return Path("/comfyui/models")

# Mapping of known model filenames to (huggingface_url, target_subfolder)
MODEL_MAP: Dict[str, Tuple[str, str]] = {
    # Flux Klein
    "flux-2-klein-9b-Q5_K_M.gguf": (
        "https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF/resolve/main/flux-2-klein-9b-Q5_K_M.gguf",
        "unet"
    ),
    "flux2-vae.safetensors": (
        "https://huggingface.co/Comfy-Org/vae-text-encorder-for-flux-klein-9b/resolve/main/split_files/vae/flux2-vae.safetensors",
        "vae"
    ),
    "qwen_3_8b_fp4mixed.safetensors": (
        "https://huggingface.co/Comfy-Org/vae-text-encorder-for-flux-klein-9b/resolve/main/split_files/text_encoders/qwen_3_8b_fp4mixed.safetensors",
        "text_encoders"
    ),
    
    # Krea-2 Turbo
    "krea2_turbo_fp8_scaled.safetensors": (
        "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors",
        "diffusion_models"
    ),
    "qwen_image_vae.safetensors": (
        "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors",
        "vae"
    ),
    "qwen3vl_4b_fp8_scaled.safetensors": (
        "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors",
        "text_encoders"
    ),
    "krea2_warmpastel.safetensors": (
        "https://huggingface.co/Comfy-Org/Krea-2/resolve/bd08c3d74c5e15941c953926e0f9f24f6016f47c/loras/krea2_warmpastel.safetensors",
        "loras"
    ),
    
    # LTX-Video 2.3
    "ltx-2.3-22b-distilled-Q5_K_M.gguf": (
        "https://huggingface.co/unsloth/LTX-2.3-GGUF/resolve/main/ltx-2.3-22b-distilled-Q5_K_M.gguf",
        "unet"
    ),
    "ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors": (
        "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_mxfp8_block32.safetensors",
        "diffusion_models"
    ),
    "ltx-2.3-22b-distilled_transformer_only_bf16.safetensors": (
        "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_bf16.safetensors",
        "diffusion_models"
    ),
    "ltx-2.3-22b-distilled_video_vae.safetensors": (
        "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors",
        "vae"
    ),
    "ltx-2.3-22b-distilled_audio_vae.safetensors": (
        "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors",
        "checkpoints"
    ),
    "ltx-2.3-22b-distilled_embeddings_connectors.safetensors": (
        "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors",
        "text_encoders"
    ),
    "gemma-3-12b-it-Q4_K_M.gguf": (
        "https://huggingface.co/unsloth/gemma-3-12b-it-GGUF/resolve/main/gemma-3-12b-it-Q4_K_M.gguf",
        "text_encoders"
    ),
    "ltx-2.3-spatial-upscaler-x2-1.1.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors",
        "latent_upscale_models"
    ),
    "ltx-2.3-spatial-upscaler-x2-1.0.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors",
        "latent_upscale_models"
    ),
    
    # Restorations
    "seedvr2_ema_3b_fp8_e4m3fn.safetensors": (
        "https://huggingface.co/themindstudio/SeedVR2-3B-FP8-e4m3fn/resolve/main/seedvr2_ema_3b_fp8_e4m3fn.safetensors",
        "SEEDVR2"
    ),
    "ema_vae_fp16.safetensors": (
        "https://huggingface.co/themindstudio/SeedVR2-3B-FP8-e4m3fn/resolve/main/ema_vae_fp16.safetensors",
        "SEEDVR2"
    ),
    "4x-UltraSharpV2.safetensors": (
        "https://huggingface.co/Kim2091/UltraSharpV2/resolve/main/4x-UltraSharpV2.safetensors",
        "upscale_models"
    ),
    "LTX-2.3-22b-AV-LoRA-talking-head-v1.safetensors": (
        "https://huggingface.co/elix3r/LTX-2.3-22b-AV-LoRA-talking-head/resolve/main/LTX-2.3-22b-AV-LoRA-talking-head-v1.safetensors",
        "loras"
    )
}

def download_file(url: str, dest_path: Path):
    """Download a file using aria2c with multi-connection acceleration, falling back to curl."""
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Use aria2c for accelerated downloading if available
    cmd = ["aria2c", "-x", "16", "-s", "16", "-o", dest_path.name, "-d", str(dest_path.parent), url]
    try:
        logger.info(f"Running download command: {' '.join(cmd)}")
        subprocess.run(cmd, check=True)
        return
    except Exception as e:
        logger.warning(f"aria2c download failed or not found ({e}). Cleaning up and falling back to curl.")
        if dest_path.exists():
            try:
                dest_path.unlink()
            except Exception:
                pass
        control_file = dest_path.with_name(dest_path.name + ".aria2")
        if control_file.exists():
            try:
                control_file.unlink()
            except Exception:
                pass
        
    cmd_fallback = ["curl", "-L", "-C", "-", "-o", str(dest_path), url]
    logger.info(f"Running fallback download command: {' '.join(cmd_fallback)}")
    subprocess.run(cmd_fallback, check=True)

def create_symlink_or_copy(src: Path, dst: Path):
    """Safely create a relative symlink to dst, or fallback to file copy."""
    if dst.exists():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        # Create a relative symlink
        rel_src = os.path.relpath(src, dst.parent)
        os.symlink(rel_src, dst)
        logger.info(f"Created symlink: {dst} -> {rel_src}")
    except Exception as e:
        logger.warning(f"Could not symlink {src} to {dst}: {e}. Falling back to copy...")
        import shutil
        try:
            shutil.copy2(src, dst)
            logger.info(f"Copied file to alternate search path: {dst}")
        except Exception as copy_err:
            logger.error(f"Failed to copy model file: {copy_err}")

def check_and_download_model(model_filename: str):
    """Check if the model exists in any of ComfyUI's paths, and download/link it if missing."""
    if model_filename not in MODEL_MAP:
        return
        
    url, subfolder = MODEL_MAP[model_filename]
    models_dir = get_comfy_models_dir()
    dest_path = models_dir / subfolder / model_filename
    
    # Special handle for linked files
    if model_filename == "ltx-2.3-spatial-upscaler-x2-1.0.safetensors":
        dest_11 = models_dir / subfolder / "ltx-2.3-spatial-upscaler-x2-1.1.safetensors"
        if not dest_11.exists():
            logger.info(f"Downloading main spatial upscaler v1.1 first...")
            check_and_download_model("ltx-2.3-spatial-upscaler-x2-1.1.safetensors")
        create_symlink_or_copy(dest_11, dest_path)
        return

    # Check alternative paths to see if already present
    alt_folders = []
    if subfolder == "text_encoders":
        alt_folders.append("clip")
    elif subfolder == "clip":
        alt_folders.append("text_encoders")
    elif subfolder == "unet":
        alt_folders.append("diffusion_models")
    elif subfolder == "diffusion_models":
        alt_folders.append("unet")

    # If already exists in main path, ensure it exists in alternative paths
    if dest_path.exists():
        logger.info(f"Model {model_filename} already exists at {dest_path}.")
        for alt in alt_folders:
            create_symlink_or_copy(dest_path, models_dir / alt / model_filename)
        return

    # Check if exists in alternative path already
    for alt in alt_folders:
        alt_path = models_dir / alt / model_filename
        if alt_path.exists():
            logger.info(f"Model {model_filename} already exists at alternative path {alt_path}. Linking to main path...")
            create_symlink_or_copy(alt_path, dest_path)
            return

    # Download to main path
    logger.info(f"Model {model_filename} is missing! Downloading from {url}...")
    download_file(url, dest_path)
    logger.info(f"Successfully downloaded {model_filename}!")

    # Populate to alternative folders
    for alt in alt_folders:
        create_symlink_or_copy(dest_path, models_dir / alt / model_filename)

def download_missing_models(workflow_prompt: Dict[str, Any]):
    """Scan the workflow prompt for inputs matching known model filenames, and download them."""
    logger.info("Scanning workflow payload for missing models...")
    found_models = set()
    
    for node_id, node in workflow_prompt.items():
        inputs = node.get("inputs", {})
        for val in inputs.values():
            if isinstance(val, str):
                if val in MODEL_MAP:
                    found_models.add(val)
            elif isinstance(val, list):
                for item in val:
                    if isinstance(item, str) and item in MODEL_MAP:
                        found_models.add(item)
                        
    if not found_models:
        logger.info("No known models found in workflow payload.")
        return
        
    logger.info(f"Found required models: {found_models}")
    for model in found_models:
        try:
            check_and_download_model(model)
        except Exception as e:
            logger.error(f"Failed to download model {model}: {e}")
            raise e
