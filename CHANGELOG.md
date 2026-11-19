# Changelog

## 5.44.0
Fixes from review round 4 (fresh reviewers on 5.43.0; performance came back solid; reports in reapersona-round4/). The review loop pauses here.
- **Window dockers go by side now** (James): a persona says a window docks bottom, left, top, right or in a floating docker, and each
  computer uses a docker on that side, so a synced persona puts StudioSync or a toolbar in the right place everywhere. Personas saved by
  5.43.0 with docker numbers are read as the side that docker has here.
- **The dockers card:** StudioSync and other script windows show under their own name (not their dialogs'); each window starts on the side
  it docks on now; the docker list has a heading and reads "Docker 1 (bottom): Mixer, ..."; Help, the Layout tab's text and search mention
  the card; Load from only shows when a persona has dockers; it says so when its switch in Settings > Personas is off.
- **Dockers fixed:** applying a persona again keeps its mixer and Media Explorer dockers; switching from a persona that docks the Media
  Explorer remembers your own docker; dockers are read from REAPER, not from settings a persona left in reaper.ini; a docked but closed
  mixer is seen as docked on every computer (REAPER's [reaper] section in any case).
- **Undo and Redo with Preview on** switch REAPER once, about 0.15 s after your last press (James). **Saving My REAPER** during a preview
  works like any persona: it's in use and Undo switch goes back (James). Save no longer turns your remembered Preview tick off.
- **Smaller:** the install without Python waits up to 30 minutes for a save question too; a cut-short JSON file is refused, not half read;
  Flatpak: the command is only said to be copied when it was, and the steps say to paste it before closing REAPER; the wheel form on Mouse &
  trackpad waits for Add like the drag form; closing the window during an install's quit check can't make REAPER restart later by itself.
- **For developers:** tools/check.py syntax-checks every .py and .lua file and gives each step a time limit; test_ui opens combos and popups.

## 5.43.0
- **Layout > More windows and dockers** (James): a persona can now say which docker any dockable window goes into. It lists your dockers
  and what REAPER keeps in each; **Add a window** offers every window REAPER has docked (toolbars, the transport, the mixer, script windows
  such as StudioSync, by their own names) plus REAPER's other windows, and each row gets a docker ("As it is" takes it out). It goes into the
  persona you're making like the other Layout parts (the bar at the top shows it, Load from takes another persona's), and your own dockers
  come back when you switch away. The mixer and Media Explorer move at once when they're open in a docker; a script's window moves the next
  time its script docks it, and other windows the next time they dock. Settings > Personas has a switch for it, like the other parts.
  Not yet: changing where a docker itself sits, and docking a floating script window from outside.

## 5.42.0
Fixes from review round 3 (fresh reviewers on 5.41.0; install and update came back solid; reports in reapersona-round3/), and three from James.
- **Mouse & trackpad** shows both ways to add your own at once (a wheel or trackpad move, and a drag or click), each with its own Ctrl/Alt/
  Shift/Win boxes: no radio buttons to switch between them.
- **Shortcuts:** "Your own shortcuts" says what they are (your REAPER keymap) instead of showing an empty list after switching back to them.
- **Undo and Redo with Preview on** update REAPER straight away.
- **Saving during a preview** makes the saved persona the one in use and says so; Undo switch takes you back to what you had (James's call).
- **Windows:** Undo History and the Routing Matrix are put back docked when you had them docked and closed (their dock state lives in REAPER's
  main settings); a docked-and-closed window a persona opened floating comes back docked; the docked state of closed windows stays out of
  saved looks and personas.
- **Personas built from one DAW** keep a key you moved; moving a key moves its other-system twin too; personas 5.40 rebuilt are rebuilt once more.
- **Sync** stays inside its time per frame (more pauses, also in reading and writing files), forgets the 12,500 old theme-folder entries
  (the state file shrinks from 4.2 to 1.5 MB), tidies and hashes big files a bit at a time, and never syncs .DS_Store, Thumbs.db or desktop.ini.
  The full sync at close stays (James's call).
- **Smaller:** the project follower starts with the new persona; Remove with a workflow on puts the workflow's settings back; Flatpak commands
  go on the clipboard (run Remove's before uninstalling); a self-update won't swap in a file that doesn't load; the installer waits while a
  save prompt is open instead of giving up after 3 minutes; the Colours page says when a persona holds the colours; plain words in more places.

## 5.41.0
Fixes from review round 2 (the same seven reviewers on 5.40.0; performance came back solid; reports in reapersona-round2/).
- **No more sync freeze:** a full sync now runs a little at a time across frames (James's call), so REAPER keeps responding; Settings > Sync
  says "Syncing..." meanwhile. Only the theme files at the top of ColorThemes sync, not unpacked theme folders, which nearly halves a full sync.
- **Personas you build:** their keys come out the same on Windows and on a Mac, also for ones saved before 5.40 and first opened on the other
  system (no Cmd+Tab left on a Mac, no Win+ keys on Windows); unticking a key takes out its other-system twin too.
- **After Remove ReaPersona,** coming back registers all of its actions again (they stayed unregistered).
- **Colours** synced in while a persona holds them no longer replace the persona's look or bounce back.
- **Docked windows** you had closed come back docked and closed; floating ones floating (James's call).
- **Previews:** picking a persona from a toolbar or key during a preview ends it in the window too; saving My REAPER no longer says it isn't
  saved; "(preview)" and "(trying)" match the bar's name.
- **Linux:** keys your desktop keeps (GNOME/KDE) are named on the persona's page, as macOS's are; Flatpak REAPER gets two terminal commands
  that put the shortcuts in (and take them out) without a restart that can't happen there; an AppImage relaunch only when REAPER is the AppImage.
- **Smaller:** a failed install puts the layer numbers back (also after a restart); the installer checks REAPER really closed; errors in the
  window are logged; plain words in a few more places.
- **For developers:** tools/check.py runs every check (sources, test_core, test_ui, test_installers, lint) in temp copies, and make_index.py
  refuses a release that fails it.

## 5.40.0
Fixes from review round 1 (seven reviewers on 5.39.0: changes, persona engine, UX, performance, cross-platform, install and update, code
health; reports and the fix list in the side-session notes, reapersona-round1/).
- **Previews:** while you preview or try a persona, the window knows it (the top bar says "<name> (preview)") instead of showing My REAPER,
  so nothing is saved over My REAPER by mistake. Closing the window, quitting REAPER, Go back, Stop or switching to another persona ends the
  preview and puts back what you had; one left over is put back when REAPER starts. A preview no longer changes the open project or queues
  REAPER preferences, and the preferences message doesn't repeat on every step. New persona and Edit ask before dropping an unsaved one.
  Undo records a change before stepping back, a slider drag is one step, and Undo says what it undid. A large project template in a persona
  no longer slows the window while you edit it.
- **Switching:** the mixer goes back where it was; a persona's colours aren't sent to your other computers as yours; the project follower
  doesn't trigger REAPER's "already running" question and picks up edited personas; the MIDI editor's docking goes in from the follower too,
  not only while the window is open; the put-back list is saved early and at the end of a switch (crash-safe, still quick), and settings are
  saved once each. A persona deleted on another computer while in use switches you back to My REAPER.
- **Personas you build** keep their keys for both Windows and macOS (one built on Windows no longer puts Cmd+Tab on the Mac); older ones
  are rebuilt from what they were made of. The install without Python now puts in Mac/Windows-only MIDI editor keys too.
- **Faster:** syncs skip shared copies they already know (also across restarts), ReaPack's package list is kept until ReaPack changes, the
  Layout tab no longer searches every window twice a second, DAW pictures load a couple at a time, and only changed action scripts are
  rewritten and registered.
- **Install and update:** the ReaPack index is built from the release commit only (a stray local file can't break updates); a self-update
  writes every file before swapping any in; the shortcut installer always brings REAPER back and says what happened; a cancelled install
  leaves the shortcut layers as they were; AppImage and Flatpak REAPER on Linux handled (Flatpak gets the keymap import steps).
- **Smaller:** Mac key names on Mouse & trackpad; plain words instead of "layer alt-N" and "blocks"; Remove takes out every DAW's FX folder;
  fonts install for accented user names; TLS 1.2 in the Windows installer; ReaPersona test copies no longer sync.
- **For developers:** tests/test_ui.lua draws all 30 pages without REAPER; tests/test_installers.py compares the Python and Lua installers
  (12 cases, identical keymaps); tools/lint.py runs LuaLS and fails on undefined globals; the engine has 41 top-level locals free.

## 5.39.0
Faster, and the window's code split by area (from a Lua efficiency review and LuaLS, the Lua language server; timings measured in
REAPER on the laptop).
- **Persona keys that run ReaPersona's own scripts are about 95x quicker:** play from start, the Pro Tools edit modes and duplicate, new
  track like this, autopunch, memory location, the gap edits and the notation editor load a 70-line module (0.34 ms) instead of the whole
  engine (32 ms) on every press. Open ReaPersona once after updating so their actions are written again.
- **Switching persona is about a quarter of a second quicker:** REAPER rewrites its ExtState file on every saved setting (12.9 ms each,
  measured), and a switch saved its put-back list after each of about 20 entries. It's kept in memory and saved once.
- **Reading ReaPersona's files is 2.5x faster** (styles.json 17 -> 7 ms, the 5.7 MB sync state 637 -> 241 ms): the JSON reader takes
  strings in one piece instead of a character at a time (output checked identical).
- **The window opens before the first sync** (about 1 s sooner), and a full sync no longer checks all 7,000 shared files' copies each time
  or starts Python for ReaPack's package list unless ReaPack's list changed.
- **Action search** (Shortcuts, Mouse & trackpad): names lowered once and answers kept, instead of 10,000 names lowered every frame while
  you type.
- **For developers:** ReaPersona.lua is now a short entry file; the window's code is in ui/ (base, personas, settings, theme_tools, check,
  home, editing, shortcuts, mouse, layout, project, main), one file per area, sharing one table of names (the one file had reached Lua's
  200 locals). Every page measured at 1-3.4 ms a frame after its first.

## 5.38.0
- **Preview as I change:** a switch in the bar at the top while you make or edit a persona. Each change on any tab goes into REAPER a
  moment after you make it (the look, layout, mouse, colours, REAPER settings and one DAW's keys), so you see it as you go; turning it
  off, Go back or Stop puts what you had back exactly. What a preview can't show is said under the bar: keys mixed from several DAWs
  (your own until it's saved and installed), REAPER preferences (at the next restart) and the project part (a new, empty project).
- **Undo and Redo** in the same bar, and Ctrl+Z / Ctrl+Shift+Z (Cmd on a Mac) while the window has focus: they step through every change
  you made to the persona, and with Preview on REAPER follows. Ctrl+Z while a key is being captured on Shortcuts is still that key.

## 5.37.1
Fixes from a second round of reviews of 5.36.1 and 5.37.0 (code, DAW personas, UI and UX, security; reports reapersona-review2-*.md).
- **Safety:** what comes from a file or another computer is checked more closely. Start scripts that come with a look, preset or setup
  are asked about once before they run or go into __startup.lua. The put-back list only ever runs ReaPersona's own settings. Synced
  scripts can't land on ReaPersona's own files or ReaPack's (paths like Scripts/./ReaPersona are refused). Synced settings can't hold
  line breaks of any kind (U+2028 too, which Python splits on), and ReaPersona's own settings can't be reached in another case. Shared
  toolbars are checked, project templates lose SWS's project startup action, ReaPack repositories from elsewhere need https and can't
  re-point one you have, a persona replaced by sync is kept under Earlier versions, and reaper.ini and reaper-screensets.ini are backed
  up before they're changed.
- **Fixed:** synced and imported personas kept ReaPersona's own script keys (Recall memory location, play from start, the Pro Tools edit
  modes...): they were dropped. Upgrades register the new scripts. "New track like this" unselects items first. The edit-mode keys make
  no undo step. Show everything and the switch token stay on each computer. Without Python, preferences no longer wait for a restart
  that can't put them in. Python is looked for once a session. Updates says the new version after updating. The REAPER tab only puts the
  setting you change in your persona.
- **DAW personas:** Cubase and Nuendo I toggles punch in, Alt+W writes like Cubase (Touch), and Nuendo has Cubase's new keys (and Cubase
  Nuendo's nudges). Ableton's M shows the virtual keyboard again. FL Studio's piano-roll quick quantize is Option+Cmd+Q on a Mac (MIDI
  editor keys can now be for one system). Logic's Undo History key is the Mac's only; Windows keeps Ctrl+Alt+Z. GarageBand's E and P close
  the editor. Labels and tips fixed (Ableton's slide modifier, Pro Tools' Playlists and edit modes, FL's patterns, Reason's Join, Audition).
- **The window:** while you make or edit a persona every tab shows, so no part is out of reach. Home lists what waits for a restart. Finish
  setting up restarts only when the shortcuts need it. Stop asks only when something changed, and leaves a trial. The restart question
  says what goes in. Help, the welcome and the screen-reader menu describe the one-step setup. Narrow windows wrap the draft bar.

## 5.37.0
- **The DAW personas checked against each DAW's own documentation** (Avid's Pro Tools Shortcuts Guide, Apple's Logic Pro 13 and GarageBand
  guides, Ableton's Live 12 manual, Bitwig's guide, Image-Line's FL Studio manual, Reason 13's key commands, Steinberg's Cubase 14 and Nuendo
  14 default key commands, the Studio One 7 sheet, Cakewalk's, Audacity's and Adobe Audition's references), and every REAPER action checked
  against REAPER 7.86's list. About 100 fixes, among them:
  - Pro Tools: F1 Shuffle, F2 Slip and F4 Grid are one exclusive group (each sets ripple and snap together), Shift+F4 toggles snap,
    Shift+S solos, waveform zoom on Ctrl+Alt+[ ], Ctrl+D duplicates the selection, E is the zoom toggle, keypad +/- nudge.
  - Logic: Undo History on Ctrl+Option+Cmd+Z, Cmd+D an empty track with the same settings (GarageBand too), comma and period move a bar,
    V shows and hides plug-in windows, E and P close the editor again. The persona follows Logic Pro 13's keys (it says so now).
  - Ableton: the Windows slide-clip modifier is Shift+Alt as in Live, M sends typing to the virtual MIDI keyboard, Option+wheel sizes the
    selected track, Ctrl+J glues to the selection; Playtime is labelled as a paid add-on.
  - FL Studio: F5 the playlist, F12 closes the other windows, Alt+M mutes and Alt+Shift+M unmutes, copies of a MIDI clip share their notes
    (like patterns), R says it records straight away. Reason: F7, Z, Shift+Enter, keypad period, Ctrl+J glues.
  - Cubase: Shift+M mutes and Shift+U unmutes, Alt+Space plays the selection, Project Setup, MixConsole, automation read/write for all
    tracks, waveform zoom, and the five keys only Nuendo had. Studio One: Shift+S zoom toggle, Redo Zoom, precount, floating windows.
  - Cakewalk: separate record and playback metronome, Delete/Cut/Copy follow the time selection, Q quantizes notes too, and Preferences,
    arm all, close project, ProChannel, lock clip. Audacity: J/K are track start/end, Shift+arrows extend the selection, Up/Down move
    between tracks. Audition: Delete/Cut/Copy follow the time selection, Shift+R repeats, Space leaves the playhead where it stopped.
  Install and restart once to get the updated keys.
- **Finish setting up, in one step:** Home's Getting started adds the startup line and installs the shortcuts with one restart.
- **Show everything** (bottom of the list on the left, or Settings > Look): off, only the main tabs show (Home, Personas, Themes,
  Colours, Shortcuts, Settings, Help); on, also the editors, Layout, Project, REAPER's options and the theme tools. A new install
  starts with it off; one already in use keeps everything.

## 5.36.1
Fixes from a review of the whole of ReaPersona (seven reviews: engine, the window, UX and wording, functionality, security, performance,
the product). What was found, fixed and left: docs/REVIEW-2026-11-18.md.
- Shared and synced files can't run actions or add startup scripts: mouse settings, synced presets, key labels, imported templates and
  startup scripts, synced preferences and scripts are checked.
- Switching twice quickly no longer loses the second persona's put-back list; a persona preference's original survives a restart in
  between; a broken project part no longer stops a switch.
- Remove ReaPersona puts your preferences back and takes out its window set and FX folders. Without Python, preferences aren't queued.
- The REAPER tab no longer copies REAPER's state into the persona you're making on every frame; pages no longer read files every frame;
  the message at the bottom wraps; a screen reader hears page names; Help and the README are up to date.

## 5.36.0
- **Each DAW's plug-ins in REAPER.** A DAW's page (Pro Tools, Logic, GarageBand, Ableton, FL Studio, Cubase/Nuendo, Studio One, Bitwig, Cakewalk, Reason, Audacity, Audition) lists its stock plug-ins with REAPER's own for each: Channel EQ is ReaEQ, Space Designer is ReaVerb, Simpler is ReaSamplOmatic5000, and so on.
- **A "<DAW> -> REAPER" folder** in REAPER's FX browser with those plug-ins, added or taken out from that page. Only REAPER's stock plug-ins (ReaPlugs and Cockos JSFX), found on each computer; every other folder (yours, StudioSync's) stays as it is. REAPER shows the folder after its next restart.
- tools/dev/restart_and_test.ps1 gives its test script to the new REAPER at its start (an evaluation copy's About box could keep -nonewinst from reaching it).

## 5.35.1
- REAPER > Preferences, checked against REAPER's config-variable reference: the default automation mode no longer changes *Arm new envelopes* (they share a number), the recording prompt changes only *on stop* (not *on punch-out*), fade and crossfade shapes are the 7 REAPER has, and the solo dim level goes to -1 dB at most. *Solo in front* itself is the switch on REAPER > Mixer (live, no restart), so it's no longer here too.
- The layout designer's dragging, checked with a real mouse drag on the laptop.

## 5.35.0
- **REAPER's preferences in a persona** (REAPER > Preferences): default fade and crossfade length and shape, where zoom centres (horizontal and vertical), new track and send volume, new track automation mode, the prompt after recording, and solo dimming. Tick *In my persona* and set each, or load them from any persona or your saved look. REAPER reads its preferences only as it starts, so a persona's go in at REAPER's next restart (*Restart REAPER now*), and yours go back the same way when you switch away; while a persona holds one, syncing leaves it out.
- **Render settings in the project part** (Project > *Use this project's*): format, sample rate, channels and file name pattern for each new project. Not the output folder: that's each computer's.
- **A theme's own settings in a persona** (Themes > Adjust > *Put this theme's settings in my persona*): the adjuster settings you changed and the default layouts, used with that theme, put back when you switch away; your theme's own saved settings aren't changed.
- The layout designer lets you drag again: the docks no longer take the mouse from the windows drawn on them.
- REAPER's tabs wrap onto a second line when they don't fit.
- On a DAW's page, "REAPER tips" is now "REAPER:" (it read as the Reapertips theme).

## 5.34.0
- **Every other window in your persona.** The Actions list, Region/Marker Manager, Track Manager, Undo History, Navigator, Performance Meter, Virtual MIDI keyboard, Routing Matrix, Video window, Project Bay and Crossfade Editor: open or closed, docked on a side, or in their own window with their place and size. Big Clock and the FX browser open and close. Saved with My REAPER's look, *Save what I'm using* and any persona; using one puts them back, and switching away puts yours back, so a stray window no longer stays when you go back to My REAPER.
- **Layout > Other windows:** load them from any persona, take them as they are now, or set each window. Settings > Personas can switch the part off.
- **Taking a window out of a docker** goes through a window set of ReaPersona's ("ReaPersona: windows", in a free set under View > Screensets). REAPER only reads window sets as it starts, so it goes in at REAPER's next restart (the Layout tab offers it). It changes only those windows; ReaPersona puts the transport, mixer, toolbars and Media Explorer back straight after.
- Closing a docked window brings the mixer (or another window in that docker) back to the front instead of an empty docker.
- The shortcut install no longer flashes a console window over REAPER on Windows (it runs Python's windowless pythonw where there is one).

## 5.33.0
- **Project defaults.** The Project tab (now *Project defaults*) also sets a new project's tempo, time signature and grid (straight or triplet), next to its sample rate, starter tracks or template and window set. Like the rest, they apply only to a project that's still empty. *Recording options* and *Playback options* jump to the click, count-in and pre-roll.
- **A REAPER tab.** REAPER's and SWS's options moved out of Settings into their own main tab, one sub-tab per area: Playback, Editing, Recording, View, Colours & icons, Automation, Monitoring & FX and Mixer. *In my persona* and *Load from* work on each, as before.
- **Settings in sub-tabs.** ReaPersona's own settings are split up: Sync (your other computers), Personas (what a persona may change, a persona per project, ReaPersona's actions), Scrolling & zoom, Look (this window, the screen-reader menu), Updates and Remove.

## 5.32.0
- **A layout designer.** Layout now opens with *Arrange your layout*: a picture of REAPER's window with its four docks (top, left, right, bottom), the transport's four places (top of the window, above the ruler, below the arrange view, bottom of the window), and *In its own window* and *Closed*. Drag the Mixer, the Media Explorer, the Transport and the MIDI editor where you want them. Windows in one dock are tabs in the order shown; drop one onto another to put it before it. It starts from the persona's own layout (or REAPER as it is now), *Back to the persona's own* undoes your arrangement, and the parts it sets show as set by it below.
- Only windows ReaPersona can also put back are in it: REAPER's other windows (the Actions list, the Region/Marker Manager, the Track Manager, the Navigator...) can be docked by a script but not undocked again, so a persona couldn't give you your layout back.
- Tabs are docked in the order shown; a window that's already in the right dock keeps its place among the tabs.

## 5.31.0
- **A mouse and trackpad editor.** Mouse & trackpad now has *Your persona's mouse and trackpad*: load any persona's mouse, then see its mouse wheel, trackpad swipe and drags and clicks by REAPER's own names (Media item left drag + Alt...), leave any out, change what one does (another behaviour known for that spot, REAPER's default, or any action), undo a change, or remove one you added. *Add your own*: a wheel or trackpad binding with any modifiers and action, or a drag or click on any of REAPER's 88 mouse contexts.
- **Every mouse action.** Everything the mouse does in REAPER now, its defaults included, and every persona's mouse, grouped by where you click or drag (items, tracks and mixer, MIDI editor, envelopes, ruler and markers, razor edits, arrange view, lanes), each to add to your persona. REAPER lists them with Help > Mouse modifier keys and action shortcuts: *Read REAPER's list* has it write the list (it opens in your browser too) and ReaPersona reads it.
- **REAPER's own keys in Every shortcut**, its defaults included, from the same list (*Read REAPER's keys*).
- What a spot's lines can be changed to comes from what REAPER and the personas have set there: REAPER doesn't list every behaviour it has for a spot anywhere a script can read.

## 5.30.0
- **A shortcut editor.** Shortcuts now has *Your persona's shortcuts*: load any persona's keys, then leave any out, change any (press the new keys; *Undo* puts it back), or remove keys you added, with a warning when two actions share a key. *Add a shortcut for any action* searches all of REAPER's actions, scripts and custom actions (over 10,000) and takes the keys you press.
- **Every shortcut, the most used first.** Every persona's keys and your own keymap's (what you, a script or an extension set, Main and the MIDI editor), sorted by how many personas use the action, filtered by text, type (REAPER action, script, custom action, SWS / extension), where it comes from and section. *Add* puts any of them in your persona.
- Personas sharing a shortcut layer write each key once (5.29 wrote Pro Tools' keys twice into the layer it shares with Pro Tools Intro).
- My REAPER's shortcuts are your own keymap: changes to them on this tab don't go into it yet (REAPER's Actions window does that).

## 5.29.0
- **Shortcut layers only for the personas you use.** REAPER has exactly 16 alternate shortcut layers (Main alt-1 to alt-16) and nothing can add more. Every DAW persona used to keep its own, 15 of the 16, which left almost none for personas of your own. Now each computer gives layers only to the personas it uses: your favourites, the one in use and the last one, and whatever your own personas and saved setups build on. Personas with the same keys share one (Pro Tools and Pro Tools Intro). A persona without a layer gets one the first time you use it: it asks, and REAPER restarts once. Home shows how many of the 16 are in use. Each computer keeps its own layers.json; until the next shortcut install, every DAW keeps the layer it had, so nothing changes by itself.
- **Layers with a few other tools' keys in them count as free.** StudioSync puts its Undo and Redo in every layer, so one such line used to mark a whole DAW layer as yours and unusable. A layer is yours only when most of it is your own keys; layers with a few others are used after clean ones. On the laptop this takes the next install from all 16 layers to 2.

## 5.28.0
- **My REAPER can be edited and saved over.** *Edit* on My REAPER opens its real look (its layout, mouse, theme and colours) on the tabs; *Save changes* makes the result its look on every computer. Its shortcuts are your own keymap, so another persona's keys don't go into it.
- **Earlier versions.** Every save over a persona of yours, and over My REAPER's look, keeps the version before (the newest 20, on this computer). *Earlier versions* on its page puts one back, keeping the one you had too.
- **Load from another persona or DAW on every tab.** Shortcuts, Mouse & trackpad, each part of the layout (and *Load the whole layout from*), the theme, the colours, the project and REAPER settings each load just that part from any persona.
- **Mouse & trackpad.** The Mouse tab shows the mouse wheel, the trackpad's sideways swipe and the drags and clicks apart, explains how pinch and two-finger scroll arrive, and has Smooth Wheel Scroll's trackpad zoom direction.
- **Themes and Colours come first** after Personas, and Themes shows the theme in use on its own at the top.
- **Colours:** *Set as this persona's default* instead of a tick box, separate from colouring the project. A project's own colours always win; the persona's are the default for projects without their own.
- What edits the persona sits indented on each tab, so it reads as part of it.

## 5.27.1
- **A DAW persona is never saved over.** Editing a DAW, My REAPER, Base REAPER or a saved setup always saves a new persona of yours (*Save as new*); only one you made yourself is saved over (*Save changes*). Leave the name empty and it's saved as "<DAW> - custom" ("Pro Tools - custom", then "Pro Tools - custom 2"...), shown in the name box until you type one. The engine refuses too: a save aimed at a persona you didn't make becomes a new one.

## 5.27.0
- **Personas: Favourites, DAWs and Your personas.** Click the star on any DAW's or persona's card (top left), or *Add to favourites* on its page, to keep it on Personas > Favourites. Setting up ReaPersona stars My REAPER and the DAW you pick; until you star anything, Favourites shows My REAPER and the persona in use. Favourites go to your other computers with your settings. DAWs now lists REAPER's own and the DAW personas; Your personas lists every persona you saved or made.
- **A tab for each part of a persona, chosen line by line.** The Persona Builder is gone: a persona is built from what you choose on the tabs. **Shortcuts** (whose keys, untick any), **Mouse** (whose wheel, drags and clicks), **Layout** (the mixer, its layout, the transport, the Media Explorer, the toolbar, MIDI editor docking, and snap and ripple, each from any persona), **Themes**, **Colours** (*In my persona*, following what's set there), **Project** (what a new project gets, or start from a workflow) and **Settings > REAPER tweaks** (*In my persona* on any group, following what's set there). Anything you don't choose stays as your own setup. Each part comes from one persona; lines for the other system (Mac or Windows) aren't listed.
- **Edit any persona the same way.** *Edit* on a persona's page loads each of its parts onto those tabs; the bar over every tab shows it, with its colour, *Try it*, *Save* and *Stop*. Personas built with the Builder open the same way, split into their parts.
- When the keys need a layer of their own and all 16 are in use, saving says how to get round it.

## 5.26.0
- **Make a persona from every tab.** *New persona* (Your personas) starts one; then *Use in my persona* wherever the part lives: on a DAW's page (everything, or just its shortcuts, mouse, mixer, transport and so on, or its theme), on Shortcuts (these keys), on any theme (Themes), for the colour look (Colours), and for any group of REAPER tweaks (Settings). What there's one of (a theme, a colour look, the mouse, a settings group) replaces the one in it. A bar at the top of every tab shows what's in it, with the name, *Save*, *Open in the Builder* and *Stop*. The Persona Builder is the same persona as blocks in order, each line to untick.
- **Edit any persona the same way.** *Edit* on a persona's page opens it as the persona being made: one you built opens as its blocks and saves over itself; a saved setup opens with its colours; a DAW persona opens whole and saves as your own version, so the original stays.

## 5.25.0
- **Set up everything no longer builds ReaPersona's own DAW themes.** That was the slow part, and the themes by other people look closer to the real DAWs. Building them (with Python and its image tools) is under Home > *Advanced: ReaPersona's own DAW themes*.
- **Set up everything shows its progress.** Each step runs behind a small window with a progress bar, one at a time, so REAPER never looks frozen and you can see what's left.
- **Colours is a main tab of its own** (it was under Themes). Its last line no longer runs off the page.

## 5.24.0
- **A persona's startup scripts come with where to get them.** Each script your look or a persona starts with REAPER now remembers the ReaPack repository and package it came from. Using it (or importing or syncing it) on a computer that doesn't have the script says so on the persona's page, with *Get it*: that adds the repository to ReaPack and shows the package, and installing stays your click. Once ReaPack has installed it, ReaPersona starts it and adds it to your startup, within a few seconds. Repository addresses from files and other computers must be https, and names plain.
- **No test versions for now.** Settings > Updates follows released versions only.

## 5.23.0
- **Updates in Settings.** Settings > Updates shows the version you have and checks GitHub for a newer one (once a day when you open Settings, or *Check now*), with *Update to ...* and *What's new*. Installed with ReaPack, a release updates through ReaPack's sync, as StudioSync's Update does; a copy ReaPack didn't install downloads the release's files in the background (REAPER isn't held up) and puts them in place only once every one has come and says the right version. Then close ReaPersona's window and open it again.
- **Test versions.** *Get test versions* (Settings > Updates, this computer only) follows ReaPersona's testing branch: new features before they're released. Switch it off and update to go back to the released version. ReaPack only ever sees released versions.

## 5.22.0
- **The scripts REAPER starts with go with your look and your personas.** Chordbox, the adaptive grid, Gridbox and anything else your startup file launches (as FTC Tools and others add them: *Start script: ...*) are kept by *Use this look on all my computers*, by *Save what I'm using...* and by a built persona's My REAPER block. Using one on a computer that has the script installed adds its start line there (your startup file is backed up first) and starts it if it's stopped; one that isn't installed yet is added once ReaPack or your scripts bring it. They're never removed, so they keep running under every persona. Only the command name travels, never code. A saved persona lists them in its description.

## 5.21.1
- **A look saved on one computer reaches the others.** A computer that had never saved a look sent an empty one, stamped newer than the look you'd just saved elsewhere, so it won. An unsaved look isn't sent now, and *Forget* is sent as a change, so your other computers forget it too.

## 5.21.0
- **Your look on every computer.** My REAPER was whatever each computer had, so a Mac kept REAPER's Default 7 theme and the transport under the arrange view while your PCs had Reapertips and the transport above the ruler. On My REAPER's page, *Use this look on all my computers* keeps this computer's theme, transport place, mixer (docked or not, showing or not, master side, inserts and sends), docked windows, snap, ripple, auto-scroll and mouse drags as your look. It syncs through your sync folder and goes in exported setup files like any setting, and My REAPER uses it on every computer as that computer's own setup: every persona sits on top of it and leaving one comes back to it. A look that comes in while you're on My REAPER is used straight away. Its theme is used where that computer has the file (Themes sync brings it), and mouse drags marked for the other system are skipped. Press it again after you change your look; *Forget* makes My REAPER each computer's own again.

## 5.20.1
- **Base REAPER has all of REAPER's own wheel shortcuts.** Read from a REAPER 7.86 started on a blank settings folder: besides the four it had, Ctrl+Shift+wheel adjusts the selected tracks' heights, Alt+Shift+wheel scrolls a page up or down, the horizontal wheel scrolls sideways and Alt+horizontal wheel zooms, so your own bindings for those no longer show through it. (Stock REAPER has no Shift+wheel action at all, and Shift+wheel does nothing there: tested.)
- `core.save_user_style` is open to scripts (a built persona with a key added by hand).

## 5.20.0
- **Colours go with personas and workflows.** *Save what I'm using...* keeps the colour look in use (Themes > Colours: how tracks, items and regions are coloured, and your instrument, folder and section colours) with the persona; the Persona Builder has a *Colours* block for the same. Switching to a persona with colours makes them your look while it's in use, and switching away gives you yours back exactly. A persona of yours with colours can be a workflow on top of any persona, and a workflow's new projects get their starter tracks (and regions) coloured in its look. Colour sets from shared files and other computers are checked: only the colour settings, each JSON.
- **The colour look survives a restart.** It was saved as several lines of JSON, and REAPER keeps only the first line of a saved setting: it's one line now.

## 5.19.0
- **Colours: StudioSync's colour system, in ReaPersona** (Themes > Colours). Colour a whole project at once: tracks by gradient, folder, instrument (from their names), stripes, rainbow or confetti; items by section, along the song, lane, takes or kind; regions by section or along the song. Seven palettes or two colours of your own, your own colours per instrument, folder and section (kept on this computer, for every project), a preview bar for each, and Try it first (Keep it, or Put it back exactly). A project remembers its look; a new one starts from your last pick. One computer only: StudioSync's "by who made it", "newest work" and studio look stay in StudioSync. (`colours.lua`, from StudioSync 0.59.7's `lib/colours.lua`.)

## 5.18.1
- **Each persona opens the way its DAW does.** Switching to a persona now also sets whether the mixer is showing, as that DAW opens: its edit window first, mixer closed, for Pro Tools (Ctrl+=), Logic (X), FL Studio (F9), Cubase and Nuendo (F3), Studio One (F3), Bitwig (M), Cakewalk (Alt+2), Ableton, GarageBand, Audacity and Audition; Base REAPER shows it docked at the bottom, as REAPER does. Reason's Main Mixer docks at the top when you open it (F5) instead of filling the window. Switching away puts your mixer back. (Settings > what personas may change > Mixer turns this off.)
- **A persona's mixer setting no longer gets undone by the last persona's windows.** Leaving a persona that moved the mixer (Reason) put it back after the next persona had set it, so that one showed the mixer anyway and then hid yours when you switched back. The last persona's windows now go back first.
- **Previews are exactly what a persona looks like.** The pictures no longer force the mixer open and docked (that made the tall mixers): each shows what using the persona gives, in its recommended theme. The README's pictures are made from the same ones.

## 5.18.0
- **Each DAW persona's best look-alike theme is its default.** Picked from all 44 community themes ReaPersona knows by capturing each one: Pro Tools and Pro Tools Intro now recommend PRO TOOLS GOLD 2026 (was ProTools2020), Bitwig INQUASAR DARK MATTER (was Reapertips Purple), Reason Dark_Side_Imperial (was ReaPersona's own); Logic and GarageBand (I Logic V3 WC), Ableton Live (rLive), FL Studio (FL Studio Theme beta 4), Cubase and Nuendo (CubeXR) and Studio One (HYDRA) keep theirs. Switching to a persona still offers its look once, and a theme you picked yourself stays yours.
- **The installer puts that look on too.** Setting up a new REAPER as a DAW now downloads the persona's recommended theme first (where there's a download for it), so the first start already looks like that DAW. If the download doesn't work, setup says so and carries on; the Themes page has it.
- **Previews show those looks.** The persona pictures (and the README's) are taken with each DAW's recommended theme, once the persona has finished moving its windows, with ReaPersona's own window out of the way. GarageBand, Nuendo and Pro Tools Intro have pictures of their own.

## 5.17.3
- **ReaPersona's window can't dock any more.** Switching to a persona that docks a window (FL Studio's browser on the left, here the Media Explorer) could leave ReaPersona's own window in a docker, often a floating or hidden one, where it was hard to find, and it stayed there after switching back. Its window and the theme adjuster now always float; one an earlier version left in a docker comes out the first time it opens.

## 5.17.2
- **The installer's restart waits for REAPER's first-start windows.** On a clean Linux, the evaluation reminder, the audio device error and ReaPack's notice were still open when setup asked REAPER to quit, so it didn't, and the shortcuts never went in. Setup now waits until they're answered (up to 20 minutes), then restarts.
- **"My REAPER as it was" really skips a brand-new REAPER now.** Besides its [hasimported] list, a new REAPER 7.86 writes two MIDI note-click mouse defaults itself; those were still taken for your own changes. The check now knows REAPER's factory mouse file. (Both found running the installer in a clean Linux VM.)

## 5.17.1
- **An installer for people new to REAPER** (`installer/`: double-click *Install ReaPersona (Windows).cmd* or *Install ReaPersona (Mac).command*, or the one-line command for Linux in the README). It installs what's missing (REAPER, ReaPack, ReaImGui, js_ReaScriptAPI, SWS), asks which DAW you're coming from, and leaves REAPER set up as it, shortcuts included, after one restart, with or without Python. `-Persona <id>` / `RP_PERSONA=<id>` answers the question up front. Tested end to end in Windows Sandbox (a clean Windows 11).
- A brand-new REAPER no longer gets a "My REAPER as it was" persona: the list of mouse contexts REAPER writes itself on its first start was taken for changed mouse behaviours (found in that Sandbox run).

## 5.17.0
- **Your own setup is kept for you.** The first time ReaPersona switches a new user to a persona, the REAPER setup they already had (theme, the settings and mouse behaviours personas touch, where the mixer and other windows sit, on their own keys) is first saved as a persona of its own, "My REAPER as it was (<computer>)", so it's one click away whatever changes later. Nothing is saved when that setup is REAPER as it ships (no keys, mouse behaviours, menus or toolbars of your own, the Default 7 theme, REAPER's factory options): Base REAPER already is that. Once per computer, never for people already using ReaPersona.

## 5.16.1
- **Per-project settings sync as defaults.** Settings REAPER keeps per project (sample rate, metronome, auto-crossfade and recording options, grid, render settings and the rest) were read from the project in front, so opening a 48 kHz voiceover project could send 48 kHz to your other computers as their default. They're now read from REAPER's saved defaults for new projects.
- **ReaPack installs no longer blocked by a leftover file record.** A file still listed for a package that's gone made ReaPack refuse the package that has it now (the Mac's eralumin MIDI Channel Toggle stayed at version 0). Package syncing clears those records first.

## 5.16.0
- **A workflow on top of any persona.** Personas > *Workflow on top* (and the screen-reader menu) adds a kind of session to whichever persona you use: keep Pro Tools' keys, theme and layout and pick Voiceover, and new projects come up at 48 kHz with an armed voiceover track and Voiceover's settings. The seven starters (Voiceover, Podcast, Music, Live looping, Mixing, Mastering, Video post) can be picked straight away, as can your own personas that have a project part (their project part and their Builder settings blocks). A workflow on top brings only REAPER toggle actions and its project part, never keys, theme, windows or the mouse; its settings win where the persona sets the same one, and None puts everything back. As before, only an untouched new project is set up, each computer keeps its own track inputs for a workflow (*Keep these inputs*), and the workflow you pick stays on each computer, like the persona in use. The top bar shows "persona + workflow".
- **Nuendo** (Nuendo 14 key commands: Edit, Nudge and Editors categories): Shift+U Unmute Events; E and D Left/Right Selection Side to Cursor (here: trim the selected events' start or end to the cursor); Alt+Left and Alt+Shift+Right Nudge Start Left/Right; Alt+Shift+Left and Alt+Right Nudge End Left/Right; Ctrl+Shift+I Edit In-Place (the item's inline MIDI editor).
- **Pro Tools and Pro Tools Intro** (Avid's Shortcuts Guide 2025.10; none of these is marked for a tier): Delete deletes like Backspace, Shift+M mutes the tracks with the Edit cursor or selection, Ctrl+Shift+W closes the session, Alt+Shift+D duplicates tracks, Ctrl+keypad 1 shows the Transport.
- **GarageBand** (GarageBand 10.4.14 Main window shortcuts): Option-C picks a colour for the selected tracks, and N opens the selected MIDI region in the MIDI editor's notation view (GarageBand's Score Editor).
- Not added: Nuendo's Alt+R and Alt+W (Read and Write Automation for All Tracks). They turn reading or writing on and off, and REAPER has no automation-off mode to switch back to, the same as Cubase's in 5.12.
- Install the shortcuts again (Home > Reinstall) to get the new keys.
- **One-button shortcut install on a Mac and Linux without Python.** macOS ships without Python, so until now a Mac got a keymap file to import by hand and no toolbars. Install and restart now works everywhere: ReaPersona plans the install inside REAPER (the same rules as install_shortcuts.py, which stays the route where Python is), and a small shell script waits for REAPER to close, checks that nothing changed the keymap or menus since, backs your keymap up first (the same backups as before), swaps the new keymap and toolbars in, and opens REAPER again (with `open` on a Mac, with the projects you had open). Remove ReaPersona takes the shortcut layers out the same way. Tested against install_shortcuts.py on a Mac's real keymap: the same keymap, toolbars and saved MIDI keys.
- **Pillow and numpy install in the background, into ReaPersona's own Python environment.** *Install them* used `pip install --user`, which Homebrew's Python 3.12+ and recent Debian and Ubuntu refuse ("externally-managed-environment"), and REAPER froze for up to 10 minutes while it ran. ReaPersona now makes a venv in its folder (`ReaPersona/venv`) and installs into it while you keep working; Home says when they're in, or what went wrong (on Debian or Ubuntu: install `python3-venv` first). A Python that already has them keeps working as before.

## 5.15.0
Fixes from a three-reviewer pass over 5.13 and 5.14:
- **Screen readers:** a new action, *ReaPersona - screen-reader menu*, always opens the menu, so turning it off can't lock anyone out. The menu also saves what you're using, opens a new project with a workflow, keeps a workflow's inputs and opens the cheat sheet. Results are no longer spoken twice. The menu setting stays on each computer instead of syncing.
- **OSARA's keys stay OSARA's:** installing the shortcuts never puts a persona key over a key OSARA uses (main section or MIDI editor), and says how many it left out.
- **Workflows are safer:** a workflow sets up only a new project nothing has been done in (untitled, unchanged, no items, markers, tempo changes or master FX), and REAPER asks before anything would be replaced. *New project with it* opens a tab without the default project template, so the workflow isn't skipped, and no longer sets up two tabs. The project goes in before the persona's settings, so a template no longer resets them.
- **Undo switch** survives closing the window or the menu.
- **Install without Python:** your own MIDI editor keys are saved before the new keymap goes in; a sync that arrives while REAPER quits waits for the next install instead of being dropped; a missing styles.json stops the install instead of removing every persona; the batch window starts minimized.
- **Backups:** sync backups no longer push the newest install backup out of the four kept.
- **Plug-in and render presets no longer sync** (5.13.0 added them): each computer has its own copy of those files, so the newest whole file could replace another computer's presets. None were lost.
- **Personas:** Cubase and Nuendo's Nudge Cursor moves by a grid division; their Cut time and fast wind keys say what they do in REAPER; workspaces are Alt+keypad 1-9. Nuendo's description says where it differs from Cubase. Pro Tools and Pro Tools Intro: clip groups are Ctrl+Alt+G/U, and the Tab to Transient and pre-roll notes match their keys.
- **On a Mac** a persona's page lists its keys macOS keeps for itself (Cmd+Space, Cmd+H, Cmd+M, F11, Cmd+Option+D).
- Getting started goes once its three steps are done (the fourth is optional); help, README and tooltips match what ReaPersona does. Workflow starters: voiceover has pre-roll on record, live looping keeps FX running while stopped, mixing has solo in front, music turns the click on.

## 5.14.0
- **Install the shortcuts on Windows without Python.** Home > Install and restart now works with no Python: ReaPersona plans the install inside REAPER (the same rules as install_shortcuts.py, which stays the route where Python is) and a small batch file waits for REAPER to close, swaps the new keymap and toolbars in, backs your keymap up first and opens REAPER again. If anything changed the keymap between the plan and REAPER closing, nothing is swapped in and ReaPersona says so. Another computer's script keys are still never taken. Preferences from your other computers still need Python (REAPER writes them as it quits). Remove ReaPersona also takes the shortcut layers out without Python on Windows.
- **A menu for screen readers.** ReaImGui's window is invisible to NVDA, JAWS and VoiceOver, so ReaPersona has a menu in REAPER's own menus with the main tasks: what's installed, pick a persona, back to My REAPER, undo the switch, install the shortcuts, sync or save and load your setup, and its help. Results come in message boxes, and OSARA speaks them and the page names in the window. Turn it on in Settings > ReaPersona > Screen readers; with OSARA installed ReaPersona asks the first time.
- **Help > How it works:** the first steps, what each page does, the keys (F1 opens it, Ctrl+K searches), screen readers and how your setup is kept safe, with Copy as plain text.
- **Getting started on Home:** the first steps with what's done and a button for each, until they're done or you hide them.

## 5.13.1
Three new DAW personas, every key checked against the maker's own documentation and cited in the persona's docs list:
- **Nuendo** (alt-13): Steinberg's Nuendo 14 default key commands are the same list as Cubase 14's, so it has Cubase's keys, MIDI editor keys, toolbars and layout. Its mouse follows Nuendo's Tool Modifiers page: Alt+drag copies, Alt+click splits, Alt+Shift+drag slips an event's contents.
- **Pro Tools Intro** (alt-14): Avid's Shortcuts Guide marks the keys only some tiers have (Studio or Ultimate only), and none of the Pro Tools persona's keys is one of them; Avid's comparison gives Intro every feature they use (comping, Elastic Audio, retrospective MIDI, freeze, clip gain, folders). So it has the Pro Tools keys, Smart Tool and toolbar, with Intro's track limits on its page.
- **GarageBand** (alt-15): GarageBand 10.4.14's Main window, Editors and Global tracks shortcuts, with Command as Ctrl and Option as Alt (Control-key commands on a Mac only), on Logic's look and toolbars and without a mixer. Drag in empty space selects regions, Option-drag copies, as Apple's guide says. Apple's GarageBand for Mac guide was offline at support.apple.com, so the links are Apple's own pages as the Internet Archive kept them.
- **Fixed:** Cubase's F2 is Rename Selected Events (here: the item/take properties), and Ctrl+Alt+T shows and hides the transport, as Cubase 14's key list has them.
- Only alt-16 is now left for personas of yours with a layer of their own. Install the shortcuts again (Home > Reinstall) to get the new layers.

## 5.13.0
- **Workflows from a whole project.** *Save what I'm using...* with "Make it a workflow too?" now keeps the whole project as the workflow's template: every track with its FX, routing and folders, the sample rate, recording format, render settings, tempo and time signature, markers and regions (not its audio, MIDI, media bay or scripts' data). The Builder's Project block can take one too (*Use this whole project*). A new, empty project with the persona starts as that project did.
- **New project with it** on a workflow's page opens a new tab set up by it.
- **Each computer's inputs:** set a workflow's track inputs once on a computer and press *Keep these inputs on this computer*; new projects with that workflow get them there, and your other computers keep their own.
- **Plug-in check:** a new project from a workflow says which of its plug-ins this computer hasn't got.
- **More of REAPER's options for personas and workflows:** a Monitoring and FX group (FX running while stopped, monitoring FX bypassed, MIDI input quantize, looped scrub) and more in Playback, Editing (razor edits, slip editing, pooled MIDI), Recording (comping fades) and Automation.
- **New starter workflows:** Mixing, Mastering and Video post (48 kHz, timecode ruler).
- **Syncing:** plug-ins' presets and render presets go with FX chains and templates.
- Fixed: ReaPack syncing on a Mac stopped at an "Obsolete packages" question when another computer had packages with no Mac version; those are no longer passed on to computers that can't install them.

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
