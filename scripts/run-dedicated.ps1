param(
    [ValidateSet('Host', 'Join', 'Status', 'Stop', 'Cleanup')]
    [string]$Action = 'Host',

    [string]$GamePath = '',
    [string]$ModulePath = '',
    [string]$CliExe = '',
    [string]$Credentials = '',
    [ValidateSet('reuse', 'refresh')]
    [string]$LicenseMode = '',
    [string]$DenuvoToken = '',
    [switch]$CredentiallessHost,
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
    [int]$ReadyTimeoutSeconds = 120,
    [int]$LogStallTimeoutSeconds = 0,
    [switch]$ShowConsole,
    [switch]$CleanupOrphans,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LogDirectory = if (Test-Path -LiteralPath (Join-Path $Root 'CLI') -PathType Container) {
    Join-Path $Root 'CLI\dev_build\one_click_logs'
} else {
    Join-Path $Root 'logs'
}
$PidFile = Join-Path $LogDirectory 'dedicated_host.pid'
$LatestStdoutPath = Join-Path $LogDirectory 'latest.stdout.path'
$LatestStderrPath = Join-Path $LogDirectory 'latest.stderr.path'
$DefaultCliExe = Join-Path $Root 'cli_bundle\bundle\bin\kyber_cli.exe'
if (!(Test-Path -LiteralPath $DefaultCliExe -PathType Leaf)) {
    $DefaultCliExe = Join-Path $Root 'CLI\dev_build\cli_bundle\bundle\bin\kyber_cli.exe'
}
if (!(Test-Path -LiteralPath $DefaultCliExe -PathType Leaf)) {
    $DefaultCliExe = Join-Path $Root 'CLI\build\cli\windows_x64\bundle\bin\kyber_cli.exe'
}

$DefaultModulePath = Join-Path $Root 'module_runtime'
if (!(Test-Path -LiteralPath $DefaultModulePath -PathType Container)) {
    $DefaultModulePath = Join-Path $Root 'CLI\dev_build\module_runtime'
}

function Get-Setting {
    param(
        [string]$Value,
        [string]$EnvName,
        [string]$Default
    )

    if (![string]::IsNullOrWhiteSpace($Value)) {
        return $Value.Trim()
    }

    $envValue = [Environment]::GetEnvironmentVariable($EnvName)
    if (![string]::IsNullOrWhiteSpace($envValue)) {
        return $envValue.Trim()
    }

    return $Default
}

function Get-IntSetting {
    param(
        [int]$Value,
        [string]$EnvName,
        [int]$Default
    )

    if ($Value -gt 0) {
        return $Value
    }

    $envValue = [Environment]::GetEnvironmentVariable($EnvName)
    if (![string]::IsNullOrWhiteSpace($envValue)) {
        $parsed = 0
        if (![int]::TryParse($envValue, [ref]$parsed) -or $parsed -le 0) {
            throw "$EnvName must be a positive integer, got '$envValue'."
        }

        return $parsed
    }

    return $Default
}

function Get-BoolSetting {
    param(
        [bool]$Explicit,
        [string]$EnvName
    )

    if ($Explicit) {
        return $true
    }

    $envValue = [Environment]::GetEnvironmentVariable($EnvName)
    if ([string]::IsNullOrWhiteSpace($envValue)) {
        return $false
    }

    switch ($envValue.Trim().ToLowerInvariant()) {
        '1' { return $true }
        'true' { return $true }
        'yes' { return $true }
        '0' { return $false }
        'false' { return $false }
        'no' { return $false }
        default { throw "$EnvName must be 1 or 0, got '$envValue'." }
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

function Resolve-ExistingPath {
    param([string]$Path)

    return (Resolve-Path -LiteralPath $Path).Path
}

function Quote-PowerShellArgument {
    param([string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Copy-FileElevated {
    param(
        [string]$Source,
        [string]$Destination
    )

    $tempScript = Join-Path ([IO.Path]::GetTempPath()) "kyber-install-vivox-$PID.ps1"
    @'
param(
    [string]$Source,
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
Copy-Item -LiteralPath $Source -Destination $Destination -Force
'@ | Set-Content -LiteralPath $tempScript -Encoding ascii

    try {
        $argumentList = @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            (Quote-PowerShellArgument $tempScript),
            '-Source',
            (Quote-PowerShellArgument $Source),
            '-Destination',
            (Quote-PowerShellArgument $Destination)
        ) -join ' '

        $process = Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList $argumentList `
            -Verb RunAs `
            -Wait `
            -PassThru

        if ($process.ExitCode -ne 0) {
            throw "elevated copy exited with code $($process.ExitCode)"
        }
    } finally {
        Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-BfiiVivoxRuntime {
    param(
        [string]$GamePath,
        [string]$ModulePath
    )

    $source = Join-Path $ModulePath 'vivoxsdk.dll'
    $target = Join-Path (Split-Path -Parent $GamePath) 'vivoxsdk.dll'

    if (Test-Path -LiteralPath $target -PathType Leaf) {
        Write-Host "BFII Vivox runtime: present at $target"
        return
    }

    Write-Host "BFII Vivox runtime: missing at $target"
    Write-Host 'Installing BFII Vivox runtime dependency before host startup...'

    try {
        Copy-Item -LiteralPath $source -Destination $target -Force
        Write-Host "Installed BFII Vivox runtime: $target"
        return
    } catch {
        if (Test-IsAdministrator) {
            throw "Failed to install BFII Vivox runtime to $target. $($_.Exception.Message)"
        }
    }

    Write-Host 'BFII install directory requires administrator permission. Requesting UAC for one-time runtime install...' -ForegroundColor Yellow
    try {
        Copy-FileElevated -Source $source -Destination $target
    } catch {
        Exit-WithError "Failed to install BFII Vivox runtime to $target. Approve the UAC prompt, run Kyber Launcher as Administrator once, or install BFII outside Program Files. $($_.Exception.Message)"
    }

    if (!(Test-Path -LiteralPath $target -PathType Leaf)) {
        Exit-WithError "BFII Vivox runtime was not installed: $target"
    }

    Write-Host "Installed BFII Vivox runtime: $target"
}

function Require-Port {
    param([int]$Port, [string]$Label)

    if ($Port -le 0 -or $Port -gt 65535) {
        throw "$Label must be between 1 and 65535, got $Port."
    }
}

function Add-ValueArgument {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $Arguments.Add($Name)
    $Arguments.Add($Value)
}

function Add-FlagArgument {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [string]$Name,
        [bool]$Enabled
    )

    if ($Enabled) {
        $Arguments.Add($Name)
    }
}

function Add-GameArgs {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [string[]]$Values
    )

    foreach ($value in $Values) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        $Arguments.Add('--game-args')
        $Arguments.Add($value.Trim())
    }
}

function Quote-Argument {
    param([string]$Value)

    if ($Value -match '[\s"]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    return $Value
}

function Join-CommandLine {
    param([string[]]$Arguments)

    return ($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
}

function Get-LogByteCount {
    param([string[]]$Paths)

    $total = 0
    foreach ($path in $Paths) {
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if ($item) {
            $total += $item.Length
        }
    }

    return $total
}

function Get-LastNonEmptyLogLine {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        $lines = Get-Content -LiteralPath $path -Tail 20 -ErrorAction SilentlyContinue |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        if ($lines) {
            return ($lines | Select-Object -Last 1)
        }
    }

    return ''
}

function Test-LogLineIsNoise {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $true
    }

    $trimmed = $Line.Trim()
    if ($trimmed -eq '<asynchronous suspension>') {
        return $true
    }

    if ($trimmed -match '^#\d+\s+' -or $trimmed -match '^\s*at\s+') {
        return $true
    }

    if ($trimmed -match '^\s*\+\s*(CategoryInfo|FullyQualifiedErrorId)\s*:') {
        return $true
    }

    if ($trimmed -match '^~{8,}$') {
        return $true
    }

    if ($trimmed -match '^(Stack backtrace|note: run with|See also|Unhandled exception:)$') {
        return $true
    }

    return $false
}

function Get-MeaningfulLogLines {
    param(
        [string[]]$Paths,
        [int]$Tail = 120
    )

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $Paths) {
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        $lines = Get-Content -LiteralPath $path -Tail $Tail -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if (Test-LogLineIsNoise $line) {
                continue
            }

            $result.Add($line.Trim())
        }
    }

    return $result.ToArray()
}

function Write-StartupFailureDiagnostics {
    param(
        [string]$StdoutPath,
        [string]$StderrPath
    )

    Write-Host "Startup stdout log: $StdoutPath"
    Write-Host "Startup stderr log: $StderrPath"

    $stderrLines = Get-MeaningfulLogLines -Paths @($StderrPath) -Tail 160 |
        Select-Object -Last 16
    $stdoutLines = Get-MeaningfulLogLines -Paths @($StdoutPath) -Tail 160 |
        Select-Object -Last 16

    if ($stderrLines) {
        Write-Host 'Startup stderr tail:'
        foreach ($line in $stderrLines) {
            Write-Host "  $line"
        }
    }

    if ($stdoutLines) {
        Write-Host 'Startup stdout tail:'
        foreach ($line in $stdoutLines) {
            Write-Host "  $line"
        }
    }
}

function Get-StartupFailureSummary {
    param(
        [string]$StdoutPath,
        [string]$StderrPath
    )

    $rawStderr = if (Test-Path -LiteralPath $StderrPath -PathType Leaf) {
        Get-Content -LiteralPath $StderrPath -Raw -ErrorAction SilentlyContinue
    } else {
        ''
    }
    if ($rawStderr -match '<error code="([^"]+)"') {
        return "EA license request failed: $($Matches[1])"
    }

    $stderrMeaningful = Get-MeaningfulLogLines -Paths @($StderrPath) -Tail 160
    if ($stderrMeaningful -and $stderrMeaningful.Count -gt 0) {
        $selected = $stderrMeaningful | Select-Object -Last 8
        $oneLine = (($selected -join ' | ') -replace '\s+', ' ').Trim()
        if ($oneLine.Length -gt 720) {
            return $oneLine.Substring(0, 720) + '...'
        }

        return $oneLine
    }

    $stdoutMeaningful = Get-MeaningfulLogLines -Paths @($StdoutPath) -Tail 160
    if ($stdoutMeaningful -and $stdoutMeaningful.Count -gt 0) {
        $selected = $stdoutMeaningful | Select-Object -Last 8
        $oneLine = (($selected -join ' | ') -replace '\s+', ' ').Trim()
        if ($oneLine.Length -gt 720) {
            return $oneLine.Substring(0, 720) + '...'
        }

        return $oneLine
    }

    return Get-LastNonEmptyLogLine -Paths @($StdoutPath)
}

function Get-MaximaServiceBinaryPath {
    $output = & sc.exe qc MaximaBackgroundService 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ''
    }

    foreach ($line in $output) {
        if ($line -match '^\s*BINARY_PATH_NAME\s*:\s*(.+)$') {
            return $matches[1].Trim().Trim('"')
        }
    }

    return ''
}

function Show-MaximaServicePreflight {
    param([string]$CliBinDirectory)

    $expectedPath = [System.IO.Path]::GetFullPath((Join-Path $CliBinDirectory 'maxima-service.exe'))
    $installedPath = Get-MaximaServiceBinaryPath
    if ([string]::IsNullOrWhiteSpace($installedPath)) {
        Write-Host 'Maxima service is not installed; startup will install it and may show a Windows UAC prompt.'
        return
    }

    $installedPath = [System.IO.Path]::GetFullPath($installedPath)
    if ($installedPath -ieq $expectedPath) {
        Write-Host "Maxima service path matches current runtime: $expectedPath"
        return
    }

    Write-Host 'Maxima service path does not match the current runtime.' -ForegroundColor Yellow
    Write-Host "Installed service: $installedPath"
    Write-Host "Current runtime:    $expectedPath"
    Write-Host 'Startup will repair the service through Maxima. Accept the Windows UAC prompt, or run Kyber Launcher as Administrator once.'
}

function Stop-MaximaService {
    $service = Get-Service -Name 'MaximaBackgroundService' -ErrorAction SilentlyContinue
    if (!$service -or $service.Status -eq 'Stopped') {
        Get-Process -Name 'maxima-bootstrap' -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Get-Process -Name 'maxima-service' -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        return
    }

    Write-Host 'Stopping Maxima background service...'
    & sc.exe stop MaximaBackgroundService | Out-Null
    $deadline = (Get-Date).AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 500
        $service.Refresh()
        if ($service.Status -eq 'Stopped') {
            Get-Process -Name 'maxima-bootstrap' -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Get-Process -Name 'maxima-service' -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Host 'Maxima background service: stopped'
            return
        }
    } while ((Get-Date) -lt $deadline)

    Write-Host 'Maxima background service is still stopping; Windows may release it shortly.' -ForegroundColor Yellow
}

function Exit-WithError {
    param([string]$Message)

    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Get-ExistingDedicatedServerProcess {
    param([int]$Port)

    try {
        $endpoint = Get-NetUDPEndpoint -ErrorAction Stop |
            Where-Object { $_.LocalPort -eq $Port } |
            Select-Object -First 1
    } catch {
        return $null
    }

    if (!$endpoint) {
        return $null
    }

    $process = Get-Process -Id $endpoint.OwningProcess -ErrorAction SilentlyContinue
    if ($process -and $process.ProcessName -eq 'starwarsbattlefrontii') {
        return $process
    }

    return $null
}

function Get-PidFileProcess {
    if (!(Test-Path -LiteralPath $PidFile -PathType Leaf)) {
        return $null
    }

    $rawPid = (Get-Content -LiteralPath $PidFile -Raw -ErrorAction SilentlyContinue).Trim()
    $pidValue = 0
    if (![int]::TryParse($rawPid, [ref]$pidValue) -or $pidValue -le 0) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        return $null
    }

    $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    if (!$process) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        return $null
    }

    return $process
}

function Get-DedicatedServerProcess {
    param([int]$Port)

    $endpointProcess = Get-ExistingDedicatedServerProcess -Port $Port
    if ($endpointProcess) {
        return $endpointProcess
    }

    return Get-PidFileProcess
}

function Get-ProcessPathSafe {
    param([System.Diagnostics.Process]$Process)

    try {
        return $Process.MainModule.FileName
    } catch {
        return ''
    }
}

function Format-ProcessSummary {
    param([System.Diagnostics.Process]$Process)

    $path = Get-ProcessPathSafe -Process $Process
    if ([string]::IsNullOrWhiteSpace($path)) {
        return "PID=$($Process.Id) name=$($Process.ProcessName)"
    }

    return "PID=$($Process.Id) name=$($Process.ProcessName) path=$path"
}

function Get-KnownDedicatedProcessIds {
    param([int]$Port)

    $ids = @()
    $endpointProcess = Get-ExistingDedicatedServerProcess -Port $Port
    if ($endpointProcess) {
        $ids += $endpointProcess.Id
    }

    $pidProcess = Get-PidFileProcess
    if ($pidProcess) {
        $ids += $pidProcess.Id
    }

    return @($ids | Select-Object -Unique)
}

function Get-OrphanedDedicatedProcesses {
    param([int]$Port)

    $knownIds = @(Get-KnownDedicatedProcessIds -Port $Port)
    $byId = @{}
    $candidates = @(
        Get-Process -Name 'starwarsbattlefrontii', 'ActivationUI', 'activation', 'kyber_cli', 'maxima-bootstrap' -ErrorAction SilentlyContinue
    )

    foreach ($process in $candidates) {
        if (!$process) {
            continue
        }

        if ($knownIds -contains $process.Id) {
            continue
        }

        $byId[$process.Id] = $process
    }

    return @($byId.Values | Sort-Object Id)
}

function Show-DedicatedProcessInventory {
    param([int]$Port)

    $orphans = @(Get-OrphanedDedicatedProcesses -Port $Port)
    if ($orphans.Count -eq 0) {
        Write-Host 'Orphan scan: no orphaned BFII/Kyber dedicated helper processes found.'
        return
    }

    Write-Host "Orphan scan: found $($orphans.Count) orphaned BFII/Kyber dedicated helper process(es)." -ForegroundColor Yellow
    foreach ($process in $orphans) {
        Write-Host ("  " + (Format-ProcessSummary -Process $process))
    }
    Write-Host 'Run -Action Cleanup to stop these processes before starting a new host.'
}

function Stop-OrphanedDedicatedProcesses {
    param(
        [int]$Port,
        [string]$Reason = 'manual cleanup'
    )

    $orphans = @(Get-OrphanedDedicatedProcesses -Port $Port)
    if ($orphans.Count -eq 0) {
        Write-Host 'No orphaned BFII/Kyber dedicated helper processes found.'
        return
    }

    Write-Host "Stopping $($orphans.Count) orphaned BFII/Kyber dedicated helper process(es): $Reason"
    foreach ($process in $orphans) {
        Write-Host ("Stopping orphaned process: " + (Format-ProcessSummary -Process $process))
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}

function Show-DedicatedStatus {
    param([int]$Port)

    $process = Get-DedicatedServerProcess -Port $Port
    if ($process) {
        Write-Host "Dedicated host process: running (PID: $($process.Id), name: $($process.ProcessName))"
        Write-Host "Server UDP port: $Port"
    } else {
        Write-Host 'Dedicated host process: not running'
    }

    Show-DedicatedProcessInventory -Port $Port

    if (Test-Path -LiteralPath $LatestStdoutPath -PathType Leaf) {
        Write-Host "stdout: $((Get-Content -LiteralPath $LatestStdoutPath -Raw).Trim())"
    }
    if (Test-Path -LiteralPath $LatestStderrPath -PathType Leaf) {
        Write-Host "stderr: $((Get-Content -LiteralPath $LatestStderrPath -Raw).Trim())"
    }
}

function Stop-DedicatedServer {
    param([int]$Port)

    $process = Get-DedicatedServerProcess -Port $Port
    if (!$process) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        Stop-OrphanedDedicatedProcesses -Port $Port -Reason 'dedicated stop requested'
        Stop-MaximaService
        Write-Host 'Dedicated host process: not running'
        return
    }

    Write-Host "Stopping dedicated host process PID=$($process.Id)..."
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Get-Process -Name 'starwarsbattlefrontii', 'ActivationUI', 'activation' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    Stop-OrphanedDedicatedProcesses -Port $Port -Reason 'dedicated stop requested'
    Stop-MaximaService
    Write-Host 'Dedicated host process: stopped'
}

function Stop-StartupProcesses {
    param(
        [System.Diagnostics.Process]$HelperProcess,
        [int]$Port
    )

    if ($HelperProcess -and !$HelperProcess.HasExited) {
        Stop-Process -Id $HelperProcess.Id -Force -ErrorAction SilentlyContinue
    }

    $dedicatedProcess = Get-DedicatedServerProcess -Port $Port
    if ($dedicatedProcess) {
        Stop-Process -Id $dedicatedProcess.Id -Force -ErrorAction SilentlyContinue
    }

    Get-Process -Name 'starwarsbattlefrontii', 'ActivationUI', 'activation' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-OrphanedDedicatedProcesses -Port $Port -Reason 'startup failed'
    Stop-MaximaService
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

function Get-HostJoinAddresses {
    try {
        return Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -notlike '127.*' -and
                $_.IPAddress -notlike '169.254.*' -and
                $_.PrefixOrigin -ne 'WellKnown'
            } |
            Select-Object -ExpandProperty IPAddress
    } catch {
        return @()
    }
}

function Ensure-FirewallRule {
    param([int]$Port)

    $ruleName = "Kyber Dedicated UDP $Port"
    try {
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "Firewall rule already exists: $ruleName"
            return
        }

        New-NetFirewallRule `
            -DisplayName $ruleName `
            -Direction Inbound `
            -Action Allow `
            -Protocol UDP `
            -LocalPort $Port `
            -Profile Private,Domain,Public | Out-Null
        Write-Host "Created firewall rule: $ruleName"
    } catch {
        Write-Host "Firewall rule was not created. Run PowerShell as Administrator or open inbound UDP $Port manually." -ForegroundColor Yellow
    }
}

function Assert-NoInitialGameProcess {
    param(
        [string]$RequestedRole,
        [int]$Port,
        [bool]$AllowCleanup
    )

    $existing = Get-Process -Name 'starwarsbattlefrontii' -ErrorAction SilentlyContinue
    if (!$existing) {
        return
    }

    if ($AllowCleanup) {
        $ids = ($existing | Select-Object -ExpandProperty Id) -join ', '
        Write-Host "Found existing Battlefront II process before $RequestedRole startup (PID: $ids). Cleaning orphaned host/client state first." -ForegroundColor Yellow
        Stop-OrphanedDedicatedProcesses -Port $Port -Reason "pre-start $RequestedRole cleanup"
        $remaining = Get-Process -Name 'starwarsbattlefrontii' -ErrorAction SilentlyContinue
        if (!$remaining) {
            return
        }

        $existing = $remaining
    }

    $ids = ($existing | Select-Object -ExpandProperty Id) -join ', '
    Exit-WithError "Battlefront II is already running (PID: $ids). This machine can only run one BFII process at a time. Stop it before starting the $RequestedRole here, or run -Action Cleanup first. If this machine needs to join as a player, run the dedicated server on another PC/VPS."
}

function Configure-CliRuntime {
    param([string]$ExecutablePath)

    $script:CliBinDirectory = Split-Path -Parent $ExecutablePath
    $script:CliBundleDirectory = Split-Path -Parent $script:CliBinDirectory
    $script:CliLibDirectory = Join-Path $script:CliBundleDirectory 'lib'

    Require-Directory $script:CliLibDirectory 'CLI runtime library directory'
    Require-File (Join-Path $script:CliLibDirectory 'rust_lib.dll') 'rust_lib.dll'

    $runtimePaths = @($script:CliBinDirectory, $script:CliLibDirectory)
    $existingPaths = $env:Path -split ';' | Where-Object {
        $_ -and ($runtimePaths -notcontains $_)
    }
    $env:Path = (($runtimePaths + $existingPaths) -join ';')
}

function Invoke-KyberCli {
    param([string[]]$Arguments)

    Push-Location $script:CliBinDirectory
    try {
        & $script:CliExe @Arguments
        return $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

function Build-ServerArguments {
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('--skip-updates')
    $arguments.Add('start_server')
    $arguments.Add('--offline')
    Add-FlagArgument $arguments '--show-console' $ShowConsole.IsPresent
    Add-ValueArgument $arguments '--server-name' $script:ServerName
    Add-ValueArgument $arguments '--game-path' $script:GamePath
    Add-ValueArgument $arguments '--module-path' $script:ModulePath
    Add-ValueArgument $arguments '--server-port' ($script:ServerPort).ToString()
    Add-ValueArgument $arguments '--max-players' ($script:MaxPlayers).ToString()
    Add-ValueArgument $arguments '--map' $script:Map
    Add-ValueArgument $arguments '--mode' $script:Mode
    Add-ValueArgument $arguments '--interface-port' ($script:ServerInterfacePort).ToString()
    Add-ValueArgument $arguments '--license-mode' $script:LicenseMode
    Add-ValueArgument $arguments '--server-password' $script:ServerPassword
    Add-ValueArgument $arguments '--raw-mods' $script:RawMods
    Add-ValueArgument $arguments '--collection-file' $script:CollectionFile
    Add-ValueArgument $arguments '--collection-mods-directory' $script:CollectionModsDirectory
    Add-ValueArgument $arguments '--mod-folder' $script:ModFolder
    Add-ValueArgument $arguments '--startup-commands' $script:StartupCommands
    Add-FlagArgument $arguments '--credentialless-host' $script:CredentiallessHost
    Add-GameArgs $arguments $script:GameArgs
    return $arguments.ToArray()
}

function Build-ClientArguments {
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('--skip-updates')
    $arguments.Add('start_game')
    Add-FlagArgument $arguments '--show-console' $ShowConsole.IsPresent
    Add-ValueArgument $arguments '--server-address' $script:ServerAddress
    Add-ValueArgument $arguments '--server-port' ($script:ServerPort).ToString()
    Add-ValueArgument $arguments '--game-path' $script:GamePath
    Add-ValueArgument $arguments '--module-path' $script:ModulePath
    Add-ValueArgument $arguments '--interface-port' ($script:ClientInterfacePort).ToString()
    Add-ValueArgument $arguments '--server-password' $script:ServerPassword
    Add-ValueArgument $arguments '--raw-mods' $script:RawMods
    Add-GameArgs $arguments $script:GameArgs
    return $arguments.ToArray()
}

function Wait-ForDedicatedReady {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$StdoutPath,
        [string]$StderrPath,
        [int]$TimeoutSeconds,
        [int]$StallTimeoutSeconds
    )

    Write-Host "Waiting for dedicated server readiness. Log: $StdoutPath"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastProgress = Get-Date
    $lastLogChange = Get-Date
    $lastLogBytes = -1
    $logPaths = @($StdoutPath, $StderrPath)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if (((Get-Date) - $lastProgress).TotalSeconds -ge 10) {
            Write-Host 'Still waiting for dedicated server ready marker...'
            $lastProgress = Get-Date
        }

        if ($Process.HasExited) {
            $summary = Get-StartupFailureSummary -StdoutPath $StdoutPath -StderrPath $StderrPath
            Write-StartupFailureDiagnostics -StdoutPath $StdoutPath -StderrPath $StderrPath
            throw "Dedicated server process exited before readiness. Last error: $summary. See $StdoutPath and $StderrPath."
        }

        $currentLogBytes = Get-LogByteCount -Paths $logPaths
        if ($currentLogBytes -ne $lastLogBytes) {
            $lastLogBytes = $currentLogBytes
            $lastLogChange = Get-Date
        }

        if (((Get-Date) - $lastLogChange).TotalSeconds -ge $StallTimeoutSeconds) {
            $lastLine = Get-LastNonEmptyLogLine -Paths $logPaths
            if ($lastLine -match '\[maxima\] - Installing service') {
                throw "Maxima service installation stalled for $StallTimeoutSeconds seconds. Accept the Windows UAC prompt, run Kyber Launcher as Administrator once, or stop the stale MaximaBackgroundService before retrying. See $StdoutPath and $StderrPath."
            }

            Write-StartupFailureDiagnostics -StdoutPath $StdoutPath -StderrPath $StderrPath
            throw "Dedicated server startup stalled for $StallTimeoutSeconds seconds with no new log output. Last log line: $lastLine. See $StdoutPath and $StderrPath."
        }

        if (!(Test-Path -LiteralPath $StdoutPath)) {
            continue
        }

        $content = Get-Content -LiteralPath $StdoutPath -Raw -ErrorAction SilentlyContinue
        if ($content -match 'Dedicated server ready:') {
            return
        }

        if ($content -match 'Invalid Cipher|Invalid license') {
            throw "BFII/EA license validation failed during startup. Sign in through the normal EA OAuth/Maxima session, verify the account owns Battlefront II, then retry. See $StdoutPath and $StderrPath."
        }

        if ($content -match 'Kyber unloaded|Destroying Kyber') {
            throw "BFII closed or rejected the injected host session before the server became ready. If an EA license dialog is visible, sign in through the normal EA OAuth/Maxima session and verify the account owns Battlefront II. See $StdoutPath and $StderrPath."
        }

        if ($content -match 'Dedicated server did not become ready|Failed to start Maxima runtime|Maxima service installation timed out|Maxima service startup timed out|Maxima service installation did not produce a valid service|module-path is missing|required runtime file|Game process exited before') {
            throw "Dedicated server failed during startup. See $StdoutPath and $StderrPath."
        }
    }

    Write-StartupFailureDiagnostics -StdoutPath $StdoutPath -StderrPath $StderrPath
    throw "Dedicated server was not ready after $TimeoutSeconds seconds. See $StdoutPath and $StderrPath."
}

function Start-DedicatedServerProcess {
    param(
        [string[]]$Arguments,
        [string]$LogPrefix
    )

    $logDirectory = $LogDirectory
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $stdoutPath = Join-Path $logDirectory "$LogPrefix`_$timestamp.stdout.log"
    $stderrPath = Join-Path $logDirectory "$LogPrefix`_$timestamp.stderr.log"

    $process = Start-Process `
        -FilePath $CliExe `
        -ArgumentList (Join-CommandLine $Arguments) `
        -WorkingDirectory $script:CliBinDirectory `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru `
        -WindowStyle Hidden

    return [pscustomobject]@{
        Process = $process
        Stdout = $stdoutPath
        Stderr = $stderrPath
    }
}

$GamePath = Get-Setting $GamePath 'KYBER_GAME_PATH' 'D:\Games\STAR WARS Battlefront II\starwarsbattlefrontii.exe'
$ModulePath = Get-Setting $ModulePath 'KYBER_MODULE_DIR' $DefaultModulePath
$CliExe = Get-Setting $CliExe 'KYBER_CLI_EXE' $DefaultCliExe
$Credentials = Get-Setting $Credentials 'KYBER_DEDICATED_CREDENTIALS' ''
$LicenseMode = Get-Setting $LicenseMode 'KYBER_DEDICATED_LICENSE_MODE' 'refresh'
$DenuvoToken = Get-Setting $DenuvoToken 'KYBER_DEDICATED_DENUVO_TOKEN' ''
$CredentiallessHost = Get-BoolSetting $CredentiallessHost.IsPresent 'KYBER_CREDENTIALLESS_HOST'
$ServerAddress = Get-Setting $ServerAddress 'KYBER_SERVER_ADDRESS' ''
$ServerName = Get-Setting $ServerName 'KYBER_SERVER_NAME' 'LAN Dedicated Test'
$Map = Get-Setting $Map 'KYBER_SERVER_MAP' 'S5_1/Levels/MP/Geonosis_01/Geonosis_01'
$Mode = Get-Setting $Mode 'KYBER_SERVER_MODE' 'HeroesVersusVillains'
$ServerPort = Get-IntSetting $ServerPort 'KYBER_SERVER_PORT' 25200
$ServerInterfacePort = Get-IntSetting $ServerInterfacePort 'KYBER_SERVER_INTERFACE_PORT' 19103
$ClientInterfacePort = Get-IntSetting $ClientInterfacePort 'KYBER_CLIENT_INTERFACE_PORT' 19104
$MaxPlayers = Get-IntSetting $MaxPlayers 'KYBER_SERVER_MAX_PLAYERS' 2
$LogStallTimeoutSeconds = Get-IntSetting $LogStallTimeoutSeconds 'KYBER_DEDICATED_LOG_STALL_TIMEOUT_SECONDS' 35

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
Require-Port $ServerPort 'ServerPort'
Require-Port $ServerInterfacePort 'ServerInterfacePort'
Require-Port $ClientInterfacePort 'ClientInterfacePort'

if ($Action -eq 'Status') {
    Show-DedicatedStatus -Port $ServerPort
    exit 0
}

if ($Action -eq 'Stop') {
    Stop-DedicatedServer -Port $ServerPort
    exit 0
}

if ($Action -eq 'Cleanup') {
    Stop-DedicatedServer -Port $ServerPort
    exit 0
}

if ($Action -eq 'Host' -and $CredentiallessHost -and ![string]::IsNullOrWhiteSpace($Credentials)) {
    Exit-WithError 'Host cannot combine -CredentiallessHost with -Credentials.'
}

if ($Action -eq 'Host' -and ![string]::IsNullOrWhiteSpace($Credentials)) {
    Exit-WithError 'Direct EA/Maxima password login is not supported by this shipping build. Sign in through the normal EA OAuth/Maxima session, clear KYBER_DEDICATED_CREDENTIALS, then retry.'
}

if ($Action -eq 'Host' -and $LicenseMode -notin @('reuse', 'refresh')) {
    Exit-WithError "LicenseMode must be reuse or refresh, got '$LicenseMode'."
}

Require-File $CliExe 'kyber_cli.exe'
$CliExe = Resolve-ExistingPath $CliExe
Configure-CliRuntime $CliExe
Require-File $GamePath 'Battlefront II executable'
$GamePath = Resolve-ExistingPath $GamePath
Require-Directory $ModulePath 'Kyber module directory'
$ModulePath = Resolve-ExistingPath $ModulePath
Require-File (Join-Path $ModulePath 'Kyber.dll') 'Kyber.dll'
Require-File (Join-Path $ModulePath 'vivoxsdk.dll') 'vivoxsdk.dll'

if ($Action -eq 'Join' -and [string]::IsNullOrWhiteSpace($ServerAddress)) {
    Exit-WithError 'ServerAddress is required for Join. Run the dedicated server on another PC/VPS, then pass -ServerAddress <host-or-ip>.'
}

if ($Action -eq 'Join') {
    if (![string]::IsNullOrWhiteSpace($ModFolder) -or
        ![string]::IsNullOrWhiteSpace($CollectionFile) -or
        ![string]::IsNullOrWhiteSpace($CollectionModsDirectory)) {
        throw 'One-click Join only supports -RawMods for shared mod loading. start_game does not support -ModFolder or -CollectionModsDirectory.'
    }
}

if (![string]::IsNullOrWhiteSpace($RawMods)) {
    Require-File $RawMods 'Raw mods manifest'
    $RawMods = Resolve-ExistingPath $RawMods
}
if (![string]::IsNullOrWhiteSpace($CollectionFile)) {
    Require-File $CollectionFile 'Collection file'
    $CollectionFile = Resolve-ExistingPath $CollectionFile
}
if (![string]::IsNullOrWhiteSpace($CollectionModsDirectory)) {
    Require-Directory $CollectionModsDirectory 'Collection mods directory'
    $CollectionModsDirectory = Resolve-ExistingPath $CollectionModsDirectory
}
if (![string]::IsNullOrWhiteSpace($ModFolder)) {
    Require-Directory $ModFolder 'Mod folder'
    $ModFolder = Resolve-ExistingPath $ModFolder
}
if (![string]::IsNullOrWhiteSpace($StartupCommands)) {
    Require-File $StartupCommands 'Startup commands file'
    $StartupCommands = Resolve-ExistingPath $StartupCommands
}

$serverArguments = Build-ServerArguments
$clientArguments = Build-ClientArguments

Write-Host "Kyber dedicated one-click action: $Action"
Write-Host "CLI: $CliExe"
Write-Host "Game: $GamePath"
Write-Host "Module: $ModulePath"
if ($Action -eq 'Join') {
    Write-Host "Server: $ServerAddress`:$ServerPort"
} else {
    Write-Host "Server port: $ServerPort"
    Write-Host "License mode: $LicenseMode"
    if (![string]::IsNullOrWhiteSpace($DenuvoToken)) {
        Write-Host 'Denuvo token override: configured'
    }
    Show-MaximaServicePreflight -CliBinDirectory $script:CliBinDirectory
}

if ($ValidateOnly) {
    Write-Host 'Validation succeeded.'
    if ($Action -eq 'Host') {
        Write-Host ('Server command: ' + $CliExe + ' ' + (Join-CommandLine $serverArguments))
    }
    if ($Action -eq 'Join') {
        Write-Host ('Client command: ' + $CliExe + ' ' + (Join-CommandLine $clientArguments))
    }
    exit 0
}

if ($Action -eq 'Host') {
    if ($CleanupOrphans.IsPresent) {
        Stop-OrphanedDedicatedProcesses -Port $ServerPort -Reason 'pre-start host cleanup'
    } else {
        Show-DedicatedProcessInventory -Port $ServerPort
    }

    $existingDedicated = Get-ExistingDedicatedServerProcess -Port $ServerPort
    if ($existingDedicated) {
        Write-Host "Dedicated server already running. PID: $($existingDedicated.Id)"
        Write-Host "Listening on UDP 0.0.0.0:$ServerPort"
        Write-Host 'Join from another PC, or stop this server before launching a local BFII player client.'
        exit 0
    }
}

if ($Action -eq 'Host') {
    Assert-NoInitialGameProcess 'dedicated server' -Port $ServerPort -AllowCleanup $CleanupOrphans.IsPresent
    Ensure-BfiiVivoxRuntime -GamePath $GamePath -ModulePath $ModulePath
    Stop-MaximaService
} elseif ($Action -eq 'Join') {
    Assert-NoInitialGameProcess 'player client' -Port $ServerPort -AllowCleanup $CleanupOrphans.IsPresent
}

$env:KYBER_BYPASS_DOCKER_I_REALLY_KNOW_WHAT_I_AM_DOING = '1'
$env:KYBER_ONLINE_MODE = '0'
if ($ShowConsole.IsPresent) {
    [Environment]::SetEnvironmentVariable('KYBER_HIDE_CONSOLE', $null, 'Process')
} else {
    $env:KYBER_HIDE_CONSOLE = '1'
}

if ($Action -eq 'Host') {
    Write-Host 'Starting dedicated server in the background...'
    $env:KYBER_DEDICATED_READY_TIMEOUT_SECONDS = $ReadyTimeoutSeconds.ToString()
    $env:KYBER_DEDICATED_LICENSE_MODE = $LicenseMode
    if ($LicenseMode -eq 'refresh') {
        $env:MAXIMA_FORCE_LICENSE_REFRESH = '1'
    } else {
        [Environment]::SetEnvironmentVariable('MAXIMA_FORCE_LICENSE_REFRESH', $null, 'Process')
    }
    if (![string]::IsNullOrWhiteSpace($DenuvoToken)) {
        $env:KYBER_DEDICATED_DENUVO_TOKEN = $DenuvoToken
        $env:MAXIMA_DENUVO_TOKEN = $DenuvoToken
    } else {
        [Environment]::SetEnvironmentVariable('KYBER_DEDICATED_DENUVO_TOKEN', $null, 'Process')
        [Environment]::SetEnvironmentVariable('MAXIMA_DENUVO_TOKEN', $null, 'Process')
    }
    [Environment]::SetEnvironmentVariable('KYBER_DEDICATED_CREDENTIALS', $null, 'Process')
    [Environment]::SetEnvironmentVariable('KYBER_BFII_HOST_CREDENTIALS', $null, 'Process')
    [Environment]::SetEnvironmentVariable('MAXIMA_CREDENTIALS', $null, 'Process')
    $server = Start-DedicatedServerProcess -Arguments $serverArguments -LogPrefix 'host_server'
    Set-Content -LiteralPath $PidFile -Value $server.Process.Id -Encoding ascii
    Set-Content -LiteralPath $LatestStdoutPath -Value $server.Stdout -Encoding ascii
    Set-Content -LiteralPath $LatestStderrPath -Value $server.Stderr -Encoding ascii
    try {
        Wait-ForDedicatedReady `
            -Process $server.Process `
            -StdoutPath $server.Stdout `
            -StderrPath $server.Stderr `
            -TimeoutSeconds $ReadyTimeoutSeconds `
            -StallTimeoutSeconds $LogStallTimeoutSeconds
    } catch {
        Stop-StartupProcesses -HelperProcess $server.Process -Port $ServerPort
        throw
    }

    Ensure-FirewallRule -Port $ServerPort
    $joinAddresses = @(Get-HostJoinAddresses)
    Write-Host "Dedicated server ready. PID: $($server.Process.Id)"
    foreach ($address in $joinAddresses) {
        Write-Host "Join address: $address`:$ServerPort"
    }
    Write-Host "Server log: $($server.Stdout)"
    Write-Host 'Leave the BFII server host process running while clients join from another machine.'
    exit 0
}

if ($Action -eq 'Join') {
    Write-Host 'Starting direct-connect client in this console...'
    exit (Invoke-KyberCli $clientArguments)
}
