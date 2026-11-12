# ReaPersona

Make REAPER feel like the DAW you know: **Pro Tools, Logic Pro, Ableton Live, FL Studio, Cubase, Studio One / Fender Studio Pro, Bitwig Studio, Cakewalk / Sonar or Reason**, or the audio editors **Audacity** and **Adobe Audition**. You can also set it back to **stock REAPER**, use **your own setup**, or build **your own personas** from blocks. Everything switches on the fly from one window, and each project can have its own persona.

![Switching personas](docs/demo.gif)

![All the personas](docs/styles.png)

A **persona** is everything REAPER feels like: shortcuts, theme, layout, mouse behaviour and REAPER's own options. ReaPersona ships one per DAW, and you can make your own.

## What a persona changes

- **Keys.** Each DAW's default shortcuts, from its maker's own documentation. The sources are linked in `styles.json` and on each persona's Shortcuts page.
  - They live on one of REAPER's shortcut layers (Main alt-1 to alt-16), so switching is instant.
  - Keys a persona doesn't define fall through to your own shortcuts.
  - In the MIDI editor, a small script per key does the same job.
  - Keys that differ on a Mac (Pro Tools' Option+Return, Logic's Control-key commands) are stored per system.
- **Theme.** A ReaPersona theme in that DAW's colours, built on your computer (see below). Third-party themes in its likeness work too, if you have them.
- **Layout.**
  - Where the transport sits.
  - The mixer docked or in its own window, with the master on the left or right, and insert/send slots.
  - The Media Explorer docked where that DAW keeps its browser: left for Live, FL and Reason; right for Logic, Cubase, Studio One, Bitwig and Cakewalk; its own window for Pro Tools.
- **Feel.**
  - Snap, ripple and follow-playhead.
  - Mouse behaviours such as Pro Tools' Smart Tool (top half selects, bottom half moves) and FL Studio's right-click delete.
  - Loop range and overlapping clips the way each DAW does them.
  - The MIDI editor docked or floating, as in that DAW (applied the next time a MIDI editor is open).
  - The smooth playhead and smooth scroll/zoom extensions, which DAW personas recommend and offer to install.
- **Toolbar.** The DAW's own toolbar takes the main toolbar's place.
- **Where things are.** Each persona lists the DAW's features with the REAPER equivalent and an Open button: Pro Tools playlists, Logic Track Stacks, Live's Session View, FL patterns, Cubase's Pool, Reason's Rack, and so on.
- **More of that DAW.** Each persona suggests other people's tools that bring more of it (Playtime, SideFX, ReaDrum Machine, Reaticulate, Lil Chordbox, the Reason Rack Plugin...) with a *Get it* button that opens ReaPack at the package, and links to keymaps others have made.

Switching away puts back everything a persona changed, so **My REAPER** is always exactly your setup. **Base REAPER** is REAPER 7.85's factory keys and settings, with tips.

## Setup, in one place

The first time, ReaPersona asks which DAW you're coming from and uses its persona straight away. The window has six pages: **Home** (setup), **Personas** (DAWs, your personas, the Persona Builder), **Shortcuts**, **Themes** (yours, get more, adjust, build one), **Settings** and **Help**. It also fits a narrow docker.

**Home** lists everything ReaPersona can use, whether you have it, and a button for each:

- **ReaPersona's own themes:** one per DAW, an approximation of its colours, built in seconds from the Default 7 theme your REAPER already has. Panels, buttons, mute/solo/arm and transport colours, track-colour strength and text all change, with all of Default 7's layout and Theme Adjuster settings kept. Nothing of Default 7 ships with ReaPersona: only the recipes do, and the theme is made from your own copy.
  - This needs Python 3 with Pillow and numpy. Setup has a button that installs those two.
- **Shortcut layers:** one button. REAPER closes (asking about anything unsaved), the shortcuts install with a backup of your keymap, and REAPER opens again. Without Python, ReaPersona makes a keymap file and walks you through importing it (Key Map > Import, choose **merge**).
- **The startup line:** brings your persona back when REAPER starts.
- **Smooth playhead and smooth scrolling:** ReaSmoothPlayhead installs through ReaPack; Smooth Wheel Scroll comes with ReaPersona on Windows.
- **Themes by other people:** each one the personas can use, with a *Get it* button to its author's page.

**Drag and drop:** drop files onto ReaPersona's window to add them.
- Themes, either `.ReaperThemeZip`/`.ReaperTheme` files or a theme pack `.zip` straight from the download.
- Toolbars (`.ReaperMenu`).
- Keymaps (`.ReaperKeyMap`), which become a persona of their own on a free shortcut layer.
- Shared personas.

## Also in the window

- **Search everything** (Ctrl+K in the top bar): personas, shortcuts in every persona ("split" shows each DAW's key), where a DAW's feature is in REAPER, themes, settings and pages.
- **New project like <DAW>:** each persona's page starts a project with that DAW's usual tracks, buses and sends (REAPER's own plugins).

- **Persona Builder:** drag blocks into a stack and see what each one sets as you go, then *Try it* or *Save*.
  - Blocks: a DAW's shortcuts, its layout and feel, or just one part of it (Ableton's mouse feel, Pro Tools' mixer layout, Logic's transport position...); REAPER settings groups (playback and scrolling, editing, recording, view, mixer), each set the way you want; any theme; a colour.
  - Where two blocks set the same thing, the lower one wins, and the one that loses shows "replaced by" in its block.
  - One DAW's shortcuts are ready straight away. Shortcuts from several DAWs get a layer of their own, installed with one click (REAPER restarts).
  - *Build on this* on any persona's page starts from it; *Edit in the Builder* reopens one you built.
- **A persona per project:** *Use for this project* on a persona's page saves it in the project. With *Switch persona with the project* on (Settings), opening that project or switching to its tab switches persona, and projects without one can keep the one in use or switch to one you pick. REAPER keeps many options per project (snap, ripple, the metronome, the mixer layout), and a persona's changes are put back in the tab they were made in.
- **Browse:** the REAPER Stash's newest, most popular and top-rated themes, key maps, custom actions and templates. *Add* downloads one and takes it in like a dropped file; anything behind a sign-in opens its page instead.
- **Import from another DAW:**
  - finds the DAWs installed on your computer;
  - turns your own Cubase/Nuendo key commands into a persona;
  - makes a ReaPersona theme from an Ableton Live theme (`.ask`).
- **What a persona may change:** switch off the parts you want to keep as they are, whatever persona you use: mixer docking (off by default), mixer layout, transport, Media Explorer, toolbar, mouse, snap/ripple.
- **Customize REAPER:** item labels, grid lines, takes, spectral peaks, crossfades, grouping, locking, mixer options and what the ruler shows, in one place.
- **Theme adjuster:** pops out into its own window; REAPER's own Theme Adjuster is one click away.

- **Save what I'm using:** the persona in use the way you like it, with its theme, layout and settings, saved under a name. You can share it as a file.
- **Themes:** every theme on your computer. *Try* wears one for 20 seconds (keep it or it goes back), *Use* applies one on its own, *Add to* puts it in a persona's Theme list.
- **Adjust:** a theme's own settings, layouts and colours, live.
- **Build one (themes):** a theme from several (layout, colours and parts from different themes).
- **Settings:** continuous scrolling, follow-playhead, smooth seek, smooth playhead and scroll/zoom, and ReaPersona's own look.
- **Cheat sheets:** every key and setting of a persona on one printable page.

## On a Mac

REAPER treats Ctrl as Cmd, so the personas should work unchanged, and keys show as Cmd and Option. Keys that differ on a Mac (Pro Tools' Option+Return, Logic's Control-key commands, Option-drag to copy in Ableton, Bitwig and Reason) are stored separately. Theme building and the shortcut install use `python3`. Smooth Wheel Scroll's bundled build is Windows-only; see its own page for macOS. Not yet tested on a Mac: reports welcome.

## Install

1. In REAPER, open **Extensions > ReaPack > Import repositories…** and paste:
   `https://github.com/FmsJay/ReaPersona/raw/main/index.xml`
2. In **Extensions > ReaPack > Browse packages**, install **ReaPersona**.
3. ReaPersona needs:
   - **ReaImGui** and **js_ReaScriptAPI** (ReaPack: ReaTeam Extensions)
   - **SWS** (sws-extension.org)
4. Run **ReaPersona** from the Actions list, open **Home**, and press **Set up everything**.

## Themes and credits

ReaPersona's own themes are built on your computer from REAPER's Default 7 (© Cockos), which every REAPER install includes.

Themes by other authors aren't redistributed: no licence means their authors keep the rights. The Cakewalk persona's BandLab recolour is built on mawi's Echolot (CC BY-NC-SA 4.0). [THEMES.md](THEMES.md) credits each one and links to its page, and the Setup page does the same with a button. Download a theme, then drop it onto the window.

Thanks also to:
- the authors of the extensions ReaPersona works with: SWS, ReaImGui, js_ReaScriptAPI, ReaPack, ReaSmoothPlayhead (DsgDnB), Helgobox/Playtime;
- **Smooth Wheel Scroll** by bobo198504, MIT licence: ReaPersona carries its Windows build unchanged (`extensions/`, with the licence) so Setup can install it in one click. Source: https://github.com/bobo198504/SmoothWheelScroll;
- the tools each persona suggests, by their authors: Suzuki (ReaDrum Machine), Conceptual Machines (SideFX), Jason Tackaberry (Reaticulate), FTC (Lil Chordbox), MPL, edkashinsky (ReAbleton), Reapertips, smandrap, pandabot (ChordGun), Navelpluisje (ReaSonus Native), git-moss (DrivenByMoss4Reaper);
- MPL's RS5k step sequencer.

## Adding a DAW persona

DAW personas are data in `styles.json`. Each key is `[key, REAPER command id or named id, what the DAW calls it]`, and the feel uses the kinds documented at the top of that file. Run `validate.py` after editing (press *Check* on Help > Check and repair first, so it can compare against your REAPER), then install the shortcuts.

## Changes

See [CHANGELOG.md](CHANGELOG.md).

## Licence

GPL-3.0. The DAW names belong to their makers; ReaPersona isn't affiliated with any of them.
