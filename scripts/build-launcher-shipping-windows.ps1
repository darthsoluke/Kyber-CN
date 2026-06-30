param(
    [string]$OutputDirectory = '',
    [string]$Configuration = 'Release',
    [switch]$NoZip
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $Root 'Launcher\build\shipping\windows'
}
$FixedShippingOutputDirectory = [System.IO.Path]::GetFullPath((Join-Path $Root 'Launcher\build\shipping\windows'))
$RequestedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
if ($RequestedOutputDirectory -ine $FixedShippingOutputDirectory) {
    throw "Shipping OutputDirectory is fixed to $FixedShippingOutputDirectory. Remove custom output paths to keep Launcher\build\shipping clean."
}

function Require-Directory {
    param([string]$Path, [string]$Label)
    if (!(Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label does not exist: $Path"
    }
}

function Reset-DirectoryInsideWorkspace {
    param([string]$Path)

    $absolutePath = [System.IO.Path]::GetFullPath($Path)
    $absoluteRoot = [System.IO.Path]::GetFullPath($Root)
    if (!$absolutePath.StartsWith($absoluteRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputDirectory must stay inside the workspace: $absolutePath"
    }

    if (Test-Path -LiteralPath $absolutePath) {
        try {
            Remove-Item -LiteralPath $absolutePath -Recurse -Force
        } catch {
            $removeError = $_
            $quarantinePath = "$absolutePath.locked.$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
            Write-Warning "Could not delete existing output directory. Moving it aside: $quarantinePath"
            try {
                Move-Item -LiteralPath $absolutePath -Destination $quarantinePath -Force
            } catch {
                $moveError = $_
                throw "Could not reset output directory: $absolutePath. Close any running Launcher, BFII host, kyber_cli.exe, maxima-bootstrap.exe, or maxima-service.exe process using this package. Delete error: $($removeError.Exception.Message). Move error: $($moveError.Exception.Message)"
            }
        }
    }
    New-Item -ItemType Directory -Path $absolutePath -Force | Out-Null
}

function Enable-ShippingRustPathRemap {
    $remapInputs = @(
        @{ From = $Root; To = 'kyber' },
        @{ From = $env:KYBER_TOOLCHAINS; To = 'kyber_toolchains' },
        @{ From = $env:CARGO_HOME; To = 'cargo_home' },
        @{ From = $env:RUSTUP_HOME; To = 'rustup_home' },
        @{ From = $env:USERPROFILE; To = 'user_profile' },
        @{ From = (Join-Path $env:USERPROFILE '.cargo'); To = 'cargo_home' }
    )

    $flags = @('--cfg', 'reqwest_unstable')
    foreach ($remap in $remapInputs) {
        $from = $remap.From
        if ([string]::IsNullOrWhiteSpace($from) -or !(Test-Path -LiteralPath $from)) {
            continue
        }

        $fullPath = [System.IO.Path]::GetFullPath($from)
        if ($fullPath.Contains(' ')) {
            Write-Warning "Skipping Rust path remap for path with spaces: $fullPath"
            continue
        }

        $flags += "--remap-path-prefix=$fullPath=$($remap.To)"
        $forwardPath = $fullPath.Replace('\', '/')
        if ($forwardPath -ne $fullPath) {
            $flags += "--remap-path-prefix=$forwardPath=$($remap.To)"
        }
    }

    $existing = @()
    if (![string]::IsNullOrWhiteSpace($env:RUSTFLAGS)) {
        $existing = @($env:RUSTFLAGS)
    }
    $env:RUSTFLAGS = (@($existing) + $flags) -join ' '
    $env:CARGO_ENCODED_RUSTFLAGS = $flags -join ([char]0x1f)
    Write-Host "Rust shipping path remap enabled: $($flags.Count) entries"
}

function Build-CliBundle {
    Push-Location (Join-Path $Root 'CLI')
    try {
        flutter pub get

        Push-Location (Join-Path $Root 'CLI\rust')
        try {
            cargo build --release
        } finally {
            Pop-Location
        }

        dart run build_runner build --delete-conflicting-outputs
        dart build cli bin/kyber_cli.dart
        Sync-CliRustRuntime
    } finally {
        Pop-Location
    }
}

function Build-LauncherRustRuntime {
    $launcherRustDirectory = Join-Path $Root 'Launcher\rust'
    if (!(Test-Path -LiteralPath (Join-Path $launcherRustDirectory 'Cargo.toml') -PathType Leaf)) {
        throw "Launcher Rust project was not found: $launcherRustDirectory"
    }

    Push-Location $launcherRustDirectory
    try {
        cargo build --release
    } finally {
        Pop-Location
    }
}

function Sync-CliRustRuntime {
    $source = Join-Path $Root 'CLI\rust\target\release\rust_lib.dll'
    $bundleRoot = Join-Path $Root 'CLI\build\cli\windows_x64\bundle'
    $bundleLib = Join-Path $bundleRoot 'lib\rust_lib.dll'
    $bundleBin = Join-Path $bundleRoot 'bin\rust_lib.dll'

    if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Latest CLI Rust runtime DLL was not built: $source"
    }
    if (!(Test-Path -LiteralPath $bundleRoot -PathType Container)) {
        throw "CLI bundle was not generated: $bundleRoot"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $bundleLib) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $bundleLib -Force

    if (Test-Path -LiteralPath (Split-Path -Parent $bundleBin) -PathType Container) {
        Copy-Item -LiteralPath $source -Destination $bundleBin -Force
    }

    Write-Host "Synced latest CLI Rust runtime into CLI bundle: $source"
}

function Sync-LauncherRustRuntime {
    param([string]$DestinationDirectory)

    $source = Join-Path $Root 'Launcher\rust\target\release\rust_lib.dll'
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Latest Launcher Rust runtime DLL was not built: $source"
    }
    if (!(Test-Path -LiteralPath $DestinationDirectory -PathType Container)) {
        throw "Launcher runtime destination does not exist: $DestinationDirectory"
    }

    Copy-Item -LiteralPath $source -Destination (Join-Path $DestinationDirectory 'rust_lib.dll') -Force
    Write-Host "Synced latest Launcher Rust runtime into: $DestinationDirectory"
}

function Remove-DebugArtifacts {
    param([string]$Path)

    $debugExtensions = @('.pdb', '.ilk', '.exp', '.lib')
    $artifacts = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $debugExtensions -contains $_.Extension.ToLowerInvariant() }
    foreach ($artifact in @($artifacts)) {
        if ($null -eq $artifact) {
            continue
        }

        Remove-Item -LiteralPath $artifact.FullName -Force
    }
}

function Remove-TransientArtifacts {
    param([string]$Path)

    foreach ($fileName in @('out.txt', 'err.txt')) {
        $target = Join-Path $Path $fileName
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
        }
    }

    foreach ($directoryName in @('.sentry-native')) {
        $target = Join-Path $Path $directoryName
        if (Test-Path -LiteralPath $target -PathType Container) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
}

$toolchain = Join-Path $PSScriptRoot 'use-local-toolchain.ps1'
if (Test-Path -LiteralPath $toolchain -PathType Leaf) {
    . $toolchain
}

Enable-ShippingRustPathRemap
Build-CliBundle
Build-LauncherRustRuntime

Push-Location (Join-Path $Root 'Launcher')
try {
    if ($Configuration -ieq 'Debug') {
        flutter build windows --debug
        $runnerDirectory = Join-Path $Root 'Launcher\build\windows\x64\runner\Debug'
    } else {
        flutter build windows --release
        $runnerDirectory = Join-Path $Root 'Launcher\build\windows\x64\runner\Release'
    }
} finally {
    Pop-Location
}

Require-Directory $runnerDirectory 'Launcher runner directory'
Sync-LauncherRustRuntime -DestinationDirectory $runnerDirectory

$runtimePackage = Join-Path $Root '.cache\shipping\dedicated_runtime_package'
& (Join-Path $PSScriptRoot 'package-windows-dedicated.ps1') `
    -OutputDirectory $runtimePackage `
    -NoZip `
    -DefaultGamePath ''

Reset-DirectoryInsideWorkspace $OutputDirectory
Copy-Item -Path (Join-Path $runnerDirectory '*') -Destination $OutputDirectory -Recurse -Force
Sync-LauncherRustRuntime -DestinationDirectory $OutputDirectory

$runtimeOut = Join-Path $OutputDirectory 'dedicated_runtime'
if (Test-Path -LiteralPath $runtimeOut) {
    Remove-Item -LiteralPath $runtimeOut -Recurse -Force
}
Copy-Item -LiteralPath $runtimePackage -Destination $runtimeOut -Recurse -Force
Remove-DebugArtifacts -Path $OutputDirectory
Remove-TransientArtifacts -Path $OutputDirectory

Write-Host "Launcher shipping directory: $OutputDirectory"
Write-Host "Dedicated runtime: $runtimeOut"
Write-Host 'No credentials are bundled. Users configure BFII path and reuse the normal EA/Maxima session inside Launcher settings.'
Write-Host 'Archive disabled. Shipping output is kept as Launcher\build\shipping\windows only.'
