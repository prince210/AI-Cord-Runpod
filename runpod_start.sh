#!/bin/bash
echo "=== Custom RunPod Startup Script ==="

# Link Custom Nodes from Network Volume
if [ -d /runpod-volume/ComfyUI/custom_nodes ]; then
  echo "Linking custom nodes from Network Volume..."
  rm -rf /comfyui/custom_nodes
  ln -s /runpod-volume/ComfyUI/custom_nodes /comfyui/custom_nodes
else
  echo "Warning: /runpod-volume/ComfyUI/custom_nodes not found!"
  mkdir -p /comfyui/custom_nodes
fi

# Ensure all critical custom nodes are present on the volume
declare -A REQUIRED_NODES=(
  ["ComfyUI-LTXVideo"]="https://github.com/lightricks/ComfyUI-LTXVideo.git"
  ["ComfyUI-VideoHelperSuite"]="https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
  ["ComfyUI-GGUF"]="https://github.com/city96/ComfyUI-GGUF.git"
  ["comfyui-kjnodes"]="https://github.com/Kijai/comfyui-kjnodes.git"
  ["rgthree-comfy"]="https://github.com/rgthree/rgthree-comfy.git"
)

for node in "${!REQUIRED_NODES[@]}"; do
  if [ ! -d "/comfyui/custom_nodes/$node" ]; then
    echo "Cloning missing custom node: $node..."
    git clone "${REQUIRED_NODES[$node]}" "/comfyui/custom_nodes/$node"
  fi
done

# Execute the original start script of the base image
echo "Executing original start.sh..."
exec /start.sh
