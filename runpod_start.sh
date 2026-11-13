#!/bin/bash
echo "=== Custom RunPod Startup Script ==="

# Optimize PyTorch memory allocation on 24GB GPUs to prevent fragmentation and budget deficits
export PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True"

# Auto-detect Python virtualenv inside worker container
PYTHON_CMD="python3"
PIP_CMD="pip"
if [ -f "/opt/venv/bin/python" ]; then
  PYTHON_CMD="/opt/venv/bin/python"
  PIP_CMD="/opt/venv/bin/pip"
fi

# 1. Link Custom Nodes from Network Volume
if [ -d /runpod-volume/ComfyUI/custom_nodes ]; then
  echo "Linking custom nodes from /runpod-volume/ComfyUI/custom_nodes..."
  rm -rf /comfyui/custom_nodes
  ln -s /runpod-volume/ComfyUI/custom_nodes /comfyui/custom_nodes
elif [ -d /workspace/ComfyUI/custom_nodes ]; then
  echo "Linking custom nodes from /workspace/ComfyUI/custom_nodes..."
  rm -rf /comfyui/custom_nodes
  ln -s /workspace/ComfyUI/custom_nodes /comfyui/custom_nodes
else
  echo "Warning: Custom nodes directory not found on network volume!"
fi

# Ensure ComfyUI_Nvidia_VFX_Nodes (RTXVideoSuperResolution) is present
if [ -d /comfyui/custom_nodes ]; then
  if [ ! -d "/comfyui/custom_nodes/ComfyUI_Nvidia_VFX_Nodes" ]; then
    echo "Cloning ComfyUI_Nvidia_VFX_Nodes for RTX Video Super Resolution..."
    git clone https://github.com/Comfy-Org/ComfyUI_Nvidia_VFX_Nodes.git /comfyui/custom_nodes/ComfyUI_Nvidia_VFX_Nodes 2>/dev/null || true
  fi
fi

# Ensure nvidia-vfx dependency is installed in Python environment
if ! $PYTHON_CMD -c "import nvvfx" 2>/dev/null; then
  echo "Installing nvidia-vfx from NVIDIA PyPI..."
  $PIP_CMD install -U --no-build-isolation nvidia-vfx --index-url https://pypi.nvidia.com 2>/dev/null || \
  $PIP_CMD install nvidia-vfx --extra-index-url https://pypi.nvidia.com 2>/dev/null || true
fi

# 2. Setup extra_model_paths.yaml and models directories on network volume
echo "Setting up volume directory paths..."
VOL_BASE=""
if [ -d "/runpod-volume" ]; then
  VOL_BASE="/runpod-volume"
elif [ -d "/workspace" ]; then
  VOL_BASE="/workspace"
else
  VOL_BASE="/comfyui"
fi

# Ensure all standard ComfyUI model subdirectories exist on persistent volume
VOL_MODELS="$VOL_BASE/models"
mkdir -p "$VOL_MODELS/diffusion_models" "$VOL_MODELS/unet" \
         "$VOL_MODELS/text_encoders" "$VOL_MODELS/clip" \
         "$VOL_MODELS/vae" "$VOL_MODELS/latent_upscale_models" \
         "$VOL_MODELS/upscale_models" "$VOL_MODELS/checkpoints" \
         "$VOL_MODELS/loras"

# Mirror to ComfyUI/models for compatibility with any templates that look under ComfyUI/
mkdir -p "$VOL_BASE/ComfyUI"
if [ ! -e "$VOL_BASE/ComfyUI/models" ]; then
  ln -sfn "$VOL_MODELS" "$VOL_BASE/ComfyUI/models" 2>/dev/null || true
fi

# Ensure extra_model_paths.yaml is present in /comfyui/
if [ ! -f /comfyui/extra_model_paths.yaml ]; then
  for p in /runpod-volume/extra_model_paths.yaml /workspace/extra_model_paths.yaml /extra_model_paths.yaml; do
    if [ -f "$p" ]; then
      cp "$p" /comfyui/extra_model_paths.yaml
      break
    fi
  done
  if [ ! -f /comfyui/extra_model_paths.yaml ]; then
    curl -sSL https://raw.githubusercontent.com/prince210/AI-Cord-Runpod/main/extra_model_paths.yaml -o /comfyui/extra_model_paths.yaml 2>/dev/null || true
  fi
fi

# Ensure the latest downloader.py is active (pull latest from GitHub or network volume)
for p in /runpod-volume/downloader.py /workspace/downloader.py; do
  if [ -f "$p" ]; then
    cp "$p" /downloader.py
    break
  fi
done
curl -sSL https://raw.githubusercontent.com/prince210/AI-Cord-Runpod/main/downloader.py -o /downloader.py 2>/dev/null || true

echo "Target models directory on volume: $VOL_MODELS"

# Helper function to download files with aria2c multi-threaded acceleration and progress logging
download_file() {
  local url="$1"
  local dest_dir="$2"
  local filename="$3"
  local token="$4"

  mkdir -p "$dest_dir"
  if [ -f "$dest_dir/$filename" ]; then
    echo "   [✓] Already exists: $filename"
    return 0
  fi

  echo "   [→] Downloading $filename..."
  local auth_header=""
  [ -n "$token" ] && auth_header="--header=Authorization: Bearer $token"

  if command -v aria2c &> /dev/null; then
    aria2c $auth_header -x 16 -s 16 -k 1M -c --summary-interval=10 --console-log-level=warn \
           -d "$dest_dir" -o "$filename" "$url"
  else
    curl -L -C - ${token:+-H "Authorization: Bearer $token"} --progress-bar -o "$dest_dir/$filename" "$url"
  fi
}

# ==============================================================================
# Model Auto-Provisioning Registry
# Automatically provisions base models when worker boots if missing from volume.
# ==============================================================================
LTX25_CHECK_FILE="$VOL_MODELS/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors"
if [ ! -f "$LTX25_CHECK_FILE" ]; then
  TOKEN_VAL="${HF_TOKEN:-$HUGGING_FACE_HUB_TOKEN}"
  if [ -n "$TOKEN_VAL" ]; then
    echo "=== Auto-downloading missing LTX-2.5 models to $VOL_MODELS using aria2 (16 threads) ==="
    
    # 1. DiT Transformer (INT8-ConvRot: 21.8 GB)
    download_file "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" \
                  "$VOL_MODELS/diffusion_models" "ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" "$TOKEN_VAL"
                  
    # 2. Text Encoder (Gemma 4 12B: 12.5 GB)
    download_file "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" \
                  "$VOL_MODELS/text_encoders" "gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" "$TOKEN_VAL"
                  
    # 3. Video VAE (1.6 GB)
    download_file "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/vae/ltx-2.5-video-vae-bf16.safetensors" \
                  "$VOL_MODELS/vae" "ltx-2.5-video-vae-bf16.safetensors" "$TOKEN_VAL"
                  
    # 4. Audio VAE (0.8 GB)
    download_file "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/vae/ltx-2.5-audio-vae-bf16.safetensors" \
                  "$VOL_MODELS/vae" "ltx-2.5-audio-vae-bf16.safetensors" "$TOKEN_VAL"
                  
    # 5. Latent Spatial Upscaler x2 (1.1 GB)
    download_file "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" \
                  "$VOL_MODELS/latent_upscale_models" "ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" "$TOKEN_VAL"
                  
    echo "=== All LTX-2.5 models downloaded successfully! ==="
  else
    echo "Notice: LTX-2.5 models not found on $VOL_MODELS and HF_TOKEN is not set."
    echo "Set HF_TOKEN in RunPod Endpoint Environment Variables to enable auto-download."
  fi
fi

MINIMAX_CHECK_FILE="$VOL_MODELS/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"
if [ ! -f "$MINIMAX_CHECK_FILE" ]; then
  TOKEN_VAL="${HF_TOKEN:-$HUGGING_FACE_HUB_TOKEN}"
  echo "=== Auto-downloading missing MiniMax H3 models to $VOL_MODELS using aria2 (16 threads) ==="
  
  # 1. DiT Transformer (INT8-ConvRot: 19.53 GB)
  download_file "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
                "$VOL_MODELS/diffusion_models" "minimax_h3_fl2va_pruned_int8_convrot.safetensors" "$TOKEN_VAL"
                
  # 2. Text Encoder (Qwen3-VL 32B NVFP4/AWQ: 14.61 GB)
  download_file "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
                "$VOL_MODELS/text_encoders" "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" "$TOKEN_VAL"
                
  # 3. Video VAE (INT8-ConvRot: 2.62 GB)
  download_file "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_int8_convrot.safetensors" \
                "$VOL_MODELS/vae" "minimax_h3_video_vae_int8_convrot.safetensors" "$TOKEN_VAL"
                
  # 4. Audio VAE (FP32: 577.2 MB)
  download_file "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors" \
                "$VOL_MODELS/vae" "minimax_h3_audio_vae_fp32.safetensors" "$TOKEN_VAL"
                
  # 5. Turbo 8-step LoRA (1.82 GB)
  download_file "https://huggingface.co/lightx2v/Minimax-h3-Turbo/resolve/main/loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors" \
                "$VOL_MODELS/loras" "minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors" "$TOKEN_VAL"
                
  echo "=== All MiniMax H3 models downloaded successfully! ==="
fi

echo "Linking models from $VOL_MODELS into /comfyui/models/..."
mkdir -p /comfyui/models
for sub in unet diffusion_models clip text_encoders vae latent_upscale_models upscale_models checkpoints loras; do
  if [ -d "$VOL_MODELS/$sub" ]; then
    mkdir -p "/comfyui/models/$sub"
    for f in "$VOL_MODELS/$sub"/*; do
      if [ -e "$f" ]; then
        ln -sf "$f" "/comfyui/models/$sub/" 2>/dev/null || true
      fi
    done
  fi
done

# Ensure unet <-> diffusion_models cross-compatibility
mkdir -p /comfyui/models/unet /comfyui/models/diffusion_models
for f in /comfyui/models/diffusion_models/*; do
  [ -e "$f" ] && ln -sf "$f" /comfyui/models/unet/ 2>/dev/null || true
done
for f in /comfyui/models/unet/*; do
  [ -e "$f" ] && ln -sf "$f" /comfyui/models/diffusion_models/ 2>/dev/null || true
done

# Ensure clip <-> text_encoders cross-compatibility
mkdir -p /comfyui/models/clip /comfyui/models/text_encoders
for f in /comfyui/models/text_encoders/*; do
  [ -e "$f" ] && ln -sf "$f" /comfyui/models/clip/ 2>/dev/null || true
done
for f in /comfyui/models/clip/*; do
  [ -e "$f" ] && ln -sf "$f" /comfyui/models/text_encoders/ 2>/dev/null || true
done

# 3. Patch handler scripts to support 'gifs' and 'videos' output keys and on-demand model downloader
echo "Patching Runpod handler script for outputs and on-demand downloader..."
$PYTHON_CMD -c "
import re
for p in ['/handler.py', '/rp_handler.py']:
    try:
        with open(p, 'r') as f: content = f.read()
        content = content.replace('\"images\" in node_output', 'any(k in node_output for k in [\"images\", \"gifs\", \"videos\"])')
        content = content.replace('\"images\" not in node_output', 'not any(k in node_output for k in [\"images\", \"gifs\", \"videos\"])')
        content = content.replace('node_output[\"images\"]', '(node_output.get(\"images\") or node_output.get(\"gifs\") or node_output.get(\"videos\") or [])')
        content = content.replace(\"node_output['images']\", \"(node_output.get('images') or node_output.get('gifs') or node_output.get('videos') or [])\")
        
        # Inject on-demand downloader invocation
        content = re.sub(
            r'def handler\s*\(\s*job\s*\)\s*:',
            'def handler(job):\n    try:\n        import sys\n        if \"/\" not in sys.path: sys.path.append(\"/\")\n        import downloader\n        downloader.download_missing_models(job.get(\"input\", {}).get(\"workflow\", {}))\n    except Exception as downloader_err:\n        print(\"On-demand downloader failed:\", downloader_err)\n        raise downloader_err\n',
            content
        )
        
        with open(p, 'w') as f: f.write(content)
        print('Successfully patched handler:', p)
    except Exception as e:
        print('Could not patch handler:', p, e)
"

# Execute the original start script of the base image
echo "Executing original start.sh..."
exec /start.sh
