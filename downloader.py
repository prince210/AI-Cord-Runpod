import os
import subprocess
import logging
from pathlib import Path
from typing import Dict, Any, Tuple, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ModelDownloader")

def get_comfy_models_dir() -> Path:
    """Dynamically discover ComfyUI models directory inside the container."""
    for path in [
        Path("/runpod-volume/ComfyUI/models"),
        Path("/runpod-volume/models"),
        Path("/workspace/ComfyUI/models"),
        Path("/workspace/models"),
        Path("/comfyui/models"),
        Path("./models"),
    ]:
        if path.exists():
            logger.info(f"Discovered ComfyUI models directory: {path}")
            return path
    logger.warning("Could not discover ComfyUI models directory. Defaulting to /comfyui/models")
    return Path("/comfyui/models")

# Mapping of known model filenames to (primary_huggingface_url, target_subfolder, optional_mirror_urls)
MODEL_MAP: Dict[str, Tuple[str, str, List[str]]] = {
    # --- LTX-Video 2.5 (Fast, Keyframe Diffusion & RTX 4090 / 5090 Optimized) ---
    "ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors",
        "diffusion_models",
        ["https://huggingface.co/PulpCut/LTX-2.5-INT8-ConvRot-safetensors/resolve/main/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors"]
    ),
    "ltx-2.5-22b-distilled-transformer-bf16.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors",
        "diffusion_models",
        []
    ),
    "gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors",
        "text_encoders",
        ["https://huggingface.co/PulpCut/LTX-2.5-INT8-ConvRot-safetensors/resolve/main/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors"]
    ),
    "gemma4-12b-with-proj-ltx-2.5-bf16.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors",
        "text_encoders",
        []
    ),
    "gemma4_e2b_it_int8_convrot.safetensors": (
        "https://huggingface.co/Comfy-Org/gemma-4/resolve/main/text_encoders/gemma4_e2b_it_int8_convrot.safetensors",
        "text_encoders",
        []
    ),
    "ltx-2.5-video-vae-bf16.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/vae/ltx-2.5-video-vae-bf16.safetensors",
        "vae",
        ["https://huggingface.co/PulpCut/LTX-2.5-INT8-ConvRot-safetensors/resolve/main/ltx-2.5-video-vae-bf16.safetensors"]
    ),
    "ltx-2.5-audio-vae-bf16.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/vae/ltx-2.5-audio-vae-bf16.safetensors",
        "vae",
        ["https://huggingface.co/PulpCut/LTX-2.5-INT8-ConvRot-safetensors/resolve/main/ltx-2.5-audio-vae-bf16.safetensors"]
    ),
    "ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors",
        "latent_upscale_models",
        ["https://huggingface.co/PulpCut/LTX-2.5-INT8-ConvRot-safetensors/resolve/main/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors"]
    ),

    # --- MiniMax H3 (Omni-Modal Video + Audio & RTX 4090 / 5090 Optimized) ---
    "minimax_h3_fl2va_pruned_int8_convrot.safetensors": (
        "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors",
        "diffusion_models",
        ["https://modelscope.cn/models/Comfy-Org/MiniMax-H3/resolve/master/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"]
    ),
    "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors": (
        "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors",
        "text_encoders",
        ["https://modelscope.cn/models/Comfy-Org/MiniMax-H3/resolve/master/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"]
    ),
    "minimax_h3_video_vae_int8_convrot.safetensors": (
        "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_int8_convrot.safetensors",
        "vae",
        ["https://modelscope.cn/models/Comfy-Org/MiniMax-H3/resolve/master/vae/minimax_h3_video_vae_int8_convrot.safetensors"]
    ),
    "minimax_h3_audio_vae_fp32.safetensors": (
        "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors",
        "vae",
        ["https://modelscope.cn/models/Comfy-Org/MiniMax-H3/resolve/master/vae/minimax_h3_audio_vae_fp32.safetensors"]
    ),
    "minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors": (
        "https://huggingface.co/lightx2v/Minimax-h3-Turbo/resolve/main/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors",
        "loras",
        ["https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors"]
    ),
    "minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors": (
        "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/loras/minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors",
        "loras",
        []
    ),

    # --- Flux Klein ---
    "flux-2-klein-9b-Q5_K_M.gguf": (
        "https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF/resolve/main/flux-2-klein-9b-Q5_K_M.gguf",
        "unet",
        []
    ),
    "flux2-vae.safetensors": (
        "https://huggingface.co/Comfy-Org/vae-text-encorder-for-flux-klein-9b/resolve/main/split_files/vae/flux2-vae.safetensors",
        "vae",
        []
    ),
    "qwen_3_8b_fp4mixed.safetensors": (
        "https://huggingface.co/Comfy-Org/vae-text-encorder-for-flux-klein-9b/resolve/main/split_files/text_encoders/qwen_3_8b_fp4mixed.safetensors",
        "text_encoders",
        []
    ),
    
    # --- Krea-2 Turbo ---
    "krea2_turbo_fp8_scaled.safetensors": (
        "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors",
        "diffusion_models",
        []
    ),
    "qwen_image_vae.safetensors": (
        "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors",
        "vae",
        []
    ),
    "qwen3vl_4b_fp8_scaled.safetensors": (
        "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors",
        "text_encoders",
        []
    ),
    "krea2_warmpastel.safetensors": (
        "https://huggingface.co/Comfy-Org/Krea-2/resolve/bd08c3d74c5e15941c953926e0f9f24f6016f47c/loras/krea2_warmpastel.safetensors",
        "loras",
        []
    ),
    
    # --- LTX-Video 2.3 Legacy ---
    "ltx-2.3-22b-distilled-Q5_K_M.gguf": (
        "https://huggingface.co/unsloth/LTX-2.3-GGUF/resolve/main/ltx-2.3-22b-distilled-Q5_K_M.gguf",
        "unet",
        []
    ),
    "ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors": (
        "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_mxfp8_block32.safetensors",
        "diffusion_models",
        []
    ),
    "ltx-2.3-22b-distilled_transformer_only_bf16.safetensors": (
        "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_bf16.safetensors",
        "diffusion_models",
        []
    ),
    "ltx-2.3-22b-distilled_video_vae.safetensors": (
        "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors",
        "vae",
        []
    ),
    "ltx-2.3-22b-distilled_audio_vae.safetensors": (
        "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors",
        "checkpoints",
        []
    ),
    "ltx-2.3-22b-distilled_embeddings_connectors.safetensors": (
        "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors",
        "text_encoders",
        []
    ),
    "gemma-3-12b-it-Q4_K_M.gguf": (
        "https://huggingface.co/unsloth/gemma-3-12b-it-GGUF/resolve/main/gemma-3-12b-it-Q4_K_M.gguf",
        "text_encoders",
        []
    ),
    "ltx-2.3-spatial-upscaler-x2-1.1.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors",
        "latent_upscale_models",
        []
    ),
    "ltx-2.3-spatial-upscaler-x2-1.0.safetensors": (
        "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors",
        "latent_upscale_models",
        []
    ),
    
    # --- Restorations & LoRAs ---
    "seedvr2_ema_3b_fp8_e4m3fn.safetensors": (
        "https://huggingface.co/themindstudio/SeedVR2-3B-FP8-e4m3fn/resolve/main/seedvr2_ema_3b_fp8_e4m3fn.safetensors",
        "SEEDVR2",
        []
    ),
    "ema_vae_fp16.safetensors": (
        "https://huggingface.co/themindstudio/SeedVR2-3B-FP8-e4m3fn/resolve/main/ema_vae_fp16.safetensors",
        "SEEDVR2",
        []
    ),
    "4x-UltraSharpV2.safetensors": (
        "https://huggingface.co/Kim2091/UltraSharpV2/resolve/main/4x-UltraSharpV2.safetensors",
        "upscale_models",
        []
    ),
    "LTX-2.3-22b-AV-LoRA-talking-head-v1.safetensors": (
        "https://huggingface.co/elix3r/LTX-2.3-22b-AV-LoRA-talking-head/resolve/main/LTX-2.3-22b-AV-LoRA-talking-head-v1.safetensors",
        "loras",
        []
    )
}

def get_hf_token() -> str:
    """Retrieve Hugging Face token from environment variables."""
    return os.getenv("HF_TOKEN") or os.getenv("HUGGING_FACE_HUB_TOKEN") or ""

def download_file_python(url: str, dest_path: Path):
    """Download a file using Python's built-in urllib with chunked writing and HF auth."""
    import urllib.request
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    temp_dest = dest_path.with_suffix(".tmp")
    
    headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
    token = get_hf_token()
    if token and "huggingface.co" in url:
        headers['Authorization'] = f'Bearer {token}'

    logger.info(f"Downloading {url} via Python urllib to {temp_dest}...")
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=300) as response, open(temp_dest, 'wb') as out_file:
            meta = response.info()
            total_size_str = meta.get("Content-Length")
            total_size = int(total_size_str) if total_size_str else 0
            
            chunk_size = 2 * 1024 * 1024  # 2 MB
            downloaded = 0
            last_reported = 0
            
            while True:
                chunk = response.read(chunk_size)
                if not chunk:
                    break
                out_file.write(chunk)
                downloaded += len(chunk)
                
                # Log progress every 500MB to avoid log spamming
                if downloaded - last_reported >= 500 * 1024 * 1024:
                    percent_str = f" ({int(downloaded/total_size*100)}%)" if total_size else ""
                    logger.info(f"Progress {dest_path.name}: {downloaded // (1024*1024)}MB / {total_size // (1024*1024)}MB{percent_str}")
                    last_reported = downloaded
                    
        temp_dest.rename(dest_path)
        logger.info(f"Completed download: {dest_path.name}")
    except Exception as e:
        if temp_dest.exists():
            try:
                temp_dest.unlink()
            except Exception:
                pass
        raise e

def download_file(url: str, dest_path: Path):
    """Download a file using aria2c with multi-connection acceleration, falling back to python urllib."""
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    
    cmd = ["aria2c", "-x", "16", "-s", "16", "-o", dest_path.name, "-d", str(dest_path.parent)]
    token = get_hf_token()
    if token and "huggingface.co" in url:
        cmd.extend(["--header", f"Authorization: Bearer {token}"])
    cmd.append(url)

    try:
        logger.info(f"Running download command: {' '.join(cmd)}")
        subprocess.run(cmd, check=True)
        return
    except Exception as e:
        logger.warning(f"aria2c download failed or not found ({e}). Cleaning up and falling back to Python urllib.")
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
        
    download_file_python(url, dest_path)

def create_symlink_or_copy(src: Path, dst: Path):
    """Safely create a relative symlink to dst, or fallback to file copy."""
    if dst.exists():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
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
        
    url_info = MODEL_MAP[model_filename]
    primary_url = url_info[0]
    subfolder = url_info[1]
    mirrors = url_info[2] if len(url_info) > 2 else []

    models_dir = get_comfy_models_dir()
    dest_path = models_dir / subfolder / model_filename
    
    # Special handle for linked files
    if model_filename == "ltx-2.3-spatial-upscaler-x2-1.0.safetensors":
        dest_11 = models_dir / subfolder / "ltx-2.3-spatial-upscaler-x2-1.1.safetensors"
        if not dest_11.exists():
            logger.info("Downloading main spatial upscaler v1.1 first...")
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

    # Download to main path with fallback to mirrors
    urls_to_try = [primary_url] + mirrors
    download_success = False
    last_err = None

    for candidate_url in urls_to_try:
        try:
            logger.info(f"Attempting download for {model_filename} from {candidate_url}...")
            download_file(candidate_url, dest_path)
            download_success = True
            logger.info(f"Successfully downloaded {model_filename}!")
            break
        except Exception as e:
            last_err = e
            logger.warning(f"Download failed from {candidate_url}: {e}")

    if not download_success:
        if "Lightricks/LTX-2.5" in primary_url and not get_hf_token():
            logger.error(
                f"Failed to download {model_filename}. Lightricks/LTX-2.5 is a gated Hugging Face repository. "
                f"Please accept terms at https://huggingface.co/Lightricks/LTX-2.5 and set the HF_TOKEN environment variable."
            )
        raise RuntimeError(f"Could not download model {model_filename}: {last_err}")

    # Populate to alternative folders
    for alt in alt_folders:
        create_symlink_or_copy(dest_path, models_dir / alt / model_filename)

def wait_for_comfyui(host="127.0.0.1", port=8188, timeout=600):
    """Wait for ComfyUI server to become reachable on the local port."""
    import socket
    import time
    logger.info(f"Pre-flight check: Waiting for ComfyUI to become reachable on {host}:{port} (timeout: {timeout}s)...")
    start_time = time.time()
    last_log = start_time
    while time.time() - start_time < timeout:
        try:
            with socket.create_connection((host, port), timeout=2):
                logger.info("ComfyUI server is reachable and active!")
                return True
        except (socket.timeout, ConnectionRefusedError):
            time.sleep(3)
            if time.time() - last_log >= 30:
                elapsed = int(time.time() - start_time)
                logger.info(f"Still waiting for ComfyUI / model download to finish ({elapsed}s / {timeout}s)...")
                last_log = time.time()
    logger.error(f"ComfyUI server was not reachable after {timeout} seconds on startup.")
    return False

def download_missing_models(workflow_prompt: Dict[str, Any]):
    """Scan the workflow prompt for inputs matching known model filenames, and download them."""
    if not wait_for_comfyui(timeout=300):
        raise RuntimeError("ComfyUI server (127.0.0.1:8188) not reachable during pre-flight check.")

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
