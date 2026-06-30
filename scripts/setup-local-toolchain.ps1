$ErrorActionPreference = 'Stop'

$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$Toolchains = Join-Path $Root '.toolchains'
$Downloads = Join-Path $Toolchains 'downloads'
$Tmp = Join-Path $Toolchains 'tmp'

function New-LocalDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-File {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )

    if (Test-Path $OutFile) {
        Write-Host "Using cached $OutFile"
        return
    }

    Write-Host "Downloading $Uri"
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile
}

function Expand-ZipOnce {
    param(
        [Parameter(Mandatory = $true)][string]$ZipFile,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$ExpectedPath
    )

    if ($ExpectedPath -and (Test-Path $ExpectedPath)) {
        Write-Host "Already expanded $ExpectedPath"
        return
    }

    New-LocalDirectory $Destination
    Expand-Archive -Path $ZipFile -DestinationPath $Destination -Force
}

function Copy-TreeOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Probe
    )

    if (Test-Path $Probe) {
        Write-Host "Already copied $Destination"
        return
    }

    if (!(Test-Path $Source)) {
        Write-Warning "Source not found: $Source"
        return
    }

    New-LocalDirectory $Destination
    Write-Host "Copying $Source -> $Destination"
    & robocopy $Source $Destination /E /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -gt 7) {
        throw "robocopy failed with exit code $LASTEXITCODE"
    }
}

function Move-FirstChildDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-Path $Destination) {
        return
    }

    $child = Get-ChildItem -Path $Parent -Directory | Select-Object -First 1
    if ($null -eq $child) {
        throw "No extracted directory found in $Parent"
    }

    Move-Item -Path $child.FullName -Destination $Destination
}

New-LocalDirectory $Toolchains
New-LocalDirectory $Downloads
New-LocalDirectory $Tmp
New-LocalDirectory (Join-Path $Toolchains 'bin')
New-LocalDirectory (Join-Path $Toolchains 'go-path')
New-LocalDirectory (Join-Path $Toolchains 'go-cache')
New-LocalDirectory (Join-Path $Toolchains 'go-mod-cache')
New-LocalDirectory (Join-Path $Toolchains 'pub-cache')
New-LocalDirectory (Join-Path $Toolchains 'cargo')
New-LocalDirectory (Join-Path $Toolchains 'rustup')
New-LocalDirectory (Join-Path $Toolchains 'bazelisk-home')

$env:TEMP = $Tmp
$env:TMP = $Tmp

$flutterSource = 'G:\tools\flutter'
$flutterDestination = Join-Path $Toolchains 'flutter'
Copy-TreeOnce `
    -Source $flutterSource `
    -Destination $flutterDestination `
    -Probe (Join-Path $flutterDestination 'bin\flutter.bat')

$goZip = Join-Path $Downloads 'go1.26.0.windows-amd64.zip'
Get-File -Uri 'https://go.dev/dl/go1.26.0.windows-amd64.zip' -OutFile $goZip
Expand-ZipOnce -ZipFile $goZip -Destination $Toolchains -ExpectedPath (Join-Path $Toolchains 'go\bin\go.exe')

$cmakeZip = Join-Path $Downloads 'cmake-3.30.0-rc3-windows-x86_64.zip'
$cmakeExtract = Join-Path $Toolchains 'cmake-extract'
$cmakeDestination = Join-Path $Toolchains 'cmake'
Get-File -Uri 'https://github.com/Kitware/CMake/releases/download/v3.30.0-rc3/cmake-3.30.0-rc3-windows-x86_64.zip' -OutFile $cmakeZip
Expand-ZipOnce -ZipFile $cmakeZip -Destination $cmakeExtract -ExpectedPath (Join-Path $cmakeDestination 'bin\cmake.exe')
Move-FirstChildDirectory -Parent $cmakeExtract -Destination $cmakeDestination

$ninjaZip = Join-Path $Downloads 'ninja-win-1.12.1.zip'
$ninjaDestination = Join-Path $Toolchains 'ninja'
Get-File -Uri 'https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-win.zip' -OutFile $ninjaZip
Expand-ZipOnce -ZipFile $ninjaZip -Destination $ninjaDestination -ExpectedPath (Join-Path $ninjaDestination 'ninja.exe')

$protocZip = Join-Path $Downloads 'protoc-33.5-win64.zip'
$protocDestination = Join-Path $Toolchains 'protoc'
Get-File -Uri 'https://github.com/protocolbuffers/protobuf/releases/download/v33.5/protoc-33.5-win64.zip' -OutFile $protocZip
Expand-ZipOnce -ZipFile $protocZip -Destination $protocDestination -ExpectedPath (Join-Path $protocDestination 'bin\protoc.exe')

$bazeliskDestination = Join-Path $Toolchains 'bazelisk'
New-LocalDirectory $bazeliskDestination
$bazeliskExe = Join-Path $bazeliskDestination 'bazelisk.exe'
Get-File -Uri 'https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-windows-amd64.exe' -OutFile $bazeliskExe
Copy-Item -Path $bazeliskExe -Destination (Join-Path $Toolchains 'bin\bazelisk.exe') -Force

$rustupExe = Join-Path $Downloads 'rustup-init.exe'
Get-File -Uri 'https://win.rustup.rs/x86_64' -OutFile $rustupExe
$env:RUSTUP_HOME = Join-Path $Toolchains 'rustup'
$env:CARGO_HOME = Join-Path $Toolchains 'cargo'
$env:Path = "$env:CARGO_HOME\bin;$env:Path"
if (!(Test-Path (Join-Path $env:CARGO_HOME 'bin\cargo.exe'))) {
    Write-Host 'Installing Rust nightly locally'
    & $rustupExe -y --default-toolchain nightly --profile default --no-modify-path
}
& (Join-Path $env:CARGO_HOME 'bin\rustup.exe') default nightly
& (Join-Path $env:CARGO_HOME 'bin\rustup.exe') component add rustfmt clippy

Copy-TreeOnce `
    -Source 'C:\msys64' `
    -Destination (Join-Path $Toolchains 'msys64') `
    -Probe (Join-Path $Toolchains 'msys64\usr\bin\bash.exe')

Copy-TreeOnce `
    -Source 'C:\Program Files\Git' `
    -Destination (Join-Path $Toolchains 'git') `
    -Probe (Join-Path $Toolchains 'git\cmd\git.exe')

$llvmBin = Join-Path $Toolchains 'llvm\bin'
New-LocalDirectory $llvmBin
$llvmSource = 'D:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\Llvm\x64\bin'
if (Test-Path $llvmSource) {
    foreach ($file in @('libclang.dll', 'LLVM-C.dll', 'LTO.dll', 'libomp.dll', 'Remarks.dll', 'clang-format.exe')) {
        $sourceFile = Join-Path $llvmSource $file
        if (Test-Path $sourceFile) {
            Copy-Item -Path $sourceFile -Destination $llvmBin -Force
        }
    }
} else {
    Write-Warning "LLVM source not found: $llvmSource"
}

. (Join-Path $PSScriptRoot 'use-local-toolchain.ps1')

Write-Host 'Installing Dart global tools into local PUB_CACHE'
dart pub global activate melos 7.1.1
dart pub global activate protoc_plugin 25.0.0
flutter pub global activate index_generator

Write-Host 'Installing Go protoc plugins into local GOPATH'
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
if ($LASTEXITCODE -ne 0) { throw 'go install protoc-gen-go failed' }
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
if ($LASTEXITCODE -ne 0) { throw 'go install protoc-gen-go-grpc failed' }

if (!(Test-Path (Join-Path $env:CARGO_HOME 'bin\flutter_rust_bridge_codegen.exe'))) {
    Write-Host 'Installing Flutter Rust Bridge codegen into local CARGO_HOME'
    cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked
    if ($LASTEXITCODE -ne 0) { throw 'cargo install flutter_rust_bridge_codegen failed' }
}

Write-Host ''
Write-Host 'Local toolchain setup completed.'
Write-Host "Run: . `"$Root\scripts\use-local-toolchain.ps1`""
