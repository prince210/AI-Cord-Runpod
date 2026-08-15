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

# Patch handler scripts to support 'gifs' and 'videos' output keys and on-demand model downloader
echo "Patching Runpod handler script for outputs and on-demand downloader..."
python3 -c "
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
