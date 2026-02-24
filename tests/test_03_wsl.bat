@echo off
setlocal enabledelayedexpansion
:: ============================================================
::  test_03_wsl.bat  — WSL import and user configuration tests
::
::  Docker mock is always in SUCCESS mode so only WSL behaviour
::  is exercised here.
:: ============================================================

set "SCRIPT=%~dp0..\container2wsl.bat"
set "OUT=%C2W_TMPDIR%\wsl_out.txt"

:: Prepend mocks directory so mock docker/wsl are found first
set "PATH=%C2W_TMPDIR%;%MOCKS_DIR%;%PATH%"

:: Place docker mock (always succeeds)
set "C2W_MOCK_IMAGE_EXISTS=1"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1

:: ---- Helper: reset WSL mock vars ----
call :reset_mocks 2>nul

:: ============================================================
::  1. WSL import succeeds
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m wsl --import succeeds
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-import > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "wsl-import-ok: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Import complete" "wsl-import-ok: import complete message"

:: ============================================================
::  2. WSL import fails → exit 1
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m wsl --import fails
call :reset_mocks 2>nul
set "C2W_MOCK_WSL_IMPORT_FAIL=1"
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-importfail > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "wsl-import-fail: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "ERROR" "wsl-import-fail: error message shown"

:: ============================================================
::  3. Default user configured (default = wsluser)
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m default user configured (wsluser)
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-defuser > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "default-user: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "wsluser" "default-user: wsluser appears in output"
call "%HELPERS%" assert_output_contains "%OUT%" "Default user set" "default-user: confirmation message"

:: ============================================================
::  4. Custom user configured
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m custom user configured (alice)
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-custuser --user alice > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "custom-user: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "alice" "custom-user: alice appears in output"

:: ============================================================
::  5. WSL bash commands fail → exit 1
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m wsl bash commands fail (user config step)
call :reset_mocks 2>nul
set "C2W_MOCK_WSL_BASH_FAIL=1"
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bashfail > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "wsl-bash-fail: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "ERROR" "wsl-bash-fail: error message shown"

:: ============================================================
::  6. Storage directory created at custom location
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m custom storage location used in wsl --import
call :reset_mocks 2>nul
set "C2W_MOCK_LOG=%C2W_TMPDIR%\mock_calls.log"
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1
if exist "%C2W_MOCK_LOG%" del /f /q "%C2W_MOCK_LOG%" >nul 2>&1

set "_CUSTOM_STORAGE=%C2W_TMPDIR%\custom-wsl"
call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-custloc --location "%_CUSTOM_STORAGE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "custom-location: exit 0"
call "%HELPERS%" assert_file_exists "%_CUSTOM_STORAGE%\%C2W_TEST_ID%-custloc" "custom-location: storage dir created"

:: ============================================================
::  7. SUCCESS banner shown on completion
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m success message shown at end
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-success > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "SUCCESS" "success-banner: SUCCESS in output"
call "%HELPERS%" assert_output_contains "%OUT%" "wsl -d %C2W_TEST_ID%-success" "success-banner: start command shown"

endlocal & set "C2W_PASS=%C2W_PASS%"& set "C2W_FAIL=%C2W_FAIL%"
goto :eof

:reset_mocks
set "C2W_MOCK_IMAGE_EXISTS=1"
set "C2W_MOCK_PULL_FAIL=0"
set "C2W_MOCK_CREATE_FAIL=0"
set "C2W_MOCK_EXPORT_FAIL=0"
set "C2W_MOCK_WSL_IMPORT_FAIL=0"
set "C2W_MOCK_WSL_BASH_FAIL=0"
set "C2W_MOCK_CONTAINER_ID=mock-container-abc123"
set "C2W_MOCK_LOG="
exit /b 0
