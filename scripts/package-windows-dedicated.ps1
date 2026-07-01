param(
    [string]$OutputDirectory = '',
    [string]$CliBundleDirectory = '',
    [string]$ModulePath = '',
    [string]$CertificatePath = '',
    [string]$DefaultGamePath = '',
    [string]$DefaultServerName = 'Kyber Direct Host',
    [int]$DefaultServerPort = 25200,
    [int]$DefaultMaxPlayers = 2,
    [string]$DefaultMap = 'S5_1/Levels/MP/Geonosis_01/Geonosis_01',
    [string]$DefaultMode = 'HeroesVersusVillains',
    [switch]$NoZip
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $Root 'CLI\dev_build\windows_dedicated_package'
}
if ([string]::IsNullOrWhiteSpace($CliBundleDirectory)) {
    $CliBundleDirectory = Join-Path $Root 'CLI\build\cli\windows_x64\bundle'
    if (!(Test-Path -LiteralPath $CliBundleDirectory -PathType Container)) {
        $CliBundleDirectory = Join-Path $Root 'CLI\dev_build\cli_bundle\bundle'
    }
}
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $candidateModulePaths = @(
        (Join-Path $Root 'artifacts\module'),
        (Join-Path $Root 'Launcher\build\windows\x64\runner\Release\module'),
        (Join-Path $Root 'Module\bazel-bin'),
        (Join-Path $Root 'Launcher\build\windows\x64\runner\Debug\module'),
        (Join-Path $Root 'CLI\dev_build\module_runtime')
    )
    $validModulePaths = @()
    foreach ($candidate in $candidateModulePaths) {
        $candidateKyber = Join-Path $candidate 'Kyber.dll'
        $candidateVivox = Join-Path $candidate 'vivoxsdk.dll'
        if ((Test-Path -LiteralPath $candidateKyber -PathType Leaf) -and
            (Test-Path -LiteralPath $candidateVivox -PathType Leaf)) {
            $validModulePaths += [pscustomobject]@{
                Path = $candidate
                KyberTime = (Get-Item -LiteralPath $candidateKyber).LastWriteTimeUtc
            }
        }
    }

    if ($validModulePaths.Count -eq 0) {
        $ModulePath = Join-Path $Root 'CLI\dev_build\module_runtime'
    } else {
        $ModulePath = ($validModulePaths | Sort-Object -Property KyberTime -Descending | Select-Object -First 1).Path
    }
}
if ([string]::IsNullOrWhiteSpace($CertificatePath)) {
    $candidateCertificatePaths = @(
        (Join-Path $ModulePath 'ca_root.pem'),
        (Join-Path $Root 'Launcher\build\windows\x64\runner\Release\module\ca_root.pem'),
        (Join-Path $Root 'Launcher\build\windows\x64\runner\Debug\module\ca_root.pem')
    )
    foreach ($candidate in $candidateCertificatePaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $CertificatePath = $candidate
            break
        }
    }
}

function Require-File {
    param([string]$Path, [string]$Label)
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label does not exist: $Path"
    }
}

function Require-Directory {
    param([string]$Path, [string]$Label)
    if (!(Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label does not exist: $Path"
    }
}

function Test-BinaryContainsAscii {
    param([string]$Path, [string]$Text)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $needle = [System.Text.Encoding]::ASCII.GetBytes($Text)
    if ($needle.Length -eq 0 -or $bytes.Length -lt $needle.Length) {
        return $false
    }

    for ($i = 0; $i -le ($bytes.Length - $needle.Length); $i++) {
        $matched = $true
        for ($j = 0; $j -lt $needle.Length; $j++) {
            if ($bytes[$i + $j] -ne $needle[$j]) {
                $matched = $false
                break
            }
        }
        if ($matched) {
            return $true
        }
    }

    return $false
}

function Require-RustRuntimeMarker {
    param([string]$Path, [string]$Marker)

    if (!(Test-BinaryContainsAscii -Path $Path -Text $Marker)) {
        throw "CLI Rust runtime DLL is stale or missing required marker '$Marker': $Path"
    }
}

function Reset-OutputDirectory {
    param([string]$Path)

    $absoluteOutput = [System.IO.Path]::GetFullPath($Path)
    $absoluteRoot = [System.IO.Path]::GetFullPath($Root)
    if (!$absoluteOutput.StartsWith($absoluteRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputDirectory must stay inside the workspace: $absoluteOutput"
    }

    if (Test-Path -LiteralPath $absoluteOutput) {
        try {
            Remove-Item -LiteralPath $absoluteOutput -Recurse -Force
        } catch {
            $removeError = $_
            $quarantinePath = "$absoluteOutput.locked.$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
            Write-Warning "Could not delete existing dedicated package directory. Moving it aside: $quarantinePath"
            try {
                Move-Item -LiteralPath $absoluteOutput -Destination $quarantinePath -Force
            } catch {
                $moveError = $_
                throw "Could not reset dedicated package directory: $absoluteOutput. Close any running dedicated package process first. Delete error: $($removeError.Exception.Message). Move error: $($moveError.Exception.Message)"
            }
        }
    }
    New-Item -ItemType Directory -Path $absoluteOutput -Force | Out-Null
}

Require-Directory $CliBundleDirectory 'CLI bundle directory'
Require-File (Join-Path $CliBundleDirectory 'bin\kyber_cli.exe') 'kyber_cli.exe'
Require-File (Join-Path $CliBundleDirectory 'lib\rust_lib.dll') 'rust_lib.dll'
Require-Directory $ModulePath 'Kyber module directory'
$moduleDllPath = Join-Path $ModulePath 'Kyber.dll'
Require-File $moduleDllPath 'Kyber.dll'
Require-File (Join-Path $ModulePath 'vivoxsdk.dll') 'vivoxsdk.dll'
Require-File $CertificatePath 'ca_root.pem'
Require-File (Join-Path $PSScriptRoot 'run-dedicated.ps1') 'run-dedicated.ps1'
if (!(Test-BinaryContainsAscii -Path $moduleDllPath -Text 'isDirectId')) {
    throw "Kyber.dll is stale or missing direct server classification marker 'isDirectId': $moduleDllPath. Rebuild Module and run Module\scripts\stage_module.ps1 before packaging."
}

Reset-OutputDirectory $OutputDirectory

$packageRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$scriptsOut = Join-Path $packageRoot 'scripts'
$configOut = Join-Path $packageRoot 'config'
$moduleOut = Join-Path $packageRoot 'module_runtime'
$cliOut = Join-Path $packageRoot 'cli_bundle'
New-Item -ItemType Directory -Path $scriptsOut, $configOut, $moduleOut, $cliOut -Force | Out-Null

Copy-Item -LiteralPath $CliBundleDirectory -Destination $cliOut -Recurse -Force
$cliBundleOut = Join-Path $cliOut 'bundle'
$cliBinOut = Join-Path $cliBundleOut 'bin'
$cliLibOut = Join-Path $cliBundleOut 'lib'
$latestRustRuntime = Join-Path $Root 'CLI\rust\target\release\rust_lib.dll'
if (Test-Path -LiteralPath $latestRustRuntime -PathType Leaf) {
    Copy-Item -LiteralPath $latestRustRuntime -Destination (Join-Path $cliLibOut 'rust_lib.dll') -Force
} else {
    Write-Warning "Latest CLI Rust runtime DLL was not found; using bundled runtime: $latestRustRuntime"
}
Copy-Item -LiteralPath (Join-Path $cliLibOut 'rust_lib.dll') -Destination (Join-Path $cliBinOut 'rust_lib.dll') -Force
Require-RustRuntimeMarker -Path (Join-Path $cliBinOut 'rust_lib.dll') -Marker 'ActivationUI.exe'
Require-RustRuntimeMarker -Path (Join-Path $cliBinOut 'rust_lib.dll') -Marker 'Activation64.dll'
$maximaFallbackDirectory = Join-Path $Root 'CLI\dev_build\cli_bundle\bundle\bin'
foreach ($name in @('maxima-bootstrap.exe', 'maxima-service.exe')) {
    $target = Join-Path $cliBinOut $name
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        continue
    }

    $source = Join-Path $CliBundleDirectory "bin\$name"
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
        $source = Join-Path $maximaFallbackDirectory $name
    }
    Require-File $source $name
    Copy-Item -LiteralPath $source -Destination $target -Force
}
Copy-Item -LiteralPath (Join-Path $ModulePath 'Kyber.dll') -Destination $moduleOut -Force
Copy-Item -LiteralPath (Join-Path $ModulePath 'vivoxsdk.dll') -Destination $moduleOut -Force
Copy-Item -LiteralPath $CertificatePath -Destination $moduleOut -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'run-dedicated.ps1') -Destination $scriptsOut -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'run-dedicated.cmd') -Destination $scriptsOut -Force

$hostConfig = @"
# Copy this file to host.local.ps1 and edit local paths/settings.
`$GamePath = '$DefaultGamePath'
`$ServerName = '$DefaultServerName'
`$ServerPort = $DefaultServerPort
`$MaxPlayers = $DefaultMaxPlayers
`$Map = '$DefaultMap'
`$Mode = '$DefaultMode'
`$ServerPassword = ''
`$RawMods = ''
`$StartupCommands = ''
`$LicenseMode = 'refresh'
`$DenuvoToken = ''

# Optional:
# `$CredentiallessHost = `$true
"@
Set-Content -LiteralPath (Join-Path $configOut 'host.example.ps1') -Value $hostConfig -Encoding ascii
Copy-Item -LiteralPath (Join-Path $configOut 'host.example.ps1') -Destination (Join-Path $configOut 'host.local.ps1') -Force

$clientConfig = @"
# Copy this file to client.local.ps1 on each joining PC and edit local paths/settings.
`$GamePath = '$DefaultGamePath'
`$ServerAddress = ''
`$ServerPort = $DefaultServerPort
`$ServerPassword = ''
`$RawMods = ''
"@
Set-Content -LiteralPath (Join-Path $configOut 'client.example.ps1') -Value $clientConfig -Encoding ascii
Copy-Item -LiteralPath (Join-Path $configOut 'client.example.ps1') -Destination (Join-Path $configOut 'client.local.ps1') -Force

$hostWrapper = @'
param(
    [string]$GamePath = '',
    [switch]$CredentiallessHost,
    [string]$ServerName = '',
    [int]$ServerPort = 0,
    [int]$MaxPlayers = 0,
    [string]$Map = '',
    [string]$Mode = '',
    [string]$ServerPassword = '',
    [string]$RawMods = '',
    [string]$StartupCommands = '',
    [ValidateSet('reuse', 'refresh')]
    [string]$LicenseMode = '',
    [string]$DenuvoToken = '',
    [int]$ReadyTimeoutSeconds = 180,
    [switch]$ShowConsole,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$PackageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$credentiallessParam = $CredentiallessHost.IsPresent
$config = Join-Path $PackageRoot 'config\host.local.ps1'
if (Test-Path -LiteralPath $config) {
    . $config
}

function Pick-String($Value, $Fallback) {
    if (![string]::IsNullOrWhiteSpace($Value)) { return $Value }
    return $Fallback
}

function Pick-Int($Value, $Fallback) {
    if ($Value -gt 0) { return $Value }
    return $Fallback
}

$resolvedGamePath = Pick-String $PSBoundParameters['GamePath'] $GamePath
$resolvedServerName = Pick-String $PSBoundParameters['ServerName'] $ServerName
$resolvedServerPort = Pick-Int $PSBoundParameters['ServerPort'] $ServerPort
$resolvedMaxPlayers = Pick-Int $PSBoundParameters['MaxPlayers'] $MaxPlayers
$resolvedMap = Pick-String $PSBoundParameters['Map'] $Map
$resolvedMode = Pick-String $PSBoundParameters['Mode'] $Mode
$resolvedPassword = Pick-String $PSBoundParameters['ServerPassword'] $ServerPassword
$resolvedRawMods = Pick-String $PSBoundParameters['RawMods'] $RawMods
$resolvedStartupCommands = Pick-String $PSBoundParameters['StartupCommands'] $StartupCommands
$resolvedLicenseMode = Pick-String $PSBoundParameters['LicenseMode'] $LicenseMode
$resolvedDenuvoToken = Pick-String $PSBoundParameters['DenuvoToken'] $DenuvoToken
$resolvedCredentialless = $credentiallessParam -or (($CredentiallessHost -as [bool]) -eq $true)

$params = @{
    Action = 'Host'
    CliExe = Join-Path $PackageRoot 'cli_bundle\bundle\bin\kyber_cli.exe'
    ModulePath = Join-Path $PackageRoot 'module_runtime'
    GamePath = $resolvedGamePath
    ServerName = $resolvedServerName
    ServerPort = $resolvedServerPort
    MaxPlayers = $resolvedMaxPlayers
    Map = $resolvedMap
    Mode = $resolvedMode
    LicenseMode = $resolvedLicenseMode
    ReadyTimeoutSeconds = $ReadyTimeoutSeconds
}
if (![string]::IsNullOrWhiteSpace($resolvedPassword)) { $params.ServerPassword = $resolvedPassword }
if (![string]::IsNullOrWhiteSpace($resolvedRawMods)) { $params.RawMods = $resolvedRawMods }
if (![string]::IsNullOrWhiteSpace($resolvedStartupCommands)) { $params.StartupCommands = $resolvedStartupCommands }
if (![string]::IsNullOrWhiteSpace($resolvedDenuvoToken)) {
    [Environment]::SetEnvironmentVariable('KYBER_DEDICATED_DENUVO_TOKEN', $resolvedDenuvoToken, 'Process')
}
if ($resolvedCredentialless) { $params.CredentiallessHost = $true }
if ($ShowConsole.IsPresent) { $params.ShowConsole = $true }
if ($ValidateOnly.IsPresent) { $params.ValidateOnly = $true }

& (Join-Path $PackageRoot 'scripts\run-dedicated.ps1') @params
exit $LASTEXITCODE
'@
Set-Content -LiteralPath (Join-Path $scriptsOut 'start-host.ps1') -Value $hostWrapper -Encoding ascii

$joinWrapper = @'
param(
    [string]$GamePath = '',
    [string]$ServerAddress = '',
    [int]$ServerPort = 0,
    [string]$ServerPassword = '',
    [string]$RawMods = '',
    [switch]$ShowConsole,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$PackageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$config = Join-Path $PackageRoot 'config\client.local.ps1'
if (Test-Path -LiteralPath $config) {
    . $config
}

function Pick-String($Value, $Fallback) {
    if (![string]::IsNullOrWhiteSpace($Value)) { return $Value }
    return $Fallback
}

function Pick-Int($Value, $Fallback) {
    if ($Value -gt 0) { return $Value }
    return $Fallback
}

$resolvedGamePath = Pick-String $PSBoundParameters['GamePath'] $GamePath
$resolvedServerAddress = Pick-String $PSBoundParameters['ServerAddress'] $ServerAddress
$resolvedServerPort = Pick-Int $PSBoundParameters['ServerPort'] $ServerPort
$resolvedPassword = Pick-String $PSBoundParameters['ServerPassword'] $ServerPassword
$resolvedRawMods = Pick-String $PSBoundParameters['RawMods'] $RawMods

$params = @{
    Action = 'Join'
    CliExe = Join-Path $PackageRoot 'cli_bundle\bundle\bin\kyber_cli.exe'
    ModulePath = Join-Path $PackageRoot 'module_runtime'
    GamePath = $resolvedGamePath
    ServerAddress = $resolvedServerAddress
    ServerPort = $resolvedServerPort
}
if (![string]::IsNullOrWhiteSpace($resolvedPassword)) { $params.ServerPassword = $resolvedPassword }
if (![string]::IsNullOrWhiteSpace($resolvedRawMods)) { $params.RawMods = $resolvedRawMods }
if ($ShowConsole.IsPresent) { $params.ShowConsole = $true }
if ($ValidateOnly.IsPresent) { $params.ValidateOnly = $true }

& (Join-Path $PackageRoot 'scripts\run-dedicated.ps1') @params
exit $LASTEXITCODE
'@
Set-Content -LiteralPath (Join-Path $scriptsOut 'join-server.ps1') -Value $joinWrapper -Encoding ascii

Set-Content -LiteralPath (Join-Path $packageRoot 'start-host.cmd') -Value '@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0scripts\start-host.ps1" %*
' -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot 'stop-host.cmd') -Value '@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0scripts\run-dedicated.ps1" -Action Stop %*
' -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot 'cleanup-host.cmd') -Value '@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0scripts\run-dedicated.ps1" -Action Cleanup %*
' -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot 'status-host.cmd') -Value '@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0scripts\run-dedicated.ps1" -Action Status %*
' -Encoding ascii
Set-Content -LiteralPath (Join-Path $packageRoot 'join-server.cmd') -Value '@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0scripts\join-server.ps1" %*
' -Encoding ascii

$readme = @'
# Kyber Windows Direct Host Package

Launcher users:
1. Run kyber_launcher.exe.
2. Sign in through the normal EA/Maxima launcher flow if this machine has not signed in before.
3. Open Settings > Accounts & Updates > BFII Dedicated Host.
4. Select the BFII executable path and use the bundled dedicated_runtime folder.

No credentials are included in this package. Direct EA/Maxima password login is disabled in shipping builds; the host uses the normal EA OAuth/Maxima session already stored by the Launcher.

Host machine:
1. Edit `config\host.local.ps1`.
2. Run `start-host.cmd`, or configure the host from the Launcher UI instead.
3. Share the printed `Join address` with other Windows clients.
4. Use `status-host.cmd`, `stop-host.cmd`, and `cleanup-host.cmd` to inspect, stop, or force-clean the host.

Process cleanup:
- `status-host.cmd` reports the managed host plus orphaned BFII/Kyber helper processes from failed or debug launches.
- `cleanup-host.cmd` stops orphaned BFII, ActivationUI, kyber_cli, maxima-bootstrap, and MaximaBackgroundService state before a new host launch.
- Launcher host startup passes `-CleanupOrphans` automatically, so accidental stale host/client processes are cleaned before startup.

License mode:
- `refresh` is the default. It uses the normal EA OAuth/Maxima session to regenerate the local BFII license before host startup.
- `reuse` is an advanced option. It is faster, but stale or machine-mismatched licenses can fail with BFII activation errors.
- `DenuvoToken` is an advanced optional override and is never printed by the scripts.

Joining machine:
1. Copy this package to the joining PC.
2. Edit `config\client.local.ps1` and set `ServerAddress` to the host IP.
3. Run `join-server.cmd`.

Network:
- Open inbound UDP 25200 by default, or the selected host port, on the host firewall/router.
- All players must use the same package/module build.
- The host machine runs the BFII host process and cannot also run a local BFII player client at the same time.
'@
Set-Content -LiteralPath (Join-Path $packageRoot 'README.md') -Value $readme -Encoding ascii

Write-Host "Windows dedicated package created: $packageRoot"
Write-Host "Host entry: $packageRoot\start-host.cmd"
Write-Host "Client entry: $packageRoot\join-server.cmd"

if (!$NoZip.IsPresent) {
    $zipPath = "$packageRoot.zip"
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -Force
    Write-Host "Package zip: $zipPath"
}
