#requires -Version 7.2
[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$RuntimeIdentifier = 'win-x64',
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'The desktop smoke tests must run on Windows.' }

$repo = Split-Path -Parent $PSScriptRoot
$expectedVersion = [regex]::Match((Get-Content (Join-Path $repo 'Info.plist') -Raw), '<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>').Groups[1].Value
if ($expectedVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Info.plist does not contain a valid release version.' }
$architecture = $RuntimeIdentifier.Substring(4)
$nativeArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
if ($nativeArchitecture -ne $architecture) {
    throw "Native architecture verification requires a $architecture runner; found $nativeArchitecture."
}
$evidence = Join-Path $repo "build/windows-test-results/$RuntimeIdentifier/$([Guid]::NewGuid().ToString('N'))"
$appDirectory = Join-Path $evidence 'application'
$profile = Join-Path $evidence 'isolated profile with spaces'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null

function Invoke-Dotnet {
    param([string[]]$Arguments)
    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) { throw "dotnet command failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')" }
}

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-DesktopSmoke {
    param([ValidateSet('seed', 'verify')][string]$Phase)
    $resultFile = Join-Path $evidence "$Phase.json"
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $appDirectory 'PiaoPal.exe'
    $start.WorkingDirectory = $appDirectory
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('--smoke-test', $resultFile, '--data-dir', $profile, '--smoke-phase', $Phase)) {
        $start.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        Assert-Condition ($process.Start()) 'The desktop smoke process did not start.'
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Desktop $Phase test did not terminate within 30 seconds."
        }
        $stdout.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $evidence "$Phase.stdout.log") -Encoding utf8
        $stderr.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $evidence "$Phase.stderr.log") -Encoding utf8
        if ($process.ExitCode -ne 0 -and (Test-Path -LiteralPath $resultFile -PathType Leaf)) {
            Write-Host (Get-Content -LiteralPath $resultFile -Raw)
        }
        Assert-Condition ($process.ExitCode -eq 0) "Desktop $Phase test failed with exit code $($process.ExitCode); see $evidence."
    }
    finally {
        $process.Dispose()
    }

    Assert-Condition (Test-Path -LiteralPath $resultFile -PathType Leaf) "Desktop $Phase test did not produce its result."
    $result = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
    Assert-Condition ($result.success -eq $true) "Desktop $Phase result was not successful."
    Assert-Condition ($result.phase -eq $Phase) "Desktop $Phase returned the wrong phase."
    Assert-Condition ($result.version.Split('+')[0] -eq $expectedVersion) "Desktop $Phase reported the wrong application version."
    Assert-Condition (@($result.checks).Count -gt 0) "Desktop $Phase did not report any checks."
    Assert-Condition ($result.framesRendered -gt 0) "Desktop $Phase did not render a layered-window frame."
    Assert-Condition ($result.overlayDisposed -eq $true -and $result.trayDisposed -eq $true) "Desktop $Phase did not cleanly dispose the overlay and tray."
    Assert-Condition ($result.processArchitecture.ToLowerInvariant() -eq $architecture) "Desktop $Phase ran under the wrong process architecture."
    Assert-Condition ($result.osArchitecture.ToLowerInvariant() -eq $architecture) "Desktop $Phase did not run on its native OS architecture."
    Assert-Condition ($result.settings.scale -eq 1.5) "Desktop $Phase did not retain the saved scale."
    Assert-Condition ($result.settings.speed -eq 2.5) "Desktop $Phase did not retain the saved speed."
    Assert-Condition ($result.settings.skinId -eq 'dog') "Desktop $Phase did not retain the saved companion."
    Assert-Condition ($result.settings.nickname -eq 'Smoke companion') "Desktop $Phase did not retain the saved name."
    Assert-Condition ($result.settings.language -eq 'en') "Desktop $Phase did not retain the saved language."
    Assert-Condition ($result.stats.distancePoints -ge 1234.5) "Desktop $Phase lost unsaved distance on normal shutdown."
    $minimumSessions = if ($Phase -eq 'verify') { 2 } else { 1 }
    Assert-Condition ($result.stats.sessionCount -ge $minimumSessions) "Desktop $Phase did not retain the session count."
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $profile 'active-session.json'))) "Desktop $Phase left its active-session marker after normal shutdown."
    $lifecycle = Get-Content -LiteralPath (Join-Path $profile 'lifecycle.log') -Raw
    Assert-Condition ($lifecycle.Contains('termination_completed')) "Desktop $Phase did not record normal termination completion."
    return $result
}

Push-Location $repo
try {
    Invoke-Dotnet -Arguments @('run', '--project', 'Windows/PiaoPal.Core.Tests/PiaoPal.Core.Tests.csproj', '--configuration', $Configuration)
    Invoke-Dotnet -Arguments @('build', 'Windows/PiaoPal.Windows/PiaoPal.Windows.csproj', '--configuration', $Configuration,
        '--runtime', $RuntimeIdentifier, '--self-contained', 'false', '--output', $appDirectory)

    # Verify the native apphost, independently of the runtime's own smoke report.
    $executable = Join-Path $appDirectory 'PiaoPal.exe'
    $bytes = [System.IO.File]::ReadAllBytes($executable)
    Assert-Condition ($bytes.Length -gt 64 -and $bytes[0] -eq 0x4d -and $bytes[1] -eq 0x5a) 'The application has no valid DOS executable header.'
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    Assert-Condition ($peOffset -gt 0 -and $peOffset -le $bytes.Length - 6) 'The PE header offset is outside the executable.'
    Assert-Condition ([BitConverter]::ToUInt32($bytes, $peOffset) -eq 0x00004550) 'The executable has no PE signature.'
    $expectedMachine = if ($architecture -eq 'arm64') { 0xaa64 } else { 0x8664 }
    Assert-Condition ([BitConverter]::ToUInt16($bytes, $peOffset + 4) -eq $expectedMachine) 'The apphost PE architecture does not match the requested runtime.'

    $seed = Invoke-DesktopSmoke -Phase seed
    $verify = Invoke-DesktopSmoke -Phase verify
    Assert-Condition ($verify.stats.distancePoints -ge $seed.stats.distancePoints) 'Saved distance decreased across process restart.'
    Assert-Condition ($verify.stats.sessionCount -gt $seed.stats.sessionCount) 'Restart did not create a new recorded session.'

    $summary = [ordered]@{
        success = $true
        runtimeIdentifier = $RuntimeIdentifier
        nativeArchitecture = $nativeArchitecture
        phases = @('seed', 'verify')
        seedFrames = $seed.framesRendered
        restartFrames = $verify.framesRendered
        isolatedProfile = $profile
    }
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
    Write-Host "PASS: core regressions, native $architecture apphost, layered desktop startup/cleanup, settings and distance across process restart."
    Write-Host "Evidence: $evidence"
}
finally {
    Pop-Location
}
