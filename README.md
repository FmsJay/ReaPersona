# ReaPersona

Make REAPER feel like the DAW you know: **Pro Tools, Pro Tools Intro, Logic Pro, GarageBand, Ableton Live, FL Studio, Cubase, Nuendo, Studio One / Fender Studio Pro, Bitwig Studio, Cakewalk / Sonar or Reason**, or the audio editors **Audacity** and **Adobe Audition**. You can also set it back to **stock REAPER**, use **your own setup**, or build **your own personas** from blocks. Everything switches on the fly from one window, and each project can have its own persona.

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
  - The Media Explorer docked where that DAW keeps its browser: left for Live, FL and Reason; right for Logic, GarageBand, Cubase, Nuendo, Studio One, Bitwig and Cakewalk; its own window for Pro Tools and Pro Tools Intro.
- **Mouse.**
  - The wheel as that DAW has it: scrolling and zooming with its modifiers (Shift+wheel scrolls sideways in Studio One, Reason, Live and Audacity; Ctrl+wheel zooms in Cubase, Reason and FL; Alt+wheel zooms in Pro Tools), each from the maker's documentation.
  - Drags and clicks such as Pro Tools' Smart Tool (top half selects, bottom half moves), Cubase's Alt+click split, Studio One's Ctrl+Alt slip, Alt+drag stretching in Logic, Bitwig and Audacity, and FL Studio's right-click delete.
- **Feel.**
  - Snap, ripple and follow-playhead.
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
  - This needs Python 3 with Pillow and numpy. Home has a button that installs those two into a Python environment of ReaPersona's own (`ReaPersona/venv`), in the background, so REAPER keeps working and your system's Python isn't changed. On Debian or Ubuntu the environment needs the `python3-venv` package first.
- **Shortcut layers:** one button, on Windows, macOS and Linux, with or without Python. REAPER closes (asking about anything unsaved), the shortcuts install with a backup of your keymap, and REAPER opens again. Without Python the install is planned inside REAPER and a small script swaps it in once REAPER has closed (a batch file on Windows, a shell script on a Mac or Linux). If anything changed the keymap in between, nothing is swapped in and ReaPersona says so. To skip the restart, Help > Check and repair > Install the shortcuts can also make a keymap file to import yourself (Key Map > Import, choose **merge**).
- **Screen readers:** ReaImGui's window can't be read by NVDA, JAWS or VoiceOver, so ReaPersona also has a menu that opens at the mouse pointer: the action *ReaPersona - screen-reader menu* always opens it, and ReaPersona's own action can too (with OSARA installed it asks the first time). It covers picking a persona, undoing a switch, saving what you're using, a new project with a workflow, installing the shortcuts, syncing, the cheat sheet and its help, with results in message boxes. Installing never puts a persona key over one of OSARA's.
- **Help:** Help > How it works explains the first steps and every page (F1 opens it); Home shows the first steps until the first three are done (the fourth, more than one computer, is optional), or you hide them.
- **The startup line:** brings your persona back when REAPER starts.
- **Smooth playhead and smooth scrolling:** ReaSmoothPlayhead installs through ReaPack; Smooth Wheel Scroll comes with ReaPersona on Windows.
- **Themes by other people:** each one the personas can use. *Install* downloads it from where its author shares it (the REAPER Stash or the author's own link) and takes it in; *Get it* opens the page for the few that need a browser (paid, or a sign-in).
  - Each persona's page has *Install <DAW>'s recommended look* and *Install all*; switching to a persona offers its look once.
  - Packs are handled for you: .zip and .rar packs (even one inside another), unzipped themes with their image folders, the fonts a theme needs (installed for your account on your yes, no administrator), a theme's own scripts (added to the Actions list on your yes), and mod packs, whose mods become theme versions to click (rLive's ModPack gives five). On Linux, packs need `unzip` (or `bsdtar` or `7z`; `unrar` or `bsdtar` for .rar), and ReaPersona says which is missing.

**Drag and drop:** drop files onto ReaPersona's window to add them.
- Themes, either `.ReaperThemeZip`/`.ReaperTheme` files or a theme pack `.zip` straight from the download.
- Toolbars (`.ReaperMenu`).
- Keymaps (`.ReaperKeyMap`), which become a persona of their own on a free shortcut layer.
- Shared personas.

## Also in the window

- **Search everything** (Ctrl+K, Cmd+K on a Mac, in the top bar when the window is wide enough): personas, shortcuts in every persona ("split" shows each DAW's key), where a DAW's feature is in REAPER, themes, settings and pages.
- **New project like <DAW>:** each persona's page starts a project with that DAW's usual tracks, buses and sends (REAPER's own plugins).

- **Persona Builder:** drag blocks into a stack and see what each one sets as you go, then *Try it* or *Save*.
  - Blocks: a DAW's shortcuts, its layout and feel, its mouse, or just one part of it (Ableton's mouse, Pro Tools' mixer layout, Logic's transport position...); REAPER settings groups (playback and scrolling, editing, recording, view, colours and icons, automation, mixer), each set the way you want; any theme; a colour.
  - Where two blocks set the same thing, the lower one wins, and the one that loses shows "replaced by" in its block. Untick any line in a block to leave just that out.
  - One DAW's shortcuts are ready straight away. Shortcuts from several DAWs get a layer of their own, installed with one click (REAPER restarts).
  - *Build on this* on any persona's page starts from it; *Edit in the Builder* reopens one you built.
- **A persona per project:** *Use for this project* on a persona's page saves it in the project. With *Switch persona with the project* on (Settings), opening that project or switching to its tab switches persona, and projects without one can keep the one in use or switch to one you pick. REAPER keeps many options per project (snap, ripple, the metronome, the mixer layout), and a persona's changes are put back in the tab they were made in.
- **Browse:** the REAPER Stash's newest, most popular and top-rated themes, key maps, custom actions and templates. *Add* downloads one and takes it in like a dropped file; anything behind a sign-in opens its page instead.
- **Import from another DAW:**
  - finds the DAWs installed on your computer;
  - turns your own Cubase/Nuendo key commands into a persona;
  - makes a ReaPersona theme from an Ableton Live theme (`.ask`).
- **What a persona may change:** switch off the parts you want to keep as they are, whatever persona you use: mixer docking, mixer layout, transport, Media Explorer, toolbar, mouse, snap/ripple.
- **REAPER tweaks** (Settings): about 60 of REAPER's and SWS's options in groups, switched live: playback and scrolling, editing, recording (count-in, recording over items, lanes), view, colours and icons (SWS auto-colour, auto icons and layouts), automation and mixer. *Add to the Builder* turns a group, as you've set it, into a block of a persona.
- **Theme adjuster:** pops out into its own window; REAPER's own Theme Adjuster is one click away.

- **Workflows:** a persona can set up a new project for a kind of session: a whole project template (tracks with their FX, routing and folders, sample rate, recording format, render settings, tempo, markers) or just a sample rate and starter tracks, plus a window set and REAPER's options for that kind of work. Choose it in a new project, or press *New project with it*, and it's ready. The Persona Builder has starters to build one from (voiceover at 48 kHz, a podcast, music at 44.1 kHz, live looping, mixing, mastering, video post), or make your own. The quickest way to make your own: set a project up the way that session wants it, then *Save what I'm using...* and say yes to "Make it a workflow too?". Each computer can keep its own track inputs for a workflow (*Keep these inputs on this computer*), and a new project says which of its plug-ins a computer hasn't got.
- **Your other computers** (Settings): *Save to a file* puts your personas, presets, ReaPersona's settings and the smooth scroll/zoom and playhead extensions' settings in one file; *Load a file* (or dropping it on the window) takes them in on another computer. Or pick a folder your computers share (Syncthing, Google Drive, Dropbox...) on each of them: each computer keeps its own file there, and the newest change to each persona or setting wins. Themes, and where each computer's windows sit, stay as they are. *Advanced* adds REAPER itself, part by part: preferences, other scripts' settings, shortcuts, mouse, menus, toolbars and window sets, FX chains and templates, your own scripts and JSFX, themes, and ReaPack's repositories and packages (what another computer has is one click to install).
- **Feedback:** report a bug or ask for something from inside ReaPersona: saved in your sync folder and/or opened as a GitHub issue.
- **Save what I'm using:** the persona in use the way you like it, with its theme, layout and settings, saved under a name. You can share it as a file.
- **Themes:** every theme on your computer. *Try* wears one for 20 seconds (keep it or it goes back), *Use* applies one on its own, *Add to...* makes it one of any persona's theme versions.
- **Theme versions:** each persona's page shows all its theme versions as buttons (Pro Tools has nine), with *Get it* links for the ones you don't have yet. Click one to make it that persona's theme.
- **Adjust:** a theme's own settings, layouts and colours, live.
- **Build one (themes):** a theme from several (layout, colours and parts from different themes).
- **Settings:** what personas may change, a persona per project, the smooth playhead and scroll/zoom extensions, ReaPersona's own look, and **Remove ReaPersona**: My REAPER comes back, and the startup block, ReaPersona's actions, settings, shortcut layers and toolbars come out (your personas, presets and themes stay). Then uninstall it in ReaPack.
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
4. Open **ReaPersona** (**Extensions > ReaPersona**, **View > ReaPersona**, or the Actions list), open **Home**, and press **Set up everything**.
   The menu items come from a small extension ReaPack installs with ReaPersona (64-bit Windows, macOS and Linux), after REAPER's next start.
   REAPER's Actions list keeps only ReaPersona and the actions its keys use. Settings > "Every ReaPersona action in REAPER's Actions list" brings back
   the persona switches ("use Ableton Live" and the rest) for your own shortcuts and toolbar buttons.

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
