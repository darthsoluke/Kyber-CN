@echo off
setlocal

set "BAZEL_EXE=bazelisk"
where %BAZEL_EXE% >nul 2>nul || set "BAZEL_EXE=bazel"

%BAZEL_EXE% --output_user_root="C:\bz" build --config=release Kyber || exit /b 1

copy /y ".\ThirdParty\vivox\SDK\Libraries\Release\x64\vivoxsdk.dll" ".\bazel-bin\vivoxsdk.dll" >nul || exit /b 1
copy /y "..\Launcher\assets\ca\ca_root.pem" ".\bazel-bin\ca_root.pem" >nul || exit /b 1

if not exist "%ProgramData%\Kyber\Module" mkdir "%ProgramData%\Kyber\Module"

copy /y ".\bazel-bin\Kyber.dll" "%ProgramData%\Kyber\Module\Kyber.dll" >nul || exit /b 1
copy /y ".\bazel-bin\vivoxsdk.dll" "%ProgramData%\Kyber\Module\vivoxsdk.dll" >nul || exit /b 1
copy /y ".\bazel-bin\ca_root.pem" "%ProgramData%\Kyber\Module\ca_root.pem" >nul || exit /b 1
