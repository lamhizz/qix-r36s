#!/bin/bash
# ==============================================================================
# QIX (R36S) - Wireless / OTG Hot-Deployment Script
# Syncs qix.love over SSH/rsync and streams runtime log directly to terminal.
# Eliminates manual physical MicroSD card swapping!
# ==============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

R36S_IP="${1}"
if [ -z "$R36S_IP" ]; then
    echo "Usage: ./deploy_remote.sh <R36S_IP_ADDRESS>"
    echo "Example: ./deploy_remote.sh 192.168.1.150"
    echo ""
    echo "Tips to connect your R36S to Wi-Fi / Network:"
    echo "  1. Plug in a cheap USB Wi-Fi dongle into the OTG port (ArkOS auto-detects RTL8188 / MT7601)."
    echo "  2. Go to Options -> Wi-Fi in ArkOS to connect to your home Wi-Fi."
    echo "  3. ArkOS default SSH login is user: 'ark', password: 'ark' on port 22."
    exit 1
fi

echo "======================================================="
echo " TARGET: R36S Console at $R36S_IP"
echo "======================================================="

# 1. Run quick pre-flight verification first
if [ -f "$DIR/verify.sh" ]; then
    echo "Running local pre-flight checks..."
    "$DIR/verify.sh"
fi

# 2. Sync qix.love over rsync / ssh
echo -e "\n[1/3] Uploading qix.love to R36S..."
REMOTE_DEST="/roms2/ports/qix"
ssh -q -o BatchMode=yes -o ConnectTimeout=3 ark@$R36S_IP "test -d /roms2/ports/qix" || REMOTE_DEST="/roms/ports/qix"

rsync -avz --progress "$DIR/qix.love" "ark@$R36S_IP:$REMOTE_DEST/qix.love"

# 3. Kill running game and relaunch
echo -e "\n[2/3] Restarting Qix on hardware..."
ssh "ark@$R36S_IP" "killall -9 love gptokeyb 2>/dev/null || true; nohup /roms2/ports/Qix.sh > /dev/null 2>&1 &"

# 4. Stream live logs
echo -e "\n[3/3] Streaming live game log (Press Ctrl+C to stop stream)...\n"
ssh "ark@$R36S_IP" "tail -f $REMOTE_DEST/log.txt"
