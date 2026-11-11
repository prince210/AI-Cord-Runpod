#!/bin/bash
# ==============================================================================
# RunPod ComfyUI Serverless Volume Setup Script
# Description: Automates cloning of ComfyUI, installation of required custom
#              nodes, Python dependencies, and downloading of all model files
#              including LTX-2.5, Krea-2 Turbo, and RTX Upscaler models.
# ==============================================================================

set -e

# Target path on the RunPod Network Volume (auto-detects /runpod-volume vs /workspace)
if [ -d "/runpod-volume" ]; then
    BASE_DIR="/runpod-volume"
elif [ -d "/workspace" ]; then
    BASE_DIR="/workspace"
else
    BASE_DIR="$(pwd)"
fi

COMFY_DIR="$BASE_DIR/ComfyUI"

echo "============================================================"
echo "Starting ComfyUI Serverless Setup on Volume: $BASE_DIR"
echo "============================================================"

# Check Hugging Face token for gated models (Lightricks/LTX-2.5)
if [ -z "$HF_TOKEN" ]; then
    echo "========================================================================"
    echo "WARNING: HF_TOKEN environment variable is not set!"
    echo "Lightricks/LTX-2.5 is a GATED model on Hugging Face."
    echo "1. Accept access: https://huggingface.co/Lightricks/LTX-2.5"
    echo "2. Generate token: https://huggingface.co/settings/tokens"
    echo "3. Run: export HF_TOKEN=\"hf_...\" before running this script."
    echo "========================================================================"
fi

# Ensure base directory exists
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# 1. Clone ComfyUI if not already present
if [ ! -d "$COMFY_DIR" ]; then
    echo " -> Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git
else
    echo " -> ComfyUI already exists."
fi

# 2. Clone/Update Custom Nodes
CUSTOM_NODES_DIR="$COMFY_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODES_DIR"
cd "$CUSTOM_NODES_DIR"

echo " -> Processing custom node repositories..."
declare -A CUSTOM_NODES=(
    ["ComfyUI-Manager"]="https://github.com/ltdrdata/ComfyUI-Manager.git"
    ["ComfyUI-VideoHelperSuite"]="https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    ["comfyui-kjnodes"]="https://github.com/Kijai/comfyui-kjnodes.git"
    ["ComfyUI-GGUF"]="https://github.com/city96/ComfyUI-GGUF.git"
    ["cg-use-everywhere"]="https://github.com/chrisgoringe/cg-use-everywhere.git"
    ["rgthree-comfy"]="https://github.com/rgthree/rgthree-comfy.git"
    ["ComfyUI-SeedVR2_VideoUpscaler"]="https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git"
    ["one-node-flux-2-klein"]="https://github.com/yanokusnir-ai/one-node-flux-2-klein.git"
    ["ComfyUI_ResolutionSelectorPlus"]="https://github.com/bradsec/ComfyUI_ResolutionSelectorPlus.git"
    ["ComfyUI-LTXVideo"]="https://github.com/lightricks/ComfyUI-LTXVideo.git"
    ["ComfyMath"]="https://github.com/evanspearman/ComfyMath.git"
    ["ComfyLiterals"]="https://github.com/M1kep/ComfyLiterals.git"
    ["ComfyUI-LTX2-MultiGPU"]="https://github.com/dreamfast/ComfyUI-LTX2-MultiGPU.git"
    ["Nvidia_RTX_Nodes_ComfyUI"]="https://github.com/NVIDIA/Nvidia_RTX_Nodes_ComfyUI.git"
)

for node in "${!CUSTOM_NODES[@]}"; do
    if [ ! -d "$node" ]; then
        echo "   - Cloning custom node: $node..."
        git clone "${CUSTOM_NODES[$node]}" "$node"
    else
        echo "   - Custom node $node already exists. Updating..."
        cd "$node" && git pull && cd ..
    fi
done

# 3. Install Python Dependencies
echo " -> Installing required Python packages..."
pip install --upgrade pip
pip install gguf decord simpleeval numpy opencv-python pillow torchaudio --hash-style=gnu || pip install gguf decord simpleeval numpy opencv-python pillow torchaudio

# Install custom node specific requirements
for req in $(find . -maxdepth 2 -name "requirements.txt"); do
    echo "   - Installing requirements from $req..."
    pip install -r "$req" || echo "Warning: Failed to install some requirements from $req"
done

# 4. Create Model Directories
echo " -> Creating model directories..."
MODELS_DIR="$COMFY_DIR/models"
mkdir -p "$MODELS_DIR/unet"
mkdir -p "$MODELS_DIR/vae"
mkdir -p "$MODELS_DIR/text_encoders"
mkdir -p "$MODELS_DIR/clip"
mkdir -p "$MODELS_DIR/checkpoints"
mkdir -p "$MODELS_DIR/latent_upscale_models"
mkdir -p "$MODELS_DIR/upscale_models"
mkdir -p "$MODELS_DIR/loras"
mkdir -p "$MODELS_DIR/SEEDVR2"
mkdir -p "$MODELS_DIR/diffusion_models"

# 5. Helper function for downloading models with aria2c and HF token support
download_model() {
    local url=$1
    local dest_path=$2
    local filename=$3
    local fallback_url=$4
    
    mkdir -p "$dest_path"
    cd "$dest_path"
    
    if [ -f "$filename" ]; then
        echo "   - Model $filename already exists, skipping."
        return 0
    fi

    echo "   - Downloading $filename..."
    local success=false

    # Build auth header if HF_TOKEN is present and URL targets huggingface.co
    local aria_auth=""
    local curl_auth=()
    if [ -n "$HF_TOKEN" ] && [[ "$url" == *"huggingface.co"* ]]; then
        aria_auth="--header=Authorization: Bearer $HF_TOKEN"
        curl_auth=(-H "Authorization: Bearer $HF_TOKEN")
    fi

    # Attempt primary download
    if command -v aria2c &> /dev/null; then
        if [ -n "$aria_auth" ]; then
            aria2c "$aria_auth" -x 16 -s 16 -o "$filename" "$url" && success=true || success=false
        else
            aria2c -x 16 -s 16 -o "$filename" "$url" && success=true || success=false
        fi
    fi

    if [ "$success" = false ]; then
        curl "${curl_auth[@]}" -L -C - -o "$filename" "$url" && success=true || success=false
    fi

    # If primary failed and fallback URL is provided, try fallback mirror
    if [ "$success" = false ] && [ -n "$fallback_url" ]; then
        echo "   ! Primary URL failed. Trying fallback mirror: $fallback_url"
        rm -f "$filename" "$filename.aria2"
        if command -v aria2c &> /dev/null; then
            aria2c -x 16 -s 16 -o "$filename" "$fallback_url" && success=true || success=false
        fi
        if [ "$success" = false ]; then
            curl -L -C - -o "$filename" "$fallback_url" && success=true || success=false
        fi
    fi

    if [ "$success" = false ]; then
        echo "   ERROR: Failed to download $filename from both primary and fallback mirrors."
        if [[ "$url" == *"Lightricks/LTX-2.5"* ]] && [ -z "$HF_TOKEN" ]; then
            echo "   NOTE: Lightricks/LTX-2.5 is a gated Hugging Face repo. Please accept license at https://huggingface.co/Lightricks/LTX-2.5 and export HF_TOKEN=hf_..."
        fi
        return 1
    fi
}

if [ "$SKIP_MODEL_DOWNLOADS" = "true" ]; then
    echo " -> SKIP_MODEL_DOWNLOADS is set to true. Bypassing model weights downloading."
    exit 0
fi

echo " -> Downloading model weights..."

# ==============================================================================
# --- LTX-Video 2.5 (Fast 22B Keyframe Diffusion for RTX 4090 / RTX 5090) ---
# ==============================================================================
echo " -> Downloading LTX-2.5 Foundation & Upscaler Models..."

mkdir -p "$MODELS_DIR/diffusion_models" "$MODELS_DIR/unet" \
         "$MODELS_DIR/text_encoders" "$MODELS_DIR/clip" \
         "$MODELS_DIR/vae" "$MODELS_DIR/latent_upscale_models"

# Prefer high-speed huggingface-cli with hf_transfer if HF_TOKEN is present
if [ -n "$HF_TOKEN" ]; then
    echo " -> HF_TOKEN detected. Using accelerated parallel huggingface-cli download..."
    pip install -q -U "huggingface_hub[hf_transfer]" || true
    export HF_HUB_ENABLE_HF_TRANSFER=1
    huggingface-cli download Lightricks/LTX-2.5 \
      diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors \
      text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors \
      vae/ltx-2.5-video-vae-bf16.safetensors \
      vae/ltx-2.5-audio-vae-bf16.safetensors \
      latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors \
      --local-dir "$MODELS_DIR" \
      --token "$HF_TOKEN" || echo "Warning: huggingface-cli encountered error, falling back to per-file download."
fi

# 1. Core DiT Transformer (INT8-ConvRot: 21.8 GB - Fits fully in 24GB/32GB VRAM without CPU paging)
if [ ! -f "$MODELS_DIR/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" ]; then
    download_model "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" \
                   "$MODELS_DIR/diffusion_models" "ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" \
                   "https://huggingface.co/PulpCut/LTX-2.5-INT8-ConvRot-safetensors/resolve/main/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors"
fi
ln -sf "$MODELS_DIR/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" "$MODELS_DIR/unet/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" 2>/dev/null || true

# 2. Text Encoder (Gemma 4 12B with Projected Embeddings)
if [ ! -f "$MODELS_DIR/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" ]; then
    download_model "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" \
                   "$MODELS_DIR/text_encoders" "gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" \
                   "https://huggingface.co/PulpCut/LTX-2.5-INT8-ConvRot-safetensors/resolve/main/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors"
fi
ln -sf "$MODELS_DIR/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" "$MODELS_DIR/clip/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" 2>/dev/null || true

# 3. Video VAE (Diffusion Decoder)
if [ ! -f "$MODELS_DIR/vae/ltx-2.5-video-vae-bf16.safetensors" ]; then
    download_model "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/vae/ltx-2.5-video-vae-bf16.safetensors" \
                   "$MODELS_DIR/vae" "ltx-2.5-video-vae-bf16.safetensors" \
                   "https://huggingface.co/PulpCut/LTX-2.5-INT8-ConvRot-safetensors/resolve/main/ltx-2.5-video-vae-bf16.safetensors"
fi

# 4. Audio VAE (Synchronized Audio Generation)
if [ ! -f "$MODELS_DIR/vae/ltx-2.5-audio-vae-bf16.safetensors" ]; then
    download_model "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/vae/ltx-2.5-audio-vae-bf16.safetensors" \
                   "$MODELS_DIR/vae" "ltx-2.5-audio-vae-bf16.safetensors" \
                   "https://huggingface.co/PulpCut/LTX-2.5-INT8-ConvRot-safetensors/resolve/main/ltx-2.5-audio-vae-bf16.safetensors"
fi

# 5. Latent Spatial Upscaler x2 (Crucial for 2-stage latent upscaling to 720p/1080p)
if [ ! -f "$MODELS_DIR/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" ]; then
    download_model "https://huggingface.co/Lightricks/LTX-2.5/resolve/main/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" \
                   "$MODELS_DIR/latent_upscale_models" "ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" \
                   "https://huggingface.co/PulpCut/LTX-2.5-INT8-ConvRot-safetensors/resolve/main/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors"
fi

# 6. Optional Prompt Enhancer Text Encoder (Expands short prompts into rich instructions)
download_model "https://huggingface.co/Comfy-Org/gemma-4/resolve/main/text_encoders/gemma4_e2b_it_int8_convrot.safetensors" \
               "$MODELS_DIR/text_encoders" "gemma4_e2b_it_int8_convrot.safetensors"


# ==============================================================================
# --- Krea-2 Turbo (Rapid 1-step Image Generation) ---
# ==============================================================================
download_model "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors" \
               "$MODELS_DIR/diffusion_models" "krea2_turbo_fp8_scaled.safetensors"

download_model "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors" \
               "$MODELS_DIR/vae" "qwen_image_vae.safetensors"

download_model "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors" \
               "$MODELS_DIR/text_encoders" "qwen3vl_4b_fp8_scaled.safetensors"

download_model "https://huggingface.co/Comfy-Org/Krea-2/resolve/bd08c3d74c5e15941c953926e0f9f24f6016f47c/loras/krea2_warmpastel.safetensors" \
               "$MODELS_DIR/loras" "krea2_warmpastel.safetensors"


# ==============================================================================
# --- LTX-Video 2.3 Legacy Checkpoints ---
# ==============================================================================
download_model "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors" \
               "$MODELS_DIR/diffusion_models" "ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors"

download_model "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors" \
               "$MODELS_DIR/vae" "ltx-2.3-22b-distilled_video_vae.safetensors"

download_model "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors" \
               "$MODELS_DIR/checkpoints" "ltx-2.3-22b-distilled_audio_vae.safetensors"

download_model "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors" \
               "$MODELS_DIR/text_encoders" "ltx-2.3-22b-distilled_embeddings_connectors.safetensors"

download_model "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors" \
               "$MODELS_DIR/latent_upscale_models" "ltx-2.3-spatial-upscaler-x2-1.1.safetensors"

ln -sf "$MODELS_DIR/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors" "$MODELS_DIR/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.0.safetensors" 2>/dev/null || true


# ==============================================================================
# --- SeedVR2 (Video Restoration / Upscaler) ---
# ==============================================================================
download_model "https://huggingface.co/themindstudio/SeedVR2-3B-FP8-e4m3fn/resolve/main/seedvr2_ema_3b_fp8_e4m3fn.safetensors" \
               "$MODELS_DIR/SEEDVR2" "seedvr2_ema_3b_fp8_e4m3fn.safetensors"

download_model "https://huggingface.co/themindstudio/SeedVR2-3B-FP8-e4m3fn/resolve/main/ema_vae_fp16.safetensors" \
               "$MODELS_DIR/SEEDVR2" "ema_vae_fp16.safetensors"


# ==============================================================================
# --- MiniMax H3 (Omni-Modal Video + Audio & RTX 4090 / 5090 Optimized) ---
# ==============================================================================
download_model "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
               "$MODELS_DIR/diffusion_models" "minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
               "https://modelscope.cn/models/Comfy-Org/MiniMax-H3/resolve/master/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"

download_model "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
               "$MODELS_DIR/text_encoders" "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
               "https://modelscope.cn/models/Comfy-Org/MiniMax-H3/resolve/master/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"

download_model "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_int8_convrot.safetensors" \
               "$MODELS_DIR/vae" "minimax_h3_video_vae_int8_convrot.safetensors" \
               "https://modelscope.cn/models/Comfy-Org/MiniMax-H3/resolve/master/vae/minimax_h3_video_vae_int8_convrot.safetensors"

download_model "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors" \
               "$MODELS_DIR/vae" "minimax_h3_audio_vae_fp32.safetensors" \
               "https://modelscope.cn/models/Comfy-Org/MiniMax-H3/resolve/master/vae/minimax_h3_audio_vae_fp32.safetensors"

download_model "https://huggingface.co/lightx2v/Minimax-h3-Turbo/resolve/main/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors" \
               "$MODELS_DIR/loras" "minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors" \
               "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors"


# ==============================================================================
# --- Extra Utilities (Upscalers & LoRAs) ---
# ==============================================================================
download_model "https://huggingface.co/Kim2091/UltraSharpV2/resolve/main/4x-UltraSharpV2.safetensors" \
               "$MODELS_DIR/upscale_models" "4x-UltraSharpV2.safetensors"

download_model "https://huggingface.co/elix3r/LTX-2.3-22b-AV-LoRA-talking-head/resolve/main/LTX-2.3-22b-AV-LoRA-talking-head-v1.safetensors" \
               "$MODELS_DIR/loras" "LTX-2.3-22b-AV-LoRA-talking-head-v1.safetensors"

# Copy extra_model_paths.yaml to the volume root and ComfyUI root if available
if [ -f "$(dirname "$0")/extra_model_paths.yaml" ]; then
    cp "$(dirname "$0")/extra_model_paths.yaml" "$BASE_DIR/extra_model_paths.yaml"
    cp "$(dirname "$0")/extra_model_paths.yaml" "$COMFY_DIR/extra_model_paths.yaml"
fi

echo "============================================================"
echo "ComfyUI Setup Completed Successfully!"
echo "Volume Base: $BASE_DIR"
echo "Models Dir:  $MODELS_DIR"
echo "============================================================"
echo "Note: If your workflows require Goddess_Durga_With_Lion_lora_000001750.safetensors,"
echo "      please upload it manually to: $MODELS_DIR/loras/"
