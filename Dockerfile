FROM runpod/worker-comfyui:5.8.6-base

# Force update ComfyUI to the latest version to support Krea-2 / Qwen3-VL
RUN cd /comfyui && git fetch --all && git reset --hard origin/master

# Patch handler scripts to support 'gifs' and 'videos' output keys from VHS_VideoCombine
RUN python3 -c " \
for p in ['/handler.py', '/rp_handler.py']: \
    try: \
        with open(p, 'r') as f: content = f.read(); \
        content = content.replace('\"images\" in node_output', 'any(k in node_output for k in [\"images\", \"gifs\", \"videos\"])'); \
        content = content.replace('node_output[\"images\"]', '(node_output.get(\"images\", []) + node_output.get(\"gifs\", []) + node_output.get(\"videos\", []))'); \
        content = content.replace('\"images\" not in node_output', 'not any(k in node_output for k in [\"images\", \"gifs\", \"videos\"])'); \
        with open(p, 'w') as f: f.write(content); \
        print('Patched', p); \
    except Exception as e: print('Could not patch', p, e) \
"

# Install updated ComfyUI requirements inside the virtual environment
RUN /opt/venv/bin/pip install --upgrade pip && \
    /opt/venv/bin/pip install -r /comfyui/requirements.txt

# Install python dependencies for custom nodes (decord, opencv, diffusers, etc.)
RUN /opt/venv/bin/pip install gguf decord simpleeval numpy opencv-python-headless pillow torchaudio diffusers imageio-ffmpeg kornia==0.8.2 rotary-embedding-torch omegaconf sentencepiece protobuf

# Copy the extra model paths configuration
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml

# Copy our custom startup wrapper script (do NOT overwrite the original /start.sh)
COPY runpod_start.sh /runpod_start.sh
RUN chmod +x /runpod_start.sh

# Run the startup wrapper script on container boot
CMD ["/runpod_start.sh"]
