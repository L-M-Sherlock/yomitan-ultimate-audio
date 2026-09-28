# System tray app for the local Yomitan audio server (Windows).
# Runs the server hidden in the background, shows whether it is up and stops it on quit.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $TrayMutexName, [ref]$createdNew)
if (-not $createdNew) {
    [void][System.Windows.Forms.MessageBox]::Show("$AppName is already running. Look for its icon in the system tray.", $AppName)
    exit
}
# Setup and uninstall set this event to ask the tray to stop the server and quit.
$quitEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $TrayQuitEventName)

Set-Location $Root
$LogPath = Join-Path $Root 'server.log'
$script:server = $null
$script:state = ''
$script:config = Get-ServerConfig

# A coloured circle with the kanji for "sound" (U+97F3); the colour shows the server state.
function New-StateIcon([System.Drawing.Color]$color) {
    $bitmap = New-Object System.Drawing.Bitmap 32, 32
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $brush = New-Object System.Drawing.SolidBrush $color
    $graphics.FillEllipse($brush, 0, 0, 31, 31)
    $font = New-Object System.Drawing.Font('Yu Gothic UI', 19, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $graphics.DrawString([string][char]0x97F3, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 0, 1, 32, 32), $format)
    $graphics.Dispose()
    $brush.Dispose()
    $font.Dispose()
    return [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
}

$icons = @{
    starting = New-StateIcon ([System.Drawing.Color]::FromArgb(214, 143, 0))
    running  = New-StateIcon ([System.Drawing.Color]::FromArgb(22, 128, 61))
    stopped  = New-StateIcon ([System.Drawing.Color]::FromArgb(110, 110, 110))
    error    = New-StateIcon ([System.Drawing.Color]::FromArgb(200, 40, 40))
}

function Show-Balloon([string]$text, [System.Windows.Forms.ToolTipIcon]$kind = [System.Windows.Forms.ToolTipIcon]::Info) {
    $tray.ShowBalloonTip(5000, $AppName, $text, $kind)
}

function Set-State([string]$state) {
    $script:state = $state
    switch ($state) {
        'starting' { $text = 'Starting...' }
        'running' { $text = "Running on port $($script:config.Port)" }
        'stopped' { $text = 'Stopped' }
        'error' { $text = 'Not running (error)' }
    }
    $tray.Icon = $icons[$state]
    $tray.Text = "$AppName - $text"
    $statusItem.Text = $text
    $startItem.Enabled = $state -eq 'stopped' -or $state -eq 'error'
    $stopItem.Enabled = $state -eq 'starting' -or $state -eq 'running'
}

function Test-PortOpen {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect($script:config.Host, $script:config.Port)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

# If a previous tray was killed, its server may still hold the port; take it back.
function Stop-LeftoverServer {
    $listeners = Get-NetTCPConnection -LocalPort $script:config.Port -State Listen -ErrorAction SilentlyContinue
    foreach ($ownerId in @($listeners | ForEach-Object { $_.OwningProcess } | Select-Object -Unique)) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ownerId"
        if ($process -and $process.Name -eq 'node.exe' -and $process.CommandLine -like "*$ServerArguments*") {
            Stop-Process -Id $ownerId -Force
            Start-Sleep -Milliseconds 500
        }
    }
}

function Get-LogError {
    $line = Get-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction SilentlyContinue |
        Where-Object { $_ -match 'Error' } |
        Select-Object -First 1
    if ($line) {
        $line = $line.Trim()
        if ($line.Length -gt 180) {
            $line = $line.Substring(0, 180) + '...'
        }
    }
    return $line
}

function Start-Server {
    $script:config = Get-ServerConfig
    Stop-LeftoverServer

    if (Test-PortOpen) {
        Set-State 'error'
        Show-Balloon "Port $($script:config.Port) is already used by another program. Change PORT in .env and start again." Error
        return
    }

    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Set-State 'error'
        Show-Balloon 'Node.js was not found. Run windows-install.cmd again.' Error
        return
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = "/d /c `"`"$($node.Source)`" $ServerArguments > `"$LogPath`" 2>&1`""
    $startInfo.WorkingDirectory = $Root
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $script:server = [System.Diagnostics.Process]::Start($startInfo)
    Set-State 'starting'
}

function Stop-Server {
    if ($script:server -and -not $script:server.HasExited) {
        & taskkill.exe /PID $script:server.Id /T /F | Out-Null
        [void]$script:server.WaitForExit(5000)
    }
    $script:server = $null
}

function Add-MenuItem([string]$text, [scriptblock]$onClick) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem $text
    if ($onClick) {
        $item.add_Click($onClick)
    }
    [void]$menu.Items.Add($item)
    return $item
}

function Add-Separator {
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
}

function Copy-YomitanUrl {
    [System.Windows.Forms.Clipboard]::SetText($script:config.YomitanUrl)
    Show-Balloon "Yomitan URL copied. Paste it into Yomitan > Settings > Audio as a 'Custom URL (JSON)' source."
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$statusItem = Add-MenuItem 'Starting...'
$statusItem.Enabled = $false
Add-Separator
[void](Add-MenuItem 'Copy Yomitan URL' { Copy-YomitanUrl })
[void](Add-MenuItem 'Test lookup in browser' {
    # term=nihon (kanji), reading=nihon (hiragana)
    Start-Process "$($script:config.BaseUrl)/audio/list?term=%E6%97%A5%E6%9C%AC&reading=%E3%81%AB%E3%81%BB%E3%82%93"
})
Add-Separator
$startItem = Add-MenuItem 'Start server' { Start-Server }
$stopItem = Add-MenuItem 'Stop server' {
    Stop-Server
    Set-State 'stopped'
}
Add-Separator
$autostartItem = Add-MenuItem 'Start with Windows' {
    if (Test-Autostart) {
        Disable-Autostart
    } else {
        Enable-Autostart
    }
    $autostartItem.Checked = Test-Autostart
}
# Re-read when the menu opens, in case it was changed in Windows' Startup apps settings.
$menu.add_Opening({ $autostartItem.Checked = Test-Autostart })
[void](Add-MenuItem 'Open log' { Start-Process notepad.exe -ArgumentList "`"$LogPath`"" })
[void](Add-MenuItem 'Open folder' { Start-Process explorer.exe -ArgumentList "`"$Root`"" })
Add-Separator
function Exit-Tray {
    Stop-Server
    $tray.Visible = $false
    [System.Windows.Forms.Application]::Exit()
}

[void](Add-MenuItem 'Quit' { Exit-Tray })

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.ContextMenuStrip = $menu

# Poll the server: exited means it crashed, an open port means it is ready.
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.add_Tick({
    if ($quitEvent.WaitOne(0)) {
        Exit-Tray
        return
    }
    if (-not $script:server) {
        return
    }
    if ($script:server.HasExited) {
        $script:server = $null
        Set-State 'error'
        $detail = Get-LogError
        if (-not $detail) {
            $detail = 'See the log for details.'
        }
        Show-Balloon "The server stopped. $detail" Error
        return
    }
    if ($script:state -eq 'starting' -and (Test-PortOpen)) {
        Set-State 'running'
    }
})

Set-State 'starting'
$tray.Visible = $true
Start-Server
$timer.Start()

try {
    [System.Windows.Forms.Application]::Run()
} finally {
    $timer.Stop()
    Stop-Server
    $tray.Dispose()
    $quitEvent.Dispose()
    $mutex.ReleaseMutex()
}
