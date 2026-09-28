# Helpers shared by setup.ps1, uninstall.ps1 and tray.ps1.

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$AppName = 'Yomitan Audio Server'
$TrayMutexName = 'Local\YomitanAudioServerTray'
$TrayQuitEventName = 'Local\YomitanAudioServerTrayQuit'
# How the tray launches the server; also used to recognise a server it left behind.
$ServerArguments = '--import tsx src/server.ts'
$TrayScript = Join-Path $PSScriptRoot 'tray.ps1'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$StartupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) "$AppName.lnk"
# Where Windows records Startup apps the user turned off in Task Manager or Settings.
$StartupApprovedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
$StartMenuShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) "$AppName.lnk"

# Same rules as loadEnvFile() in src/lib/env.ts.
function Read-DotEnv {
    $values = @{}
    $path = Join-Path $Root '.env'
    if (-not (Test-Path -LiteralPath $path)) {
        return $values
    }

    foreach ($rawLine in Get-Content -LiteralPath $path -Encoding UTF8) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#')) {
            continue
        }

        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) {
            continue
        }

        $value = $line.Substring($separatorIndex + 1).Trim()
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $values[$line.Substring(0, $separatorIndex).Trim()] = $value
    }

    return $values
}

# Resolves a path from .env the way the server does (relative to the project folder).
function Resolve-ProjectPath([string]$value, [string]$fallback) {
    if (-not $value) {
        $value = $fallback
    }
    return [IO.Path]::GetFullPath([IO.Path]::Combine($Root, $value))
}

function Get-ServerConfig {
    $envValues = Read-DotEnv

    $bindHost = '127.0.0.1'
    if ($envValues['HOST']) {
        $bindHost = $envValues['HOST']
    }
    $urlHost = $bindHost
    if ($bindHost -eq '0.0.0.0') {
        $urlHost = '127.0.0.1'
    }

    $port = 8787
    if ($envValues['PORT']) {
        $port = [int]$envValues['PORT']
    }

    # Like the server, authentication is on unless .env turns it off.
    $authenticationEnabled = $true
    if ($envValues.ContainsKey('AUTHENTICATION_ENABLED')) {
        $authenticationEnabled = @('1', 'true', 'yes', 'on') -contains $envValues['AUTHENTICATION_ENABLED'].Trim().ToLower()
    }

    $yomitanUrl = "http://${urlHost}:$port/audio/list?term={term}&reading={reading}"
    if ($authenticationEnabled -and $envValues['API_KEYS']) {
        $yomitanUrl += '&apiKey=' + $envValues['API_KEYS'].Split(',')[0].Trim()
    }

    return [pscustomobject]@{
        Host       = $urlHost
        Port       = $port
        BaseUrl    = "http://${urlHost}:$port"
        YomitanUrl = $yomitanUrl
    }
}

# Yes/no question; Enter picks the default named in the hint.
function Confirm-Choice([string]$question, [switch]$DefaultNo) {
    $hint = '[Y/n] (default: yes)'
    if ($DefaultNo) {
        $hint = '[y/N] (default: no)'
    }
    while ($true) {
        $answer = (Read-Host "$question $hint").Trim().ToLower()
        if (-not $answer) {
            return -not $DefaultNo
        }
        if ($answer -eq 'y' -or $answer -eq 'yes') {
            return $true
        }
        if ($answer -eq 'n' -or $answer -eq 'no') {
            return $false
        }
        Write-Host 'Please answer y or n.'
    }
}

function Test-TrayRunning {
    $existing = $null
    if ([System.Threading.Mutex]::TryOpenExisting($TrayMutexName, [ref]$existing)) {
        $existing.Dispose()
        return $true
    }
    return $false
}

# Asks a running tray to stop its server and quit. Returns $false if it is still running.
function Stop-Tray {
    $quitEvent = $null
    if ([System.Threading.EventWaitHandle]::TryOpenExisting($TrayQuitEventName, [ref]$quitEvent)) {
        [void]$quitEvent.Set()
        $quitEvent.Dispose()
    }
    for ($i = 0; $i -lt 20 -and (Test-TrayRunning); $i++) {
        Start-Sleep -Milliseconds 500
    }
    return -not (Test-TrayRunning)
}

# True when the shortcut exists and opens this copy of the tray app.
function Test-TrayShortcut([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        return $false
    }
    $shell = New-Object -ComObject WScript.Shell
    return $shell.CreateShortcut($path).Arguments -like "*`"$TrayScript`"*"
}

# True when the startup shortcut is in place and not turned off in Windows' Startup apps settings.
function Test-Autostart {
    if (-not (Test-TrayShortcut $StartupShortcut)) {
        return $false
    }
    $flags = (Get-ItemProperty -LiteralPath $StartupApprovedKey -ErrorAction SilentlyContinue).(Split-Path -Leaf $StartupShortcut)
    # No entry means enabled; an odd first byte (e.g. 03) means the user turned it off.
    return -not ($flags -and ($flags[0] -band 1))
}

# Also clears Windows' "turned off" flag, which would otherwise keep a new shortcut from running.
function Enable-Autostart {
    New-TrayShortcut $StartupShortcut
    Remove-ItemProperty -LiteralPath $StartupApprovedKey -Name (Split-Path -Leaf $StartupShortcut) -ErrorAction SilentlyContinue
}

function Disable-Autostart {
    Remove-Item -LiteralPath $StartupShortcut -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $StartupApprovedKey -Name (Split-Path -Leaf $StartupShortcut) -ErrorAction SilentlyContinue
}

function New-TrayShortcut([string]$path) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $PowerShellExe
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrayScript`""
    $shortcut.WorkingDirectory = $Root
    $shortcut.WindowStyle = 7
    $shortcut.IconLocation = (Join-Path $env:SystemRoot 'System32\SndVol.exe') + ',0'
    $shortcut.Description = 'Local audio source for Yomitan'
    $shortcut.Save()
}

function Start-Tray {
    Start-Process -FilePath $PowerShellExe -WorkingDirectory $Root -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$TrayScript`""
    )
}
