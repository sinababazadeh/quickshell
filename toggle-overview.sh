#!/usr/bin/env bash
# =============================================================================
#  TOGGLE-OVERVIEW.SH — trigger Quickshell workspace overview from Hyprland
# =============================================================================
#  Add this keybind to ~/.config/hypr/hyprland.conf:
#     bind = $mainMod, Tab, exec, ~/.config/quickshell/toggle-overview.sh
#  or
#     bind = $mainMod, grave, exec, ~/.config/quickshell/toggle-overview.sh
# =============================================================================

FIFO="/tmp/quickshell-overview.fifo"
if [ ! -p "$FIFO" ]; then
    rm -f "$FIFO" 2>/dev/null
    mkfifo "$FIFO" 2>/dev/null
fi

echo "toggle" > "$FIFO" 2>/dev/null || true
