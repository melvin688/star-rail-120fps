<#
    fps-cap.ps1 - Unlock / restore the hidden 120 FPS cap for Honkai: Star Rail (PC).

    The in-game menu only offers 30/60 FPS. The 120 FPS option exists but is
    only reachable by editing the game's own graphics-settings value in the
    registry (HKCU). This script edits exactly that value and nothing else:
    no game files, no injection, no anti-cheat interaction.

    Distributed under the MIT License. See the LICENSE file in the repository root.

    Usage:
        fps-cap.ps1 -Mode status     Show the current cap (read-only, default)
        fps-cap.ps1 -Mode unlock     Set the cap to 120
        fps-cap.ps1 -Mode unlock -TargetFps 60    Use a specific tier
        fps-cap.ps1 -Mode unlock -Auto            Pick the tier from the display
        fps-cap.ps1 -Mode restore    Set the cap back to 60 (official default)

    Frame-rate tiers:
        The game accepts exactly 30, 60 and 120. Values above 120 are ignored by
        the client (community-tested; v1.5+ clamps to the three tiers), so this
        script never writes anything outside that set. -Auto maps the primary
        display's refresh rate onto the nearest tier that does not exceed it:
        120+ Hz -> 120, 60-119 Hz -> 60, below 60 Hz -> 30.

    Notes:
        * Close the game before unlock/restore - the game rewrites this value
          on exit and would overwrite the change.
        * Changing any graphics option in-game resets the cap to 60;
          just run unlock again.
        * A backup of the original value is written once to
          %LOCALAPPDATA%\star-rail-120fps\backup.b64

    Tested with Windows PowerShell 5.1 (preinstalled on Windows 10/11).
#>
[CmdletBinding()]
param(
    [ValidateSet('status', 'unlock', 'restore')]
    [string]$Mode = 'status',

    # Target tier for -Mode unlock. The game only honours 30/60/120.
    [int]$TargetFps = 120,

    # Derive the tier from the primary display's refresh rate instead.
    [switch]$Auto,

    # For self-tests only: override the registry key path
    # (e.g. 'Software\Cognosphere\Star Rail-SELFTEST').
    [string]$KeyPath
)

$ErrorActionPreference = 'Stop'

$SupportedTiers = @(30, 60, 120)

# --- primary display refresh rate (WMI mixes up iGPU/dGPU values) ---------
if (-not ('CapHz' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class CapHz {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet=CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
    static DEVMODE Blank() {
        DEVMODE d = new DEVMODE();
        d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        return d;
    }
    public static int Current() {
        DEVMODE d = Blank();
        if (EnumDisplaySettings(null, -1, ref d)) return d.dmDisplayFrequency;
        return 0;
    }
    public static int Max() {
        DEVMODE cur = Blank();
        if (!EnumDisplaySettings(null, -1, ref cur)) return 0;
        int best = cur.dmDisplayFrequency;
        for (int i = 0; i < 500; i++) {
            DEVMODE d = Blank();
            if (!EnumDisplaySettings(null, i, ref d)) break;
            if (d.dmPelsWidth != cur.dmPelsWidth || d.dmPelsHeight != cur.dmPelsHeight) continue;
            if (d.dmDisplayFrequency > best) best = d.dmDisplayFrequency;
        }
        return best;
    }
}
'@
}

function Get-DisplayHz {
    $hz = 0
    try { $hz = [CapHz]::Max() } catch { }
    if ($hz -le 0) {
        try {
            $hz = (Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
                   Measure-Object -Property CurrentRefreshRate -Maximum).Maximum
        } catch { }
    }
    return [int]$hz
}

# Highest useful tier for a display: never exceed the refresh rate, never
# write a value the client does not understand.
function Get-TierForHz([int]$hz) {
    if ($hz -ge 120) { return 120 }
    if ($hz -ge 60)  { return 60 }
    return 30
}

$ClientKeys = @(
    'Software\Cognosphere\Star Rail',       # Global client
    'Software\miHoYo\崩坏：星穹铁道'         # China client
)

function Find-SettingsValue {
    param([string[]]$Candidates)
    foreach ($k in $Candidates) {
        $psPath = 'HKCU:\' + $k
        if (-not (Test-Path -LiteralPath $psPath)) { continue }
        $item = Get-Item -LiteralPath $psPath
        $valueNames = @($item.GetValueNames() | Where-Object { $_ -like 'GraphicsSettings_Model_h*' })
        if ($valueNames.Count -gt 0) {
            return [pscustomobject]@{ KeyPath = $k; ValueName = $valueNames[0] }
        }
    }
    return $null
}

function Get-CurrentFps {
    param($raw)
    if ($raw -isnot [byte[]]) { return -1 }
    $text = [System.Text.Encoding]::UTF8.GetString($raw)
    if ($text -match '"FPS":(\d+)') { return [int]$Matches[1] }
    return -1
}

Write-Host ''
Write-Host '== Star Rail FPS Cap ==' -ForegroundColor Cyan
Write-Host ''

# --- 1. Locate the game's settings value --------------------------------
$candidates = if ($KeyPath) {
    # Self-tests only. Refuse anything that is not obviously a test key, so a
    # typo can never rewrite another game's settings by accident.
    if ($KeyPath -notmatch 'SELFTEST') {
        Write-Host '[x] -KeyPath is for self-tests only (the key name must contain SELFTEST).' -ForegroundColor Red
        exit 1
    }
    @($KeyPath)
} else { $ClientKeys }
$found = Find-SettingsValue -Candidates $candidates
if (-not $found) {
    Write-Host '[x] Could not find the game settings in the registry.' -ForegroundColor Red
    Write-Host '    Run the game once (so it creates its settings), then try again.'
    exit 1
}

$fullPath = 'HKCU:\' + $found.KeyPath
$key = Get-Item -LiteralPath $fullPath
$raw = $key.GetValue($found.ValueName)
$current = Get-CurrentFps -raw $raw

Write-Host ('[i] Client      : ' + $found.KeyPath)
Write-Host ('[i] Value       : ' + $found.ValueName)
if ($current -lt 0) {
    Write-Host '[x] The settings value does not contain an "FPS" field - not touching it.' -ForegroundColor Red
    exit 1
}
Write-Host ('[i] Current cap : ' + $current + ' FPS')

if ($Mode -eq 'status') { exit 0 }

# --- 2. Refuse to write while the game is running -----------------------
# (skipped when -KeyPath points at a test key, which the game never touches)
if (-not $KeyPath -and (Get-Process -Name 'StarRail' -ErrorAction SilentlyContinue)) {
    Write-Host '[x] ABORT: StarRail is running. Close the game completely first -' -ForegroundColor Red
    Write-Host '    the game rewrites this setting on exit and would overwrite the change.'
    exit 1
}

$target = 60
$tierNote = $null
if ($Mode -eq 'unlock') {
    if ($Auto) {
        $hz = Get-DisplayHz
        if ($hz -gt 0) {
            $target = Get-TierForHz $hz
            $tierNote = 'display ' + $hz + ' Hz -> ' + $target + ' FPS tier'
        } else {
            $target = 120
            $tierNote = 'display refresh rate unknown -> using the 120 FPS tier'
        }
    } elseif ($SupportedTiers -contains $TargetFps) {
        $target = $TargetFps
    } else {
        Write-Host ('[!] ' + $TargetFps + ' FPS is not a tier the game accepts (30/60/120) - using 120.') -ForegroundColor Yellow
        $target = 120
    }
}
if ($target -gt 120) { $target = 120 }   # hard ceiling: the client ignores anything above 120
if ($tierNote) { Write-Host ('[i] ' + $tierNote) }

if ($current -eq $target) {
    Write-Host ('[=] Already at ' + $target + ' FPS - nothing to do.')
    exit 0
}

# --- 3. Backup (first time only) ----------------------------------------
$backupDir = Join-Path $env:LOCALAPPDATA 'star-rail-120fps'
if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}
$backupFile = Join-Path $backupDir 'backup.b64'
if (-not (Test-Path -LiteralPath $backupFile)) {
    [Convert]::ToBase64String([byte[]]$raw) | Set-Content -LiteralPath $backupFile -Encoding Ascii
    Write-Host ('[i] Original value backed up to ' + $backupFile)
}

# --- 4. Patch and write back --------------------------------------------
$text = [System.Text.Encoding]::UTF8.GetString($raw)   # keeps the trailing NUL inside the string
$text = [regex]::Replace($text, '"FPS":\d+', '"FPS":' + $target)
$bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
try {
    $writable = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($found.KeyPath, $true)
    $writable.SetValue($found.ValueName, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
    $writable.Close()
} catch {
    Write-Host ('[x] Could not write to the registry: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

# --- 5. Read back and verify --------------------------------------------
$check = (Get-Item -LiteralPath $fullPath).GetValue($found.ValueName)
$now = Get-CurrentFps -raw $check
if ($now -ne $target) {
    Write-Host ('[x] Write did not stick (still ' + $now + '). Nothing was broken - please try again.') -ForegroundColor Red
    exit 1
}
Write-Host ('[+] FPS cap set to ' + $target + ' (verified).') -ForegroundColor Green
Write-Host ''

# --- 6. Post-unlock guidance --------------------------------------------
if ($Mode -eq 'unlock') {
    $maxHz = Get-DisplayHz
    if ($maxHz -gt 0 -and $maxHz -lt 120) {
        Write-Host ('[!] Your display reports a max refresh rate of ' + $maxHz + ' Hz - so ' + $target + ' FPS is the most you will actually see.') -ForegroundColor Yellow
        Write-Host ''
    }
    Write-Host 'Launch the game and verify the real frame rate with any of these:' -ForegroundColor Cyan
    Write-Host '  - FPS-MONITOR.bat  (small on-screen counter, works on any GPU)'
    Write-Host '  - Xbox Game Bar    (press Win+G, pin the Performance widget)'
    Write-Host '  - NVIDIA app       (press Alt+R, NVIDIA GPUs only)'
    Write-Host ''
    Write-Host 'Note: the in-game settings menu may still show 30/60 -' -ForegroundColor DarkGray
    Write-Host 'that is a known display bug; the game actually runs at 120.' -ForegroundColor DarkGray
}
exit 0
