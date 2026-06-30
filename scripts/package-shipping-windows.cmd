@echo off
setlocal EnableExtensions

set "ROOT=%~dp0.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"

set "OUTPUT_DIR=%ROOT%\Launcher\build\shipping\windows"
set "CONFIGURATION=Release"
set "DO_CLEAN=0"
set "DO_ZIP=0"

:parse_args
if "%~1"=="" goto parsed_args
if /I "%~1"=="--clean" (
    set "DO_CLEAN=1"
    shift
    goto parse_args
)
if /I "%~1"=="--no-zip" (
    set "DO_ZIP=0"
    shift
    goto parse_args
)
if /I "%~1"=="--zip" (
    echo ERROR: Shipping archives are disabled. Keep the shipping output as Launcher\build\shipping\windows only.
    exit /b 2
)
if /I "%~1"=="--debug" (
    set "CONFIGURATION=Debug"
    shift
    goto parse_args
)
if /I "%~1"=="--release" (
    set "CONFIGURATION=Release"
    shift
    goto parse_args
)
if /I "%~1"=="--configuration" (
    if "%~2"=="" goto usage
    set "CONFIGURATION=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="--output" (
    echo ERROR: --output is disabled. Shipping output is fixed to Launcher\build\shipping\windows.
    exit /b 2
)
if /I "%~1"=="--help" goto help
if /I "%~1"=="/?" goto help

echo ERROR: Unknown argument: %~1
echo.
goto usage

:parsed_args
for %%I in ("%OUTPUT_DIR%") do set "OUTPUT_DIR=%%~fI"

echo.
echo === [1/6] Verify packaging inputs ===
if not exist "%ROOT%\scripts\build-launcher-shipping-windows.ps1" (
    echo ERROR: Missing shipping build script: %ROOT%\scripts\build-launcher-shipping-windows.ps1
    exit /b 1
)
echo OK: shipping build script
if not exist "%ROOT%\scripts\package-windows-dedicated.ps1" (
    echo ERROR: Missing dedicated package script: %ROOT%\scripts\package-windows-dedicated.ps1
    exit /b 1
)
echo OK: dedicated package script
if not exist "%ROOT%\scripts\run-dedicated.ps1" (
    echo ERROR: Missing dedicated runtime script: %ROOT%\scripts\run-dedicated.ps1
    exit /b 1
)
echo OK: dedicated runtime script
if not exist "%ROOT%\Launcher\pubspec.yaml" (
    echo ERROR: Missing Launcher project: %ROOT%\Launcher\pubspec.yaml
    exit /b 1
)
echo OK: Launcher project
if not exist "%ROOT%\CLI\pubspec.yaml" (
    echo ERROR: Missing CLI project: %ROOT%\CLI\pubspec.yaml
    exit /b 1
)
echo OK: CLI project
where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo ERROR: powershell.exe is required because Flutter Windows build hooks and existing Kyber package scripts use PowerShell.
    exit /b 1
)
echo OK: powershell.exe

echo.
if "%DO_CLEAN%"=="1" (
    echo === [2/6] Clean previous shipping output ===
    if exist "%OUTPUT_DIR%" echo Existing output directory will be reset by the staging script.
) else (
    echo === [2/6] Clean skipped ===
)

echo.
echo === [3/6] Build and stage Launcher plus dedicated runtime ===
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\build-launcher-shipping-windows.ps1" -Configuration "%CONFIGURATION%" -NoZip
if errorlevel 1 (
    echo ERROR: Shipping build failed.
    exit /b 1
)

echo.
echo === [4/6] Validate staged application ===
if not exist "%OUTPUT_DIR%\kyber_launcher.exe" (
    echo ERROR: Missing Launcher executable: %OUTPUT_DIR%\kyber_launcher.exe
    exit /b 1
)
echo OK: Launcher executable
if not exist "%OUTPUT_DIR%\dedicated_runtime\cli_bundle\bundle\bin\kyber_cli.exe" (
    echo ERROR: Missing dedicated CLI executable: %OUTPUT_DIR%\dedicated_runtime\cli_bundle\bundle\bin\kyber_cli.exe
    exit /b 1
)
echo OK: dedicated CLI executable
if not exist "%OUTPUT_DIR%\dedicated_runtime\cli_bundle\bundle\bin\rust_lib.dll" (
    echo ERROR: Missing CLI Rust runtime DLL: %OUTPUT_DIR%\dedicated_runtime\cli_bundle\bundle\bin\rust_lib.dll
    exit /b 1
)
echo OK: CLI Rust runtime DLL
if not exist "%OUTPUT_DIR%\dedicated_runtime\cli_bundle\bundle\bin\maxima-bootstrap.exe" (
    echo ERROR: Missing Maxima bootstrap executable: %OUTPUT_DIR%\dedicated_runtime\cli_bundle\bundle\bin\maxima-bootstrap.exe
    exit /b 1
)
echo OK: Maxima bootstrap executable
if not exist "%OUTPUT_DIR%\dedicated_runtime\cli_bundle\bundle\bin\maxima-service.exe" (
    echo ERROR: Missing Maxima service executable: %OUTPUT_DIR%\dedicated_runtime\cli_bundle\bundle\bin\maxima-service.exe
    exit /b 1
)
echo OK: Maxima service executable
if not exist "%OUTPUT_DIR%\dedicated_runtime\module_runtime\Kyber.dll" (
    echo ERROR: Missing Kyber module DLL: %OUTPUT_DIR%\dedicated_runtime\module_runtime\Kyber.dll
    exit /b 1
)
echo OK: Kyber module DLL
if not exist "%OUTPUT_DIR%\dedicated_runtime\module_runtime\vivoxsdk.dll" (
    echo ERROR: Missing Vivox runtime DLL: %OUTPUT_DIR%\dedicated_runtime\module_runtime\vivoxsdk.dll
    exit /b 1
)
echo OK: Vivox runtime DLL
if not exist "%OUTPUT_DIR%\dedicated_runtime\module_runtime\ca_root.pem" (
    echo ERROR: Missing Kyber module root certificate: %OUTPUT_DIR%\dedicated_runtime\module_runtime\ca_root.pem
    exit /b 1
)
echo OK: Kyber module root certificate
if not exist "%OUTPUT_DIR%\dedicated_runtime\scripts\run-dedicated.ps1" (
    echo ERROR: Missing dedicated host controller script: %OUTPUT_DIR%\dedicated_runtime\scripts\run-dedicated.ps1
    exit /b 1
)
echo OK: dedicated host controller script

echo.
echo === [5/6] Validate shipping hygiene ===
for /r "%OUTPUT_DIR%" %%F in (*.pdb *.ilk *.exp *.lib) do (
    echo ERROR: Debug/build artifact found in shipping output: %%F
    exit /b 1
)
echo OK: no debug/build artifacts
if exist "%OUTPUT_DIR%\out.txt" (
    echo ERROR: transient file found: %OUTPUT_DIR%\out.txt
    exit /b 1
)
if exist "%OUTPUT_DIR%\err.txt" (
    echo ERROR: transient file found: %OUTPUT_DIR%\err.txt
    exit /b 1
)
if exist "%OUTPUT_DIR%\.sentry-native" (
    echo ERROR: transient directory found: %OUTPUT_DIR%\.sentry-native
    exit /b 1
)
echo OK: no transient build artifacts

echo.
echo === [6/6] Archive skipped ===

echo.
echo Shipping package is ready:
echo   %OUTPUT_DIR%
exit /b 0

:help
echo Usage:
echo   scripts\package-shipping-windows.cmd [--clean] [--release^|--debug] [--no-zip]
echo.
echo Examples:
echo   scripts\package-shipping-windows.cmd --clean
exit /b 0

:usage
echo Usage:
echo   scripts\package-shipping-windows.cmd [--clean] [--release^|--debug] [--no-zip]
echo.
echo Examples:
echo   scripts\package-shipping-windows.cmd --clean
exit /b 2
