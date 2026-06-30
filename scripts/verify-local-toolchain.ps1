$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'use-local-toolchain.ps1')

$commands = @(
    'flutter',
    'dart',
    'go',
    'rustc',
    'cargo',
    'rustfmt',
    'protoc',
    'cmake',
    'ninja',
    'bazelisk',
    'git',
    'bash',
    'clang-format'
)

foreach ($command in $commands) {
    $resolved = Get-Command $command -ErrorAction SilentlyContinue
    if ($null -eq $resolved) {
        Write-Host "[missing] $command" -ForegroundColor Red
        continue
    }

    $source = $resolved.Source
    $insideWorkspace = $source -like "$env:KYBER_TOOLCHAINS*"
    $status = if ($insideWorkspace) { 'local' } else { 'external' }
    $color = if ($insideWorkspace) { 'Green' } else { 'Yellow' }
    Write-Host "[$status] $command -> $source" -ForegroundColor $color
}

Write-Host ''
flutter --version
dart --version
go version
rustc --version
cargo --version
rustfmt --version
protoc --version
cmake --version
ninja --version
git --version
clang-format --version
