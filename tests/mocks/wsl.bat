@echo off
:: ============================================================
::  tests\mocks\wsl.bat  — Mock wsl executable for testing
::
::  Control variables:
::    C2W_MOCK_WSL_IMPORT_FAIL    1 = wsl --import fails (default: 0)
::    C2W_MOCK_WSL_BASH_FAIL      1 = wsl bash commands fail (default: 0)
::    C2W_MOCK_LOG                path to log file (optional)
:: ============================================================
setlocal enabledelayedexpansion

if not defined C2W_MOCK_WSL_IMPORT_FAIL  set "C2W_MOCK_WSL_IMPORT_FAIL=0"
if not defined C2W_MOCK_WSL_BASH_FAIL    set "C2W_MOCK_WSL_BASH_FAIL=0"

if defined C2W_MOCK_LOG echo wsl %* >> "%C2W_MOCK_LOG%"

if "%~1"=="--import"    goto :do_import
if "%~1"=="--terminate" goto :do_terminate
if "%~1"=="-d"          goto :do_run
if "%~1"=="--list"      goto :do_list

echo [MOCK wsl] Unhandled arguments: %*
exit /b 0

:do_import
:: wsl --import <name> <location> <tar> [--version N]
if %C2W_MOCK_WSL_IMPORT_FAIL% equ 1 (
    echo [MOCK wsl] --import failed
    exit /b 1
)
echo [MOCK wsl] --import %~2 %~3 %~4
exit /b 0

:do_terminate
:: wsl --terminate <name>
echo [MOCK wsl] --terminate %~2
exit /b 0

:do_run
:: wsl -d <name> [-u <user>] -- bash -c <cmd>
if %C2W_MOCK_WSL_BASH_FAIL% equ 1 (
    echo [MOCK wsl] bash command failed
    exit /b 1
)
echo [MOCK wsl] -d %~2 (bash command)
exit /b 0

:do_list
echo [MOCK wsl] --list
exit /b 0
