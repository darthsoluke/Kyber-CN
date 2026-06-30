param(
    [ValidateSet('Host', 'Status', 'Stop', 'Join', 'ProvisionLicense')]
    [string]$Action = 'Host',

    [string]$Distro = 'KyberDedicated',
    [string]$WslUser = 'kyber',
    [string]$GamePath = '',
    [string]$ModulePath = '',
    [string]$CliBinPath = '',
    [string]$Credentials = '',
    [switch]$CredentiallessHost,
    [string]$LicenseImportDirectory = '',
    [string]$ContentId = '',
    [string]$ServerAddress = '',
    [string]$ServerName = '',
    [int]$ServerPort = 0,
    [int]$ServerInterfacePort = 0,
    [int]$ClientInterfacePort = 0,
    [int]$MaxPlayers = 0,
    [string]$Map = '',
    [string]$Mode = '',
    [string]$ServerPassword = '',
    [string]$RawMods = '',
    [string]$CollectionFile = '',
    [string]$CollectionModsDirectory = '',
    [string]$ModFolder = '',
    [string]$StartupCommands = '',
    [string[]]$GameArgs = @(),
    [int]$ReadyTimeoutSeconds = 300,
    [switch]$ShowConsole,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LogDirectory = Join-Path $Root 'CLI\dev_build\wsl_dedicated_logs'
$PidFile = Join-Path $LogDirectory 'server.pid'
$EnvFile = Join-Path $LogDirectory 'server.env'
$GameArgsFile = Join-Path $LogDirectory 'game_args.txt'
$LatestStdoutPath = Join-Path $LogDirectory 'latest.stdout.path'
$LatestStderrPath = Join-Path $LogDirectory 'latest.stderr.path'
$ServerScript = Join-Path $PSScriptRoot 'run-wsl-dedicated-server.sh'

function Get-Setting {
    param(
        [string]$Value,
        [string[]]$EnvNames,
        [string]$Default
    )

    if (![string]::IsNullOrWhiteSpace($Value)) {
        return $Value.Trim()
    }

    foreach ($envName in $EnvNames) {
        $envValue = [Environment]::GetEnvironmentVariable($envName)
        if (![string]::IsNullOrWhiteSpace($envValue)) {
            return $envValue.Trim()
        }

        foreach ($target in @('User', 'Machine')) {
            $envValue = [Environment]::GetEnvironmentVariable($envName, $target)
            if (![string]::IsNullOrWhiteSpace($envValue)) {
                return $envValue.Trim()
            }
        }
    }

    return $Default
}

function Get-IntSetting {
    param(
        [int]$Value,
        [string[]]$EnvNames,
        [int]$Default
    )

    if ($Value -gt 0) {
        return $Value
    }

    foreach ($envName in $EnvNames) {
        $envValue = [Environment]::GetEnvironmentVariable($envName)
        if (![string]::IsNullOrWhiteSpace($envValue)) {
            $parsed = 0
            if (![int]::TryParse($envValue, [ref]$parsed) -or $parsed -le 0) {
                throw "$envName must be a positive integer, got '$envValue'."
            }

            return $parsed
        }

        foreach ($target in @('User', 'Machine')) {
            $envValue = [Environment]::GetEnvironmentVariable($envName, $target)
            if (![string]::IsNullOrWhiteSpace($envValue)) {
                $parsed = 0
                if (![int]::TryParse($envValue, [ref]$parsed) -or $parsed -le 0) {
                    throw "$envName must be a positive integer, got '$envValue'."
                }

                return $parsed
            }
        }
    }

    return $Default
}

function Get-BoolEnvironmentSetting {
    param([string[]]$EnvNames)

    foreach ($envName in $EnvNames) {
        foreach ($target in @('', 'User', 'Machine')) {
            $envValue = if ($target -eq '') {
                [Environment]::GetEnvironmentVariable($envName)
            } else {
                [Environment]::GetEnvironmentVariable($envName, $target)
            }

            if ([string]::IsNullOrWhiteSpace($envValue)) {
                continue
            }

            switch ($envValue.Trim().ToLowerInvariant()) {
                '1' { return $true }
                'true' { return $true }
                'yes' { return $true }
                '0' { return $false }
                'false' { return $false }
                'no' { return $false }
                default {
                    throw "$envName must be 1 or 0, got '$envValue'."
                }
            }
        }
    }

    return $false
}

function Require-File {
    param([string]$Path, [string]$Label)

    if (Test-IsWslPath $Path) {
        $pathLiteral = Quote-Bash $Path
        $result = Invoke-WslBash -Script "test -f $pathLiteral" -AllowFailure
        if ($result.ExitCode -ne 0) {
            throw "$Label does not exist in WSL: $Path"
        }
        return
    }

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label does not exist: $Path"
    }
}

function Require-Directory {
    param([string]$Path, [string]$Label)

    if (Test-IsWslPath $Path) {
        $pathLiteral = Quote-Bash $Path
        $result = Invoke-WslBash -Script "test -d $pathLiteral" -AllowFailure
        if ($result.ExitCode -ne 0) {
            throw "$Label does not exist in WSL: $Path"
        }
        return
    }

    if (!(Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label does not exist: $Path"
    }
}

function Require-Port {
    param([int]$Port, [string]$Label)

    if ($Port -le 0 -or $Port -gt 65535) {
        throw "$Label must be between 1 and 65535, got $Port."
    }
}

function ConvertTo-WslPath {
    param([string]$Path)

    if (Test-IsWslPath $Path) {
        return $Path
    }

    $absolute = [System.IO.Path]::GetFullPath($Path)
    if ($absolute -notmatch '^([A-Za-z]):\\?(.*)$') {
        throw "Only Windows drive paths can be converted to WSL paths: $Path"
    }

    $drive = $Matches[1].ToLowerInvariant()
    $rest = ($Matches[2] -replace '\\', '/').TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($rest)) {
        return "/mnt/$drive"
    }

    return "/mnt/$drive/$rest"
}

function Test-IsWslPath {
    param([string]$Path)

    return $Path -match '^/'
}

function Quote-Bash {
    param([string]$Value)

    return "'" + (($Value -split "'", -1) -join "'\''") + "'"
}

function New-BashAssignment {
    param([string]$Name, [string]$Value)

    return "$Name=$(Quote-Bash $Value)"
}

function Invoke-WslBash {
    param(
        [string]$Script,
        [string[]]$BashArgs = @(),
        [switch]$AllowFailure
    )

    $encodedScript = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
    $runner = 'printf %s ' + (Quote-Bash $encodedScript) + ' | base64 -d | bash -s --'
    $output = & wsl.exe -d $script:Distro --exec bash -lc $runner bash @BashArgs 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and !$AllowFailure.IsPresent) {
        throw "WSL command failed with exit code $exitCode.`n$output"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Test-WslDistro {
    $result = Invoke-WslBash -Script 'true' -AllowFailure
    if ($result.ExitCode -ne 0) {
        throw "WSL distro '$Distro' is not available. Run scripts\setup-wsl-dedicated-env.sh after importing the distro."
    }
}

function Test-WslRuntimeUser {
    if ([string]::IsNullOrWhiteSpace($script:WslUser)) {
        return
    }

    $userLiteral = Quote-Bash $script:WslUser
    $result = Invoke-WslBash -Script "id -u $userLiteral >/dev/null 2>&1" -AllowFailure
    if ($result.ExitCode -ne 0) {
        throw "WSL runtime user '$($script:WslUser)' is not available. Run scripts\setup-wsl-dedicated-env.sh in the WSL distro."
    }
}

function Get-WslIpAddress {
    $result = Invoke-WslBash -Script 'hostname -I | awk ''{print $1}'''
    $ip = (($result.Output | Select-Object -First 1) -as [string]).Trim()
    if ([string]::IsNullOrWhiteSpace($ip)) {
        throw "Unable to resolve WSL IP address for distro '$Distro'."
    }

    return $ip
}

function Stage-WslModuleRuntime {
    param([string]$SourcePath)

    $sourceWsl = ConvertTo-WslPath $SourcePath
    if ((Test-IsWslPath $SourcePath) -and ($SourcePath -notmatch '^/mnt/')) {
        return $SourcePath
    }

    $scriptText = @'
set -euo pipefail
user=__USER__
src=__SOURCE__

if [[ ! -d "$src" ]]; then
  echo "Kyber module source directory does not exist: $src" >&2
  exit 66
fi
if [[ ! -f "$src/Kyber.dll" ]]; then
  echo "Kyber.dll is missing from module source directory: $src" >&2
  exit 66
fi
if [[ ! -f "$src/vivoxsdk.dll" ]]; then
  echo "vivoxsdk.dll is missing from module source directory: $src" >&2
  exit 66
fi

home_dir="$(getent passwd "$user" | cut -d: -f6)"
if [[ -z "$home_dir" ]]; then
  echo "Unable to resolve home directory for WSL user: $user" >&2
  exit 66
fi

stage_root="$home_dir/.kyber-dedicated"
stage="$stage_root/module_runtime"
tmp="$stage_root/module_runtime.tmp.$$"
prev="$stage_root/module_runtime.prev"

rm -rf "$tmp"
mkdir -p "$tmp"
cp -a "$src"/. "$tmp"/
chown -R "$user" "$tmp" 2>/dev/null || true

rm -rf "$prev"
if [[ -e "$stage" ]]; then
  mv "$stage" "$prev"
fi
mv "$tmp" "$stage"
rm -rf "$prev"

echo "$stage"
'@.
        Replace('__USER__', (Quote-Bash $script:WslUser)).
        Replace('__SOURCE__', (Quote-Bash $sourceWsl))

    $result = Invoke-WslBash -Script $scriptText
    $stagePath = (($result.Output | Select-Object -Last 1) -as [string]).Trim()
    if ([string]::IsNullOrWhiteSpace($stagePath)) {
        throw 'Failed to stage Kyber module runtime into WSL ext4.'
    }

    return $stagePath
}

function Get-WslServerPid {
    param([string]$PidFileWsl)

    $pidFileLiteral = Quote-Bash $PidFileWsl
    $scriptText = @'
pidfile=__PIDFILE__
if [[ ! -f "$pidfile" ]]; then
  exit 1
fi
pid="$(cat "$pidfile" 2>/dev/null || true)"
if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
  echo "$pid"
  exit 0
fi
exit 1
'@.Replace('__PIDFILE__', $pidFileLiteral)

    $result = Invoke-WslBash -Script $scriptText -AllowFailure
    if ($result.ExitCode -ne 0) {
        return $null
    }

    return (($result.Output | Select-Object -First 1) -as [string]).Trim()
}

function Stop-WslServer {
    param([string]$PidFileWsl)

    $pidFileLiteral = Quote-Bash $PidFileWsl
    $userLiteral = Quote-Bash $script:WslUser
    $scriptText = @'
pidfile=__PIDFILE__
run_user=__USER__
if [[ ! -f "$pidfile" ]]; then
  status="not running"
else
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
    rm -f "$pidfile"
    status="removed stale pid file"
  else
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      for _ in $(seq 1 15); do
        if ! kill -0 "$pid" 2>/dev/null; then
          break
        fi
        sleep 1
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
      fi
    fi

    rm -f "$pidfile"
    status="stopped"
  fi
fi

if id "$run_user" >/dev/null 2>&1; then
  patterns=(
    'starwarsbattlefrontii.exe'
    'umu-run .*starwarsbattlefrontii.exe'
    'proton waitforexitandrun .*starwarsbattlefrontii.exe'
    'c:\\windows\\system32\\umu.exe .*starwarsbattlefrontii.exe'
  )
  for pattern in "${patterns[@]}"; do
    pkill -TERM -u "$run_user" -f "$pattern" 2>/dev/null || true
  done
  sleep 2
  for pattern in "${patterns[@]}"; do
    pkill -KILL -u "$run_user" -f "$pattern" 2>/dev/null || true
  done

  home_dir="$(getent passwd "$run_user" | cut -d: -f6)"
  wineserver="$home_dir/.local/share/maxima/wine/proton/files/bin/wineserver"
  if [[ -x "$wineserver" ]]; then
    runuser -u "$run_user" -- env WINEPREFIX="$home_dir/.local/share/maxima/wine/prefix" "$wineserver" -k 2>/dev/null || true
  fi
fi

echo "$status"
'@.
        Replace('__PIDFILE__', $pidFileLiteral).
        Replace('__USER__', $userLiteral)

    return Invoke-WslBash -Script $scriptText
}

function Get-LatestLogPath {
    param([string]$PointerPath)

    if (!(Test-Path -LiteralPath $PointerPath -PathType Leaf)) {
        return ''
    }

    return (Get-Content -LiteralPath $PointerPath -Raw).Trim()
}

function Show-Status {
    param([string]$PidFileWsl)

    $serverPid = Get-WslServerPid -PidFileWsl $PidFileWsl
    $ip = Get-WslIpAddress
    $stdoutPath = Get-LatestLogPath -PointerPath $LatestStdoutPath
    $stderrPath = Get-LatestLogPath -PointerPath $LatestStderrPath

    Write-Host "WSL distro: $Distro"
    Write-Host "WSL IP: $ip"
    if ($serverPid) {
        Write-Host "BFII host server: running (PID: $serverPid)"
        Write-Host "Join command:"
        Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-wsl-dedicated.ps1 -Action Join -ServerAddress $ip -ServerPort $ServerPort"
    } else {
        Write-Host 'BFII host server: not running'
    }

    if (![string]::IsNullOrWhiteSpace($stdoutPath)) {
        Write-Host "stdout: $stdoutPath"
    }
    if (![string]::IsNullOrWhiteSpace($stderrPath)) {
        Write-Host "stderr: $stderrPath"
    }
}

function Add-OptionalAssignment {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Name,
        [string]$Value
    )

    if (![string]::IsNullOrWhiteSpace($Value)) {
        $Lines.Add((New-BashAssignment $Name $Value))
    }
}

function Add-OptionalPathAssignment {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Name,
        [string]$Path,
        [string]$Label,
        [bool]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if ($Directory) {
        Require-Directory $Path $Label
    } else {
        Require-File $Path $Label
    }

    $Lines.Add((New-BashAssignment $Name (ConvertTo-WslPath $Path)))
}

function Write-ServerEnvFile {
    param(
        [string]$EnvFilePath,
        [string]$GameArgsFilePath
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    Add-OptionalAssignment $lines 'KYBER_WSL_RUN_USER' $script:WslUser
    $lines.Add((New-BashAssignment 'KYBER_CLI_BIN' (ConvertTo-WslPath $script:CliBinPath)))
    $lines.Add((New-BashAssignment 'KYBER_GAME_PATH' (ConvertTo-WslPath $script:GamePath)))
    if (!$script:ProvisionLicense) {
        $lines.Add((New-BashAssignment 'KYBER_MODULE_DIR' (ConvertTo-WslPath $script:EffectiveModulePath)))
    }
    $lines.Add((New-BashAssignment 'KYBER_PROVISION_LICENSE_ONLY' ($(if ($script:ProvisionLicense) { '1' } else { '0' }))))
    $lines.Add((New-BashAssignment 'KYBER_CONTENT_ID' $script:ContentId))
    $lines.Add((New-BashAssignment 'KYBER_CREDENTIALLESS_HOST' ($(if ($script:CredentiallessHost) { '1' } else { '0' }))))
    if (!$script:ProvisionLicense) {
        Add-OptionalPathAssignment $lines 'KYBER_LICENSE_IMPORT_DIR' $script:LicenseImportDirectory 'BFII license import directory' $true
        $lines.Add((New-BashAssignment 'KYBER_SERVER_NAME' $script:ServerName))
        $lines.Add((New-BashAssignment 'KYBER_SERVER_MAP' $script:Map))
        $lines.Add((New-BashAssignment 'KYBER_SERVER_MODE' $script:Mode))
        $lines.Add((New-BashAssignment 'KYBER_SERVER_PORT' ($script:ServerPort).ToString()))
        $lines.Add((New-BashAssignment 'KYBER_SERVER_MAX_PLAYERS' ($script:MaxPlayers).ToString()))
        $lines.Add((New-BashAssignment 'KYBER_SERVER_INTERFACE_PORT' ($script:ServerInterfacePort).ToString()))
        $lines.Add((New-BashAssignment 'KYBER_DEDICATED_READY_TIMEOUT_SECONDS' ($ReadyTimeoutSeconds).ToString()))
        $lines.Add((New-BashAssignment 'KYBER_SHOW_CONSOLE' ($(if ($ShowConsole.IsPresent) { '1' } else { '0' }))))

        Add-OptionalAssignment $lines 'KYBER_SERVER_PASSWORD' $script:ServerPassword
        Add-OptionalPathAssignment $lines 'KYBER_RAW_MODS' $script:RawMods 'Raw mods manifest' $false
        Add-OptionalPathAssignment $lines 'KYBER_COLLECTION_FILE' $script:CollectionFile 'Collection file' $false
        Add-OptionalPathAssignment $lines 'KYBER_COLLECTION_MODS_DIRECTORY' $script:CollectionModsDirectory 'Collection mods directory' $true
        Add-OptionalPathAssignment $lines 'KYBER_MOD_FOLDER' $script:ModFolder 'Mod folder' $true
        Add-OptionalPathAssignment $lines 'KYBER_STARTUP_COMMANDS' $script:StartupCommands 'Startup commands file' $false
    }

    if ($script:GameArgs.Count -gt 0) {
        [System.IO.File]::WriteAllText(
            $GameArgsFilePath,
            (($script:GameArgs -join "`n") + "`n"),
            [Text.Encoding]::ASCII
        )
        $lines.Add((New-BashAssignment 'KYBER_GAME_ARGS_FILE' (ConvertTo-WslPath $GameArgsFilePath)))
    } elseif (Test-Path -LiteralPath $GameArgsFilePath) {
        Remove-Item -LiteralPath $GameArgsFilePath -Force
    }

    [System.IO.File]::WriteAllText(
        $EnvFilePath,
        (($lines -join "`n") + "`n"),
        [Text.Encoding]::ASCII
    )
}

function Wait-ForReady {
    param(
        [string]$PidFileWsl,
        [string]$StdoutPath,
        [string]$StderrPath,
        [int]$TimeoutSeconds
    )

    Write-Host "Waiting for isolated BFII host-server readiness. Log: $StdoutPath"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastProgress = Get-Date
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2

        if (((Get-Date) - $lastProgress).TotalSeconds -ge 10) {
            Write-Host 'Still waiting for BFII host-server ready marker...'
            $lastProgress = Get-Date
        }

        $serverPid = Get-WslServerPid -PidFileWsl $PidFileWsl
        if (!$serverPid) {
            $stdoutTail = if (Test-Path -LiteralPath $StdoutPath) { Get-Content -LiteralPath $StdoutPath -Tail 60 -ErrorAction SilentlyContinue } else { @() }
            $stderrTail = if (Test-Path -LiteralPath $StderrPath) { Get-Content -LiteralPath $StderrPath -Tail 60 -ErrorAction SilentlyContinue } else { @() }
            throw "Isolated BFII host server exited before readiness.`nstdout tail:`n$stdoutTail`nstderr tail:`n$stderrTail"
        }

        if (!(Test-Path -LiteralPath $StdoutPath) -and !(Test-Path -LiteralPath $StderrPath)) {
            continue
        }

        $stdoutContent = if (Test-Path -LiteralPath $StdoutPath) { Get-Content -LiteralPath $StdoutPath -Raw -ErrorAction SilentlyContinue } else { '' }
        $stderrContent = if (Test-Path -LiteralPath $StderrPath) { Get-Content -LiteralPath $StderrPath -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($stdoutContent -match 'Dedicated server ready:') {
            return
        }

        $failureContent = "$stdoutContent`n$stderrContent"
        if ($failureContent -match 'Dedicated server did not become ready|Failed to start Maxima runtime|module-path is missing|required runtime file|Login failed|Invalid credentials|credentialless launch requires|Activation64\.dll.*failed|Failed to run wine command|Game process exited before LSX ChallengeResponse') {
            throw "BFII host server failed during startup. See $StdoutPath and $StderrPath."
        }
    }

    throw "BFII host server was not ready after $TimeoutSeconds seconds. See $StdoutPath and $StderrPath."
}

$script:Distro = $Distro
$script:WslUser = Get-Setting $WslUser @('KYBER_WSL_RUN_USER') 'kyber'
$script:GamePath = Get-Setting $GamePath @('KYBER_GAME_PATH') 'D:\Games\STAR WARS Battlefront II\starwarsbattlefrontii.exe'
$script:ModulePath = Get-Setting $ModulePath @('KYBER_MODULE_DIR') (Join-Path $Root 'CLI\dev_build\module_runtime')
$script:EffectiveModulePath = $script:ModulePath
$script:CliBinPath = Get-Setting $CliBinPath @('KYBER_WSL_CLI_BIN') (Join-Path $Root 'CLI\build\cli\linux_x64\bundle\bin')
$script:Credentials = Get-Setting $Credentials @('KYBER_BFII_HOST_CREDENTIALS', 'KYBER_DEDICATED_CREDENTIALS', 'MAXIMA_CREDENTIALS') ''
$script:ProvisionLicense = $Action -eq 'ProvisionLicense'
$script:ContentId = Get-Setting $ContentId @('KYBER_CONTENT_ID') '1035052'
$script:CredentiallessHost = $CredentiallessHost.IsPresent -or (Get-BoolEnvironmentSetting @('KYBER_CREDENTIALLESS_HOST'))

if ($script:ProvisionLicense) {
    $script:CredentiallessHost = $false
    if ([string]::IsNullOrWhiteSpace($script:Credentials)) {
        throw 'ProvisionLicense requires EA/Maxima credentials. Pass -Credentials "persona:password" or set KYBER_BFII_HOST_CREDENTIALS.'
    }
} elseif ([string]::IsNullOrWhiteSpace($script:Credentials)) {
    $script:CredentiallessHost = $true
}
if ($script:CredentiallessHost -and ![string]::IsNullOrWhiteSpace($script:Credentials)) {
    throw 'Credentialless host mode cannot be combined with EA/Maxima credentials.'
}
$script:LicenseImportDirectory = Get-Setting $LicenseImportDirectory @('KYBER_LICENSE_IMPORT_DIR', 'KYBER_WINDOWS_LICENSE_DIR') ''
$script:ServerAddress = Get-Setting $ServerAddress @('KYBER_SERVER_ADDRESS') ''
$script:ServerName = Get-Setting $ServerName @('KYBER_SERVER_NAME') 'WSL BFII Host Test'
$script:Map = Get-Setting $Map @('KYBER_SERVER_MAP') 'S5_1/Levels/MP/Geonosis_01/Geonosis_01'
$script:Mode = Get-Setting $Mode @('KYBER_SERVER_MODE') 'HeroesVersusVillains'
$script:ServerPassword = Get-Setting $ServerPassword @('KYBER_SERVER_PASSWORD') ''
$script:RawMods = Get-Setting $RawMods @('KYBER_RAW_MODS') ''
$script:CollectionFile = Get-Setting $CollectionFile @('KYBER_COLLECTION_FILE') ''
$script:CollectionModsDirectory = Get-Setting $CollectionModsDirectory @('KYBER_COLLECTION_MODS_DIRECTORY') ''
$script:ModFolder = Get-Setting $ModFolder @('KYBER_MOD_FOLDER') ''
$script:StartupCommands = Get-Setting $StartupCommands @('KYBER_STARTUP_COMMANDS') ''
$script:GameArgs = $GameArgs
$script:ServerPort = Get-IntSetting $ServerPort @('KYBER_SERVER_PORT') 25200
$script:ServerInterfacePort = Get-IntSetting $ServerInterfacePort @('KYBER_SERVER_INTERFACE_PORT') 19103
$script:ClientInterfacePort = Get-IntSetting $ClientInterfacePort @('KYBER_CLIENT_INTERFACE_PORT') 19104
$script:MaxPlayers = Get-IntSetting $MaxPlayers @('KYBER_SERVER_MAX_PLAYERS') 2

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
Test-WslDistro
Test-WslRuntimeUser
Require-Port $script:ServerPort 'ServerPort'
Require-Port $script:ServerInterfacePort 'ServerInterfacePort'
Require-Port $script:ClientInterfacePort 'ClientInterfacePort'

$pidFileWsl = ConvertTo-WslPath $PidFile

if ($Action -eq 'Status') {
    Show-Status -PidFileWsl $pidFileWsl
    exit 0
}

if ($Action -eq 'Stop') {
    $result = Stop-WslServer -PidFileWsl $pidFileWsl
    Write-Host (($result.Output | Out-String).Trim())
    exit 0
}

if ($Action -eq 'Join') {
    $joinAddress = $script:ServerAddress
    if ([string]::IsNullOrWhiteSpace($joinAddress)) {
        $joinAddress = Get-WslIpAddress
    }

    $joinParams = @{
        Action = 'Join'
        ServerAddress = $joinAddress
        ServerPort = $script:ServerPort
        GamePath = $script:GamePath
        ModulePath = $script:ModulePath
        ClientInterfacePort = $script:ClientInterfacePort
        ServerPassword = $script:ServerPassword
        RawMods = $script:RawMods
        GameArgs = $script:GameArgs
        ShowConsole = $ShowConsole.IsPresent
        ValidateOnly = $ValidateOnly.IsPresent
    }
    & (Join-Path $PSScriptRoot 'run-dedicated.ps1') @joinParams
    exit $LASTEXITCODE
}

Require-File $ServerScript 'WSL server script'
Require-Directory $script:CliBinPath 'Linux CLI bundle bin directory'
Require-File (Join-Path $script:CliBinPath 'kyber_cli') 'Linux kyber_cli'
Require-File (Join-Path $script:CliBinPath 'librust_lib.so') 'librust_lib.so'
Require-File (Join-Path $script:CliBinPath 'maxima-bootstrap') 'maxima-bootstrap'
Require-File (Join-Path $script:CliBinPath 'wine-helper.exe') 'wine-helper.exe'
Require-File $script:GamePath 'Battlefront II executable'
if (!$script:ProvisionLicense) {
    Require-Directory $script:ModulePath 'Kyber module directory'
    Require-File (Join-Path $script:ModulePath 'Kyber.dll') 'Kyber.dll'
    Require-File (Join-Path $script:ModulePath 'vivoxsdk.dll') 'vivoxsdk.dll'
}

if (!$script:CredentiallessHost) {
    if ([string]::IsNullOrWhiteSpace($script:Credentials)) {
        throw 'Credentials are required unless credentialless host mode is enabled.'
    }

    $credentialParts = $script:Credentials -split ':'
    if ($credentialParts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($credentialParts[0]) -or [string]::IsNullOrWhiteSpace($credentialParts[1])) {
        throw 'Credentials must use the exact persona:password format required by Maxima.'
    }
}
if (!$script:ProvisionLicense -and ![string]::IsNullOrWhiteSpace($script:LicenseImportDirectory)) {
    Require-Directory $script:LicenseImportDirectory 'BFII license import directory'
    Require-File (Join-Path $script:LicenseImportDirectory '1035052.dlf') 'BFII license file'
}

$existingPid = Get-WslServerPid -PidFileWsl $pidFileWsl
if ($existingPid) {
    throw "Isolated BFII host server is already running in WSL. PID: $existingPid. Use -Action Status or -Action Stop."
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdoutPath = Join-Path $LogDirectory "host_$timestamp.stdout.log"
$stderrPath = Join-Path $LogDirectory "host_$timestamp.stderr.log"
$stdoutWsl = ConvertTo-WslPath $stdoutPath
$stderrWsl = ConvertTo-WslPath $stderrPath
$envFileWsl = ConvertTo-WslPath $EnvFile
$serverScriptWsl = ConvertTo-WslPath $ServerScript

if ($ValidateOnly) {
    Write-Host 'Validation succeeded.'
    Write-Host "WSL distro: $Distro"
    Write-Host "WSL runtime user: $script:WslUser"
    Write-Host "Linux CLI bin: $script:CliBinPath"
    Write-Host "Game: $script:GamePath"
    Write-Host "Provision license: $(if ($script:ProvisionLicense) { 'yes' } else { 'no' })"
    Write-Host "Content ID: $script:ContentId"
    if (!$script:ProvisionLicense) {
        Write-Host "Module source: $script:ModulePath"
        Write-Host 'Module runtime will be staged into WSL ext4 before host startup.'
        Write-Host "Server port: $script:ServerPort"
        Write-Host "Interface port: $script:ServerInterfacePort"
    }
    Write-Host "Auth mode: $(if ($script:CredentiallessHost) { 'credentialless offline host' } else { 'EA/Maxima credentials' })"
    if (!$script:ProvisionLicense) {
        Write-Host "License import: $(if ([string]::IsNullOrWhiteSpace($script:LicenseImportDirectory)) { 'none' } else { $script:LicenseImportDirectory })"
    }
    exit 0
}

if (!$script:ProvisionLicense) {
    Write-Host 'Staging Kyber module runtime into WSL ext4...'
    $script:EffectiveModulePath = Stage-WslModuleRuntime -SourcePath $script:ModulePath
    Write-Host "WSL module runtime: $script:EffectiveModulePath"
}

Write-ServerEnvFile -EnvFilePath $EnvFile -GameArgsFilePath $GameArgsFile
Set-Content -LiteralPath $LatestStdoutPath -Value $stdoutPath -Encoding ascii
Set-Content -LiteralPath $LatestStderrPath -Value $stderrPath -Encoding ascii

if ($script:ProvisionLicense) {
    $provisionScript = 'set -euo pipefail; set -a; source ' +
        (Quote-Bash $envFileWsl) +
        '; set +a; export MAXIMA_CREDENTIALS=' +
        (Quote-Bash $script:Credentials) +
        '; bash ' +
        (Quote-Bash $serverScriptWsl)

    Write-Host 'Provisioning BFII license inside the WSL Wine prefix...'
    $result = Invoke-WslBash -Script $provisionScript
    Write-Host (($result.Output | Out-String).Trim())
    exit 0
}

$pidWriter = 'echo $$ > "$1"; exec bash "$2"'
$launchScript = 'set -euo pipefail; set -a; source ' +
    (Quote-Bash $envFileWsl) +
    '; set +a; ' +
    ($(if (!$script:CredentiallessHost) { 'export MAXIMA_CREDENTIALS=' + (Quote-Bash $script:Credentials) + '; ' } else { '' })) +
    'nohup setsid bash -c ' +
    (Quote-Bash $pidWriter) +
    ' _ ' +
    (Quote-Bash $pidFileWsl) +
    ' ' +
    (Quote-Bash $serverScriptWsl) +
    ' > ' +
    (Quote-Bash $stdoutWsl) +
    ' 2> ' +
    (Quote-Bash $stderrWsl) +
    ' < /dev/null & for _ in $(seq 1 20); do [[ -f ' +
    (Quote-Bash $pidFileWsl) +
    ' ]] && exit 0; sleep 0.1; done; exit 1'

if ($script:CredentiallessHost) {
    Write-Host 'Starting isolated BFII host server in WSL without EA/Maxima credentials...'
} else {
    Write-Host 'Starting isolated BFII host server in WSL with EA/Maxima credentials...'
}
Invoke-WslBash -Script $launchScript | Out-Null
try {
    Wait-ForReady -PidFileWsl $pidFileWsl -StdoutPath $stdoutPath -StderrPath $stderrPath -TimeoutSeconds $ReadyTimeoutSeconds
} catch {
    Stop-WslServer -PidFileWsl $pidFileWsl | Out-Null
    throw
}

$serverPid = Get-WslServerPid -PidFileWsl $pidFileWsl
$ip = Get-WslIpAddress
Write-Host "Isolated BFII host server ready. PID: $serverPid"
Write-Host "WSL IP: $ip"
Write-Host "Server: $ip`:$script:ServerPort"
Write-Host "stdout: $stdoutPath"
Write-Host "stderr: $stderrPath"
Write-Host "Join command:"
Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-wsl-dedicated.ps1 -Action Join -ServerAddress $ip -ServerPort $script:ServerPort"
