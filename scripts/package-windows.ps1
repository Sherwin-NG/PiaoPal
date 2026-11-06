param(
    [ValidateSet('win-x64', 'win-arm64')][string]$RuntimeIdentifier = 'win-x64',
    [string]$Version = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
$sourceVersion = [regex]::Match((Get-Content (Join-Path $repo 'Info.plist') -Raw), '<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>').Groups[1].Value
if (-not $Version) { $Version = $sourceVersion }
if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $Version -ne $sourceVersion) { throw 'Version must match Info.plist.' }
[xml]$properties = Get-Content (Join-Path $repo 'Windows/Directory.Build.props') -Raw
if ($properties.Project.PropertyGroup.Version -ne $Version) { throw 'Windows version must match Info.plist.' }
$architecture = $RuntimeIdentifier.Substring(4)
$dist = Join-Path $repo 'dist'
$work = Join-Path $repo ('build/windows-package-' + [guid]::NewGuid().ToString('N'))
$app = Join-Path $work 'PiaoPal'
$smoke = Join-Path $work 'published-smoke.json'
$data = Join-Path $work 'smoke-profile'
$reports = Join-Path $repo "build/windows-test-results/$RuntimeIdentifier/package"
New-Item -ItemType Directory -Force $dist, $app | Out-Null
try {
    & dotnet publish (Join-Path $repo 'Windows/PiaoPal.Windows/PiaoPal.Windows.csproj') -c Release -r $RuntimeIdentifier --self-contained true '-p:PublishSingleFile=false' '-p:PublishReadyToRun=false' '-p:ContinuousIntegrationBuild=true' -o $app
    if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
    Copy-Item (Join-Path $repo 'LICENSE'), (Join-Path $repo 'THIRD_PARTY_NOTICES.md') -Destination $app
    Copy-Item (Join-Path $repo 'Windows/README.txt') (Join-Path $app 'README.txt')
    # Self-contained publish does not copy the NuGet runtime packs' license files.
    $packageLocation = & dotnet nuget locals global-packages --list --force-english-output
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate runtime package notices.' }
    $packageRoot = ([regex]::Match(($packageLocation -join "`n"), 'global-packages:\s*(.+)').Groups[1].Value).Trim()
    if (-not $packageRoot) { throw 'NuGet package root was not returned.' }
    $runtimeConfig = Get-Content (Join-Path $app 'PiaoPal.runtimeconfig.json') -Raw | ConvertFrom-Json
    foreach ($framework in $runtimeConfig.runtimeOptions.includedFrameworks) {
        $packageName = ($framework.name + '.Runtime.' + $RuntimeIdentifier).ToLowerInvariant()
        $runtimePackage = Join-Path $packageRoot "$packageName/$($framework.version)"
        $licenses = @(Get-ChildItem $runtimePackage -File | Where-Object { $_.Name -like 'LICENSE*' -or $_.Name -like '*NOTICE*' })
        if (-not ($licenses | Where-Object Name -Like 'LICENSE*')) { throw "Runtime license missing: $packageName" }
        if ($framework.name -eq 'Microsoft.NETCore.App' -and -not ($licenses | Where-Object Name -Like '*NOTICE*')) { throw 'Core runtime third-party notices are missing.' }
        $noticeDirectory = Join-Path $app "RuntimeNotices/$($framework.name)"
        New-Item -ItemType Directory -Force $noticeDirectory | Out-Null
        $licenses | Copy-Item -Destination $noticeDirectory
    }
    $exe = Join-Path $app 'PiaoPal.exe'
    $fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion
    if ($fileVersion -ne "$Version.0") { throw "Incorrect executable version: $fileVersion" }
    $pe = [IO.BinaryReader]::new([IO.File]::OpenRead($exe))
    try {
        $pe.BaseStream.Position = 0x3c
        $header = $pe.ReadInt32()
        $pe.BaseStream.Position = $header
        if ($pe.ReadUInt32() -ne 0x00004550) { throw 'Invalid PE executable.' }
        $machine = $pe.ReadUInt16()
        $expectedMachine = if ($architecture -eq 'x64') { 0x8664 } else { 0xAA64 }
        if ($machine -ne $expectedMachine) { throw "Unexpected PE architecture: $machine" }
    } finally { $pe.Dispose() }
    foreach ($sprite in Get-ChildItem (Join-Path $repo 'Resources/Sprites') -File) {
        $copy = Join-Path $app "Resources/Sprites/$($sprite.Name)"
        if (-not (Test-Path $copy) -or (Get-FileHash $copy).Hash -ne (Get-FileHash $sprite.FullName).Hash) { throw "Sprite mismatch: $($sprite.Name)" }
    }
    $start = [Diagnostics.ProcessStartInfo]::new($exe)
    $start.UseShellExecute = $false
    foreach ($arg in @('--smoke-test', $smoke, '--data-dir', $data, '--smoke-phase', 'seed')) { $start.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        if (-not $process.WaitForExit(60000)) { $process.Kill($true); $process.WaitForExit(); throw 'Published application smoke test timed out.' }
        if ($process.ExitCode -ne 0) { throw "Published application smoke test failed: $($process.ExitCode)" }
    } finally { $process.Dispose() }
    $result = Get-Content $smoke -Raw | ConvertFrom-Json
    if (-not $result.success -or -not $result.overlayDisposed -or -not $result.trayDisposed -or $result.framesRendered -lt 1) { throw 'Published application failed runtime checks.' }
    if ($result.phase -ne 'seed' -or $result.processArchitecture.ToLowerInvariant() -ne $architecture -or $result.osArchitecture.ToLowerInvariant() -ne $architecture) { throw 'Published smoke did not run natively on the requested architecture.' }
    $name = "PiaoPal-v$Version-Windows-$architecture.zip"
    $stagedZip = Join-Path $work $name
    [IO.Compression.ZipFile]::CreateFromDirectory($app, $stagedZip, [IO.Compression.CompressionLevel]::Optimal, $true)
    $inspection = Join-Path $work 'zip-check'
    [IO.Compression.ZipFile]::ExtractToDirectory($stagedZip, $inspection)
    $unzipped = Join-Path $inspection 'PiaoPal'
    foreach ($file in Get-ChildItem $app -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($app, $file.FullName)
        $copy = Join-Path $unzipped $relative
        if ((Get-FileHash $file.FullName).Hash -ne (Get-FileHash $copy).Hash) { throw "ZIP contents differ: $relative" }
    }
    $target = Join-Path $dist $name
    Move-Item $stagedZip $target -Force
    $hash = (Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $dist "SHA256SUMS-Windows-$architecture.txt"), "$hash  $name`n", [Text.UTF8Encoding]::new($false))
    Write-Host "PASS: v$Version $RuntimeIdentifier, self-contained runtime, native smoke, ZIP contents, and SHA256 verified."
} finally {
    if ((Test-Path $smoke) -or (Test-Path $data)) {
        New-Item -ItemType Directory -Force $reports | Out-Null
        if (Test-Path $smoke) { Copy-Item $smoke (Join-Path $reports 'published-smoke.json') -Force }
        if (Test-Path $data) { Copy-Item $data $reports -Recurse -Force }
    }
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
}
