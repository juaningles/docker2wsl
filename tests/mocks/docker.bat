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
::    C2W_MOCK_INSPECT_FILE   file whose content `image inspect` prints (optional JSON)
::    C2W_MOCK_LOG            path to log file (optional)
::    C2W_MOCK_CT_EXISTS      1 = container inspect finds the container (default: 0)
::    C2W_MOCK_RUN_FAIL       1 = docker run fails (default: 0)
::    C2W_MOCK_EXEC_FAIL      1 = docker exec fails (default: 0)
::    C2W_MOCK_COMMIT_FAIL    1 = docker commit fails (default: 0)
:: ============================================================
setlocal enabledelayedexpansion

if not defined C2W_MOCK_IMAGE_EXISTS  set "C2W_MOCK_IMAGE_EXISTS=0"
if not defined C2W_MOCK_PULL_FAIL     set "C2W_MOCK_PULL_FAIL=0"
if not defined C2W_MOCK_CREATE_FAIL   set "C2W_MOCK_CREATE_FAIL=0"
if not defined C2W_MOCK_EXPORT_FAIL   set "C2W_MOCK_EXPORT_FAIL=0"
if not defined C2W_MOCK_CONTAINER_ID  set "C2W_MOCK_CONTAINER_ID=mock-container-abc123"
if not defined C2W_MOCK_CT_EXISTS     set "C2W_MOCK_CT_EXISTS=0"
if not defined C2W_MOCK_RUN_FAIL      set "C2W_MOCK_RUN_FAIL=0"
if not defined C2W_MOCK_EXEC_FAIL     set "C2W_MOCK_EXEC_FAIL=0"
if not defined C2W_MOCK_COMMIT_FAIL   set "C2W_MOCK_COMMIT_FAIL=0"

if defined C2W_MOCK_LOG echo docker %* >> "%C2W_MOCK_LOG%"

:: Dispatch on first argument using explicit if chains
if "%~1"=="image"  goto :do_image
if "%~1"=="pull"   goto :do_pull
if "%~1"=="create" goto :do_create
if "%~1"=="export" goto :do_export
if "%~1"=="rm"     goto :do_rm
if "%~1"=="container" goto :do_container
if "%~1"=="run"    goto :do_run
if "%~1"=="exec"   goto :do_exec
if "%~1"=="commit" goto :do_commit
if "%~1"=="--version" goto :do_version

echo [MOCK docker] Unhandled subcommand: %*
exit /b 0

:do_image
:: docker image inspect <name>  → 0 if exists, 1 if not
if %C2W_MOCK_IMAGE_EXISTS% neq 1 exit /b 1
if defined C2W_MOCK_INSPECT_FILE if exist "%C2W_MOCK_INSPECT_FILE%" type "%C2W_MOCK_INSPECT_FILE%"
exit /b 0

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

:do_container
:: docker container inspect <name>  -> 0 if C2W_MOCK_CT_EXISTS=1
if %C2W_MOCK_CT_EXISTS% equ 1 exit /b 0
exit /b 1

:do_run
:: docker run -d --name N ... IMAGE infinity: echo the full command line for the tests
if %C2W_MOCK_RUN_FAIL% equ 1 (
    echo [MOCK docker] run failed
    exit /b 1
)
echo [MOCK docker] run: %*
echo %C2W_MOCK_CONTAINER_ID%
exit /b 0

:do_exec
:: docker exec -u USER NAME cmd...
if %C2W_MOCK_EXEC_FAIL% equ 1 (
    echo [MOCK docker] exec failed
    exit /b 1
)
echo [MOCK docker] exec -u %~3 %~4 (command)
exit /b 0

:do_commit
if %C2W_MOCK_COMMIT_FAIL% equ 1 (
    echo [MOCK docker] commit failed
    exit /b 1
)
echo [MOCK docker] commit: %*
exit /b 0

:do_version
echo MOCK docker version 0.0
exit /b 0
