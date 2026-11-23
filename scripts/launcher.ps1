# Daytona USA (recompiled) - settings launcher.
#
# A small window for the daytona.ini options people actually change: render
# resolution, window size, fullscreen, vsync and monitor. "Play" saves them and
# starts the game; "Save" only saves. Everything else in daytona.ini is left
# exactly as it was, comments included.
#
# Works from the repo (finds out\build\win-amd64-release\daytona.exe and the
# extracted\ game data) or copied next to daytona.exe in a packaged build
# (where the game finds assets\ on its own). Run it through launcher.bat.
#
# There is deliberately no refresh-rate option: the game paces its own logic
# off a fixed 60Hz tick, so the ini's refresh_rate is ignored (changing it
# would change game speed). With vsync on, frames follow the display.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System.Runtime.InteropServices;
public static class DtDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
'@
# Real pixels, not Windows' scaled ones, so the sizes listed are the sizes
# you get.
[DtDpi]::SetProcessDPIAware() | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Where things are -------------------------------------------------------
$here = $PSScriptRoot
$repo = Split-Path $here -Parent
$exe = $null
foreach ($cand in @((Join-Path $here 'daytona.exe'),
                    (Join-Path $repo 'daytona.exe'),
                    (Join-Path $repo 'out\build\win-amd64-release\daytona.exe'))) {
    if (Test-Path -LiteralPath $cand) { $exe = (Resolve-Path -LiteralPath $cand).Path; break }
}
if (-not $exe) {
    [System.Windows.Forms.MessageBox]::Show("daytona.exe was not found. Build the game first, or put this launcher next to daytona.exe.",
        'Daytona USA', 'OK', 'Error') | Out-Null
    exit 1
}
$exeDir = Split-Path $exe -Parent
$iniPath = Join-Path $exeDir 'daytona.ini'

# The game looks for assets\ beside the exe by itself; a raw build-output exe
# has none, so point it at the repo's extracted\ data instead.
$gameArgs = @()
if (-not (Test-Path -LiteralPath (Join-Path $exeDir 'assets'))) {
    $extracted = Join-Path $repo 'extracted'
    if (Test-Path -LiteralPath $extracted) { $gameArgs += "--game_data_root=`"$extracted`"" }
}

if (-not (Test-Path -LiteralPath $iniPath)) {
    $template = Join-Path $repo 'daytona.ini'
    if (Test-Path -LiteralPath $template) {
        Copy-Item -LiteralPath $template -Destination $iniPath
    } else {
        [IO.File]::WriteAllLines($iniPath, [string[]]@('[Display]', '[Graphics]'))
    }
}

# --- Ini read / write (line-preserving) -------------------------------------
$script:lines = [System.Collections.Generic.List[string]]::new()
$script:lines.AddRange([string[]][IO.File]::ReadAllLines($iniPath))

function Get-Ini([string]$section, [string]$key, [string]$default) {
    $cur = ''
    foreach ($l in $script:lines) {
        $t = $l.Trim()
        if ($t -match '^\[(.+)\]$') { $cur = $Matches[1]; continue }
        if ($cur -ieq $section -and $t -match "^$([regex]::Escape($key))\s*=\s*(.*)$") { return $Matches[1].Trim() }
    }
    return $default
}

function Set-Ini([string]$section, [string]$key, [string]$value) {
    $cur = ''; $headerAt = -1
    for ($i = 0; $i -lt $script:lines.Count; $i++) {
        $t = $script:lines[$i].Trim()
        if ($t -match '^\[(.+)\]$') { $cur = $Matches[1]; if ($cur -ieq $section) { $headerAt = $i }; continue }
        if ($cur -ieq $section -and $t -match "^$([regex]::Escape($key))\s*=") {
            $script:lines[$i] = "$key = $value"; return
        }
    }
    if ($headerAt -lt 0) {
        $script:lines.Add(''); $script:lines.Add("[$section]"); $headerAt = $script:lines.Count - 1
    }
    $script:lines.Insert($headerAt + 1, "$key = $value")
}

# --- Choices ----------------------------------------------------------------
$dpiScale = 1.0
$g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
try { $dpiScale = $g.DpiX / 96.0 } finally { $g.Dispose() }

$screens = [System.Windows.Forms.Screen]::AllScreens
$primary = [System.Windows.Forms.Screen]::PrimaryScreen

# Render resolution = internal_resolution_scale x 1280x720.
$renderChoices = @(
    @{ Text = '1280 x 720   (original)'; Scale = 1.0 },
    @{ Text = '1600 x 900';              Scale = 1.25 },
    @{ Text = '1920 x 1080  (1080p)';    Scale = 1.5 },
    @{ Text = '2560 x 1440  (1440p)';    Scale = 2.0 },
    @{ Text = '3200 x 1800';             Scale = 2.5 },
    @{ Text = '3840 x 2160  (4K)';       Scale = 3.0 },
    @{ Text = '5120 x 2880  (5K)';       Scale = 4.0 }
)

# Window sizes in REAL pixels. daytona.ini stores them in Windows' scaled
# units, so they are converted on save -- the source of the "zoomed in,
# edges cut off" window on a display set to 150%.
$windowChoices = @()
foreach ($wh in @(@(1280, 720), @(1600, 900), @(1920, 1080), @(2560, 1440), @(3200, 1800), @(3840, 2160))) {
    if ($wh[0] -le $primary.Bounds.Width -and $wh[1] -le $primary.Bounds.Height) {
        $windowChoices += @{ Text = "$($wh[0]) x $($wh[1])"; W = $wh[0]; H = $wh[1] }
    }
}
if ($windowChoices.Count -eq 0) { $windowChoices += @{ Text = '1280 x 720'; W = 1280; H = 720 } }

# --- Form -------------------------------------------------------------------
$font = New-Object System.Drawing.Font('Segoe UI', 10)
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Daytona USA - Settings'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.AutoSize = $true
$form.AutoSizeMode = 'GrowAndShrink'
$form.Font = $font
$form.Padding = New-Object System.Windows.Forms.Padding(14)

$grid = New-Object System.Windows.Forms.TableLayoutPanel
$grid.ColumnCount = 2
$grid.AutoSize = $true
$grid.AutoSizeMode = 'GrowAndShrink'
$grid.Dock = 'Fill'
$form.Controls.Add($grid)

function Add-Row([string]$label, $control) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $label
    $l.AutoSize = $true
    $l.Anchor = 'Left'
    $l.Margin = New-Object System.Windows.Forms.Padding(3, 8, 12, 8)
    $control.Margin = New-Object System.Windows.Forms.Padding(3, 5, 3, 5)
    $grid.Controls.Add($l)
    $grid.Controls.Add($control)
}

function New-Combo($items) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'
    $c.Width = 260
    foreach ($i in $items) { [void]$c.Items.Add($i.Text) }
    return $c
}

# Render resolution: pick the preset nearest the ini's scale.
$renderBox = New-Combo $renderChoices
$curScale = 1.0
[double]::TryParse((Get-Ini 'Graphics' 'internal_resolution_scale' '1'),
    [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$curScale) | Out-Null
$best = 0
for ($i = 0; $i -lt $renderChoices.Count; $i++) {
    if ([math]::Abs($renderChoices[$i].Scale - $curScale) -lt [math]::Abs($renderChoices[$best].Scale - $curScale)) { $best = $i }
}
$renderBox.SelectedIndex = $best
Add-Row 'Render resolution' $renderBox

# Window size: nearest preset to the ini's value converted to real pixels.
$windowBox = New-Combo $windowChoices
$curW = 1920
if ((Get-Ini 'Display' 'resolution' '1920x1080') -match '^(\d+)\s*[xX]\s*(\d+)$') { $curW = [int]([int]$Matches[1] * $dpiScale) }
$best = 0
for ($i = 0; $i -lt $windowChoices.Count; $i++) {
    if ([math]::Abs($windowChoices[$i].W - $curW) -lt [math]::Abs($windowChoices[$best].W - $curW)) { $best = $i }
}
$windowBox.SelectedIndex = $best
Add-Row 'Window size' $windowBox

$monitorItems = @(@{ Text = 'Default' })
for ($i = 0; $i -lt $screens.Count; $i++) {
    $s = $screens[$i]
    $tag = if ($s.Primary) { ' (main)' } else { '' }
    $monitorItems += @{ Text = "Display $($i + 1): $($s.Bounds.Width) x $($s.Bounds.Height)$tag" }
}
$monitorBox = New-Combo $monitorItems
$curMon = 0
[int]::TryParse((Get-Ini 'Display' 'monitor' '0'), [ref]$curMon) | Out-Null
$monitorBox.SelectedIndex = [math]::Min([math]::Max($curMon, 0), $monitorItems.Count - 1)
Add-Row 'Monitor' $monitorBox

$fullscreen = New-Object System.Windows.Forms.CheckBox
$fullscreen.Text = 'Fullscreen (F11 switches in game)'
$fullscreen.AutoSize = $true
$fullscreen.Checked = (Get-Ini 'Display' 'fullscreen' 'false') -match '^(true|yes|on|1)$'
Add-Row '' $fullscreen

$vsync = New-Object System.Windows.Forms.CheckBox
$vsync.Text = 'VSync (no tearing)'
$vsync.AutoSize = $true
$vsync.Checked = (Get-Ini 'Display' 'vsync' 'true') -match '^(true|yes|on|1)$'
Add-Row '' $vsync

$note = New-Object System.Windows.Forms.Label
$note.Text = 'The game always runs at 60 fps; it has no refresh-rate setting.'
$note.AutoSize = $true
$note.ForeColor = [System.Drawing.SystemColors]::GrayText
$note.Margin = New-Object System.Windows.Forms.Padding(3, 10, 3, 4)
$grid.Controls.Add($note)
$grid.SetColumnSpan($note, 2)

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.FlowDirection = 'RightToLeft'
$buttons.AutoSize = $true
$buttons.Dock = 'Fill'
$buttons.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
$grid.Controls.Add($buttons)
$grid.SetColumnSpan($buttons, 2)

function New-Button([string]$text) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.AutoSize = $true
    $b.Padding = New-Object System.Windows.Forms.Padding(10, 2, 10, 2)
    $buttons.Controls.Add($b)
    return $b
}
$play = New-Button 'Play'
$save = New-Button 'Save'
$cancel = New-Button 'Cancel'
$form.AcceptButton = $play
$form.CancelButton = $cancel

function Save-Settings {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $r = $renderChoices[$renderBox.SelectedIndex]
    Set-Ini 'Graphics' 'internal_resolution_scale' $r.Scale.ToString($inv)
    $w = $windowChoices[$windowBox.SelectedIndex]
    $lw = [int][math]::Round($w.W / $dpiScale)
    $lh = [int][math]::Round($w.H / $dpiScale)
    Set-Ini 'Display' 'resolution' "${lw}x${lh}"
    Set-Ini 'Display' 'monitor' ([string]$monitorBox.SelectedIndex)
    Set-Ini 'Display' 'fullscreen' $(if ($fullscreen.Checked) { 'true' } else { 'false' })
    Set-Ini 'Display' 'vsync' $(if ($vsync.Checked) { 'true' } else { 'false' })
    [IO.File]::WriteAllLines($iniPath, $script:lines, (New-Object System.Text.UTF8Encoding($false)))
}

$save.Add_Click({ Save-Settings; $form.Close() })
$play.Add_Click({
    Save-Settings
    if ($gameArgs.Count -gt 0) {
        Start-Process -FilePath $exe -ArgumentList $gameArgs -WorkingDirectory $exeDir
    } else {
        Start-Process -FilePath $exe -WorkingDirectory $exeDir
    }
    $form.Close()
})
$cancel.Add_Click({ $form.Close() })

[void]$form.ShowDialog()
