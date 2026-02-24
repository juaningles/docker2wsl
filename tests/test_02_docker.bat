@echo off
setlocal enabledelayedexpansion
:: ============================================================
::  test_02_docker.bat  — Docker image check / pull / export tests
::
::  Injects mock docker and wsl commands via PATH override.
::  WSL mock is always in SUCCESS mode so only docker behaviour
::  is exercised here.
:: ============================================================

set "SCRIPT=%~dp0..\container2wsl.bat"
set "OUT=%C2W_TMPDIR%\docker_out.txt"

:: Prepend mocks directory so mock docker/wsl are found first
set "PATH=%C2W_TMPDIR%;%MOCKS_DIR%;%PATH%"

:: Copy wsl mock to temp dir (always succeeds)
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

:: ---- Helper: reset all mock vars ----
call :reset_mocks 2>nul

:: ============================================================
::  1. Image exists locally — no pull
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m image found locally: no pull
call :reset_mocks 2>nul
set "C2W_MOCK_IMAGE_EXISTS=1"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-localimg > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "local-image: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Found locally" "local-image: found locally message"
call "%HELPERS%" assert_output_not_contains "%OUT%" "Pulling from registry" "local-image: no pull message"

:: ============================================================
::  2. Image not local — pull succeeds
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m image not local, pull succeeds
call :reset_mocks 2>nul
set "C2W_MOCK_IMAGE_EXISTS=0"
set "C2W_MOCK_PULL_FAIL=0"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-pullok > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "pull-success: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Pulling from registry" "pull-success: pull attempted"
call "%HELPERS%" assert_output_contains "%OUT%" "Pull complete" "pull-success: pull complete message"

:: ============================================================
::  3. Image not local — pull fails → exit 1
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m image not local, pull fails
call :reset_mocks 2>nul
set "C2W_MOCK_IMAGE_EXISTS=0"
set "C2W_MOCK_PULL_FAIL=1"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-pullfail > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "pull-fail: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "ERROR" "pull-fail: error message shown"

:: ============================================================
::  4. Export succeeds — tar file created
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m docker export creates tar file
call :reset_mocks 2>nul
set "C2W_MOCK_IMAGE_EXISTS=1"
set "C2W_MOCK_EXPORT_FAIL=0"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-export > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "export-success: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Export complete" "export-success: export complete message"

:: ============================================================
::  5. docker create fails → exit 1
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m docker create fails
call :reset_mocks 2>nul
set "C2W_MOCK_IMAGE_EXISTS=1"
set "C2W_MOCK_CREATE_FAIL=1"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-createfail > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "create-fail: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "ERROR" "create-fail: error message shown"

:: ============================================================
::  6. docker export fails → exit 1
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m docker export fails
call :reset_mocks 2>nul
set "C2W_MOCK_IMAGE_EXISTS=1"
set "C2W_MOCK_EXPORT_FAIL=1"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-exportfail > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "export-fail: non-zero exit"

endlocal & set "C2W_PASS=%C2W_PASS%"& set "C2W_FAIL=%C2W_FAIL%"
goto :eof

:reset_mocks
set "C2W_MOCK_IMAGE_EXISTS=0"
set "C2W_MOCK_PULL_FAIL=0"
set "C2W_MOCK_CREATE_FAIL=0"
set "C2W_MOCK_EXPORT_FAIL=0"
set "C2W_MOCK_WSL_IMPORT_FAIL=0"
set "C2W_MOCK_WSL_BASH_FAIL=0"
set "C2W_MOCK_CONTAINER_ID=mock-container-abc123"
exit /b 0
