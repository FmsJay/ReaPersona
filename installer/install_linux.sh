#!/bin/bash
# ReaPersona setup for Linux: REAPER set up like the music app you're coming from, shortcuts included. For people new to REAPER.
# Run it in a terminal on the computer's own desktop (not over SSH: REAPER has to open):
#   curl -fsSL "https://raw.githubusercontent.com/FmsJay/ReaPersona/main/installer/install_linux.sh?$(date +%s)" | bash
# The Linux twin of install_mac.sh: same question, same answer up front, same steps. Installs what's missing and skips what's there:
# REAPER, ReaPack, ReaImGui, js_ReaScriptAPI and SWS, then ReaPersona itself (through ReaPack), then sets REAPER up as the DAW you pick;
# REAPER restarts once at the end, for the shortcuts. Everything goes in for you only (your home folder), from its official source: no sudo.
# The question can be answered up front: RP_PERSONA=<id>, one of ReaPersona's own (ReaPersona/styles.json): base_reaper is plain REAPER.
# RP_REAPER=<folder> names a portable REAPER this doesn't find by itself.
# Modelled on StudioSync's installer (github.com/FmsJay/studiosync, same author, GPL-3.0).
set -u
RAW="https://github.com/FmsJay/ReaPersona/raw/main"
REAPER_VERSION="7.86" # as StudioSync's installer; the tarball is reaper786_linux_<arch>.tar.xz
REAPACK="v1.2.6"
REAIMGUI="0.10.0.5"   # shortcut: pinned, like the Windows and Mac installers
JSAPI="v1.310"
SWS="v2.14.0.7"
# REAPER and the extensions name their Linux builds x86_64, aarch64 and armv7l (32-bit ARM)
case "$(uname -m)" in
  x86_64|amd64) ARCH=x86_64;;
  aarch64|arm64) ARCH=aarch64;;
  armv7*|armv8l|armhf) ARCH=armv7l;;
  *) echo "ReaPersona's Linux setup runs on x86_64, aarch64 or armv7l computers; this one is $(uname -m)."; exit 1;;
esac
[ "$ARCH" = aarch64 ] && [ "$(getconf LONG_BIT 2>/dev/null)" = 32 ] && ARCH=armv7l # (a 64-bit kernel under a 32-bit system, as Raspberry Pi OS: 32-bit builds)
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"
[ "$(uname -s)" = Linux ] || { echo "This is the Linux setup. On a Mac use install_mac.sh; on Windows, Install ReaPersona (Windows).cmd."; exit 1; }
[ "$(id -u)" = 0 ] && { echo "Run this as yourself, not as root (no sudo in front of it): everything goes in your own home folder."; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/reapersona_setup.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT # (also when it stops early)

say()  { printf '\033[36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  OK  %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  !!  %s\033[0m\n' "$*"; }
ask()  { local a; read -e -r -p "$1${2:+ [$2]} " a </dev/tty; echo "${a:-${2:-}}"; } # (-e: arrow keys edit, not type escape codes)
# (curl | bash: bash reads the rest of this script from stdin, so nothing started here may read it: </dev/null)
detach() { setsid "$@" >/dev/null 2>&1 </dev/null & }

say "ReaPersona setup"
echo "This installs REAPER and what ReaPersona needs, then sets REAPER up like the music app you're used to: its shortcuts,"
echo "mouse and look. Everything goes in for you only, in your home folder. Nothing already installed is changed."
echo

# ---------- 0. the question ----------
# ReaPersona's own ids and names (ReaPersona/styles.json), in the same order as the other installers. Enter: plain REAPER (base_reaper).
IDS="pro_tools pro_tools_intro logic garageband ableton fl_studio cubase nuendo studio_one bitwig cakewalk reason audacity audition reapertips my_reaper base_reaper"
NAMES=("Pro Tools" "Pro Tools Intro" "Logic Pro" "GarageBand" "Ableton Live" "FL Studio" "Cubase" "Nuendo" "Studio One / Fender Studio Pro" "Bitwig Studio"
  "Cakewalk / Sonar" "Reason" "Audacity" "Adobe Audition" "REAPER with the Reapertips theme" "My REAPER: keep the setup I already have" "None: plain REAPER")
PERSONA="$(printf '%s' "${RP_PERSONA:-}" | tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cd 'a-z_')"
case "$PERSONA" in none|plain|reaper) PERSONA=base_reaper;; esac
if [ -n "$PERSONA" ] && ! printf ' %s ' "$IDS" | grep -q " $PERSONA "; then warn "'$RP_PERSONA' isn't one of ReaPersona's DAWs ($IDS)."; PERSONA=""; fi
if [ -z "$PERSONA" ]; then
  say "Which music app are you coming from? REAPER takes on its shortcuts, mouse and look (switch any time, in ReaPersona):"
  i=0; for n in "${NAMES[@]}"; do i=$((i + 1)); printf '  %2d) %s\n' "$i" "$n"; done
  while :; do
    n="$(ask "Its number, or Enter for none (plain REAPER)")"
    [ -z "$n" ] && { PERSONA=base_reaper; break; }
    case "$n" in *[!0-9]*) ;; *) [ "$n" -ge 1 ] && [ "$n" -le ${#NAMES[@]} ] && { PERSONA="$(echo $IDS | cut -d' ' -f"$n")"; break; };; esac
    warn "A number from the list, or Enter."
  done
fi
i=0; for id in $IDS; do [ "$id" = "$PERSONA" ] && ok "REAPER will be set up as: ${NAMES[$i]}"; i=$((i + 1)); done
echo

say "Downloads show no progress here: a pause of a minute on a big one is normal."
# ---------- 1. REAPER ----------
# The running one first, then the usual places; its own install script puts it in ~/opt/REAPER. A Flatpak REAPER (Flathub's
# fm.reaper.Reaper) answers "flatpak", an AppImage its own file: each starts differently and keeps its settings elsewhere (below).
# (StudioSync cross-platform review, 0.58.78)
find_reaper() {
  local p c
  p="$(pgrep -x reaper | head -1)"
  if [ -n "$p" ]; then
    [ -f "/proc/$p/root/.flatpak-info" ] && { echo flatpak; return 0; }
    c="$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | sed -n 's/^APPIMAGE=//p' | head -1)"; [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
    c="$(readlink -f "/proc/$p/exe" 2>/dev/null)"; [ -x "$c" ] && { echo "$c"; return 0; }
  fi
  if [ -n "${RP_REAPER:-}" ]; then
    for c in "$RP_REAPER" "$RP_REAPER/reaper"; do [ -f "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }; done
  fi
  c="$(command -v reaper 2>/dev/null)" && c="$(readlink -f "$c")" && [ -x "$c" ] && { echo "$c"; return 0; }
  for c in "$HOME/opt/REAPER/reaper" /opt/REAPER/reaper "$HOME/REAPER/reaper"; do [ -x "$c" ] && { echo "$c"; return 0; }; done
  command -v flatpak >/dev/null && flatpak info fm.reaper.Reaper >/dev/null 2>&1 && { echo flatpak; return 0; }
  for c in "$HOME"/Applications/*[Rr][Ee][Aa][Pp][Ee][Rr]*.AppImage "$HOME"/*[Rr][Ee][Aa][Pp][Ee][Rr]*.AppImage "$HOME"/Downloads/*[Rr][Ee][Aa][Pp][Ee][Rr]*.AppImage; do
    [ -f "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}
if ! find_reaper >/dev/null && [ -z "${RP_REAPER:-}" ]; then
  # (a REAPER somewhere this doesn't look is asked for, rather than a second one installed beside it)
  RP_REAPER="$(ask "REAPER wasn't found. If it's somewhere else (a portable copy), type the folder it's in; or press Enter to install it")"
  RP_REAPER="$(printf '%s' "$RP_REAPER" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e "s/^'\(.*\)'$/\1/")"; RP_REAPER="${RP_REAPER/#\~/$HOME}"
  [ -n "$RP_REAPER" ] && ! find_reaper >/dev/null && warn "No REAPER in $RP_REAPER: installing one."
fi
if REAPER_BIN="$(find_reaper)"; then ok "REAPER is already installed ($REAPER_BIN)"
else
  say "Installing REAPER $REAPER_VERSION into ~/opt/REAPER (a 60-day evaluation; see reaper.fm for the licence) ..."
  rtar="$WORK/reaper.tar.xz"
  if curl -fsSL "https://www.reaper.fm/files/${REAPER_VERSION%%.*}.x/reaper${REAPER_VERSION//./}_linux_$ARCH.tar.xz" -o "$rtar" && tar -xJf "$rtar" -C "$WORK"; then
    # (its own script: --install copies to ~/opt/REAPER, --integrate-user-desktop adds the menu entry and .rpp files for you only)
    sh "$WORK/reaper_linux_$ARCH/install-reaper.sh" --install "$HOME/opt" --integrate-user-desktop --quiet >"$WORK/reaper_install.log" 2>&1 </dev/null
    if [ -x "$HOME/opt/REAPER/reaper" ]; then
      mkdir -p "$BIN"; [ -e "$BIN/reaper" ] || ln -s "$HOME/opt/REAPER/reaper" "$BIN/reaper"
      ok "REAPER installed (in your applications menu, and as 'reaper' in a new terminal)"
    else warn "REAPER didn't install:"; tail -5 "$WORK/reaper_install.log"; fi
    rm -rf "$rtar" "$WORK/reaper_linux_$ARCH"
  else warn "REAPER didn't download: get it from reaper.fm"; fi
fi
REAPER_BIN="$(find_reaper)" || { warn "REAPER isn't installed: get it from reaper.fm and run this again."; exit 1; }
# REAPER's resource folder, found the way REAPER finds it: a reaper.ini beside the program makes it portable (everything there), else
# ~/.config/REAPER (XDG_CONFIG_HOME, if set), or an old ~/.REAPER that already has its settings. A Flatpak REAPER starts through flatpak
# and keeps its settings in its own folder under ~/.var/app.
FLATPAK_APP="$HOME/.var/app/fm.reaper.Reaper"
EXE_DIR="$(dirname "$REAPER_BIN")"
REAPER_RUN=("$REAPER_BIN")
if [ "$REAPER_BIN" = flatpak ]; then REAPER_RUN=(flatpak run fm.reaper.Reaper); RES="$FLATPAK_APP/config/REAPER"
elif [ -f "$EXE_DIR/reaper.ini" ]; then RES="$EXE_DIR"
elif [ -f "$CFG/REAPER/reaper.ini" ]; then RES="$CFG/REAPER"
elif [ -f "$HOME/.REAPER/reaper.ini" ]; then RES="$HOME/.REAPER"
else RES="$CFG/REAPER"; fi
ok "REAPER: $REAPER_BIN (settings in $RES)"

# ---------- 2. REAPER extensions: ReaPack, ReaImGui, js_ReaScriptAPI, SWS ----------
# Each skipped when any copy of it is there already. js_ReaScriptAPI and SWS: the files ReaPack's ReaTeam Extensions index points at
# (both MIT). (js_ReaScriptAPI's only Linux build is x86_64)
PLUG="$RES/UserPlugins"
need=""
ls "$PLUG"/reaper_reapack* >/dev/null 2>&1 || need="$need reaper_reapack-$ARCH.so=https://github.com/cfillion/reapack/releases/download/$REAPACK/reaper_reapack-$ARCH.so"
ls "$PLUG"/reaper_imgui* >/dev/null 2>&1 || need="$need reaper_imgui-$ARCH.so=https://github.com/cfillion/reaimgui/releases/download/v$REAIMGUI/reaper_imgui-$ARCH.so"
JS_NONE=""
if ! ls "$PLUG"/reaper_js_ReaScriptAPI* >/dev/null 2>&1; then
  if [ "$ARCH" = x86_64 ]; then need="$need reaper_js_ReaScriptAPI64.so=https://github.com/juliansader/ReaExtensions/raw/master/js_ReaScriptAPI/$JSAPI/reaper_js_ReaScriptAPI64.so"
  else JS_NONE=1; fi
fi
ls "$PLUG"/reaper_sws* >/dev/null 2>&1 || need="$need reaper_sws-$ARCH.so=https://github.com/reaper-oss/sws/releases/download/$SWS/reaper_sws-$ARCH.so"
REOPEN=""
if [ -n "$need" ]; then
  if pgrep -x reaper >/dev/null; then
    say "REAPER has to restart to load its new extensions: quit REAPER now (File > Quit, or Ctrl+Q; save if it asks). It's reopened afterwards."
    REOPEN=1
    waited=0
    while pgrep -x reaper >/dev/null; do
      sleep 1; waited=$((waited + 1))
      [ $((waited % 30)) -eq 0 ] && say "Still waiting for REAPER to close (answer its save question if it asked one) ..."
    done
  fi
  mkdir -p "$PLUG"
  # (to a .part file first: one cut off half way stayed there, broken, and a second run said it was already installed)
  for n in $need; do
    f="$PLUG/${n%%=*}"
    if curl -fsSL "${n#*=}" -o "$f.part" && [ -s "$f.part" ] && mv -f "$f.part" "$f"; then ok "${n%%=*} installed"
    else rm -f "$f.part"; warn "${n%%=*} didn't download"; fi
  done
else ok "ReaPack, ReaImGui, js_ReaScriptAPI and SWS are already installed"; fi

# ---------- 3. ReaPersona, inside REAPER ----------
[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || { warn "There's no desktop here (over SSH?): REAPER can't open. Run this again in a terminal on the computer's own desktop."; exit 1; }
# reapersona_setup.lua (beside this script in a checkout, else from GitHub) runs in REAPER: it adds ReaPersona's ReaPack repository, syncs,
# waits for ReaPersona, sets REAPER up as the persona and starts the shortcut install (one restart).
# (a Flatpak REAPER has a /tmp of its own and can't see this one: the setup files go in its own folder instead. StudioSync, 0.58.78)
SRC="$WORK"; [ "$REAPER_BIN" = flatpak ] && { SRC="$FLATPAK_APP/cache/reapersona_setup"; rm -rf "$SRC"; mkdir -p "$SRC"; trap 'rm -rf "$WORK" "$SRC"' EXIT; }
HELPER="$SRC/reapersona_setup.lua"
SELF="${BASH_SOURCE[0]:-}" # (empty when piped from curl)
if [ -n "$SELF" ] && [ -f "$(dirname "$SELF")/reapersona_setup.lua" ]; then cp "$(dirname "$SELF")/reapersona_setup.lua" "$HELPER"
else curl -fsSL "$RAW/installer/reapersona_setup.lua?$(date +%s)" -o "$HELPER" || { warn "ReaPersona's setup step didn't download: check the internet connection, then run this again."; exit 1; }; fi
RESULT="$SRC/reapersona_setup_result.json"; STARTED="$SRC/reapersona_setup_started"
printf '{"persona":"%s","repo_url":"%s/index.xml"}' "$PERSONA" "$RAW" > "$SRC/reapersona_setup.json"
# REAPER -nonewinst <file>: to the REAPER that's running, or a new one when none is. A REAPER finds the running one by a pipe in
# XDG_RUNTIME_DIR named from XDG_SESSION_ID, so started from another login session it opened a second REAPER: it's started with the running
# REAPER's own session, or none if it has none. (StudioSync, REAPER 7.86 Linux VM, 0.58.77)
handoff() {
  local p sid
  p="$(pgrep -x reaper | head -1)"
  if [ -z "$p" ] || [ ! -r "/proc/$p/environ" ]; then detach "${REAPER_RUN[@]}" -nonewinst "$1"; return; fi
  sid="$(tr '\0' '\n' < "/proc/$p/environ" | sed -n 's/^XDG_SESSION_ID=//p' | head -1)"
  if [ -n "$sid" ]; then detach env XDG_SESSION_ID="$sid" "${REAPER_RUN[@]}" -nonewinst "$1"
  else detach env -u XDG_SESSION_ID "${REAPER_RUN[@]}" -nonewinst "$1"; fi
}
if [ -n "$REOPEN" ] && ! pgrep -x reaper >/dev/null; then
  # we had REAPER quit: start it the way you do, so it reopens your project as it always does, then hand it the helper once it's up
  detach "${REAPER_RUN[@]}"
  for i in $(seq 1 60); do pgrep -x reaper >/dev/null && break; sleep 1; done
  sleep 8
fi
say "Setting up ReaPersona inside REAPER. REAPER opens now; the first time, it scans your plug-ins (a while) and asks a few things:"
say "  the audio device: ALSA, or JACK if you use it (PipeWire's works); set it in Options > Preferences > Audio > Device before you play."
say "  ReaPack's 'Manage repositories' and 'Transaction report': OK. A new REAPER shows its evaluation reminder first: wait for it, then Still evaluating."
WAS_UP=""; pgrep -x reaper >/dev/null && WAS_UP=1
handoff "$HELPER" # ONE request: the helper waits inside REAPER for ReaPack itself
GONE=""; asked=1; i=0; at=""
# (a REAPER's first start scans every plug-in before it runs anything: until the helper starts, this waits while REAPER is open, and says
# what's happening; once it has, the 4 minutes the helper gives ReaPack and some to spare)
while [ ! -f "$RESULT" ]; do
  i=$((i + 1))
  [ -z "$at" ] && [ -f "$STARTED" ] && at=$i
  if [ -n "$at" ]; then [ $((i - at)) -gt 420 ] && break; elif [ "$i" -gt 2700 ]; then break; fi
  # (a REAPER that was already open sometimes never gets the hand-off: handed over again, only while the helper hasn't started, so it never
  # runs twice. StudioSync, AgentBox 0.58.65)
  if [ -n "$WAS_UP" ] && [ $asked -lt 4 ] && [ "$i" -eq $((20 * asked)) ] && [ ! -f "$STARTED" ]; then
    say "REAPER hasn't picked up the setup step yet: handing it over again."
    handoff "$HELPER"
    asked=$((asked + 1))
  fi
  if [ "$i" -gt 15 ] && ! pgrep -x reaper >/dev/null; then GONE=1; break; fi
  [ "$i" -eq 90 ] && say "Still waiting for ReaPersona to arrive through ReaPack. Look in REAPER for its first-start windows and answer them: the audio device question, then OK on ReaPack's Manage repositories, Notice and Transaction report (another window may be covering them)."
  [ -z "$at" ] && [ "$i" -gt 90 ] && [ $((i % 120)) -eq 0 ] && say "Still waiting ($((i / 60)) minutes). A first start scans every plug-in on this computer before anything else runs: 10 minutes or more with a big collection (REAPER's window names each one). Nothing is stuck while REAPER is open."
  sleep 1
done

# ---------- 4. what was done, and what's left ----------
# (the result's strings never hold a quote or backslash: reapersona_setup.lua's clean(), so grep reads them whole)
echo
LEFT=()
if [ -f "$RESULT" ]; then
  sleep 0.3
  while IFS= read -r line; do
    name="$(printf '%s' "$line" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')"; detail="$(printf '%s' "$line" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')"
    case "$line" in *'"ok":true'*) ok "$name${detail:+: $detail}";; *) warn "$name: $detail";; esac
  done < <(grep '^{"name":' "$RESULT")
  note="$(sed -n 's/.*"note":"\([^"]*\)".*/\1/p' "$RESULT" | head -1)"
  [ -n "$note" ] && LEFT+=("$note")
  grep -q '"restart":true' "$RESULT" && LEFT+=("Once REAPER is back: try a few of your old shortcuts. ReaPersona's window (Extensions > ReaPersona) switches DAWs, themes and cheat sheets any time.")
elif [ -n "$GONE" ]; then
  warn "REAPER closed unexpectedly during setup. Open REAPER, then run this again."
else
  # (REAPER still on its first-start windows, or ReaPack still bringing ReaPersona: the setup step carries on by itself once they're answered,
  # so its files stay. StudioSync, Windows Sandbox run 0.58.78)
  trap - EXIT
  if [ -f "$STARTED" ]; then warn "ReaPersona's setup step is still running inside REAPER (ReaPack is taking its time): it finishes by itself, and REAPER restarts once when it's done."
  else warn "REAPER hasn't got to ReaPersona's setup step yet: it's still on its first-start windows (the audio device, ReaPack's Manage repositories, Notice and Transaction report), which another window may be hiding. Answer them: setup then carries on by itself."; fi
  LEFT+=("If REAPER never restarts by itself: Extensions > ReaPack > Synchronize packages, then open ReaPersona (Extensions > ReaPersona, or the Actions list) and pick your DAW on Home.")
fi
[ -n "$JS_NONE" ] && LEFT+=("js_ReaScriptAPI has no $ARCH build: ReaPersona works without it, minus its file pickers (sharing a persona, choosing a sync folder).")
# (a Flatpak REAPER can't do the restart install: everything it starts, the waiting install step included, dies with it when it quits.
# The same install runs from a terminal here with REAPER closed. reapersona_setup.lua's note gives the command when it got that far;
# otherwise it's said here, with the installer found under REAPER's Scripts folder. Round 2, B1)
if [ "$REAPER_BIN" = flatpak ] && ! grep -q 'install_shortcuts.py' "$RESULT" 2>/dev/null; then
  IS="$(find "$RES/Scripts/ReaPersona" -name install_shortcuts.py 2>/dev/null | head -1)"
  LEFT+=("This REAPER is the Flatpak one, which can't restart itself to put shortcuts in. Once ReaPersona is set up: close REAPER, run  python3 \"${IS:-$RES/Scripts/ReaPersona/Workflow/install_shortcuts.py}\" --apply-setup  in a terminal, then start REAPER again. REAPER from reaper.fm avoids this (move the Flatpak one aside and run this again: it installs that one in ~/opt/REAPER).")
fi
LEFT+=("REAPER is a 60-day evaluation: after that it still works, and reminds you to buy a licence (reaper.fm/purchase.php).")
say "Done. What's left:"
for l in "${LEFT[@]}"; do echo "  - $l"; done
