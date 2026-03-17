#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Trend AI Demo — Full Setup Script
# Target: AWS EC2 g4dn.4xlarge (Ubuntu 22.04, NVIDIA T4 16GB)
# Compatible with: Deep Learning Base OSS Nvidia AMI Ubuntu 22.04
#
# Usage: bash setup.sh --hf-token hf_xxxxxxxxxxxx
# ═══════════════════════════════════════════════════════════════
set -e

# ─── Parse arguments ─────────────────────────────────────────────────────────
HF_TOKEN=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --hf-token) HF_TOKEN="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$HF_TOKEN" ]; then
    echo ""
    echo "Usage: bash setup.sh --hf-token hf_xxxxxxxxxxxx"
    echo ""
    echo "Get your token at: https://huggingface.co/settings/tokens"
    echo "You need access to: https://huggingface.co/meta-llama/Meta-Llama-3.1-8B-Instruct"
    echo ""
    read -p "Enter your HuggingFace token: " HF_TOKEN
    if [ -z "$HF_TOKEN" ]; then
        echo "ERROR: HuggingFace token is required."
        exit 1
    fi
fi

# ─── Resolve repo root ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "════════════════════════════════════════"
echo " Trend AI Demo — Setup Starting"
echo " Repo: $REPO_ROOT"
echo "════════════════════════════════════════"
echo ""

# ─── 1. System update ────────────────────────────────────────────────────────
echo "[1/7] Updating system packages..."
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y \
    build-essential \
    git curl wget unzip \
    python3.11 python3.11-dev python3.11-venv python3-pip \
    apt-transport-https ca-certificates gnupg lsb-release

# ─── 2. Check NVIDIA driver + CUDA ───────────────────────────────────────────
echo "[2/7] Checking GPU and CUDA..."

if command -v nvidia-smi &> /dev/null; then
    echo "✅ NVIDIA driver already installed:"
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
else
    echo "Installing NVIDIA drivers..."
    sudo apt-get install -y ubuntu-drivers-common
    sudo ubuntu-drivers autoinstall
    echo "⚠  Drivers installed. Reboot required — run: sudo reboot"
    echo "   Then re-run setup.sh with the same token."
    exit 0
fi

if command -v nvcc &> /dev/null; then
    echo "✅ CUDA already installed: $(nvcc --version | grep release | awk '{print $6}')"
    CUDA_PATH=$(dirname $(dirname $(which nvcc)))
    grep -qxF "export PATH=$CUDA_PATH/bin:\$PATH" ~/.bashrc || \
        echo "export PATH=$CUDA_PATH/bin:\$PATH" >> ~/.bashrc
    grep -qxF "export LD_LIBRARY_PATH=$CUDA_PATH/lib64:\$LD_LIBRARY_PATH" ~/.bashrc || \
        echo "export LD_LIBRARY_PATH=$CUDA_PATH/lib64:\$LD_LIBRARY_PATH" >> ~/.bashrc
    source ~/.bashrc
else
    echo "⚠  nvcc not found — PyTorch will use its bundled CUDA runtime. OK for inference."
fi

# ─── 3. Python environment ───────────────────────────────────────────────────
echo "[3/7] Setting up Python virtual environment..."
if [ -d "$HOME/trend-ai-env" ]; then
    echo "✅ Virtual environment already exists, reusing it."
else
    python3.11 -m venv "$HOME/trend-ai-env"
fi
source "$HOME/trend-ai-env/bin/activate"
pip install --upgrade pip wheel setuptools -q

# ─── 4. PyTorch ──────────────────────────────────────────────────────────────
echo "[4/7] Installing PyTorch with CUDA 12.1..."
pip install torch==2.3.0 torchvision==0.18.0 torchaudio==2.3.0 \
    --index-url https://download.pytorch.org/whl/cu121 -q

python3 -c "
import torch
print('CUDA available:', torch.cuda.is_available())
if torch.cuda.is_available():
    print('GPU:', torch.cuda.get_device_name(0))
    print('VRAM:', round(torch.cuda.get_device_properties(0).total_memory / 1e9, 1), 'GB')
else:
    print('WARNING: CUDA not detected — check nvidia-smi and reboot if needed')
"

# ─── 5. Backend dependencies ─────────────────────────────────────────────────
echo "[5/7] Installing backend dependencies..."
cd "$REPO_ROOT/backend"
pip install -r requirements.txt -q
pip install bitsandbytes==0.43.1 -q
echo "✅ Backend dependencies installed"

# ─── 6. HuggingFace login + model download ───────────────────────────────────
echo "[6/7] HuggingFace login and model prefetch..."
huggingface-cli login --token "$HF_TOKEN"

python3 -c "
from transformers import AutoTokenizer
print('Downloading tokenizer...')
AutoTokenizer.from_pretrained('meta-llama/Meta-Llama-3.1-8B-Instruct')
print('✅ Tokenizer ready.')
"

# ─── 7. Node.js + Frontend ───────────────────────────────────────────────────
echo "[7/7] Installing Node.js and building frontend..."

if command -v node &> /dev/null; then
    echo "✅ Node.js already installed: $(node --version)"
else
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - -q
    sudo apt-get install -y nodejs -q
fi

# Configure Next.js proxy (backend → localhost:8000)
cat > "$REPO_ROOT/frontend/next.config.mjs" << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:8000/:path*",
      },
    ];
  },
};
export default nextConfig;
EOF

# Patch page.js to use relative /api paths (idempotent)
PAGE_JS="$REPO_ROOT/frontend/app/page.js"
echo "Patching: $PAGE_JS"
python3 -c "
import re, sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()
content = re.sub(r'const API_URL.*\n', '', content)
content = re.sub(r'https?://[^\"\x27\`\s]*:8000/aws-context', '/api/aws-context', content)
content = re.sub(r'https?://[^\"\x27\`\s]*:8000/chat', '/api/chat', content)
content = content.replace('fetch(\`\${API_URL}/aws-context\`)', 'fetch("/api/aws-context")')
content = content.replace('fetch(\`\${API_URL}/chat\`', 'fetch("/api/chat"')
with open(path, 'w') as f:
    f.write(content)
print('Frontend API URLs patched OK')
" "$PAGE_JS"

cd "$REPO_ROOT/frontend"
npm install -q
npm run build
echo "✅ Frontend built"

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo " ✅ Setup complete!"
echo " Run the app with:"
echo "   bash $REPO_ROOT/setup/run.sh"
echo "════════════════════════════════════════════════════════════"
echo ""
