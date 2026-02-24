@echo off
:: ============================================================
::  tests\mocks\docker.bat  — Mock docker executable for testing
::
::  Control variables (set before calling the script):
::    C2W_MOCK_IMAGE_EXISTS   1 = image inspect succeeds (default: 0)
::    C2W_MOCK_PULL_FAIL      1 = docker pull returns error (default: 0)
::    C2W_MOCK_CREATE_FAIL    1 = docker create returns error (default: 0)
::    C2W_MOCK_EXPORT_FAIL    1 = docker export returns error (default: 0)
::    C2W_MOCK_CONTAINER_ID   ID echoed on create (default: mock-container-abc123)
::    C2W_MOCK_LOG            path to log file (optional)
:: ============================================================
setlocal enabledelayedexpansion

if not defined C2W_MOCK_IMAGE_EXISTS  set "C2W_MOCK_IMAGE_EXISTS=0"
if not defined C2W_MOCK_PULL_FAIL     set "C2W_MOCK_PULL_FAIL=0"
if not defined C2W_MOCK_CREATE_FAIL   set "C2W_MOCK_CREATE_FAIL=0"
if not defined C2W_MOCK_EXPORT_FAIL   set "C2W_MOCK_EXPORT_FAIL=0"
if not defined C2W_MOCK_CONTAINER_ID  set "C2W_MOCK_CONTAINER_ID=mock-container-abc123"

if defined C2W_MOCK_LOG echo docker %* >> "%C2W_MOCK_LOG%"

:: Dispatch on first argument using explicit if chains
if "%~1"=="image"  goto :do_image
if "%~1"=="pull"   goto :do_pull
if "%~1"=="create" goto :do_create
if "%~1"=="export" goto :do_export
if "%~1"=="rm"     goto :do_rm

echo [MOCK docker] Unhandled subcommand: %*
exit /b 0

:do_image
:: docker image inspect <name>  → 0 if exists, 1 if not
if %C2W_MOCK_IMAGE_EXISTS% equ 1 exit /b 0
exit /b 1

:do_pull
:: docker pull <image>
if %C2W_MOCK_PULL_FAIL% equ 1 (
    echo [MOCK docker] pull failed
    exit /b 1
)
echo [MOCK docker] pull: %~2
exit /b 0

:do_create
:: docker create <image>  →  echoes container ID
:: On failure: output goes to stderr (which callers typically discard) so for/f captures nothing
if %C2W_MOCK_CREATE_FAIL% equ 1 (
    echo [MOCK docker] create failed>&2
    exit /b 1
)
echo %C2W_MOCK_CONTAINER_ID%
exit /b 0

:do_export
:: docker export CONTAINER_ID -o OUTPUT_PATH
:: Args: %1=export  %2=container_id  %3=-o  %4=output_path
if %C2W_MOCK_EXPORT_FAIL% equ 1 (
    echo [MOCK docker] export failed
    exit /b 1
)
if "%~3"=="-o" (
    echo [MOCK docker] creating fake tar: %~4
    type nul > "%~4"
) else (
    echo [MOCK docker] export: unexpected args: %*
)
exit /b 0

:do_rm
:: docker rm -f <container>  — always succeed silently
exit /b 0
