@echo off
:: ============================================================
::  tests\mocks\wsl.bat  — Mock wsl executable for testing
::
::  Control variables:
::    C2W_MOCK_WSL_IMPORT_FAIL    1 = wsl --import fails (default: 0)
::    C2W_MOCK_WSL_BASH_FAIL      1 = wsl bash commands fail (default: 0)
::    C2W_MOCK_WSL_DISTRO_EXISTS  name of distro to report as existing (default: unset)
::    C2W_MOCK_LOG                path to log file (optional)
:: ============================================================
setlocal enabledelayedexpansion

if not defined C2W_MOCK_WSL_IMPORT_FAIL  set "C2W_MOCK_WSL_IMPORT_FAIL=0"
if not defined C2W_MOCK_WSL_BASH_FAIL    set "C2W_MOCK_WSL_BASH_FAIL=0"

if defined C2W_MOCK_LOG echo wsl %* >> "%C2W_MOCK_LOG%"

if "%~1"=="--import"      goto :do_import
if "%~1"=="--terminate"   goto :do_terminate
if "%~1"=="--unregister"  goto :do_unregister
if "%~1"=="-d"            goto :do_run
if "%~1"=="--list"        goto :do_list

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

:do_unregister
:: wsl --unregister <name>
:: Write a sentinel file so subsequent --list calls know it was unregistered
if defined C2W_TMPDIR (
    echo %~2 > "%C2W_TMPDIR%\c2w_mock_unregistered.flag"
)
echo [MOCK wsl] --unregister %~2
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
:: When C2W_MOCK_WSL_DISTRO_EXISTS is set, output its value as UTF-16 LE
:: (matching real wsl --list --quiet output encoding)
:: If the sentinel file exists (from --unregister), skip reporting the distro.
if defined C2W_MOCK_WSL_DISTRO_EXISTS (
    if defined C2W_TMPDIR (
        if exist "%C2W_TMPDIR%\c2w_mock_unregistered.flag" goto :do_list_empty
    )
    powershell -noprofile -command "[Console]::OutputEncoding = [Text.Encoding]::Unicode; Write-Host '%C2W_MOCK_WSL_DISTRO_EXISTS%'"
    exit /b 0
)
:do_list_empty
echo [MOCK wsl] --list
exit /b 0
