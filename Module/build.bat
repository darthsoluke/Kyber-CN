@echo off
setlocal

if not defined BAZEL_SH (
  for %%P in (
    "%ProgramFiles%\Git\bin\bash.exe"
    "%ProgramFiles%\Git\usr\bin\bash.exe"
    "%ProgramFiles(x86)%\Git\bin\bash.exe"
    "%ProgramFiles(x86)%\Git\usr\bin\bash.exe"
    "%LocalAppData%\Programs\Git\bin\bash.exe"
    "%LocalAppData%\Programs\Git\usr\bin\bash.exe"
  ) do (
    if not defined BAZEL_SH if exist %%~fP set "BAZEL_SH=%%~fP"
  )
)

set "BAZEL_EXE=bazelisk"
where %BAZEL_EXE% >nul 2>nul || set "BAZEL_EXE=bazel"

%BAZEL_EXE% --output_user_root="C:\bz" build --config=release Kyber || exit /b 1

copy /y ".\ThirdParty\vivox\SDK\Libraries\Release\x64\vivoxsdk.dll" ".\bazel-bin\vivoxsdk.dll" >nul || exit /b 1
copy /y "..\Launcher\assets\ca\ca_root.pem" ".\bazel-bin\ca_root.pem" >nul || exit /b 1

powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\stage_module.ps1" || exit /b 1
