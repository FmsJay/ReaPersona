#!/bin/bash
# ReaPersona setup for macOS: REAPER set up like the music app you're coming from, shortcuts included. For people new to REAPER.
# Run it with "Install ReaPersona (Mac).command" (if macOS blocks it: System Settings > Privacy & Security > Open Anyway), or in Terminal:
#   curl -fsSL "https://raw.githubusercontent.com/FmsJay/ReaPersona/main/installer/install_mac.sh?$(date +%s)" | bash
# (the ?<time>: GitHub's cache can hand out the previous version for minutes after a change)
# Installs what's missing and skips what's there: REAPER, ReaPack, ReaImGui, js_ReaScriptAPI and SWS, then ReaPersona itself (through
# ReaPack), then sets REAPER up as the DAW you pick; REAPER restarts once at the end, for the shortcuts. Every app comes from its official
# source. Uses only tools a stock Mac has (curl, hdiutil, ditto): nothing here triggers the Xcode tools prompt.
# The question can be answered up front: RP_PERSONA=<id>, one of ReaPersona's own (ReaPersona/styles.json): base_reaper is plain REAPER.
# RP_REAPER=<REAPER.app or its folder> names a REAPER this doesn't find by itself.
# Modelled on StudioSync's installer (github.com/FmsJay/studiosync, same author, GPL-3.0).
set -u
[ "$(uname -s)" = Darwin ] || { echo "This is the Mac setup. On Linux use install_linux.sh; on Windows, Install ReaPersona (Windows).cmd."; exit 1; }
RAW="https://github.com/FmsJay/ReaPersona/raw/main"
REAPACK="v1.2.6"
REAIMGUI="0.10.0.5" # shortcut: pinned, as StudioSync's installer; ReaPack keeps them updated only if later reinstalled through ReaPack
JSAPI="v1.310"
SWS="v2.14.0.7"
# arm64 or x86_64, which is also how the extensions name their builds. (Not uname -m: a Terminal running under Rosetta says x86_64 on an
# Apple Silicon Mac, and those builds don't load in REAPER there.)
ARCH="x86_64"; [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] && ARCH="arm64"
RES="$HOME/Library/Application Support/REAPER"
WORK="$(mktemp -d /tmp/reapersona_setup.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT # (also when it stops early)

say()  { printf '\033[36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  OK  %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  !!  %s\033[0m\n' "$*"; }
ask()  { local a; read -e -r -p "$1${2:+ [$2]} " a </dev/tty; echo "${a:-${2:-}}"; } # (-e: arrow keys edit, not type escape codes)

say "ReaPersona setup"
echo "This installs REAPER and what ReaPersona needs, then sets REAPER up like the music app you're used to: its shortcuts,"
echo "mouse and look. Nothing already installed is changed."
echo

# ---------- 0. the question ----------
# ReaPersona's own ids and names (ReaPersona/styles.json), in the same order as the Windows installer. Return: plain REAPER (base_reaper).
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
    n="$(ask "Its number, or Return for none (plain REAPER)")"
    [ -z "$n" ] && { PERSONA=base_reaper; break; }
    case "$n" in *[!0-9]*) ;; *) [ "$n" -ge 1 ] && [ "$n" -le ${#NAMES[@]} ] && { PERSONA="$(echo $IDS | cut -d' ' -f"$n")"; break; };; esac
    warn "A number from the list, or Return."
  done
fi
i=0; for id in $IDS; do [ "$id" = "$PERSONA" ] && ok "REAPER will be set up as: ${NAMES[$i]}"; i=$((i + 1)); done
echo

say "Downloads show no progress here: a pause of a few minutes on a big one is normal."
# ---------- 1. REAPER ----------
# REAPER.app: the running one (a portable REAPER in a folder of its own, REAPER64.app), then the usual places, then Spotlight. RP_REAPER, or
# the answer when none is found, names another. (StudioSync installer review, 0.58.78)
find_reaper_app() {
  local p c
  p="$(pgrep -x REAPER | head -1)"
  [ -n "$p" ] && c="$(ps -o comm= -p "$p" 2>/dev/null | sed -n 's#^\(.*\.app\)/Contents/MacOS/.*#\1#p')" && [ -d "$c" ] && { echo "$c"; return 0; }
  for c in "${RP_REAPER:-/-}" "${RP_REAPER:-/-}/REAPER.app" /Applications/REAPER.app /Applications/REAPER64.app "$HOME/Applications/REAPER.app"; do
    case "$c" in *.app) [ -d "$c/Contents/MacOS" ] && { echo "$c"; return 0; };; esac
  done
  c="$(mdfind 'kMDItemCFBundleIdentifier == "com.cockos.reaper"' 2>/dev/null | head -1)"; [ -n "$c" ] && [ -d "$c" ] && { echo "$c"; return 0; }
  return 1
}
if ! find_reaper_app >/dev/null && [ -z "${RP_REAPER:-}" ]; then
  # (a REAPER somewhere this doesn't look is asked for, rather than a second one installed beside it)
  RP_REAPER="$(ask "REAPER wasn't found. If it's somewhere else (a portable copy), drag its folder or REAPER.app here; or press Return to install it")"
  RP_REAPER="$(printf '%s' "$RP_REAPER" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\\\(.\)/\1/g')"; RP_REAPER="${RP_REAPER/#\~/$HOME}"; RP_REAPER="${RP_REAPER%/}"
  [ -n "$RP_REAPER" ] && ! find_reaper_app >/dev/null && warn "No REAPER in $RP_REAPER: installing one."
fi
if REAPER_APP="$(find_reaper_app)"; then ok "REAPER is already installed ($REAPER_APP)"
else
  say "Installing REAPER (a 60-day evaluation; see reaper.fm for the licence) ..."
  dmg="$(curl -fsSL https://www.reaper.fm/download.php | grep -o 'files/[0-9.x]*/reaper[0-9]*_universal\.dmg' | head -1)"
  mnt="$WORK/mnt"; mkdir -p "$mnt"
  if [ -n "$dmg" ] && curl -fsSL "https://www.reaper.fm/$dmg" -o "$WORK/reaper.dmg"; then
    # (the disk image shows REAPER's licence here and waits for you to agree: it used to go to /dev/null and look hung. StudioSync)
    PAGER=cat hdiutil attach -noverify -nobrowse -mountpoint "$mnt" "$WORK/reaper.dmg" </dev/tty | grep -v '^/dev/' || true
    app="$(find "$mnt" -maxdepth 1 -name 'REAPER*.app' | head -1)"
    if [ -n "$app" ] && ditto "$app" "/Applications/$(basename "$app")"; then ok "REAPER installed"; else warn "REAPER didn't install: get it from reaper.fm"; fi
    hdiutil detach "$mnt" -quiet
  else warn "REAPER didn't download: get it from reaper.fm"; fi
fi
REAPER_APP="$(find_reaper_app)" || { warn "REAPER isn't installed: get it from reaper.fm and run this again."; exit 1; }
# (a portable REAPER keeps its settings beside REAPER.app when that folder has a reaper.ini)
[ -f "$(dirname "$REAPER_APP")/reaper.ini" ] && RES="$(dirname "$REAPER_APP")"
ok "REAPER: $REAPER_APP (settings in $RES)"

# ---------- 2. REAPER extensions: ReaPack, ReaImGui, js_ReaScriptAPI, SWS ----------
# Each skipped when any copy of it is there already. js_ReaScriptAPI and SWS: the files ReaPack's ReaTeam Extensions index points at (both MIT).
# (curl doesn't quarantine what it downloads, so Gatekeeper lets REAPER load them)
PLUG="$RES/UserPlugins"
need=""
ls "$PLUG"/reaper_reapack* >/dev/null 2>&1 || need="$need reaper_reapack-$ARCH.dylib=https://github.com/cfillion/reapack/releases/download/$REAPACK/reaper_reapack-$ARCH.dylib"
ls "$PLUG"/reaper_imgui* >/dev/null 2>&1 || need="$need reaper_imgui-$ARCH.dylib=https://github.com/cfillion/reaimgui/releases/download/v$REAIMGUI/reaper_imgui-$ARCH.dylib"
JSF="reaper_js_ReaScriptAPI64.dylib"; [ "$ARCH" = arm64 ] && JSF="reaper_js_ReaScriptAPI64ARM.dylib"
ls "$PLUG"/reaper_js_ReaScriptAPI* >/dev/null 2>&1 || need="$need $JSF=https://github.com/juliansader/ReaExtensions/raw/master/js_ReaScriptAPI/$JSAPI/$JSF"
ls "$PLUG"/reaper_sws* >/dev/null 2>&1 || need="$need reaper_sws-$ARCH.dylib=https://github.com/reaper-oss/sws/releases/download/$SWS/reaper_sws-$ARCH.dylib"
REOPEN=""
if [ -n "$need" ]; then
  if pgrep -x REAPER >/dev/null; then
    say "REAPER has to restart to load its new extensions: quit REAPER now (Cmd+Q; save if it asks). It's reopened afterwards."
    REOPEN=1
    waited=0
    while pgrep -x REAPER >/dev/null; do
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
# reapersona_setup.lua (beside this script when it runs from a checkout or the .command's folder, else from GitHub) runs in REAPER: it adds
# ReaPersona's ReaPack repository, syncs, waits for ReaPersona, sets REAPER up as the persona and starts the shortcut install (one restart).
HELPER="$WORK/reapersona_setup.lua"
SELF="${BASH_SOURCE[0]:-}" # (empty when piped from curl)
if [ -n "$SELF" ] && [ -f "$(dirname "$SELF")/reapersona_setup.lua" ]; then cp "$(dirname "$SELF")/reapersona_setup.lua" "$HELPER"
else curl -fsSL "$RAW/installer/reapersona_setup.lua?$(date +%s)" -o "$HELPER" || { warn "ReaPersona's setup step didn't download: check the internet connection, then run this again."; exit 1; }; fi
RESULT="$WORK/reapersona_setup_result.json"; STARTED="$WORK/reapersona_setup_started"
printf '{"persona":"%s","repo_url":"%s/index.xml"}' "$PERSONA" "$RAW" > "$WORK/reapersona_setup.json"
if [ -n "$REOPEN" ] && ! pgrep -x REAPER >/dev/null; then
  # we had REAPER quit: start it the way you do, so it reopens your project tabs as it always does (started WITH the helper it came back
  # with one tab, StudioSync 2026-10-28), then hand it the helper once it's up
  open -a "$REAPER_APP"
  for i in $(seq 1 60); do pgrep -x REAPER >/dev/null && break; sleep 1; done
  sleep 8
fi
say "Setting up ReaPersona inside REAPER. REAPER opens now; the first time, it scans your plug-ins (a while) and asks a few things:"
say "  'Select your audio device now?': No is fine for now (pick your audio interface in Settings > Audio before you play)."
say "  ReaPack's 'Manage repositories', 'Notice' and 'Transaction report': OK."
# (any Apple Event, "open -a", reaching REAPER while ReaPack's report window is open crashes it on macOS: StudioSync, 2026-10-28)
if pgrep -x REAPER >/dev/null; then
  say "First close any ReaPack window in REAPER (like its 'Transaction report'): one left open makes REAPER quit. Then press Return."
  read -r </dev/tty
fi
open -a "$REAPER_APP" "$HELPER" # ONE request: the helper waits inside REAPER for ReaPack itself
GONE=""; i=0; at=""
# (a REAPER's first start scans every plug-in before it runs anything: until the helper starts (its first act writes reapersona_setup_started),
# this waits while REAPER is open, and says what's happening; once it has, the 4 minutes the helper gives ReaPack and some to spare)
while [ ! -f "$RESULT" ]; do
  i=$((i + 1))
  [ -z "$at" ] && [ -f "$STARTED" ] && at=$i
  if [ -n "$at" ]; then [ $((i - at)) -gt 420 ] && break; elif [ $i -gt 2700 ]; then break; fi
  if [ $i -gt 15 ] && ! pgrep -x REAPER >/dev/null; then GONE=1; break; fi
  [ $i -eq 30 ] && say "Waiting for ReaPersona to arrive through ReaPack. ReaPack opens its own windows on a first run (Manage repositories, Notice, Transaction report): press OK on them (another window may be covering them)."
  [ -z "$at" ] && [ $i -gt 90 ] && [ $((i % 120)) -eq 0 ] && say "Still waiting ($((i / 60)) minutes). A first start scans every plug-in on this Mac before anything else runs: 10 minutes or more with a big collection (REAPER's window names each one). Nothing is stuck while REAPER is open."
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
LEFT+=("macOS may ask to let REAPER use the microphone: click Allow, or what you record is silent.")
LEFT+=("Pick your audio interface: REAPER > Settings > Audio > Device.")
LEFT+=("REAPER is a 60-day evaluation: after that it still works, and reminds you to buy a licence (reaper.fm/purchase.php).")
say "Done. What's left:"
for l in "${LEFT[@]}"; do echo "  - $l"; done
