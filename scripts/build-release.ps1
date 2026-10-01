param(
    [string]$Version
)

$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$addonFile = Join-Path $repoRoot 'pupman.lua'

if ([string]::IsNullOrWhiteSpace($Version)) {
    $match = Select-String -LiteralPath $addonFile -Pattern "addon\.version\s*=\s*'([^']+)'" |
        Select-Object -First 1
    if ($null -eq $match) {
        throw 'Could not read addon.version from pupman.lua.'
    }
    $Version = $match.Matches[0].Groups[1].Value
}

$Version = $Version.TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid release version: $Version"
}

$declaredVersion = (Select-String -LiteralPath $addonFile -Pattern "addon\.version\s*=\s*'([^']+)'" |
    Select-Object -First 1).Matches[0].Groups[1].Value
if ($declaredVersion -ne $Version) {
    throw "Requested version $Version does not match addon.version $declaredVersion."
}

$distRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'dist'))
$stageRoot = [IO.Path]::GetFullPath((Join-Path $distRoot "stage-$Version"))
if (-not $stageRoot.StartsWith($distRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe staging path: $stageRoot"
}

New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}

$addonRoot = New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'pupman')
$libsRoot = New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'libs')

$addonFiles = @(
    'pupman.lua',
    'maneuverview.lua',
    'actionpacket.lua',
    'petstatus.lua',
    'README.md',
    'LICENSE',
    'THIRD_PARTY_NOTICES.md'
)
$libraryFiles = @(
    'automatonws.lua',
    'burdenforecast.lua',
    'burdenmodel.lua',
    'pupcooldowns.lua',
    'pupmagic.lua',
    'pupstats.lua'
)

foreach ($file in $addonFiles) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination $addonRoot.FullName
}
foreach ($file in $libraryFiles) {
    Copy-Item -LiteralPath (Join-Path $repoRoot (Join-Path 'libs' $file)) -Destination $libsRoot.FullName
}

$archive = Join-Path $distRoot "PUPMan-v$Version.zip"
if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $archive -CompressionLevel Optimal
Remove-Item -LiteralPath $stageRoot -Recurse -Force

Write-Output $archive
