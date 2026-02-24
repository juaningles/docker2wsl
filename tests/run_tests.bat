@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  tests\run_tests.bat  — Test runner for container2wsl
::
::  Discovers and runs all test_*.bat files in this directory.
::  Exits with 0 if all tests pass, 1 if any fail.
::
::  Usage:
::    tests\run_tests.bat                        (run all tests)
::    tests\run_tests.bat test_01                (run a specific test file)
::    tests\run_tests.bat --html report.html     (save colored HTML report)
::    tests\run_tests.bat --force                (run even if test WSL names exist)
::    tests\run_tests.bat test_01 --html out.html --force
:: ============================================================

set "TESTS_DIR=%~dp0"
set "HELPERS=%TESTS_DIR%helpers.bat"
set "MOCKS_DIR=%TESTS_DIR%mocks"
set "SCRIPT_ROOT=%TESTS_DIR%.."

:: ---- Parse runner arguments ----
set "TEST_FILTER="
set "HTML_OUT="
set "FORCE=0"

:parse_runner_args
if "%~1"=="" goto :after_runner_args
if "%~1"=="--html" (
    set "HTML_OUT=%~2"
    shift
    shift
    goto :parse_runner_args
)
if "%~1"=="--force" (
    set "FORCE=1"
    shift
    goto :parse_runner_args
)
:: Anything else is a test filter
set "TEST_FILTER=%~1"
shift
goto :parse_runner_args

:after_runner_args

:: ---- If --html, re-run ourselves and capture output ----
if defined HTML_OUT (
    set "_RUNNER_CMD="%TESTS_DIR%run_tests.bat""
    if defined TEST_FILTER set "_RUNNER_CMD=!_RUNNER_CMD! !TEST_FILTER!"
    if "!FORCE!"=="1" set "_RUNNER_CMD=!_RUNNER_CMD! --force"

    :: Run tests and capture raw ANSI output to a temp file
    set "_RAW=%TEMP%\c2w_html_%RANDOM%.txt"
    cmd /c !_RUNNER_CMD! > "!_RAW!" 2>&1
    set "_TEST_RC=!errorlevel!"

    :: Convert ANSI to HTML via PowerShell
    powershell -noprofile -executionpolicy bypass -command ^
        "$raw = Get-Content -Raw -Path '!_RAW!'; " ^
        "$esc = [char]27; " ^
        "$h = $raw -replace '&','&amp;' -replace '<','&lt;'; " ^
        "$h = $h -replace \"$esc\[1;97m\",'<span style=\"color:#fff;font-weight:bold\">'; " ^
        "$h = $h -replace \"$esc\[1;36m\",'<span style=\"color:#5cf;font-weight:bold\">'; " ^
        "$h = $h -replace \"$esc\[1;91m\",'<span style=\"color:#f55;font-weight:bold\">'; " ^
        "$h = $h -replace \"$esc\[1;92m\",'<span style=\"color:#5f5;font-weight:bold\">'; " ^
        "$h = $h -replace \"$esc\[97m\",'<span style=\"color:#ddd\">'; " ^
        "$h = $h -replace \"$esc\[36m\",'<span style=\"color:#5bc\">'; " ^
        "$h = $h -replace \"$esc\[33m\",'<span style=\"color:#fd5\">'; " ^
        "$h = $h -replace \"$esc\[93m\",'<span style=\"color:#fd5\">'; " ^
        "$h = $h -replace \"$esc\[92m\",'<span style=\"color:#5f5\">'; " ^
        "$h = $h -replace \"$esc\[91m\",'<span style=\"color:#f55\">'; " ^
        "$h = $h -replace \"$esc\[90m\",'<span style=\"color:#888\">'; " ^
        "$h = $h -replace \"$esc\[0m\",'</span>'; " ^
        "$page = '<html><body style=\"background:#1e1e1e;color:#ccc;font-family:Consolas,monospace;font-size:14px;padding:20px;white-space:pre\">' + $h + '</body></html>'; " ^
        "$page | Out-File -Encoding utf8 '!HTML_OUT!'"
    del /f /q "!_RAW!" >nul 2>&1

    echo   HTML report: !HTML_OUT!
    exit /b !_TEST_RC!
)

:: Build an ESC (0x1B) character for ANSI color codes.
for /f %%e in ('echo prompt $E ^| cmd') do set "C2W_ESC=%%e"

:: ---- Generate a unique test ID for WSL distro names ----
set "C2W_TEST_ID=c2wt%RANDOM%"

:: ---- Pre-flight: check for colliding WSL distros ----
:: Capture wsl --list output and look for our test prefix pattern
set "_WSL_TMP=%TEMP%\c2w_wsllist_%RANDOM%.txt"
wsl --list --quiet > "!_WSL_TMP!" 2>&1
:: Convert UTF-16 LE to searchable ASCII by stripping null bytes
set "_WSL_ASCII=%TEMP%\c2w_wslascii_%RANDOM%.txt"
powershell -noprofile -command "Get-Content -Path '!_WSL_TMP!' -Encoding Unicode | Out-File -Encoding ascii '!_WSL_ASCII!'" 2>nul

set "_COLLISION=0"
set "_COLLIDED_NAMES="
for /f "usebackq tokens=*" %%n in ("!_WSL_ASCII!") do (
    set "_NAME=%%n"
    :: Trim trailing whitespace
    for /l %%i in (1,1,5) do if "!_NAME:~-1!"==" " set "_NAME=!_NAME:~0,-1!"
    :: Check if name starts with c2wt (our test prefix)
    if "!_NAME:~0,4!"=="c2wt" (
        set "_COLLISION=1"
        set "_COLLIDED_NAMES=!_COLLIDED_NAMES! !_NAME!"
    )
)
del /f /q "!_WSL_TMP!" "!_WSL_ASCII!" >nul 2>&1

if !_COLLISION! equ 1 (
    if !FORCE! equ 0 (
        echo.
        echo  %C2W_ESC%[91mERROR: WSL distros from a previous test run still exist:%C2W_ESC%[0m
        for %%n in (!_COLLIDED_NAMES!) do echo    %C2W_ESC%[33m%%n%C2W_ESC%[0m
        echo.
        echo  These may contain data. Run with %C2W_ESC%[97m--force%C2W_ESC%[0m to unregister them and continue.
        echo.
        exit /b 1
    )
    :: --force: unregister colliding distros
    echo  %C2W_ESC%[33mCleaning up leftover test distros...%C2W_ESC%[0m
    for %%n in (!_COLLIDED_NAMES!) do (
        wsl --unregister %%n >nul 2>&1
        echo    Unregistered: %%n
    )
    echo.
)

:: Shared counters used by helpers.bat
set "C2W_PASS=0"
set "C2W_FAIL=0"

:: Temp directory for test artefacts
set "C2W_TMPDIR=%TEMP%\c2w_tests_%RANDOM%"
mkdir "%C2W_TMPDIR%" >nul 2>&1

:: Log file for mock calls
set "C2W_MOCK_LOG=%C2W_TMPDIR%\mock_calls.log"

echo.
echo  %C2W_ESC%[97m============================================================%C2W_ESC%[0m
echo  %C2W_ESC%[1;97m container2wsl Test Suite%C2W_ESC%[0m
echo  %C2W_ESC%[97m============================================================%C2W_ESC%[0m
echo  %C2W_ESC%[90m  Test ID: %C2W_TEST_ID%%C2W_ESC%[0m
echo.

set "FILE_PASS=0"
set "FILE_FAIL=0"
set "FILE_COUNT=0"

:: ---- Determine which tests to run ----
if defined TEST_FILTER (
    set "TEST_PATTERN=%TESTS_DIR%!TEST_FILTER!*.bat"
) else (
    set "TEST_PATTERN=%TESTS_DIR%test_*.bat"
)

for %%f in ("!TEST_PATTERN!") do (
    set /a FILE_COUNT+=1

    :: Snapshot counters before this file
    set "_PASS_BEFORE=!C2W_PASS!"
    set "_FAIL_BEFORE=!C2W_FAIL!"

    echo  %C2W_ESC%[1;36m%%~nf%C2W_ESC%[0m
    echo  %C2W_ESC%[36m------------------------------------%C2W_ESC%[0m

    :: Clear mock log for this test file
    if exist "%C2W_MOCK_LOG%" del /f /q "%C2W_MOCK_LOG%" >nul 2>&1

    :: Run the test file
    call "%%f"

    :: Compute delta
    set /a "_FILE_PASS=C2W_PASS - _PASS_BEFORE"
    set /a "_FILE_FAIL=C2W_FAIL - _FAIL_BEFORE"

    if !_FILE_FAIL! equ 0 (
        echo.
        echo    %C2W_ESC%[92m!_FILE_PASS! passed%C2W_ESC%[0m
        set /a FILE_PASS+=1
    ) else (
        echo.
        echo    %C2W_ESC%[92m!_FILE_PASS! passed%C2W_ESC%[0m, %C2W_ESC%[91m!_FILE_FAIL! failed%C2W_ESC%[0m
        set /a FILE_FAIL+=1
    )
    echo.
)

if %FILE_COUNT% equ 0 (
    echo  %C2W_ESC%[93m[WARN] No test files found matching: !TEST_PATTERN!%C2W_ESC%[0m
    echo.
)

:: ---- Cleanup: unregister any WSL distros created during tests ----
set "_WSL_TMP2=%TEMP%\c2w_wsllist2_%RANDOM%.txt"
set "_WSL_ASCII2=%TEMP%\c2w_wslascii2_%RANDOM%.txt"
wsl --list --quiet > "!_WSL_TMP2!" 2>&1
powershell -noprofile -command "Get-Content -Path '!_WSL_TMP2!' -Encoding Unicode | Out-File -Encoding ascii '!_WSL_ASCII2!'" 2>nul

set "_CLEANED=0"
for /f "usebackq tokens=*" %%n in ("!_WSL_ASCII2!") do (
    set "_NAME=%%n"
    for /l %%i in (1,1,5) do if "!_NAME:~-1!"==" " set "_NAME=!_NAME:~0,-1!"
    :: Check for our test ID prefix
    if "!_NAME:~0,4!"=="c2wt" (
        wsl --unregister !_NAME! >nul 2>&1
        if !_CLEANED! equ 0 echo  %C2W_ESC%[90mCleaning up test distros...%C2W_ESC%[0m
        echo    %C2W_ESC%[90mUnregistered: !_NAME!%C2W_ESC%[0m
        set /a _CLEANED+=1
    )
)
del /f /q "!_WSL_TMP2!" "!_WSL_ASCII2!" >nul 2>&1

:: Also clean up storage dirs under C:\wsl-storage matching our test ID
for /d %%d in ("C:\wsl-storage\!C2W_TEST_ID!*") do (
    rmdir /s /q "%%d" >nul 2>&1
)
if !_CLEANED! gtr 0 echo.

:: ---- Cleanup temp dir ----
if exist "%C2W_TMPDIR%" rmdir /s /q "%C2W_TMPDIR%" >nul 2>&1

:: ---- Summary ----
echo  %C2W_ESC%[97m============================================================%C2W_ESC%[0m
if !C2W_FAIL! gtr 0 (
    echo   Assertions: %C2W_ESC%[92m!C2W_PASS! passed%C2W_ESC%[0m  %C2W_ESC%[91m!C2W_FAIL! failed%C2W_ESC%[0m
) else (
    echo   Assertions: %C2W_ESC%[92m!C2W_PASS! passed%C2W_ESC%[0m
)
if !FILE_FAIL! gtr 0 (
    echo   Files:      %C2W_ESC%[92m!FILE_PASS! passed%C2W_ESC%[0m  %C2W_ESC%[91m!FILE_FAIL! failed%C2W_ESC%[0m
) else (
    echo   Files:      %C2W_ESC%[92m!FILE_PASS! passed%C2W_ESC%[0m
)
echo  %C2W_ESC%[97m============================================================%C2W_ESC%[0m
echo.

if !C2W_FAIL! gtr 0 (
    echo  %C2W_ESC%[1;91m FAIL %C2W_ESC%[0m
    echo.
    exit /b 1
)
echo  %C2W_ESC%[1;92m PASS %C2W_ESC%[0m
echo.
exit /b 0
