# ReaPersona setup for Windows: REAPER set up like the music app you're coming from, shortcuts included. For people new to REAPER.
# Run it with "Install ReaPersona (Windows).cmd" (double-click). Windows PowerShell 5.1 compatible.
# Installs what's missing and skips what's there: REAPER, ReaPack, ReaImGui, js_ReaScriptAPI and SWS, then ReaPersona itself (through
# ReaPack), then sets REAPER up as the DAW you pick. Each comes from its official source: REAPER from winget (or reaper.fm), the extensions
# from their own releases (the files ReaPack's ReaTeam Extensions index points at). REAPER restarts once at the end, for the shortcuts.
# The question can be answered up front: -Persona <id>, one of ReaPersona's own (ReaPersona/styles.json): base_reaper is plain REAPER.
# Modelled on StudioSync's installer (github.com/FmsJay/studiosync, same author, GPL-3.0).
param(
  [string]$Persona = "",
  [string]$ReaperPath = "" # a REAPER somewhere this doesn't look (a portable folder): its folder or reaper.exe
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue" # Invoke-WebRequest is 10x slower with the progress bar
# (Windows PowerShell 5.1 on older Windows 10 offers only TLS 1.0/1.1 unless .NET's strong crypto is set, and GitHub refuses those:
# "Could not create SSL/TLS secure channel" on every download. 3072 = TLS 1.2, added to whatever is allowed already. Round 1)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$Raw = "https://github.com/FmsJay/ReaPersona/raw/main"
$ReaPackVer = "v1.2.6"
$ReaImGuiVer = "0.10.0.5" # shortcut: pinned, as StudioSync's installer; ReaPack keeps them updated only if later reinstalled through ReaPack
$JsApiVer = "v1.310"
$SwsVer = "v2.14.0.7"

# Programs started from some sandboxed apps (seen: the Claude desktop app) get a private copy of AppData, so the REAPER settings set up
# there are invisible to the same REAPER started normally. The process isn't "packaged", so test what matters: does a write to AppData
# land in an app's sandbox? Then reopen through Explorer, which starts things outside it, with the same answers. (StudioSync, 2026-10-27)
$probe = "reapersona_probe_" + [guid]::NewGuid().ToString("N")
Set-Content (Join-Path $env:LOCALAPPDATA $probe) "x"
$boxed = Get-ChildItem "$env:LOCALAPPDATA\Packages\*\LocalCache\Local\$probe" -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA $probe) -ErrorAction SilentlyContinue
if ($boxed) {
  $argv = @()
  foreach ($k in "Persona", "ReaperPath") { $v = Get-Variable $k -ValueOnly; if ($v) { $argv += @("-$k", $v) } }
  $quoted = ($argv | ForEach-Object { if ($_ -match '^-') { $_ } else { '"' + $_ + '"' } }) -join " "
  $cmd = Join-Path $env:TEMP "reapersona_install_outside.cmd"
  # (UTF-8 with chcp 65001: a user name with accents in the path came out as "?" in an ASCII file. StudioSync, 0.58.78)
  [IO.File]::WriteAllText($cmd, "@echo off`r`nchcp 65001 >nul`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $quoted`r`npause`r`n", (New-Object System.Text.UTF8Encoding($false)))
  Start-Process explorer.exe -ArgumentList "`"$cmd`""
  Write-Host "This window runs inside another app's sandbox; ReaPersona setup continues in a new window. If none appears, double-click 'Install ReaPersona (Windows).cmd' yourself." -ForegroundColor Yellow
  exit 0
}

function Say($t) { Write-Host $t -ForegroundColor Cyan }
function Ok($t) { Write-Host "  OK  $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  !!  $t" -ForegroundColor Yellow }
function Ask($q, $def) { $a = Read-Host "$q$(if ($def) { " [$def]" })"; if ($a) { $a.Trim() } else { $def } }

Say "ReaPersona setup"
Write-Host "This installs REAPER and what ReaPersona needs, then sets REAPER up like the music app you're used to: its shortcuts,"
Write-Host "mouse and look. Windows may ask permission to install REAPER. Nothing already installed is changed."
Write-Host ""

# ---------- 0. the question ----------
# ReaPersona's own ids and names (ReaPersona/styles.json). Enter: plain REAPER (base_reaper), for someone who isn't coming from anywhere.
$personas = @(
  @("pro_tools", "Pro Tools"), @("pro_tools_intro", "Pro Tools Intro"), @("logic", "Logic Pro"), @("garageband", "GarageBand"),
  @("ableton", "Ableton Live"), @("fl_studio", "FL Studio"), @("cubase", "Cubase"), @("nuendo", "Nuendo"),
  @("studio_one", "Studio One / Fender Studio Pro"), @("bitwig", "Bitwig Studio"), @("cakewalk", "Cakewalk / Sonar"), @("reason", "Reason"),
  @("audacity", "Audacity"), @("audition", "Adobe Audition"), @("reapertips", "REAPER with the Reapertips theme"),
  @("my_reaper", "My REAPER: keep the setup I already have"), @("base_reaper", "None: plain REAPER"))
$ids = @($personas | ForEach-Object { $_[0] })
$persona = $Persona.Trim().ToLower()
if ($persona -in "none", "plain", "reaper") { $persona = "base_reaper" }
if ($persona -and $persona -notin $ids) { Warn "'$Persona' isn't one of ReaPersona's DAWs ($($ids -join ', '))."; $persona = "" }
if (-not $persona) {
  Write-Host "Which music app are you coming from? REAPER takes on its shortcuts, mouse and look (switch any time, in ReaPersona):"
  for ($i = 0; $i -lt $personas.Count; $i++) { Write-Host ("  {0,2}) {1}" -f ($i + 1), $personas[$i][1]) }
  while (-not $persona) {
    $n = Ask "Its number, or Enter for none (plain REAPER)" ""
    if (-not $n) { $persona = "base_reaper" } elseif ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $personas.Count) { $persona = $ids[[int]$n - 1] } else { Warn "A number from the list, or Enter." }
  }
}
$names = @{}; foreach ($p in $personas) { $names[$p[0]] = $p[1] }
Ok "REAPER will be set up as: $($names[$persona])"
Write-Host ""

# ---------- 1. REAPER ----------
function Get-Reaper { Get-Process reaper -ErrorAction SilentlyContinue }
# REAPER wherever it is: the running one, -ReaperPath (a portable folder), the usual folders, where Windows' list of installed programs says,
# what opens .rpp files, a REAPER folder at the top of a drive. (StudioSync installer review, 0.58.78)
function Find-Reaper {
  $p = Get-Reaper | Select-Object -First 1
  if ($p -and $p.Path) { return $p.Path }
  $c = @()
  if ($ReaperPath) { $c += $ReaperPath, (Join-Path $ReaperPath "reaper.exe") }
  $c += "$env:ProgramFiles\REAPER (x64)\reaper.exe", "$env:ProgramFiles\REAPER\reaper.exe"
  $c += Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match '^REAPER' } | ForEach-Object {
      if ($_.InstallLocation) { Join-Path $_.InstallLocation "reaper.exe" }
      if ($_.UninstallString) { Join-Path (Split-Path ($_.UninstallString -replace '"', '')) "reaper.exe" }
    }
  $type = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\.rpp" -ErrorAction SilentlyContinue).'(default)'
  $open = if ($type) { (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$type\shell\open\command" -ErrorAction SilentlyContinue).'(default)' }
  if ("$open" -match '"([^"]*reaper\.exe)"') { $c += $Matches[1] }
  $c += [IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -in 'Fixed', 'Removable' } | ForEach-Object { Join-Path $_.Name "REAPER\reaper.exe"; Join-Path $_.Name "REAPER (x64)\reaper.exe" }
  foreach ($x in $c) { if ($x -and $x -match 'reaper\.exe$' -and (Test-Path -LiteralPath $x -PathType Leaf)) { return $x } }
  return $null
}
$downloads = @() # (installers fetched here: deleted at the end)
if (-not (Find-Reaper) -and -not $ReaperPath) {
  # (a REAPER somewhere this doesn't look is asked for, rather than a second one installed beside it)
  $ReaperPath = "$(Ask "REAPER wasn't found. If it's somewhere else (a portable copy), paste the folder it's in; or press Enter to install it" '')".Trim().Trim('"')
  if ($ReaperPath -and -not (Find-Reaper)) { Warn "No reaper.exe in $ReaperPath : installing REAPER." }
}
if (Find-Reaper) { Ok "REAPER is already installed" }
else {
  $ErrorActionPreference = "Continue" # (winget writes to stderr, which Windows PowerShell 5.1 turns into errors)
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Say "Installing REAPER (winget; a 60-day evaluation, see reaper.fm for the licence) ..."
    & winget install --id Cockos.REAPER --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Warn "winget couldn't install REAPER (exit $LASTEXITCODE)" }
  } else { # (an older Windows 10, or App Installer removed: REAPER's own installer from reaper.fm)
    try {
      $m = [regex]::Match((Invoke-WebRequest -UseBasicParsing "https://www.reaper.fm/download.php").Content, 'files/[0-9.x]+/reaper[0-9]+_x64-install\.exe')
      $file = Join-Path $env:TEMP ($m.Value -split '/')[-1]
      Say "Downloading REAPER from reaper.fm (no winget here) ..."
      Invoke-WebRequest -UseBasicParsing ("https://www.reaper.fm/" + $m.Value) -OutFile $file
      $downloads += $file
      Say "  REAPER's own installer opens: click through it (the defaults are fine)."
      Start-Process $file -Wait
    } catch { Warn "REAPER didn't download: $_" }
  }
  $ErrorActionPreference = "Stop"
}
$reaper = Find-Reaper
if (-not $reaper) { Warn "REAPER wasn't found after installing: install it from reaper.fm and run this again."; exit 1 }
$exeDir = Split-Path $reaper
$res = if (Test-Path (Join-Path $exeDir "reaper.ini")) { $exeDir } else { Join-Path $env:APPDATA "REAPER" } # portable installs keep everything beside reaper.exe
Ok "REAPER: $reaper (settings in $res)"

# ---------- 2. REAPER extensions: ReaPack, ReaImGui, js_ReaScriptAPI, SWS ----------
# Each skipped when any copy of it is there already (UserPlugins, or an older install's Plugins folder beside reaper.exe: two copies of an
# extension make REAPER complain at every start). js_ReaScriptAPI and SWS: the files ReaPack's ReaTeam Extensions index points at (both MIT).
$userPlugins = Join-Path $res "UserPlugins"
function Have($glob) { [bool](Get-ChildItem $userPlugins, (Join-Path $exeDir "Plugins") -Filter $glob -ErrorAction SilentlyContinue) }
$need = @()
if (-not (Have "reaper_reapack*")) { $need += @{ file = "reaper_reapack-x64.dll"; url = "https://github.com/cfillion/reapack/releases/download/$ReaPackVer/reaper_reapack-x64.dll" } }
if (-not (Have "reaper_imgui*")) { $need += @{ file = "reaper_imgui-x64.dll"; url = "https://github.com/cfillion/reaimgui/releases/download/v$ReaImGuiVer/reaper_imgui-x64.dll" } }
if (-not (Have "reaper_js_ReaScriptAPI*")) { $need += @{ file = "reaper_js_ReaScriptAPI64.dll"; url = "https://github.com/juliansader/ReaExtensions/raw/master/js_ReaScriptAPI/$JsApiVer/reaper_js_ReaScriptAPI64.dll" } }
if (-not (Have "reaper_sws*")) { $need += @{ file = "reaper_sws-x64.dll"; url = "https://github.com/reaper-oss/sws/releases/download/$SwsVer/reaper_sws-x64.dll" } }
$Reopen = $false
if ($need.Count -gt 0) {
  if (Get-Reaper) {
    Say "REAPER has to restart to load its new extensions. Press Enter and REAPER is asked to close (it asks to save"
    Say "anything unsaved first; it reopens afterwards), or close it yourself."
    Read-Host | Out-Null
    Get-Reaper | ForEach-Object { [void]$_.CloseMainWindow() } # like clicking X: REAPER asks to save
    $Reopen = $true
    $waited = 0
    while (Get-Reaper) {
      Start-Sleep 1; $waited++
      if ($waited % 30 -eq 0) { # (asking again: REAPER drops a close asked for while it's busy, say scanning plug-ins for the first time)
        Get-Reaper | ForEach-Object { [void]$_.CloseMainWindow() }
        Say "Still waiting for REAPER to close (it may be scanning plug-ins, or waiting on a question: answer it if it asked one) ..."
      }
    }
  }
  New-Item -ItemType Directory -Force $userPlugins | Out-Null
  # (to a .part file first: one cut off half way stayed there, broken, and a second run said it was already installed)
  foreach ($n in $need) {
    $dest = Join-Path $userPlugins $n.file
    try { Invoke-WebRequest -UseBasicParsing $n.url -OutFile "$dest.part" } catch { }
    if ((Test-Path "$dest.part") -and (Get-Item "$dest.part").Length -gt 0) { Move-Item -Force "$dest.part" $dest; Ok "$($n.file) installed" }
    else { Remove-Item -Force "$dest.part" -ErrorAction SilentlyContinue; Warn "$($n.file) didn't download" }
  }
} else { Ok "ReaPack, ReaImGui, js_ReaScriptAPI and SWS are already installed" }

# ---------- 3. ReaPersona, inside REAPER ----------
# reapersona_setup.lua (beside this script in a checkout, else from GitHub) runs in REAPER: it adds ReaPersona's ReaPack repository, syncs,
# waits for ReaPersona, sets REAPER up as the persona, and starts the shortcut install (one restart). It reads a request JSON beside itself
# and writes its result beside itself; this waits for that.
$work = Join-Path $env:TEMP "reapersona_setup"
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $work | Out-Null
$helper = Join-Path $work "reapersona_setup.lua"
$local = if ($PSScriptRoot) { Join-Path $PSScriptRoot "reapersona_setup.lua" } else { "" }
if ($local -and (Test-Path $local)) { Copy-Item $local $helper }
else {
  try { Invoke-WebRequest -UseBasicParsing "$Raw/installer/reapersona_setup.lua" -OutFile $helper }
  catch { Warn "ReaPersona's setup step didn't download ($($_.Exception.Message)). Check the internet connection, then run this again."; exit 1 }
}
$result = Join-Path $work "reapersona_setup_result.json"
$started = Join-Path $work "reapersona_setup_started" # (the helper's first act: it has the request)
$req = @{ persona = $persona; repo_url = "$Raw/index.xml" } | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $work "reapersona_setup.json"), $req, (New-Object System.Text.UTF8Encoding($false))) # no BOM: Lua reads plain UTF-8
if ($Reopen -and -not (Get-Reaper)) {
  # we closed REAPER: start it the way you do, so it reopens your projects as it always does (started WITH the helper it came back
  # with an empty project), then hand it the helper once it's up
  Start-Process $reaper
  for ($i = 0; $i -lt 60 -and -not (Get-Reaper | Where-Object { $_.MainWindowHandle -ne 0 }); $i++) { Start-Sleep 1 }
  Start-Sleep 5
}
Say "Setting up ReaPersona inside REAPER. REAPER opens now; the first time, it scans your plug-ins and asks a few things, which need answering:"
Say "  'Select your audio device now?': No is fine for now (pick your audio interface in Options > Preferences > Audio before you play)."
Say "  ReaPack's 'Manage repositories', 'Notice' and 'Transaction report': OK. This window carries on by itself once ReaPersona has arrived."
$wasUp = [bool](Get-Reaper | Where-Object { $_.MainWindowHandle -ne 0 })
Start-Process $reaper -ArgumentList @("-nonewinst", "`"$helper`"") # ONE request: the helper waits inside REAPER for ReaPack itself
$gone = $false
$asked = 1
# (a REAPER's first start scans every plug-in and asks its questions before it runs anything: until the helper starts, this waits while REAPER
# is open, and says what's happening; once it has, the 4 minutes the helper gives ReaPack and some to spare. StudioSync, 0.58.78)
$at = $null
for ($i = 0; -not (Test-Path $result); $i++) {
  Start-Sleep 1
  if ($null -eq $at -and (Test-Path $started)) { $at = $i }
  if ($null -ne $at) { if ($i - $at -gt 420) { break } } elseif ($i -gt 2700) { break }
  if ($null -eq $at -and $i -gt 90 -and $i % 120 -eq 0) { Say "Still waiting ($([int]($i / 60)) minutes). A first start scans every plug-in on this PC before anything else runs: 10 minutes or more with a big collection (REAPER's window names each one), and its questions may be hidden behind other windows. Nothing is stuck while REAPER is open." }
  # (a REAPER that was already open sometimes never gets the hand-off; handed over again only while the helper hasn't started, so it never
  # runs twice. StudioSync, AgentBox 0.58.65)
  if ($wasUp -and $asked -lt 4 -and $i -eq 20 * $asked -and -not (Test-Path $started)) {
    Say "REAPER hasn't picked up the setup step yet: handing it over again."
    Start-Process $reaper -ArgumentList @("-nonewinst", "`"$helper`"")
    $asked++
  }
  if ($i -gt 15 -and -not (Get-Reaper)) { $gone = $true; break }
  if ($i -eq 90) { Say "Still waiting for ReaPersona to arrive through ReaPack. Look in REAPER for its first-start windows and answer them: 'select your audio device now?' (No is fine), then OK on ReaPack's Manage repositories, Notice and Transaction report. Another window may be covering them." }
}
$r = $null
if (Test-Path $result) { Start-Sleep -Milliseconds 300; $r = Get-Content $result -Raw | ConvertFrom-Json }

# ---------- 4. what was done, and what's left ----------
$left = @()
if ($r) {
  foreach ($s in $r.steps) { if ($s.ok) { Ok "$($s.name)$(if ($s.detail) { ": $($s.detail)" })" } else { Warn "$($s.name): $($s.detail)" } }
  if ($r.note) { $left += $r.note }
  if ($r.restart) { $left += "Once REAPER is back: try a few of your old shortcuts. ReaPersona's window (Extensions > ReaPersona) switches DAWs, themes and cheat sheets any time." }
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
} elseif ($gone) {
  Warn "REAPER closed unexpectedly during setup. Open REAPER, then run this again."
} else {
  # (REAPER still on its first-start windows, or ReaPack still bringing ReaPersona: the setup step carries on by itself once they're
  # answered, so its files stay. StudioSync, Windows Sandbox run 0.58.78)
  if (Test-Path $started) { Warn "ReaPersona's setup step is still running inside REAPER (ReaPack is taking its time): it finishes by itself, and REAPER restarts once when it's done." }
  else { Warn "REAPER hasn't got to ReaPersona's setup step yet: it's still on its first-start windows (the audio device, ReaPack's Manage repositories, Notice and Transaction report), which another window may be hiding. Answer them: setup then carries on by itself." }
  $left += "If REAPER never restarts by itself: Extensions > ReaPack > Synchronize packages, then open ReaPersona (Extensions > ReaPersona, or the Actions list) and pick your DAW on Home."
}
$left += "Pick your audio interface: Options > Preferences > Audio > Device (an ASIO driver if your interface has one)."
$left += "REAPER is a 60-day evaluation: after that it still works, and reminds you to buy a licence (reaper.fm/purchase.php)."
foreach ($d in $downloads) { Remove-Item -Force $d -ErrorAction SilentlyContinue }
Write-Host ""
Say "Done. What's left:"
foreach ($l in $left) { Write-Host "  - $l" }
