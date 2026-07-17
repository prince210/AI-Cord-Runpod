#!/bin/bash
echo "=== Custom RunPod Startup Script ==="

# Link Custom Nodes from Network Volume
if [ -d /runpod-volume/ComfyUI/custom_nodes ]; then
  echo "Linking custom nodes from Network Volume..."
  rm -rf /comfyui/custom_nodes
  ln -s /runpod-volume/ComfyUI/custom_nodes /comfyui/custom_nodes
else
  echo "Warning: /runpod-volume/ComfyUI/custom_nodes not found!"
fi

# Execute the original start script of the base image
echo "Executing original start.sh..."
exec /start.sh
