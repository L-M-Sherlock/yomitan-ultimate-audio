# Undoes what setup.ps1 added outside this folder: stops the server and removes the shortcuts.
# Files inside the folder (audio data, database, packages, settings) are left alone.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$trayRunning = Test-TrayRunning
$hasStartMenuEntry = Test-TrayShortcut $StartMenuShortcut
# Counts even when turned off in Windows' Startup apps settings, so the shortcut is still cleaned up.
$hasAutostart = Test-TrayShortcut $StartupShortcut

Write-Host "$AppName uninstall" -ForegroundColor Cyan
Write-Host ''
if (-not ($trayRunning -or $hasStartMenuEntry -or $hasAutostart)) {
    Write-Host 'Nothing to do: the server is not running, and there is no Start menu entry or start with Windows to remove.'
} else {
    Write-Host 'This will:'
    if ($trayRunning) {
        Write-Host '  - stop the running server and close its tray icon'
    }
    if ($hasStartMenuEntry) {
        Write-Host "  - remove the '$AppName' Start menu entry"
    }
    if ($hasAutostart) {
        Write-Host '  - turn off starting with Windows'
    }
    Write-Host ''
    if (-not (Confirm-Choice 'Continue?')) {
        Write-Host 'Nothing was changed.'
        exit 1
    }

    if ($trayRunning) {
        if (Stop-Tray) {
            Write-Host 'Stopped the server.'
        } else {
            Write-Host 'The server did not stop. Quit it from its tray icon.' -ForegroundColor Yellow
        }
    }
    if ($hasStartMenuEntry) {
        Remove-Item -LiteralPath $StartMenuShortcut
        Write-Host 'Removed the Start menu entry.'
    }
    if ($hasAutostart) {
        Disable-Autostart
        Write-Host 'Turned off starting with Windows.'
    }
}

$audioPath = Resolve-ProjectPath (Read-DotEnv)['AUDIO_DATA_PATH'] 'data'
$audioInsideFolder = $audioPath.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
if ($audioInsideFolder) {
    Write-Host @"

To remove everything else, delete this folder, which includes the audio data
(about 6 GB), the database and the downloaded packages:
  $Root
"@
} else {
    Write-Host @"

To remove everything else, delete this folder (the database and the downloaded packages):
  $Root

The audio data (about 6 GB) is in a separate folder you chose during setup.
Delete it too if nothing else uses it:
  $audioPath
"@
}

Write-Host @"

Node.js was not removed. If nothing else uses it, uninstall it from
Settings > Apps > Installed apps.
"@
