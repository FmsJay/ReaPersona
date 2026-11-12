# Changelog

## 5.5.2
- Persona Builder: every line inside a block has a tick box, so you can leave out one part of a block (Pro Tools' undocked mixer, say) and keep the rest.
- Saving changes to the persona in use applies them straight away.
- A block's title no longer runs into its Up/Down/Remove buttons in a narrow window, and the DAW list starts on a DAW with shortcuts.

## 5.5.1
- The shortcut install never removes its first keymap backup (your keymap from before ReaPersona); it keeps that one and the newest 4.

## 5.5.0
- **Styles are now personas** everywhere in the window: a persona is everything REAPER feels like, from shortcuts and theme to layout and REAPER's own options. Your saved setups are personas too. (Files, actions and shortcuts keep their names, so nothing you set up breaks.)
- **Persona Builder** (Personas > Persona Builder, in place of Combine): drag blocks into a stack and see what each sets as you go. Blocks are a DAW (its shortcuts, layout and feel, theme), one part of a DAW's feel (mouse, mixer layout, transport, Media Explorer, toolbar, snap/ripple, MIDI editor docking), REAPER settings groups (playback and scrolling, editing, recording, view, mixer) set the way you want, a theme and a colour. The lower block wins a clash, and the block that loses shows "replaced by". *Try it*, *Go back*, *Save*; *Build on this* and *Edit in the Builder* on persona pages. One DAW's shortcuts work straight away; several DAWs' get a layer of their own.
- **A persona per project:** *Use for this project* saves a persona in the project; with *Switch persona with the project* on (Settings), opening a project or switching to its tab switches persona. Projects without one keep the persona in use, or switch to one you pick.
- REAPER keeps many options per project (snap, ripple, the metronome, the mixer layout). What a persona changed is now put back in the project tab it changed it in; before, switching tabs and then personas could leave one project's mixer layout on another.
- Fixes from a full review:
  - A theme on trial gives way when another theme or persona goes on, and goes back when the window closes.
  - Search clears when you change page, and Escape clears it at any width.
  - The top bar's buttons wrap under the title in a narrow window instead of sliding over it.
  - Colour tweaks in Adjust belong to the theme they were made on.
  - Deleting a persona says it can't be undone.
  - The Stash says it's loading.
  - Text size reaches the main buttons.
  - The picker's toolbar button lights while it's open.
  - Shared personas and presets can only change settings ReaPersona's own personas use, and always get a free shortcut layer that holds none of your keys.
  - A failed write never replaces a good file.
  - A MIDI-editor docking still waiting for an editor counts as how it is.
  - My REAPER's theme comes back even from outside ColorThemes.
  - Mouse behaviours marked for one system are read correctly in saved personas.
  - The keymap file route never writes over an unreadable midi_fallback.json.
  - A persona of yours named like a shipped one gets its own action.
  - The install: detects a running REAPER even with accented letters in its path, or one it can't look into; without installed.json it only replaces tagged lines (a shortcut layer of your own keeps its keys); writes reaper-menu.ini safely; keeps the first backup and the newest 4; stops waiting if you cancel REAPER's quit; reopens REAPER on the same `-cfgfile`; and refuses to run outside a REAPER folder.
  - Logic: Y opens the Library, B Smart Controls, F the Browsers and O the Loop Browser, as in Logic.

## 5.4.5
- Themes > Your themes opens with every theme on your computer (search, Try, Use, Add to style); the theme styles come after.

## 5.4.4
- Adding a theme pack (Browse > Add or a dropped zip) gives a short report: what was added, one line for the rest of the pack, and notes when it comes with fonts or its own scripts. It used to list every file.
- A theme you already have is replaced when the download is different (the older copy is kept), and the report says when it's the same file.
- New themes show at the top of Themes > Your themes, marked new, and the report names them with their Stash title.

## 5.4.3
- **Studio One / Fender Studio Pro** checked against Fender's Studio Pro key shortcuts sheet: Redo on Ctrl+Y, Enter starts, NumPad , returns to zero; nudges, Goto Time, Find Command (Actions list), browser tabs (F6-F10), Channel Editor, export and import, Show Envelopes, next/previous event and bar, normalize, event volume, channel navigation, Insert Instrument Part, Undo Zoom. Keys from older lists that aren't on Fender's sheet (comma, Tab/Shift+Tab, Shift+NumPad *) are gone.

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
