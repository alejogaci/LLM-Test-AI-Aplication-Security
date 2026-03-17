#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Trend AI Demo — Run Script
# Starts backend and frontend in background using screen
#
# Usage: bash run.sh [--stop]
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV="$HOME/trend-ai-env"

# ─── Stop mode ───────────────────────────────────────────────────────────────
if [[ "$1" == "--stop" ]]; then
    echo "Stopping Trend AI Demo..."
    screen -X -S trend-backend quit 2>/dev/null && echo "✅ Backend stopped" || echo "Backend was not running"
    screen -X -S trend-frontend quit 2>/dev/null && echo "✅ Frontend stopped" || echo "Frontend was not running"
    echo "Done."
    exit 0
fi

# ─── Kill any previous sessions ──────────────────────────────────────────────
screen -X -S trend-backend quit 2>/dev/null || true
screen -X -S trend-frontend quit 2>/dev/null || true
sleep 1

# ─── Install screen if missing ───────────────────────────────────────────────
if ! command -v screen &> /dev/null; then
    echo "Installing screen..."
    sudo apt-get install -y screen -q
fi

# ─── Get public IP ───────────────────────────────────────────────────────────
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")

echo ""
echo "════════════════════════════════════════════════"
echo " Trend AI Demo — Starting"
echo " Repo:       $REPO_ROOT"
echo " Public IP:  $PUBLIC_IP"
echo "════════════════════════════════════════════════"
echo ""

# ─── Start Backend ───────────────────────────────────────────────────────────
echo "Starting backend..."
screen -dmS trend-backend bash -c "
    source $VENV/bin/activate
    cd $REPO_ROOT/backend
    echo '[backend] Starting uvicorn...'
    uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1 2>&1 | tee $HOME/backend.log
"

# Wait for backend to be ready
echo -n "Waiting for backend to load model (this takes ~2 min)"
for i in $(seq 1 60); do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo ""
        echo "✅ Backend is ready"
        break
    fi
    echo -n "."
    sleep 3
done

if ! curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo ""
    echo "⚠  Backend took too long. Check logs with: tail -f ~/backend.log"
fi

# ─── Start Frontend ──────────────────────────────────────────────────────────
echo "Starting frontend..."
screen -dmS trend-frontend bash -c "
    cd $REPO_ROOT/frontend
    echo '[frontend] Starting Next.js...'
    npm start 2>&1 | tee $HOME/frontend.log
"

sleep 3

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo " ✅ Trend AI Demo is running!"
echo ""
echo "  🌐 Open in browser:"
echo "     http://$PUBLIC_IP:3000"
echo ""
echo "  📋 View logs:"
echo "     tail -f ~/backend.log"
echo "     tail -f ~/frontend.log"
echo ""
echo "  🖥  Attach to sessions:"
echo "     screen -r trend-backend"
echo "     screen -r trend-frontend"
echo ""
echo "  ⛔ Stop everything:"
echo "     bash $SCRIPT_DIR/run.sh --stop"
echo "════════════════════════════════════════════════════════════"
echo ""
