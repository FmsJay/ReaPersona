# Changelog

## 5.12.2
- **Fixed: syncing REAPER's keys could turn Undo off.** A key that runs a script (StudioSync's Undo, say) carries an id that differs on each computer, so taking another computer's copy left a key that runs nothing here, and REAPER dropped it. The keymap merge now leaves those keys alone, along with keys another computer turned off and the persona layers (each computer installs those itself).

## 5.12.1
- **Make a workflow by setting it up and saving it.** Save what I'm using... now asks "Make it a workflow too?": yes takes this project's sample rate and its tracks (the selected ones, or all; with their FX and routing, not their items) into the persona, so a new, empty project with it starts the same way. It goes to your other computers with your other personas.
- **Your other computers is easier to find:** first on Settings, which now opens on ReaPersona's own settings (REAPER tweaks second), and a card on Home.
- Sample rates read "48 kHz", not "48.0 kHz".

## 5.12.0
Keys from a review of the DAW personas, each checked against the maker's own documentation (and cited in the persona's docs list):
- **Fixed:** Live's Ctrl+Shift+C is Copy Time in Arrangement View, not Capture MIDI (Live gives Capture MIDI no default key; the Ableton toolbar's button still runs it), so ReaPersona no longer takes the key. Logic's B is now the Browser and Y Smart Controls, as Apple's current key list has them (its O and F browser keys are gone). FL Studio's piano roll Quick quantize is Ctrl+Q on Windows. Audacity's Ctrl+D makes a new track holding only the selection, as Audacity's Duplicate does.
- **Pro Tools:** the Commands Keyboard Focus single keys A/S (trim clip start/end to the cursor), D/G (fades to and from the cursor), F (crossfade), B (separate), E (zoom toggle), P/; (previous/next track), L/' (previous/next edit), and keypad 1/2 rewind and fast forward.
- **Logic Pro:** Forward (.), Cmd+U (loop to the selected regions), Undo History (Option-Cmd-Z), Play Surface (Cmd+K), New Audio / Software Instrument Track, screensets 1-9, and on a Mac all-tracks automation Read/Touch/Latch and Toggle Autopunch.
- **Ableton Live:** Undo History (Ctrl+Alt+Z) and A, Toggle Automation Mode. **Studio One:** J/K read and touch automation, I Auto Punch, Shift+NumPad* recalls the retrospective recording, Ctrl+Shift+A in the note editor. **Cakewalk:** Select None, zoom undo/redo (Alt+Z, Alt+Shift+Z), F12 / Ctrl+F12 global automation write off and read on/off. **FL Studio:** Ctrl+P recording precount. **Audacity:** Silence (Ctrl+L), Delete and Cut leaving a gap (Ctrl+Alt+K, Ctrl+Alt+X), zero crossings (Z), Preferences (Ctrl+P).
- New actions those keys run: *duplicate to new track*, *remove/cut leaving a gap* (ripple off for that one edit) and *autopunch* (time-selection auto-punch on and off). ReaPersona registers them the next time its window opens; install the shortcuts again (Home > Reinstall) to get the new keys.

## 5.11.4
- An audio interface's recording latency offsets and buffer sizes stay each computer's own when REAPER's preferences sync (one computer's offset would shift every recording on another).


## 5.11.3
- **A ReaPack repository that comes from another computer never installs everything in it.** 5.11.2 added it "as ReaPack is set here", and where ReaPack installs new packages by itself, a whole repository came in; its packages now come one by one (Install them), only the ones your other computers have.
- StudioSync's per-computer tab scripts (its old BandSync name too) aren't synced as your scripts.

## 5.11.2
- **Syncing REAPER's preferences can't crash REAPER any more.** 5.11.0-5.11.1 set them live through SWS, guessing each one's type; SWS reports whole-number preferences as doubles too, so some were written into memory too small for them, and REAPER crashed seconds later. Preferences now wait for REAPER's restart (Apply) and go into reaper.ini, which REAPER reads itself.
- **Syncing doesn't hold REAPER up.** The sync state and the other computers' files stay in memory while they're unchanged, and nothing is written when nothing changed: a look takes milliseconds instead of a second with every advanced part on. REAPER's own parts sync when the window has been open 10 seconds, on Sync now and every 30 minutes; at REAPER's start, 10 seconds after it opens.
- Switching an advanced part on with "take theirs" forgets what this computer knew of it, so your other computers' versions really win that time.

## 5.11.1
Fixes from four reviews of 5.10-5.11 (DAW coverage, settings and use cases, correctness and data safety, cross-platform and UX):
- **Syncing is safe against what it takes in.** Every item from your sync folder or a setup file passes the same checks as what goes out: it can't switch on syncing or point it elsewhere, set REAPER's paths, or put files outside FX chains/templates, Scripts/Effects and ColorThemes (never `__startup.lua`); file content is checked against its hash. A setup file dropped on the window, or loaded, says what it holds and asks first.
- **No bouncing.** A keymap or preference waiting for REAPER's restart isn't sent back as this computer's own (it could undo your change on the computer it came from); a computer with a clock ahead can't make later edits lose (incoming times are believed a day ahead at most); equal times settle the same way on every computer; personas made on two computers on the same shortcut layer settle on one (the smaller id keeps it).
- **Your setup, not a persona's:** REAPER's preferences and the keymap, mouse and menus go out (and come in) only while My REAPER is in use, since a persona changes some of them live; ReaPersona's own toolbars and keymap lines never travel. Window sets stay each computer's (they hold its screens' places), as do text size, look and the extensions you declined. Kernel Streaming device settings and font/scale preferences stay each computer's too.
- **A file of yours that can't be read for a moment** (locked by antivirus) no longer counts as "no personas", which deleted them on your other computers; one that doesn't parse is now said in Settings.
- **Without a sync folder**, the parts made of files are left out of a setup file (5.11.0 could write their content to the drive's root).
- **Workflows:** the device really takes the workflow's sample rate (the driver's requested rate is set too, or it says it couldn't); a project with tracks keeps its rate and tracks, and you're told; no device restart while another tab plays; a new project made while a workflow persona is in use (Ctrl+N, a new tab) gets its setup; starter tracks drop receives from tracks that weren't taken.
- Preferences are set by their variable's type; ReaPack repositories that come in never auto-install everything; blobs no computer uses any more are cleaned up; this computer's sync file name stays the same (a Mac's network name changes); REAPER starts quickly (REAPER's own parts sync 15 seconds later).
- **Feedback** goes to GitHub by default when you don't sync (your own folder reached nobody), without your home folder's name. **Mac:** Python from Homebrew or python.org is found. Smooth Wheel Scroll isn't offered where it can't run. Live's Ctrl+Shift+C is Capture MIDI. Messages name Home and Personas, not the old pages.

## 5.11.0
- **Workflows.** A persona can set up a new project: its sample rate (the audio device follows), starter tracks (any tracks you pick, with their FX and routing, kept inside the persona so they go to your other computers with it) and a window set. Choose the persona in an empty project and it's ready; a project with your work in it keeps its rate and tracks. Four starter workflows in the Persona Builder: *Voiceover (48 kHz)* (one armed mono track, ripple per track, no click), *Podcast (48 kHz)*, *Music (44.1 kHz)* and *Live looping* (loop playback, a take per pass, count-in, four armed loop tracks), each added as blocks you can change, plus a *Project* block of your own.
- **Advanced syncing: REAPER itself on your other computers too** (Settings > Your other computers > Advanced), each part ticked on each computer: REAPER's preferences (set straight away where REAPER allows, the rest at its next start; paths, audio and MIDI devices and window places stay each computer's own), other scripts' settings, your keymap, mouse modifiers, menus and toolbars and window sets (merged into each computer's, never replacing it, when REAPER restarts: *Apply*), FX chains and templates, your own scripts and JSFX (not ReaPack's, nor their data), themes, and ReaPack's repositories and packages: what another computer has and this one doesn't is one click (*Install them*), ReaPack fetching this system's version (a Mac's, not Windows'). Files go through the folder by content, so a copy is never sent back as a change; deleting a file doesn't delete it elsewhere. Switching a part on asks whether your other computers' or this one's win the first time.
- **Feedback** (top right), as in StudioSync: a bug report, feedback or a feature request, saved in your sync folder (or on this computer) and/or opened as an issue on GitHub for you to send, with what the computer runs and ReaPersona's last errors if you like.

## 5.10.0
- **Every DAW persona has that DAW's mouse.** The wheel scrolls and zooms as it does there, with its modifiers (Studio One and Reason: Shift+wheel sideways, Ctrl+wheel zooms; Pro Tools: Alt+wheel zooms; Live: Ctrl+wheel zooms, Alt+wheel sizes tracks, Shift+wheel scrolls; Cubase, FL, Bitwig, Cakewalk, Logic, Audacity likewise), and more of its drags and clicks: Cubase's Alt+click split and Ctrl+Alt slip, Studio One's slip and Alt-resize stretch, Alt+drag stretching in Logic, Bitwig and Audacity, snap-free dragging in Live, FL, Bitwig and Pro Tools, and Pro Tools' Start-drag that keeps a clip in time. Each is from the maker's documentation, and which way REAPER's wheel actions go was measured in REAPER, so wheel down scrolls right and wheel up zooms in, as in those DAWs. Base REAPER has all four of REAPER's own wheel shortcuts. **Install the shortcuts again** (Home) for the wheel shortcuts; Home now counts a persona whose keys grew as not installed.
- **Mouse is a block of its own in the Persona Builder**, and a part of every DAW block: one DAW's keys with another's mouse takes all of that DAW's wheel shortcuts, drags and clicks, and nothing of the first one's. Personas you built before keep their mouse as it was.
- **Your setup on your other computers** (Settings > Your other computers): *Save to a file* and *Load a file* (or drop it on the window) for your personas, presets, theme recipes, ReaPersona's settings, and Smooth Wheel Scroll's and ReaSmoothPlayhead's settings. Or keep them the same through a folder your computers share (Syncthing, Google Drive, Dropbox...): each computer keeps its own file in it, the newest change to each persona or setting wins, a deleted persona goes everywhere, and a file that doesn't parse (yours, or another computer's half-synced one) is never written over. ReaPersona looks when REAPER starts, every 20 seconds while its window is open, and when it closes; the extensions read their settings at REAPER's next start.

## 5.9.5
- **The mouse wheel can be any persona's shortcut**: Mousewheel and HorizWheel with any mix of Ctrl, Alt and Shift ("Shift+Mousewheel", "Ctrl+Alt+HorizWheel" in styles.json), written as REAPER writes them, and REAPER's own longer form read back (an existing Shift+wheel line, say). Before, only plain Mousewheel and Ctrl+Alt+Mousewheel could be. (The Windows key has no wheel code.) Mouse drags and clicks were already part of a persona's feel.

## 5.9.4
- **Remove ReaPersona** (Settings): My REAPER comes back, then the startup block, ReaPersona's actions and its settings go, and with Python its shortcut layers and toolbars (REAPER restarts). Your personas, presets and themes stay. The startup block from any version, or one written by hand, is now recognised, swapped for the one that stays quiet once ReaPersona is gone, and also when the window opens.
- **Your personas' keys are their own.** A Builder persona with some of a DAW's keys left out, or one that already has a layer, gets a layer of its own instead of the DAW's; *Make them its own* (Shortcuts) copies a persona's borrowed keys onto its own layer before you change them. One of yours on a layer a newer built-in took moves to a free one.
- **The Actions list trim keeps what a mouse modifier or an SWS cycle action runs**, as it already did for keys and toolbars.
- **Linux: .zip and .rar theme packs open**, with `unzip`, `unrar`, `bsdtar` or `7z`, whichever is installed, and a message naming what to install when none is. Windows and macOS are unchanged.

## 5.9.3
- **Linux: Python is found.** The check that skips macOS's stand-in Python (which only asks to install the developer tools) ran on Linux too, so Linux's own `/usr/bin/python3` was never used.
- **Removing ReaPersona leaves no startup error.** Its line in `__startup.lua` now runs only while ReaPersona is there; the line from older versions is swapped for it at the next start.
- **A theme on trial stays a trial.** Saving your tweaks during a trial no longer went back when the trial ran out, and switching persona mid-trial no longer kept the trial theme as My REAPER's own.

## 5.9.2
- **Linux: REAPER comes back after Install shortcuts.** The relaunched REAPER inherited a dead output pipe from the one that quit and was killed before it showed; it now starts on its own, is checked to be running, and is tried once more if not. The relaunch looks for Linux's `reaper` program too. Tested on Ubuntu 24.04.

## 5.9.1
- **The Extensions/View menu items on macOS and Linux too** (ReaPersona menus 1.0.1: a universal Mac build and Linux x86_64/aarch64). They appear after REAPER's next start.

## 5.9.0
- **ReaPersona is in REAPER's menus:** Extensions > ReaPersona and View > ReaPersona open it, ticked while it's open. A small extension ReaPack installs with ReaPersona does it (64-bit Windows now, the Mac build follows); the items appear after REAPER's next start.
- **A shorter Actions list:** only ReaPersona and the actions its keys use (play from start, memory location) and project following stay. The persona switches ("use Ableton Live" and the rest, next and restore last) come back with Settings > "Every ReaPersona action in REAPER's Actions list"; one a key or toolbar button already uses stays either way.

## 5.8.4
- **Mac: REAPER really comes back after Install shortcuts.** Right after REAPER quits, macOS still lists it as running, so reopening it only woke the REAPER that was closing. ReaPersona now waits until it's fully gone, reopens it, checks that it's running (trying once more if not), and only then says it started again.

## 5.8.3
- **Mac: REAPER comes back after Install shortcuts.** The shortcuts installed, but REAPER didn't reopen: the relaunch was started and left as the installer exited. It's now waited for (it returns at once), and whether REAPER started again goes into the install's result.

## 5.8.2
- **Mac: Python is found.** REAPER on a Mac runs a bare `python3` as nothing, so ReaPersona never saw Python there: no theme building, and Install shortcuts always took the manual route. It now finds Python's full path (the developer tools' Python counts only when they're installed). Theme downloads and folder clean-up had the same problem with `curl` and `rm`.

## 5.8.1
- **Mac: Install shortcuts brings REAPER back.** REAPER quit for the shortcut install and never reopened on a Mac (it looked for REAPER.app in the wrong place). It now reopens with your projects, as on Windows.

## 5.8.0
- **One-click theme installs.** 41 of the catalog's themes install with one click (Install on a persona's page and on Home), downloaded from where their authors share them: the REAPER Stash, or the author's own link. Themes that need a browser (paid, or a sign-in) keep a Get it link.
- **Each persona's recommended look:** a button on its page installs it and makes it the persona's theme; switching to a persona whose look isn't installed offers it once. *Install all* gets every version of a persona's theme.
- **Involved installs done for you:**
  - theme packs in .zip or .rar, including a pack inside a pack (I Logic's bonus Ultimate theme);
  - unzipped themes keep their folder of images (Mordi's FL Studio theme);
  - fonts a theme needs are installed for your account on your yes, with no administrator needed (Beatwing, CONCEPT SIX, FL Studio theme); REAPER uses them after a restart;
  - a theme's own scripts (CONCEPT SIX's theme adjuster) go into the Actions list on your yes;
  - mod packs become theme versions you can click: rLive's ModPack gives five (two item-selection styles, three routing-icon styles).
- **More looks per DAW:**
  - Ableton: rLive by Odys, now the recommended look, plus its ModPack.
  - Logic: I Logic 3.90, normal, Big and Ultimate.
  - FL Studio: Mordi's FL Studio theme.
  - Studio One: CONCEPT SIX Basic SX.
  - Bitwig: Beatwing Bright.
  - Cakewalk: Echolot.
  - Reason: IMPERIAL 24 and Dark Side Imperial, hardware looks.
  - Audacity: ReAudacity.
- The catalog's names now match what the downloads contain (FLogic B, CONCEPT SIX Basic SX, I Logic 3.90).

## 5.7.0
- **REAPER tweaks** (Settings > REAPER tweaks): about 60 of REAPER's and SWS's options in groups, switched live: playback and scrolling, editing, recording, view, **colours and icons (SWS auto-colour, auto icons, auto layouts, red ruler while recording)**, automation and mixer. New ones include count-in and metronome for playback and recording, what recording over an item does, fixed lanes, the edit cursor after recording, grouping what's recorded together, media cues, item tooltips, FX inserts and sends in the track panel, the track panel on the right, and automation behaviour. *Colour the tracks now* and *Colour and icon rules...* open SWS's auto-colour. Options that need SWS say so.
- Each group has **Add to the Builder**: it goes into the Persona Builder as a block, set the way you have it, so a persona (or a project) can carry its own workflow.
- The same groups are the Builder's REAPER settings blocks; the Settings page's old playback and Customize REAPER lists are now on REAPER tweaks.

## 5.6.0
- **Theme versions:** each persona's page shows every version of its theme as a button (Pro Tools has nine: ReaPersona's own, Pro Tools 2020, Pro Tools Gold and more). Click one to make it that persona's theme; the ones you don't have yet are listed with Get it links. Right-click a version you added to take it off the list.
- Themes > Your themes: **Add to...** adds a theme to any persona's versions, not only the one in use.
- Persona Builder: each DAW's theme versions are blocks of their own.
- Mixer docking is on by default, so a persona moves the mixer the way its DAW does (Pro Tools, FL Studio and Cubase keep it in its own window). Switch it off in Settings > What a persona may change to keep yours where it is.

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
