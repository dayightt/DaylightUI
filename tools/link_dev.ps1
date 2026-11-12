# Puts this repo into the game. The repo lives OUTSIDE the game folder
# (C:\dev\DaylightUI): Battle.net can't update WoW while a dev tool has files
# open inside it. WoW lists only the folders directly in Interface\AddOns, so
# this makes junctions there (links that look like folders):
#     AddOns\DaylightUI          -> <repo>
#     AddOns\DaylightUI_<Module> -> <repo>\DaylightUI_<Module>   (every module, and _Dev)
# Run once per PC, and again after adding a module, from anywhere:
#
#     powershell -ExecutionPolicy Bypass -File tools\link_dev.ps1
#
# The game folder: -Game, else $env:WOW_FOREVER, else the usual install.
# Safe to run again: a right junction is left alone, a stale one is remade.
# The junctions are outside the repo, so git never sees them.

param([string]$Game = $(if ($env:WOW_FOREVER) { $env:WOW_FOREVER } else { "C:\Program Files (x86)\World of Warcraft\_forever_" }))

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$addons = Join-Path $Game "Interface\AddOns"
if (-not (Test-Path -LiteralPath $addons)) {
    Write-Error "No AddOns folder at $addons. Pass the game folder: -Game 'D:\World of Warcraft\_forever_'"
    exit 1
}

function Link($name, $target) {
    $link = Join-Path $addons $name
    $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.LinkType -ne "Junction") {
            if ($item.FullName.TrimEnd("\") -eq $target.TrimEnd("\")) {
                Write-Output "Skipped: $link is the repo itself (move it out first: DaylightMogul's tools\move_out_of_game.ps1)"
                return
            }
            Write-Error "$link is a real folder, not a junction. Move it away, then run this again."
            exit 1
        }
        if (@($item.Target)[0].TrimEnd("\") -eq $target.TrimEnd("\")) {
            Write-Output "Already linked: $name -> $target"
            return
        }
        cmd /c rmdir "$link" | Out-Null   # removes only the junction, never what it points to
    }
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Write-Output "Linked: $name -> $target"
}

Link "DaylightUI" $repo
Get-ChildItem -LiteralPath $repo -Directory -Filter "DaylightUI_*" | ForEach-Object {
    if (Test-Path -LiteralPath (Join-Path $_.FullName ($_.Name + ".toc"))) { Link $_.Name $_.FullName }
}
Write-Output "In game: /reload."
