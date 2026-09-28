# One-click setup for Windows. Every step explains what it will change and asks first;
# steps that are already done are skipped, so it is safe to run again.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $Root

$DataZipName = 'yomitan_ultimate_audio_source.zip'
$DataDownloadPage = 'https://animecards.site/discord/'
$NodeDownloadPage = 'https://nodejs.org'
$MinNodeMajor = 20
# Unpacked audio (about 6 GB) plus the database (about 300 MB), with some headroom.
$RequiredFreeBytes = 7GB

function Write-Step([string]$text) {
    Write-Host ''
    Write-Host "==> $text" -ForegroundColor Cyan
}

function Write-Done([string]$text) {
    Write-Host $text -ForegroundColor DarkGray
}

function Stop-Setup([string]$text) {
    Write-Host ''
    Write-Host $text -ForegroundColor Yellow
    exit 1
}

function Get-NodeMajorVersion {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        return 0
    }
    return [int]((& node --version).TrimStart('v').Split('.')[0])
}

# True when the native SQLite module loads and tsx is installed.
function Test-Dependencies {
    # Windows PowerShell turns redirected stderr from native commands into errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    & node -e "require('better-sqlite3'); require.resolve('tsx')" 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

function Get-AudioFolders([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $path -Directory -Filter '*_files')
}

# One picker for both cases: the downloaded zip, or entry_and_pitch_db.sql inside an unzipped folder.
function Select-AudioData {
    Add-Type -AssemblyName System.Windows.Forms
    # An invisible topmost owner keeps the dialog from opening behind the console window.
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select $DataZipName, or entry_and_pitch_db.sql in the folder you unzipped it to"
    $dialog.Filter = "Audio data ($DataZipName, entry_and_pitch_db.sql)|*.zip;entry_and_pitch_db.sql"
    try {
        if ($dialog.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
        return $null
    } finally {
        $dialog.Dispose()
        $owner.Dispose()
    }
}

function Test-DataFolder([string]$path) {
    return (Test-Path -LiteralPath (Join-Path $path 'entry_and_pitch_db.sql')) -and (Get-AudioFolders $path).Count -gt 0
}

function Wait-AnyKey([string]$prompt) {
    Write-Host $prompt -NoNewline
    if ([Console]::IsInputRedirected) {
        [void][Console]::ReadLine()
    } else {
        [void][Console]::ReadKey($true)
    }
    Write-Host ''
}

# Sets KEY=value in .env, replacing the existing line or adding one.
function Set-DotEnvValue([string]$key, [string]$value) {
    $envPath = Join-Path $Root '.env'
    $lines = [System.Collections.Generic.List[string]]([IO.File]::ReadAllLines($envPath))
    $index = $lines.FindIndex({ param($line) $line.TrimStart().StartsWith("$key=") })
    if ($index -ge 0) {
        $lines[$index] = "$key=$value"
    } else {
        $lines.Add("$key=$value")
    }
    [IO.File]::WriteAllLines($envPath, $lines)
}

# Reads only the zip's file list. Returns how many entries it has, or 0 if it is not the audio data.
function Get-DataZipEntryCount([string]$path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($path)
    } catch {
        return 0
    }
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -eq 'entry_and_pitch_db.sql') {
                return $archive.Entries.Count
            }
        }
        return 0
    } finally {
        $archive.Dispose()
    }
}

# Unpacks with Windows' tar, counting the file names it prints to show progress.
function Expand-DataZip([string]$zip, [string]$destination, [int]$entryCount) {
    # Windows PowerShell turns redirected stderr from native commands into errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    $script:unpacked = 0
    & (Join-Path $env:SystemRoot 'System32\tar.exe') -xvf $zip -C $destination 2>&1 | & {
        process {
            $script:unpacked++
            if ($script:unpacked % 1000 -eq 0) {
                [Console]::Write(("`r  {0:N0} of {1:N0} files ({2}%)   " -f $script:unpacked, $entryCount, [int](100 * $script:unpacked / $entryCount)))
            }
        }
    }
    $exitCode = $LASTEXITCODE
    [Console]::WriteLine(("`r  {0:N0} of {1:N0} files          " -f $script:unpacked, $entryCount))
    return $exitCode -eq 0
}

function Get-FreeBytes([string]$path) {
    $drive = New-Object System.IO.DriveInfo ([IO.Path]::GetPathRoot($path))
    return $drive.AvailableFreeSpace
}

Write-Host "$AppName setup" -ForegroundColor Cyan
Write-Host @"

This sets up a local audio source for Yomitan in:
  $Root
"@

if (Test-TrayRunning) {
    Write-Step 'Stopping the running server'
    Write-Host 'The audio server is running from this folder and has to be stopped during setup.'
    if (-not (Confirm-Choice 'Stop it now?')) {
        Stop-Setup 'Setup stopped. Quit the server from its tray icon, then run setup again.'
    }
    if (-not (Stop-Tray)) {
        Stop-Setup 'The server did not stop. Quit it from its tray icon, then run setup again.'
    }
    Write-Host 'Stopped.'
}

Write-Step "1. Node.js ($MinNodeMajor or newer)"
$nodeMajor = Get-NodeMajorVersion
if ($nodeMajor -ge $MinNodeMajor) {
    Write-Done "Found Node.js $(& node --version)."
} else {
    if ($nodeMajor -eq 0) {
        Write-Host 'The server runs on Node.js, which was not found on this computer.'
    } else {
        Write-Host "The server needs Node.js $MinNodeMajor or newer, but this computer has $(& node --version)."
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Stop-Setup "Install the LTS version from $NodeDownloadPage, then run setup again."
    }
    Write-Host @"
Setup can install the current Node.js LTS with winget (Windows' package manager).
It is installed for all users and Windows may ask for administrator permission.
Uninstalling this audio server later does not remove Node.js.
"@
    if (-not (Confirm-Choice 'Install Node.js LTS now?')) {
        Stop-Setup "Setup stopped. Install the LTS version from $NodeDownloadPage yourself, then run setup again."
    }
    & winget install --id OpenJS.NodeJS.LTS --exact --source winget --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if ((Get-NodeMajorVersion) -lt $MinNodeMajor) {
        Stop-Setup 'Node.js was installed but this window cannot see it yet. Close this window and run setup again.'
    }
    Write-Host "Installed Node.js $(& node --version)."
}

Write-Step '2. Node dependencies'
if (Test-Dependencies) {
    Write-Done 'Already installed.'
} else {
    if (-not (Confirm-Choice 'Install Node dependencies (npm ci, about 60 MB)?')) {
        Stop-Setup 'Setup stopped. The server cannot run without its dependencies.'
    }
    & npm.cmd ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
        Stop-Setup 'Installing the dependencies failed. See the messages above.'
    }
    if (-not (Test-Dependencies)) {
        Stop-Setup 'The SQLite module (better-sqlite3) did not install correctly. See the messages above.'
    }
}

Write-Step '3. Settings'
$envPath = Join-Path $Root '.env'
if (Test-Path -LiteralPath $envPath) {
    Write-Done 'Keeping your existing .env file.'
} else {
    # The server only listens on this computer, so an API key adds nothing.
    $settings = [IO.File]::ReadAllText((Join-Path $Root '.env.example'))
    $settings = $settings -replace '(?m)^AUTHENTICATION_ENABLED=[^\r\n]*', 'AUTHENTICATION_ENABLED=false'
    $settings = $settings -replace '(?m)^API_KEYS=[^\r\n]*', 'API_KEYS='
    [IO.File]::WriteAllText($envPath, $settings)
    Write-Host @"
Created $envPath with these defaults:
  - only reachable from this computer (127.0.0.1, port 8787)
  - no API key, since nothing outside this computer can reach it
  - text-to-speech off (it needs an AWS account)
You can edit it any time, then restart the server from the tray icon.
"@
}

$envValues = Read-DotEnv
$dataPath = Resolve-ProjectPath $envValues['AUDIO_DATA_PATH'] 'data'

Write-Step '4. Audio data'
if ((Get-AudioFolders $dataPath).Count -gt 0) {
    Write-Done ('Found: ' + (((Get-AudioFolders $dataPath).Name -replace '_files$', '') -join ', '))
} else {
    Write-Host @"
Needs the audio data download (about 5 GB), from the Animecards Discord:
  $DataDownloadPage

Select one of:
  $DataZipName  -> setup unzips it for you (needs 7 GB free, a few minutes)
  entry_and_pitch_db.sql             -> if you already unzipped it yourself (nothing is copied)

"@
    Wait-AnyKey 'Press any key to open the file picker...'
    $selected = Select-AudioData
    if (-not $selected) {
        Stop-Setup 'Nothing selected. Run setup again when you are ready.'
    }
    if ([IO.Path]::GetExtension($selected) -ne '.zip') {
        $folder = Split-Path -Parent $selected
        if (-not (Test-DataFolder $folder)) {
            Stop-Setup "$folder does not contain the audio folders (*_files) next to entry_and_pitch_db.sql."
        }
        # Only the audio location changes; the database is still built in this folder's data directory.
        Set-DotEnvValue 'AUDIO_DATA_PATH' $folder
        Set-DotEnvValue 'SQL_PATH' $selected
        $dataPath = $folder
        Write-Host "Using: $folder (saved in .env)"
    } else {
        $freeBytes = Get-FreeBytes $dataPath
        if ($freeBytes -lt $RequiredFreeBytes) {
            Stop-Setup ("Not enough free space on that drive ({0:N1} GB free, about 7 GB needed)." -f ($freeBytes / 1GB))
        }
        Write-Host 'Checking the zip...'
        $entryCount = Get-DataZipEntryCount $selected
        if ($entryCount -eq 0) {
            Stop-Setup "$selected does not look like the audio data (entry_and_pitch_db.sql is missing). Select $DataZipName."
        }
        Write-Host "Unpacking $selected ..."
        New-Item -ItemType Directory -Force -Path $dataPath | Out-Null
        if (-not (Expand-DataZip $selected $dataPath $entryCount)) {
            Stop-Setup 'Unpacking the audio data failed. Try unzipping it yourself and selecting entry_and_pitch_db.sql instead.'
        }
        Write-Host "Done. You can delete $selected now if you want the space back."
    }
}

$envValues = Read-DotEnv
$dbPath = Resolve-ProjectPath $envValues['DB_PATH'] (Join-Path $dataPath 'yomitan-audio.db')
$sqlPath = Resolve-ProjectPath $envValues['SQL_PATH'] (Join-Path $dataPath 'entry_and_pitch_db.sql')

Write-Step '5. Word database'
if (Test-Path -LiteralPath $dbPath) {
    Write-Done 'Already built.'
} else {
    if (-not (Test-Path -LiteralPath $sqlPath)) {
        Stop-Setup "Missing $sqlPath. It comes with the audio data zip."
    }
    Write-Host "Building the word and pitch-accent database (about 300 MB, usually under a minute) at:"
    Write-Host "  $dbPath"
    & npm.cmd run db:init
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $dbPath -ErrorAction SilentlyContinue
        Stop-Setup 'Building the database failed. See the messages above.'
    }
}

Write-Step '6. Shortcuts (optional)'
if (Test-TrayShortcut $StartMenuShortcut) {
    Write-Done 'Start menu entry already added.'
} elseif (Confirm-Choice "Add '$AppName' to the Start menu, so you can start the server later?") {
    New-TrayShortcut $StartMenuShortcut
    Write-Host 'Added.'
}
if (Test-Autostart) {
    Write-Done 'Already starts when you log in (change this from the tray icon).'
} elseif (Confirm-Choice 'Start the server automatically when you log in? (You can change this from the tray icon.)' -DefaultNo) {
    Enable-Autostart
    Write-Host 'Added.'
}

$yomitanUrl = (Get-ServerConfig).YomitanUrl
Write-Step '7. Start'
Write-Host 'The server runs in the background, with an icon in the system tray to stop it.'
if (Confirm-Choice 'Start it now?') {
    Start-Tray
    Set-Clipboard -Value $yomitanUrl
    Write-Host ''
    Write-Host 'All set! The tray icon turns green when the server is ready.' -ForegroundColor Green
    Write-Host 'The Yomitan URL below has been copied to your clipboard.'
} else {
    Write-Host ''
    Write-Host 'All set! Start it later from the Start menu entry.' -ForegroundColor Green
}
Write-Host ''
Write-Host 'In Yomitan, open Settings > Audio > Configure audio playback sources,'
Write-Host 'add a "Custom URL (JSON)" source and paste this URL:'
Write-Host ''
Write-Host "  $yomitanUrl"
Write-Host ''
Write-Host 'To remove the shortcuts and stop the server later, run windows-uninstall.cmd.'
