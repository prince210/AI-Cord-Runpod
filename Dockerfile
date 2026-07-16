FROM runpod/worker-comfyui:5.8.6-base

# Force update ComfyUI to the latest version to support Krea-2 / Qwen3-VL
RUN cd /comfyui && git fetch --all && git reset --hard origin/master

# Copy the extra model paths configuration
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml

# Copy our custom startup wrapper script (do NOT overwrite the original /start.sh)
COPY runpod_start.sh /runpod_start.sh
RUN chmod +x /runpod_start.sh

# Run the startup wrapper script on container boot
CMD ["/runpod_start.sh"]
