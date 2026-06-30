$ErrorActionPreference = 'Stop'

$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$Toolchains = Join-Path $Root '.toolchains'
$Tmp = Join-Path $Toolchains 'tmp'

foreach ($path in @(
    $Toolchains,
    $Tmp,
    (Join-Path $Toolchains 'go-path'),
    (Join-Path $Toolchains 'go-cache'),
    (Join-Path $Toolchains 'go-mod-cache'),
    (Join-Path $Toolchains 'pub-cache'),
    (Join-Path $Toolchains 'cargo'),
    (Join-Path $Toolchains 'rustup'),
    (Join-Path $Toolchains 'bazelisk-home')
)) {
    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

$env:KYBER_ROOT = $Root
$env:KYBER_TOOLCHAINS = $Toolchains
$env:TEMP = $Tmp
$env:TMP = $Tmp

$env:FLUTTER_ROOT = Join-Path $Toolchains 'flutter'
$env:PUB_CACHE = Join-Path $Toolchains 'pub-cache'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:FLUTTER_DISABLE_TELEMETRY = 'true'

$env:RUSTUP_HOME = Join-Path $Toolchains 'rustup'
$env:CARGO_HOME = Join-Path $Toolchains 'cargo'

$env:GOROOT = Join-Path $Toolchains 'go'
$env:GOPATH = Join-Path $Toolchains 'go-path'
$env:GOCACHE = Join-Path $Toolchains 'go-cache'
$env:GOMODCACHE = Join-Path $Toolchains 'go-mod-cache'

$env:BAZELISK_HOME = Join-Path $Toolchains 'bazelisk-home'
$env:KYBER_BAZEL_OUTPUT_USER_ROOT = Join-Path $Root 'Module\.bazel_out'
$env:BAZEL_SH = Join-Path $Toolchains 'msys64\usr\bin\bash.exe'

$env:PROTOC = Join-Path $Toolchains 'protoc\bin\protoc.exe'
$env:LIBCLANG_PATH = Join-Path $Toolchains 'llvm\bin'
$env:KYBER_LIBCLANG = Join-Path $Toolchains 'llvm\bin\libclang.dll'

function Import-VsDevEnvironment {
    $vswhereCandidates = @(@(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    ) | Where-Object { $_ -and (Test-Path $_) })

    $installationPath = ''
    if ($vswhereCandidates.Count -gt 0) {
        $installationPath = & ($vswhereCandidates[0]) -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath
    }

    if (!$installationPath) {
        $fallback = 'C:\Program Files\Microsoft Visual Studio\2022\Community'
        if (Test-Path $fallback) {
            $installationPath = $fallback
        }
    }

    if (!$installationPath) {
        Write-Warning 'MSVC was not found. Rust MSVC and Module builds may fail.'
        return
    }

    $vsDevCmd = Join-Path $installationPath 'Common7\Tools\VsDevCmd.bat'
    if (!(Test-Path $vsDevCmd)) {
        Write-Warning "VsDevCmd.bat not found at $vsDevCmd"
        return
    }

    $environment = cmd /s /c "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && set"
    foreach ($line in $environment) {
        $separator = $line.IndexOf('=')
        if ($separator -le 0) {
            continue
        }

        $name = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        Set-Item -Path "Env:$name" -Value $value
    }
}

Import-VsDevEnvironment

$msvcLinker = if ($env:VCToolsInstallDir) {
    Join-Path $env:VCToolsInstallDir 'bin\Hostx64\x64\link.exe'
} else {
    ''
}
if ($msvcLinker -and (Test-Path $msvcLinker)) {
    $env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER = $msvcLinker
}

$paths = @(
    (Join-Path $Toolchains 'bin'),
    (Join-Path $Toolchains 'flutter\bin'),
    (Join-Path $Toolchains 'pub-cache\bin'),
    (Join-Path $Toolchains 'go\bin'),
    (Join-Path $Toolchains 'go-path\bin'),
    (Join-Path $Toolchains 'cargo\bin'),
    (Join-Path $Toolchains 'protoc\bin'),
    (Join-Path $Toolchains 'cmake\bin'),
    (Join-Path $Toolchains 'ninja'),
    (Join-Path $Toolchains 'git\cmd'),
    (Join-Path $Toolchains 'git\mingw64\bin'),
    (Join-Path $Toolchains 'msys64\usr\bin'),
    (Join-Path $Toolchains 'msys64\mingw64\bin'),
    (Join-Path $Toolchains 'msys64\clang64\bin'),
    (Join-Path $Toolchains 'git\usr\bin'),
    (Join-Path $Toolchains 'llvm\bin')
) | Where-Object { Test-Path $_ }

$existing = $env:Path -split ';' | Where-Object {
    $_ -and ($paths -notcontains $_)
}
$env:Path = (($paths + $existing) -join ';')

function Invoke-KyberBazel {
    & (Join-Path $env:KYBER_TOOLCHAINS 'bazelisk\bazelisk.exe') `
        --output_user_root="$env:KYBER_BAZEL_OUTPUT_USER_ROOT" @args
}

Set-Alias kbazel Invoke-KyberBazel -Scope Global

Write-Host "KYBER local toolchain active: $Toolchains"
Write-Host 'Use kbazel from PowerShell for Module builds so Bazel output stays under Module\.bazel_out.'
