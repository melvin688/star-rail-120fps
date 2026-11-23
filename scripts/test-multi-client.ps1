$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$keyGlobal = 'Software\Cognosphere\Star Rail-SELFTEST'
$keyChina  = 'Software\miHoYo\崩坏：星穹铁道-SELFTEST'
$valueName = 'GraphicsSettings_Model_h987654321'
$testDir   = Join-Path $env:TEMP ('sr-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

function New-FakeClient([string]$keyPath, [int]$fps) {
    $full = 'HKCU:\' + $keyPath
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
    New-Item -Path $full -Force | Out-Null
    # the real value is UTF-8 JSON with a trailing NUL, stored as binary
    $json = '{"FPS":' + $fps + ',"VSync":0,"RenderScale":1.0}'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json + [char]0)
    New-ItemProperty -Path $full -Name $valueName -Value $bytes -PropertyType Binary -Force | Out-Null
}

function Get-FakeFps([string]$keyPath) {
    $full = 'HKCU:\' + $keyPath
    $raw = (Get-Item -LiteralPath $full).GetValue($valueName)
    $txt = [System.Text.Encoding]::UTF8.GetString([byte[]]$raw)
    if ($txt -match '"FPS":(\d+)') { return [int]$Matches[1] }
    return -1
}

function Clear-FakeClient([string]$keyPath) {
    $full = 'HKCU:\' + $keyPath
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
}

$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { Write-Host ('  PASS  ' + $name); $script:pass++ }
    else { Write-Host ('  FAIL  ' + $name + '  [' + $detail + ']') -ForegroundColor Red; $script:fail++ }
}

$cap = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\fps-cap.ps1')).Path
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$env:STARRAIL_SELFTEST_DIR = $testDir

# -File does not parse array arguments, so build a -Command string instead.
function Run-Cap([string]$capMode, [int]$tier, [string[]]$keys) {
    $quoted = ($keys | ForEach-Object { "'" + $_ + "'" }) -join ','
    $line = "& '$cap' -Mode $capMode"
    if ($tier -gt 0) { $line += " -TargetFps $tier" }
    $line += " -ClientKeysOverride @($quoted)"
    return (& powershell -NoProfile -ExecutionPolicy Bypass -Command $line 2>&1)
}

try {
    Write-Host '=== setup: two fake clients, different starting caps ==='
    # different starting values so the two backups cannot look identical
    New-FakeClient $keyGlobal 60
    New-FakeClient $keyChina 30
    Write-Host ('  global=' + (Get-FakeFps $keyGlobal) + ' china=' + (Get-FakeFps $keyChina))

    Write-Host ''
    Write-Host '=== 1. status lists both ==='
    $out = Run-Cap 'status' 0 @($keyGlobal, $keyChina)
    $text = $out -join "`n"
    $both = ($text -match 'Cognosphere') -and ($text -match 'miHoYo')
    Check 'status reports both clients' $both $text.Substring(0, [Math]::Min(200, $text.Length))

    Write-Host ''
    Write-Host '=== 2. unlock writes both ==='
    $out = Run-Cap 'unlock' 120 @($keyGlobal, $keyChina)
    $g = Get-FakeFps $keyGlobal; $c = Get-FakeFps $keyChina
    Check 'global is 120' ($g -eq 120) ('got ' + $g)
    Check 'china is 120'  ($c -eq 120) ('got ' + $c)
    $verified = ($out | Select-String -SimpleMatch 'verified').Count
    Check 'both reported verified' ($verified -eq 2) ('verified lines: ' + $verified)

    Write-Host ''
    Write-Host '=== 3. per-client backups ==='
    $bg = Join-Path $testDir 'backup-global.b64'
    $bc = Join-Path $testDir 'backup-cn.b64'
    Check 'backup-global.b64 exists' (Test-Path $bg) $bg
    Check 'backup-cn.b64 exists'     (Test-Path $bc) $bc
    if ((Test-Path $bg) -and (Test-Path $bc)) {
        $gB64 = (Get-Content -Raw $bg).Trim()
        $cB64 = (Get-Content -Raw $bc).Trim()
        $gTxt = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($gB64))
        $cTxt = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($cB64))
        Check 'global backup records 60' ($gTxt -match '"FPS":60') $gTxt
        Check 'china backup records 30'  ($cTxt -match '"FPS":30') $cTxt
        Check 'backups are separate files' ($gB64 -ne $cB64) 'identical content'
    }

    Write-Host ''
    Write-Host '=== 4. re-running unlock is a no-op ==='
    $out = Run-Cap 'unlock' 120 @($keyGlobal, $keyChina)
    # count only the per-client result lines; the summary line also says
    # "already at" and would be counted a third time
    $already = ($out | Select-String -Pattern '^\[=\] .*already at').Count
    Check 'both reported already set' ($already -eq 2) ('already lines: ' + $already)

    Write-Host ''
    Write-Host '=== 5. restore returns both to 60 ==='
    $out = Run-Cap 'restore' 0 @($keyGlobal, $keyChina)
    $g = Get-FakeFps $keyGlobal; $c = Get-FakeFps $keyChina
    Check 'global back to 60' ($g -eq 60) ('got ' + $g)
    Check 'china back to 60'  ($c -eq 60) ('got ' + $c)

    Write-Host ''
    Write-Host '=== 6. one client drifted, only that one is touched ==='
    New-FakeClient $keyChina 120
    $out = Run-Cap 'unlock' 60 @($keyGlobal, $keyChina)
    $g = Get-FakeFps $keyGlobal; $c = Get-FakeFps $keyChina
    Check 'global untouched at 60' ($g -eq 60) ('got ' + $g)
    Check 'china pulled back to 60' ($c -eq 60) ('got ' + $c)

    Write-Host ''
    Write-Host '=== 7. override guard rejects keys without SELFTEST ==='
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -Command "& '$cap' -Mode unlock -ClientKeysOverride 'Software\Cognosphere\Star Rail'" 2>&1
    $blocked = ($out -join ' ') -match 'SELFTEST'
    Check 'real key path refused' $blocked (($out -join ' ') -replace '\s+', ' ')
}
finally {
    Clear-FakeClient $keyGlobal
    Clear-FakeClient $keyChina
    Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\STARRAIL_SELFTEST_DIR -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host '=== cleanup ==='
    Write-Host ('  global key gone : ' + (-not (Test-Path ('HKCU:\' + $keyGlobal))))
    Write-Host ('  china key gone  : ' + (-not (Test-Path ('HKCU:\' + $keyChina))))
    Write-Host ('  temp dir gone   : ' + (-not (Test-Path $testDir)))
    $real = 'HKCU:\Software\Cognosphere\Star Rail'
    if (Test-Path $real) {
        $raw = (Get-Item -LiteralPath $real).GetValue('GraphicsSettings_Model_h2986158309')
        $txt = [System.Text.Encoding]::UTF8.GetString([byte[]]$raw)
        if ($txt -match '"FPS":(\d+)') { Write-Host ('  real client cap : ' + $Matches[1] + ' (must still be 120)') }
    }
}

Write-Host ''
Write-Host ('RESULT: ' + $pass + ' passed, ' + $fail + ' failed')
if ($fail -gt 0) { exit 1 }
