# Changelog

## 5.4.2
- **Cubase** checked against Steinberg's official Cubase Pro 14 default key commands: Tap Tempo back on Shift+Space, plus Invert Selection, Rename Track, Tempo Track, Video, Performance Monitor, On-Screen Keyboard, nudges, hitpoints, markers 3-9, Zoom Tracks Exclusive and workspaces 6-9.
- **Audition** checked against Adobe's default shortcut list: * on the keypad adds a marker too.

## 5.4.1
- Settings: ReaPersona's look changes straight away (no reopening), and a **Text size** choice (Small to Larger).
- **Undo switch** in the top bar goes back to the style you had before the last switch.

## 5.4.0
- **Docks made for you:** a style that wants a window on a side your REAPER has no docker on (Reason's mixer at the top, say) sets up a spare docker there; switching back puts the window where it was.
- **Search everything** from the top bar (Ctrl+K): styles, shortcuts in every style ("split" finds each DAW's key), where a DAW's feature is in REAPER, themes, settings and pages.
- **New project like <DAW>:** a project template per style with that DAW's usual starting tracks, buses and sends, using REAPER's own plugins.
- **Adobe Audition** style (alt-12), with only the keys a source documents (Adobe publishes a partial list).
- One-button install reopens the projects you had open; it waits only for the REAPER it belongs to (portable, `-cfgfile` or installed) and works on a REAPER that hasn't written its keymap yet.
- Smooth Wheel Scroll's Windows build goes to 64-bit Windows only.
- Preview pictures retaken with the themes ReaPersona ships, without personal folders; a demo GIF in the README.

## 5.3.0
- **Audacity** style (alt-11) from Audacity's own shortcut reference.
- The MIDI editor docked or floating per DAW, applied when an editor is open and put back on switching away.
- **Try** a theme for 20 seconds, then keep it or go back; theme names instead of file names.
- One "Make your own style" card with three ways: what's in use, one DAW's keys with another's layout, or a blend.
- *Get it* leaves a ReaPack repository you already have untouched.

## 5.2.0
After a four-part review (code, DAW accuracy, themes and tools, ease of use).
- **Safety and correctness:** style snapshots survive restarts; MIDI editor keys work in My REAPER; the installer validates first, writes atomically and keeps a list of what it wrote; shared styles can't write outside their folders or put code in generated scripts; Stash downloads validated; your files are never overwritten when they don't parse.
- **Closer to each DAW:** Pro Tools and Studio One's Smart Tool the right way up; range cut, copy, delete and split; quantize moves notes; loop range and overlapping clips per DAW; keypad Enter and Mac-only keys; about 300 more default keys.
- **Themes and tools:** catalog corrected and credited (licences where known), ten more themes, per-DAW tools with *Get it*, Smooth Wheel Scroll bundled (MIT).
- **Easier:** first run asks which DAW you're coming from; one-button shortcut install that restarts REAPER; six pages with tabs; readable on every look; keyboard navigation; works docked narrow.

## 5.1.0
Combine several DAWs into one style with every clash listed; Browse the REAPER Stash; import from another DAW (Cubase key commands, Ableton Live themes); choose what a style may change; Customize REAPER; pop-out theme adjuster; recovery from errors with an error log.

## 5.0.0
Setup page; drag and drop for themes, packs, toolbars, keymaps, styles and presets; mix-and-match profiles; Cakewalk / Sonar and Reason; ReaPersona's own theme per DAW, built from your Default 7.

## 4.x (as DAW Styles)
Shortcut layers per DAW, themes, feel (snap, mouse behaviours, layout) snapshotted and put back, MIDI editor keys, presets, Base REAPER.
