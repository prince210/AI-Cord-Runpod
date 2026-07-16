FROM runpod/worker-comfyui:5.8.6-base

# Force update ComfyUI to the latest version to support Krea-2 / Qwen3-VL
RUN cd /comfyui && git fetch --all && git reset --hard origin/master

# Copy the extra model paths configuration
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml

# Copy our custom startup script and make it executable
COPY runpod_start.sh /start.sh
RUN chmod +x /start.sh

# Run the startup script on container boot
CMD ["/start.sh"]
