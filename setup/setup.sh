#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Trend AI Demo — Full Setup Script
# Target: AWS EC2 g4dn.4xlarge (Ubuntu 22.04, NVIDIA T4 16GB)
# ═══════════════════════════════════════════════════════════════
set -e

echo "════════════════════════════════════════"
echo " Trend AI Demo — Setup Starting"
echo "════════════════════════════════════════"

# ─── 1. System update ────────────────────────────────────────────────────────
echo "[1/9] Updating system packages..."
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y \
    build-essential \
    git curl wget unzip \
    python3.11 python3.11-dev python3.11-venv python3-pip \
    linux-headers-$(uname -r) \
    apt-transport-https ca-certificates gnupg lsb-release

# ─── 2. NVIDIA Driver ────────────────────────────────────────────────────────
echo "[2/9] Installing NVIDIA drivers..."
sudo apt-get install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall

# Verify (may need reboot first)
echo "Driver install done. If nvidia-smi fails, reboot and re-run from step 3."

# ─── 3. CUDA 12.1 Toolkit ────────────────────────────────────────────────────
echo "[3/9] Installing CUDA 12.1..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get install -y cuda-toolkit-12-1

# Add CUDA to PATH
echo 'export PATH=/usr/local/cuda-12.1/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.1/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc

# ─── 4. Python environment ───────────────────────────────────────────────────
echo "[4/9] Setting up Python virtual environment..."
cd ~
python3.11 -m venv trend-ai-env
source ~/trend-ai-env/bin/activate

pip install --upgrade pip wheel setuptools

# ─── 5. PyTorch with CUDA ────────────────────────────────────────────────────
echo "[5/9] Installing PyTorch with CUDA 12.1 support..."
pip install torch==2.3.0 torchvision==0.18.0 torchaudio==2.3.0 \
    --index-url https://download.pytorch.org/whl/cu121

# Quick GPU sanity check
python3 -c "import torch; print('CUDA available:', torch.cuda.is_available()); print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NONE')"

# ─── 6. Backend dependencies ─────────────────────────────────────────────────
echo "[6/9] Installing backend dependencies..."
cd ~/trend-ai-demo/backend
pip install -r requirements.txt

# bitsandbytes needs CUDA to compile — install separately
pip install bitsandbytes==0.43.1

# ─── 7. HuggingFace login & model download ───────────────────────────────────
echo "[7/9] HuggingFace setup..."
echo ""
echo "⚠  You need a HuggingFace account with access to Meta Llama 3.1"
echo "   Get access at: https://huggingface.co/meta-llama/Meta-Llama-3.1-8B-Instruct"
echo ""
read -p "Enter your HuggingFace token (hf_...): " HF_TOKEN
huggingface-cli login --token "$HF_TOKEN"

echo "Pre-downloading model weights (this may take 10-15 min, ~16GB)..."
python3 -c "
from transformers import AutoTokenizer, AutoModelForCausalLM
import torch
print('Downloading tokenizer...')
AutoTokenizer.from_pretrained('meta-llama/Meta-Llama-3.1-8B-Instruct')
print('Tokenizer downloaded. Model will be loaded at runtime.')
print('Done.')
"

# ─── 8. Node.js & Frontend ───────────────────────────────────────────────────
echo "[8/9] Installing Node.js and frontend dependencies..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

cd ~/trend-ai-demo/frontend
npm install

echo "Building Next.js frontend..."
npm run build

# ─── 9. IAM Policy (informational) ──────────────────────────────────────────
echo "[9/9] Setup complete!"
echo ""
echo "════════════════════════════════════════════════════════════"
echo " REQUIRED IAM POLICY FOR DEMO EC2 INSTANCE"
echo "════════════════════════════════════════════════════════════"
cat << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "IAMReadForDemo",
      "Effect": "Allow",
      "Action": [
        "iam:ListRoles",
        "iam:ListAttachedRolePolicies",
        "iam:GetRole",
        "iam:ListRolePolicies"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2ReadForDemo",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeInstanceTypes"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSForDemo",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF
echo ""
echo "Attach this policy to the EC2 instance IAM role."
echo "════════════════════════════════════════════════════════════"
echo ""
echo "✅ Setup complete! Next steps:"
echo ""
echo "  1. Reboot if you just installed NVIDIA drivers:"
echo "       sudo reboot"
echo ""
echo "  2. Start the backend:"
echo "       source ~/trend-ai-env/bin/activate"
echo "       cd ~/trend-ai-demo/backend"
echo "       uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1"
echo ""
echo "  3. Start the frontend (new terminal):"
echo "       cd ~/trend-ai-demo/frontend"
echo "       npm start"
echo ""
echo "  4. Open in browser:"
echo "       http://<EC2-PUBLIC-IP>:3000"
echo ""
echo "  5. Make sure security group allows inbound TCP on 3000 and 8000."
echo ""
