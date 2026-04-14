param()

$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $moduleRoot
$stageDir = Join-Path $repoRoot 'artifacts\module'
$releaseModuleDir = Join-Path $repoRoot 'Launcher\build\windows\x64\runner\Release\module'
$programDataModuleDir = Join-Path $env:ProgramData 'Kyber\Module'

$kyberDll = Join-Path $moduleRoot 'bazel-bin\Kyber.dll'
$vivoxDll = Join-Path $moduleRoot 'ThirdParty\vivox\SDK\Libraries\Release\x64\vivoxsdk.dll'
$caRoot = Join-Path $repoRoot 'Launcher\assets\ca\ca_root.pem'
$versionHeader = Join-Path $moduleRoot 'Public\Base\Version.h'

function Require-File {
  param([string] $Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required file not found: $Path"
  }
}

function Copy-IfExists {
  param(
    [string] $Source,
    [string] $Destination
  )

  if (Test-Path -LiteralPath $Source -PathType Leaf) {
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    return $true
  }

  return $false
}

function Expand-FileFromZip {
  param(
    [string] $ZipPath,
    [string] $EntryName,
    [string] $DestinationPath
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $entry = $archive.Entries | Where-Object { $_.FullName -eq $EntryName } | Select-Object -First 1
    if ($null -eq $entry) {
      return $false
    }

    $destinationDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
      New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $DestinationPath, $true)
    return $true
  } finally {
    $archive.Dispose()
  }
}

function Read-VersionValue {
  param(
    [string] $HeaderPath,
    [string] $MacroName
  )

  $line = Select-String -Path $HeaderPath -Pattern "^\#define\s+$MacroName\s+" | Select-Object -First 1
  if ($null -eq $line) {
    throw "Unable to find version macro $MacroName in $HeaderPath"
  }

  return ($line.Line -replace "^\#define\s+$MacroName\s+", '').Trim().Trim('"')
}

Require-File $kyberDll
Require-File $vivoxDll
Require-File $caRoot
Require-File $versionHeader

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

Copy-Item -LiteralPath $kyberDll -Destination (Join-Path $stageDir 'Kyber.dll') -Force
Copy-Item -LiteralPath $vivoxDll -Destination (Join-Path $stageDir 'vivoxsdk.dll') -Force
Copy-Item -LiteralPath $caRoot -Destination (Join-Path $stageDir 'ca_root.pem') -Force

$major = Read-VersionValue -HeaderPath $versionHeader -MacroName 'KYBER_VERSION_MAJOR'
$minor = Read-VersionValue -HeaderPath $versionHeader -MacroName 'KYBER_VERSION_MINOR'
$patch = Read-VersionValue -HeaderPath $versionHeader -MacroName 'KYBER_VERSION_PATCH'
$suffix = Read-VersionValue -HeaderPath $versionHeader -MacroName 'KYBER_SUFFIX'
$version = "$major.$minor.$patch$suffix"
Set-Content -LiteralPath (Join-Path $stageDir 'VERSION') -Value $version -NoNewline

$aggregationPath = Join-Path $stageDir 'VanillaBundleAggregation.kb'
$zipPath = Join-Path $stageDir 'kyber-module.zip'

if (-not (Test-Path -LiteralPath $aggregationPath -PathType Leaf)) {
  if (-not (Copy-IfExists -Source (Join-Path $releaseModuleDir 'VanillaBundleAggregation.kb') -Destination $aggregationPath)) {
    $copied = $false
    foreach ($zipCandidate in @(
      (Join-Path $releaseModuleDir 'kyber-module.zip'),
      (Join-Path $programDataModuleDir 'kyber-module.zip')
    )) {
      if (Test-Path -LiteralPath $zipCandidate -PathType Leaf) {
        $copied = Expand-FileFromZip -ZipPath $zipCandidate -EntryName 'VanillaBundleAggregation.kb' -DestinationPath $aggregationPath
        if ($copied) {
          break
        }
      }
    }

    if (-not $copied) {
      Copy-IfExists -Source (Join-Path $programDataModuleDir 'VanillaBundleAggregation.kb') -Destination $aggregationPath | Out-Null
    }
  }
}

Require-File $aggregationPath

$existingZipCandidates = @(
  (Join-Path $releaseModuleDir 'kyber-module.zip'),
  (Join-Path $programDataModuleDir 'kyber-module.zip')
)

$copiedZip = $false
foreach ($zipCandidate in $existingZipCandidates) {
  if (Copy-IfExists -Source $zipCandidate -Destination $zipPath) {
    $copiedZip = $true
    break
  }
}

if (-not $copiedZip) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $tempZip = Join-Path $env:TEMP "kyber-module-$PID.zip"
  if (Test-Path -LiteralPath $tempZip -PathType Leaf) {
    Remove-Item -LiteralPath $tempZip -Force
  }
  if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
    Remove-Item -LiteralPath $zipPath -Force
  }

  [System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stageDir,
    $tempZip,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
  )
  Move-Item -LiteralPath $tempZip -Destination $zipPath -Force
}

if (Test-Path -LiteralPath $releaseModuleDir -PathType Container) {
  New-Item -ItemType Directory -Path $releaseModuleDir -Force | Out-Null
  foreach ($name in @(
    'Kyber.dll',
    'vivoxsdk.dll',
    'ca_root.pem',
    'VERSION',
    'VanillaBundleAggregation.kb',
    'kyber-module.zip'
  )) {
    Copy-Item -LiteralPath (Join-Path $stageDir $name) -Destination (Join-Path $releaseModuleDir $name) -Force
  }
}

Write-Host "Staged bundled module to $stageDir"
