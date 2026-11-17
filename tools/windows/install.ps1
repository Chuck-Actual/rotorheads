<#
.SYNOPSIS
  Installs the Rotorheads scripts into a DCS World game or dedicated server on this PC.

.DESCRIPTION
  - Copies rotorheads.lua and downloads Moose_.lua into   <Saved Games>\Missions\Rotorheads\
  - Copies the server hook into                            <Saved Games>\Scripts\Hooks\
  - With -Desanitize, edits <DCS install>\Scripts\MissionScripting.lua so missions can save files
    (keeps a backup next to it). This needs an Administrator PowerShell when DCS is under Program Files.

  Run it again after every update of this repo, and -Desanitize again after every DCS update.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\windows\install.ps1 -Desanitize

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\windows\install.ps1 -Server -Desanitize
#>
[CmdletBinding()]
param(
  # Install into the dedicated server (Saved Games\DCS.dcs_serverrelease) instead of the game.
  [switch]$Server,
  # Edit MissionScripting.lua so the campaign can save. Needs Administrator for Program Files installs.
  [switch]$Desanitize,
  # Override the Saved Games\DCS... folder.
  [string]$SavedGamesDir,
  # Override the DCS install folder (the one containing bin\ and Scripts\).
  [string]$DcsInstallDir,
  [string]$MooseVersion = "latest"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$utf8 = New-Object System.Text.UTF8Encoding $false

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "    $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

function Get-SavedGamesRoot {
  $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
  $raw = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)."{4C5C32FF-BB9D-43b0-B5B4-2D72E54EAAA4}"
  if ($raw) { return [Environment]::ExpandEnvironmentVariables($raw) }
  return Join-Path $env:USERPROFILE "Saved Games"
}

function Find-SavedGamesDir {
  if ($SavedGamesDir) { return $SavedGamesDir }
  $root = Get-SavedGamesRoot
  $names = if ($Server) { @("DCS.dcs_serverrelease", "DCS.server") } else { @("DCS", "DCS.openbeta") }
  foreach ($n in $names) {
    $p = Join-Path $root $n
    if (Test-Path $p) { return $p }
  }
  throw "Could not find $($names -join ' or ') under '$root'. Start DCS once so it creates the folder, or pass -SavedGamesDir."
}

function Find-DcsInstallDir {
  if ($DcsInstallDir) { return $DcsInstallDir }
  $keys = if ($Server) {
    @("HKCU:\Software\Eagle Dynamics\DCS World Server", "HKCU:\Software\Eagle Dynamics\DCS World OpenBeta Server")
  } else {
    @("HKCU:\Software\Eagle Dynamics\DCS World", "HKCU:\Software\Eagle Dynamics\DCS World OpenBeta")
  }
  foreach ($k in $keys) {
    $p = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).Path
    if ($p -and (Test-Path (Join-Path $p "Scripts\MissionScripting.lua"))) { return $p }
  }
  $guesses = @(
    "C:\Program Files\Eagle Dynamics\DCS World",
    "C:\Program Files\Eagle Dynamics\DCS World Server",
    "C:\Program Files (x86)\Steam\steamapps\common\DCSWorld"
  )
  foreach ($p in $guesses) {
    if (Test-Path (Join-Path $p "Scripts\MissionScripting.lua")) { return $p }
  }
  throw "Could not find the DCS install folder. Pass -DcsInstallDir 'D:\path\to\DCS World'."
}

$saved = Find-SavedGamesDir
Step "Saved Games folder: $saved"

$missionDir = Join-Path $saved "Missions\Rotorheads"
$hooksDir = Join-Path $saved "Scripts\Hooks"
New-Item -ItemType Directory -Force -Path $missionDir, $hooksDir | Out-Null

Step "Copying rotorheads.lua"
Copy-Item -Force (Join-Path $repo "mission\dist\rotorheads.lua") (Join-Path $missionDir "rotorheads.lua")
Ok (Join-Path $missionDir "rotorheads.lua")

Step "Copying server hook"
Copy-Item -Force (Join-Path $repo "server\Hooks\rh_hooks.lua") (Join-Path $hooksDir "rh_hooks.lua")
Copy-Item -Force (Join-Path $repo "mission\src\rh\miz.lua") (Join-Path $hooksDir "rh_miz.lua")
Copy-Item -Force (Join-Path $repo "mission\src\rh\inflate.lua") (Join-Path $hooksDir "inflate.lua")
Ok (Join-Path $hooksDir "rh_hooks.lua")
Ok (Join-Path $hooksDir "rh_miz.lua")
Ok (Join-Path $hooksDir "inflate.lua")

Step "Downloading MOOSE ($MooseVersion)"
$moose = Join-Path $missionDir "Moose_.lua"
$url = if ($MooseVersion -eq "latest") {
  "https://github.com/FlightControl-Master/MOOSE/releases/latest/download/Moose_.lua"
} else {
  "https://github.com/FlightControl-Master/MOOSE/releases/download/$MooseVersion/Moose_.lua"
}
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $moose
  Ok "$moose ($([math]::Round((Get-Item $moose).Length / 1MB, 1)) MB)"
} catch {
  if (Test-Path $moose) {
    Warn "Download failed, keeping the existing Moose_.lua. ($($_.Exception.Message))"
  } else {
    Warn "Download failed: $($_.Exception.Message)"
    Warn "Download Moose_.lua by hand from https://github.com/FlightControl-Master/MOOSE/releases and put it in $missionDir"
  }
}

$dcs = $null
try { $dcs = Find-DcsInstallDir } catch { Warn $_.Exception.Message }
$ms = if ($dcs) { Join-Path $dcs "Scripts\MissionScripting.lua" } else { $null }

if ($ms) {
  Step "MissionScripting.lua: $ms"
  $text = [IO.File]::ReadAllText($ms)
  # Single quotes: the replacement must stay literal. In double quotes PowerShell treats $1 as a variable.
  $pattern = '(?m)^(\s*)(sanitizeModule\(''(os|io|lfs)''\))'
  if ($Desanitize) {
    if ($text -match $pattern) {
      $backup = "$ms.rh-backup"
      try {
        if (-not (Test-Path $backup)) { Copy-Item $ms $backup }
        $edited = [regex]::Replace($text, $pattern, '$1--$2')
        # A safety check: the edit must change exactly the three expected lines and nothing else.
        $diff = Compare-Object ($text -split "`n") ($edited -split "`n")
        if (($diff | Where-Object { $_.SideIndicator -eq '=>' }).Count -ne 3) {
          Warn "MissionScripting.lua does not look like the standard DCS file, so it was left untouched."
          Warn "Back up $ms, then comment out the three lines sanitizeModule('os'), sanitizeModule('io') and sanitizeModule('lfs') by hand."
        } else {
          [IO.File]::WriteAllText($ms, $edited, $utf8)
          Ok "Commented out sanitizeModule for os, io and lfs (backup: $backup)"
        }
      } catch {
        Warn "Could not edit it: $($_.Exception.Message)"
        Warn "Re-run this script from an Administrator PowerShell."
      }
    } else {
      Ok "Already desanitized"
    }
  } elseif ($text -match $pattern) {
    Warn "Still sanitized: the campaign will run but NOT save. Re-run with -Desanitize (as Administrator)."
  } else {
    Ok "Already desanitized"
  }
}

Write-Host ""
Write-Host "Done. In the Mission Editor use these two DO SCRIPT actions (see docs\LOCAL_TESTING.md):" -ForegroundColor Cyan
Write-Host '  dofile(lfs.writedir() .. [[Missions\Rotorheads\Moose_.lua]])'
Write-Host '  dofile(lfs.writedir() .. [[Missions\Rotorheads\rotorheads.lua]])'
Write-Host "Campaign saves go to: $(Join-Path $saved 'rotorheads')"
