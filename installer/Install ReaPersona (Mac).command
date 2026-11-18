#!/bin/bash
# ReaPersona setup for macOS: double-click this file (if macOS blocks it: System Settings > Privacy & Security > Open Anyway, since it isn't from
# the App Store). It runs install_mac.sh from this folder, or downloads it from ReaPersona's GitHub if this file was downloaded on its own.
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HERE/install_mac.sh" ]; then bash "$HERE/install_mac.sh"
else curl -fsSL "https://github.com/FmsJay/ReaPersona/raw/main/installer/install_mac.sh?$(date +%s)" | bash; fi
echo
read -r -p "Press Return to close this window. " _
