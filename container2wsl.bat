@echo off
:: Capture the command line for the manifest before delayed expansion can eat "!".
setlocal
set "C2W_ARGV=%*"
set "C2W_CWD=%CD%"
:: An inherited C2W_PRIVATE_DIRS is an input (default for --private); the script rebuilds the
:: variable itself, so keep the caller's value under another name.
set "C2W_PRIVATE_DIRS_IN=%C2W_PRIVATE_DIRS%"
:: Same for C2W_TARGET (default for --target): the script sets it for the straps.
set "C2W_TARGET_IN=%C2W_TARGET%"
:: Set only when this run was started by --recipe (see :recipe_run); recorded in the manifest.
set "C2W_RECIPE=%_C2W_FROM_RECIPE%"
set "_C2W_FROM_RECIPE="
:: Script folder, captured before argument parsing: plain `shift` also shifts %0,
:: so %~dp0 is wrong in the main flow afterwards (subroutines are fine).
set "C2W_SCRIPT_DIR=%~dp0"
setlocal enabledelayedexpansion

:: ============================================================
::  container2wsl.bat
::  Creates a WSL instance from a Docker image.
::
::  Usage:
::    container2wsl.bat <image> [options]
::
::  Options:
::    --name,     -n <name>   WSL distro name (default: derived from image)
::    --user,     -u <user>   Default user   (default: wsluser)
::    --location, -l <path>   WSL storage    (default: C:\wsl-storage)
::    --bootstrap, -b <file>  Run commands from file as root after setup (repeatable)
::    --poststrap, -p <file>  Run commands from file as user after setup (repeatable)
::    --private <dir>         Private overlay folder (repeatable). Default: C2W_PRIVATE_DIRS
::                            (semicolon list), else sibling folders of this script that
::                            contain a .devtools-overlay marker file.
::    --force,    -f          Overwrite existing WSL distro with same name
::    --target <wsl|container>  Build a WSL distro (default, or C2W_TARGET) or a running
::                            docker/podman container named after --name
::    --commit <image:tag>    Container target: also save the result as an image
::    --dry-run               Parse and print config, do not execute
::    --recipe <name|file>    Defaults from a recipe: recipes\<name>.conf here or in a private overlay
::                            (or a .conf path); the other arguments still override them
::    --recipes               List the recipes in the private overlays
::    --help,     -h          Show this help
::
::  Bootstrap variables (use %VAR% syntax in bootstrap files):
::    %C2W_NAME%       WSL distro name
::    %C2W_USER%       Default Linux user
::    %C2W_IMAGE%      Docker image name
::    %C2W_TARGET%     wsl or container
::    %C2W_ENGINE%     wsl, docker or podman
::    %C2W_LOCATION%   WSL storage root path
::    %C2W_SCRIPT_DIR%       this script's folder (Windows, trailing \)
::    %C2W_SCRIPT_DIR_LX%    the same as /mnt/<drive>/... (no trailing /)
::    %C2W_STRAP_DIR%        folder of the strap being run (Windows, trailing \)
::    %C2W_STRAP_DIR_LX%     the same as /mnt/<drive>/...
::    %C2W_USERPROFILE_LX%   the Windows user profile as /mnt/<drive>/Users/<name>
::    %C2W_PRIVATE_DIRS%     private overlay folders, Windows paths, ; separated
::    %C2W_PRIVATE_DIRS_LX%  the same as /mnt paths, : separated
::    (plus any standard environment variables)
::  Bare strap names resolve from bootstraps\ / poststraps\ here, then from each private
::  folder's straps\, bootstraps\ and poststraps\.
:: ============================================================

set "VERSION=1.0.0"

:: --- Recipes: --recipe expands into arguments and the script runs again with them ---
set "_RCP=" & set "_RCP_SET=0" & set "_RCP_LIST=0" & set "_RCP_REST=" & set "_RCP_PRIV="
call :recipe_scan %*
if "%_RCP_LIST%"=="1" goto :recipe_list_exit
if "%_RCP_SET%"=="1" goto :recipe_run
set "SCRIPT_NAME=%~n0"

:: --- Defaults (C2W_LOCATION overrides the storage root for every build) ---
if defined C2W_LOCATION (set "DEFAULT_STORAGE=%C2W_LOCATION%") else set "DEFAULT_STORAGE=%SystemDrive%\wsl-storage"
set "DEFAULT_USER=wsluser"

:: --- Runtime flags ---
set "DRY_RUN=0"
set "FORCE=0"

:: --- Parsed values (empty until set) ---
set "ARG_IMAGE="
set "ARG_WSL_NAME="
set "ARG_WSL_USER="
set "ARG_WSL_LOCATION="
set "ARG_BOOTSTRAP_N=0"
set "ARG_POSTSTRAP_N=0"
set "ARG_PRIVATE_N=0"
set "ARG_TARGET="
set "ARG_COMMIT="

:: ============================================================
::  ARGUMENT PARSING
:: ============================================================
:parse_args
if "%~1"==""           goto :after_parse
if "%~1"=="--help"     goto :show_help_ok
if "%~1"=="-h"         goto :show_help_ok
if "%~1"=="--dry-run"  goto :arg_dryrun
if "%~1"=="--force"    goto :arg_force
if "%~1"=="-f"         goto :arg_force
if "%~1"=="--name"     goto :arg_name
if "%~1"=="-n"         goto :arg_name
if "%~1"=="--user"     goto :arg_user
if "%~1"=="-u"         goto :arg_user
if "%~1"=="--location" goto :arg_location
if "%~1"=="-l"         goto :arg_location
if "%~1"=="--bootstrap" goto :arg_bootstrap
if "%~1"=="-b"          goto :arg_bootstrap
if "%~1"=="--poststrap" goto :arg_poststrap
if "%~1"=="-p"          goto :arg_poststrap
if "%~1"=="--private"   goto :arg_private
if "%~1"=="--target"    goto :arg_target
if "%~1"=="--commit"    goto :arg_commit
if not defined ARG_IMAGE goto :arg_image
echo [ERROR] Unexpected argument: %~1
echo.
goto :show_help_error

:arg_dryrun
set "DRY_RUN=1"
shift
goto :parse_args

:arg_force
set "FORCE=1"
shift
goto :parse_args

:arg_name
if "%~2"=="" (
    echo [ERROR] Missing value for option: %~1
    echo.
    goto :show_help_error
)
if "%~2"=="--help" goto :arg_name_invalid
if "%~2"=="-h" goto :arg_name_invalid
if "%~2"=="--dry-run" goto :arg_name_invalid
if "%~2"=="--name" goto :arg_name_invalid
if "%~2"=="-n" goto :arg_name_invalid
if "%~2"=="--user" goto :arg_name_invalid
if "%~2"=="-u" goto :arg_name_invalid
if "%~2"=="--location" goto :arg_name_invalid
if "%~2"=="-l" goto :arg_name_invalid
if "%~2"=="--bootstrap" goto :arg_name_invalid
if "%~2"=="-b" goto :arg_name_invalid
if "%~2"=="--poststrap" goto :arg_name_invalid
if "%~2"=="-p" goto :arg_name_invalid
if "%~2"=="--force" goto :arg_name_invalid
if "%~2"=="-f" goto :arg_name_invalid
set "ARG_WSL_NAME=%~2"
shift
shift
goto :parse_args

:arg_name_invalid
echo [ERROR] Missing value for option: %~1
echo.
goto :show_help_error

:arg_user
if "%~2"=="" (
    echo [ERROR] Missing value for option: %~1
    echo.
    goto :show_help_error
)
if "%~2"=="--help" goto :arg_user_invalid
if "%~2"=="-h" goto :arg_user_invalid
if "%~2"=="--dry-run" goto :arg_user_invalid
if "%~2"=="--name" goto :arg_user_invalid
if "%~2"=="-n" goto :arg_user_invalid
if "%~2"=="--user" goto :arg_user_invalid
if "%~2"=="-u" goto :arg_user_invalid
if "%~2"=="--location" goto :arg_user_invalid
if "%~2"=="-l" goto :arg_user_invalid
if "%~2"=="--bootstrap" goto :arg_user_invalid
if "%~2"=="-b" goto :arg_user_invalid
if "%~2"=="--poststrap" goto :arg_user_invalid
if "%~2"=="-p" goto :arg_user_invalid
if "%~2"=="--force" goto :arg_user_invalid
if "%~2"=="-f" goto :arg_user_invalid
set "ARG_WSL_USER=%~2"
shift
shift
goto :parse_args

:arg_user_invalid
echo [ERROR] Missing value for option: %~1
echo.
goto :show_help_error

:arg_location
if "%~2"=="" (
    echo [ERROR] Missing value for option: %~1
    echo.
    goto :show_help_error
)
if "%~2"=="--help" goto :arg_location_invalid
if "%~2"=="-h" goto :arg_location_invalid
if "%~2"=="--dry-run" goto :arg_location_invalid
if "%~2"=="--name" goto :arg_location_invalid
if "%~2"=="-n" goto :arg_location_invalid
if "%~2"=="--user" goto :arg_location_invalid
if "%~2"=="-u" goto :arg_location_invalid
if "%~2"=="--location" goto :arg_location_invalid
if "%~2"=="-l" goto :arg_location_invalid
if "%~2"=="--bootstrap" goto :arg_location_invalid
if "%~2"=="-b" goto :arg_location_invalid
if "%~2"=="--poststrap" goto :arg_location_invalid
if "%~2"=="-p" goto :arg_location_invalid
if "%~2"=="--force" goto :arg_location_invalid
if "%~2"=="-f" goto :arg_location_invalid
set "ARG_WSL_LOCATION=%~2"
shift
shift
goto :parse_args

:arg_location_invalid
echo [ERROR] Missing value for option: %~1
echo.
goto :show_help_error

:arg_bootstrap
if "%~2"=="" (
    echo [ERROR] Missing value for option: %~1
    echo.
    goto :show_help_error
)
if "%~2"=="--help" goto :arg_bootstrap_invalid
if "%~2"=="-h" goto :arg_bootstrap_invalid
if "%~2"=="--dry-run" goto :arg_bootstrap_invalid
if "%~2"=="--name" goto :arg_bootstrap_invalid
if "%~2"=="-n" goto :arg_bootstrap_invalid
if "%~2"=="--user" goto :arg_bootstrap_invalid
if "%~2"=="-u" goto :arg_bootstrap_invalid
if "%~2"=="--location" goto :arg_bootstrap_invalid
if "%~2"=="-l" goto :arg_bootstrap_invalid
if "%~2"=="--bootstrap" goto :arg_bootstrap_invalid
if "%~2"=="-b" goto :arg_bootstrap_invalid
if "%~2"=="--poststrap" goto :arg_bootstrap_invalid
if "%~2"=="-p" goto :arg_bootstrap_invalid
if "%~2"=="--force" goto :arg_bootstrap_invalid
if "%~2"=="-f" goto :arg_bootstrap_invalid
set /a ARG_BOOTSTRAP_N+=1
set "ARG_BOOTSTRAP_!ARG_BOOTSTRAP_N!=%~2"
set "ARG_BOOTSTRAP_REQ_!ARG_BOOTSTRAP_N!=%~2"
shift
shift
goto :parse_args

:arg_bootstrap_invalid
echo [ERROR] Missing value for option: %~1
echo.
goto :show_help_error

:arg_poststrap
if "%~2"=="" (
    echo [ERROR] Missing value for option: %~1
    echo.
    goto :show_help_error
)
if "%~2"=="--help" goto :arg_poststrap_invalid
if "%~2"=="-h" goto :arg_poststrap_invalid
if "%~2"=="--dry-run" goto :arg_poststrap_invalid
if "%~2"=="--name" goto :arg_poststrap_invalid
if "%~2"=="-n" goto :arg_poststrap_invalid
if "%~2"=="--user" goto :arg_poststrap_invalid
if "%~2"=="-u" goto :arg_poststrap_invalid
if "%~2"=="--location" goto :arg_poststrap_invalid
if "%~2"=="-l" goto :arg_poststrap_invalid
if "%~2"=="--bootstrap" goto :arg_poststrap_invalid
if "%~2"=="-b" goto :arg_poststrap_invalid
if "%~2"=="--poststrap" goto :arg_poststrap_invalid
if "%~2"=="-p" goto :arg_poststrap_invalid
if "%~2"=="--force" goto :arg_poststrap_invalid
if "%~2"=="-f" goto :arg_poststrap_invalid
set /a ARG_POSTSTRAP_N+=1
set "ARG_POSTSTRAP_!ARG_POSTSTRAP_N!=%~2"
set "ARG_POSTSTRAP_REQ_!ARG_POSTSTRAP_N!=%~2"
shift
shift
goto :parse_args

:arg_poststrap_invalid
echo [ERROR] Missing value for option: %~1
echo.
goto :show_help_error

:arg_private
if "%~2"=="" (
    echo [ERROR] Missing value for option: %~1
    echo.
    goto :show_help_error
)
if not exist "%~2\" (
    echo [ERROR] --private folder not found: %~2
    exit /b 1
)
set /a ARG_PRIVATE_N+=1
set "ARG_PRIVATE_!ARG_PRIVATE_N!=%~f2"
shift
shift
goto :parse_args

:arg_target
if "%~2"=="" (
    echo [ERROR] Missing value for option: %~1
    echo.
    goto :show_help_error
)
set "ARG_TARGET=%~2"
shift
shift
goto :parse_args

:arg_commit
if "%~2"=="" (
    echo [ERROR] Missing value for option: %~1
    echo.
    goto :show_help_error
)
set "ARG_COMMIT=%~2"
shift
shift
goto :parse_args

:arg_image
set "ARG_IMAGE=%~1"
shift
goto :parse_args

:after_parse
:: --- Validate required args ---
if not defined ARG_IMAGE (
    echo [ERROR] Docker image name is required.
    echo.
    goto :show_help_error
)

:: --- Apply defaults ---
if not defined ARG_TARGET if defined C2W_TARGET_IN set "ARG_TARGET=%C2W_TARGET_IN%"
if not defined ARG_TARGET set "ARG_TARGET=wsl"
if /i "%ARG_TARGET%"=="wsl" set "ARG_TARGET=wsl"
if /i "%ARG_TARGET%"=="container" set "ARG_TARGET=container"
if not "%ARG_TARGET%"=="wsl" if not "%ARG_TARGET%"=="container" (
    echo [ERROR] --target must be wsl or container, not: %ARG_TARGET%
    exit /b 1
)
if defined ARG_COMMIT if "%ARG_TARGET%"=="wsl" (
    echo [ERROR] --commit needs --target container.
    exit /b 1
)
if not defined ARG_WSL_USER     set "ARG_WSL_USER=%DEFAULT_USER%"
if not defined ARG_WSL_LOCATION set "ARG_WSL_LOCATION=%DEFAULT_STORAGE%"

:: --- Derive WSL name from image if not supplied ---
if not defined ARG_WSL_NAME (
    set "ARG_WSL_NAME=%ARG_IMAGE%"
    set "ARG_WSL_NAME=!ARG_WSL_NAME::=-!"
    set "ARG_WSL_NAME=!ARG_WSL_NAME:/=-!"
    set "ARG_WSL_NAME=!ARG_WSL_NAME:\=-!"
)

:: --- Private overlay folders: --private, else C2W_PRIVATE_DIRS, else siblings with a marker ---
set "C2W_PRIVATE_DIRS="
set "C2W_PRIVATE_DIRS_LX="
if %ARG_PRIVATE_N% geq 1 (
    for /l %%i in (1,1,%ARG_PRIVATE_N%) do call :add_private "!ARG_PRIVATE_%%i!"
) else if defined C2W_PRIVATE_DIRS_IN (
    for %%d in ("!C2W_PRIVATE_DIRS_IN:;=" "!") do if not "%%~d"=="" call :add_private "%%~fd"
) else (
    for /d %%d in ("%C2W_SCRIPT_DIR%..\*") do if exist "%%~fd\.devtools-overlay" call :add_private "%%~fd"
)

:: --- Paths every strap can use: this script and the Windows profile, in /mnt form ---
call :win2lx "%C2W_SCRIPT_DIR%" C2W_SCRIPT_DIR_LX
call :win2lx "%USERPROFILE%" C2W_USERPROFILE_LX

:: --- Resolve strap paths: as given, then <script_dir>\bootstraps|poststraps\<name>, then private folders ---
if %ARG_BOOTSTRAP_N% geq 1 for /l %%i in (1,1,%ARG_BOOTSTRAP_N%) do call :resolve_strap ARG_BOOTSTRAP_%%i bootstraps
if %ARG_POSTSTRAP_N% geq 1 for /l %%i in (1,1,%ARG_POSTSTRAP_N%) do call :resolve_strap ARG_POSTSTRAP_%%i poststraps

goto :main

:add_private
:: %~1 = folder (full path). Appends to C2W_PRIVATE_DIRS (;) and C2W_PRIVATE_DIRS_LX (:), no duplicates.
set "_AP=%~f1"
if "!_AP:~-1!"=="\" set "_AP=!_AP:~0,-1!"
if defined C2W_PRIVATE_DIRS if not "!C2W_PRIVATE_DIRS:%_AP%=!"=="!C2W_PRIVATE_DIRS!" goto :eof
call :win2lx "%_AP%" _AP_LX
if defined C2W_PRIVATE_DIRS (set "C2W_PRIVATE_DIRS=!C2W_PRIVATE_DIRS!;%_AP%") else set "C2W_PRIVATE_DIRS=%_AP%"
if defined C2W_PRIVATE_DIRS_LX (set "C2W_PRIVATE_DIRS_LX=!C2W_PRIVATE_DIRS_LX!:!_AP_LX!") else set "C2W_PRIVATE_DIRS_LX=!_AP_LX!"
goto :eof

:resolve_strap
:: %~1 = variable holding the strap as given   %~2 = bootstraps or poststraps
:: Every candidate must be a FILE ("exist X" alone is also true for a folder): run from C:\code,
:: "-b devtools" would otherwise pick the devtools repo folder in the current directory.
set "_RS_VAL=!%~1!"
if exist "%_RS_VAL%" if not exist "%_RS_VAL%\" goto :eof
if exist "%C2W_SCRIPT_DIR%%~2\%_RS_VAL%" if not exist "%C2W_SCRIPT_DIR%%~2\%_RS_VAL%\" (set "%~1=%C2W_SCRIPT_DIR%%~2\%_RS_VAL%" & goto :eof)
if exist "%C2W_SCRIPT_DIR%%_RS_VAL%" if not exist "%C2W_SCRIPT_DIR%%_RS_VAL%\" (set "%~1=%C2W_SCRIPT_DIR%%_RS_VAL%" & goto :eof)
if not defined C2W_PRIVATE_DIRS goto :eof
for %%d in ("!C2W_PRIVATE_DIRS:;=" "!") do (
    if exist "%%~d\straps\%_RS_VAL%" if not exist "%%~d\straps\%_RS_VAL%\" (set "%~1=%%~d\straps\%_RS_VAL%" & goto :eof)
    if exist "%%~d\%~2\%_RS_VAL%" if not exist "%%~d\%~2\%_RS_VAL%\" (set "%~1=%%~d\%~2\%_RS_VAL%" & goto :eof)
)
goto :eof

:win2lx
:: %~1 = Windows path   %~2 = variable to receive /mnt/<drive>/path (lowercase drive, no trailing /)
set "_W2L=%~1"
set "_W2L=!_W2L:\=/!"
if "!_W2L:~-1!"=="/" set "_W2L=!_W2L:~0,-1!"
set "_W2L_D=!_W2L:~0,1!"
for %%L in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do if /i "!_W2L_D!"=="%%L" set "_W2L_D=%%L"
set "%~2=/mnt/!_W2L_D!!_W2L:~2!"
goto :eof

:: ============================================================
:show_help_ok
set "_HELP_EXIT=1"
goto :show_help

:show_help_error
set "_HELP_EXIT=1"
goto :show_help

:show_help
:: ============================================================
echo.
echo Usage: %SCRIPT_NAME% ^<image^> [options]
echo.
echo  image                Docker image (e.g. ubuntu:22.04, myrepo/img:tag)
echo.
echo Options:
echo  --name,     -n NAME  WSL distribution name (default: derived from image)
echo  --user,     -u USER  Default Linux user    (default: %DEFAULT_USER%)
echo  --location, -l PATH  WSL storage root      (default: %DEFAULT_STORAGE%)
echo  --bootstrap, -b FILE Run commands from FILE as root after setup (repeatable)
echo  --poststrap, -p FILE Run commands from FILE as user after setup (repeatable)
echo  --private DIR        Private overlay folder for straps/ssh-keys (repeatable; default:
echo                       C2W_PRIVATE_DIRS, else siblings with a .devtools-overlay marker)
echo  --force,    -f       Overwrite existing WSL distro (or container) with same name
echo  --target T          wsl (default, or C2W_TARGET) or container: a running docker/podman
echo                       container named NAME instead of a WSL distro
echo  --commit IMAGE:TAG   container target: also save the result as an image
echo  --dry-run            Show resolved config without executing
echo  --recipe NAME        Defaults from ^<private overlay^>\recipes\NAME.conf ^(or a .conf path^);
echo                       the other arguments override them. --recipes lists them.
echo  --help,     -h       Show this help
echo.
echo Examples:
echo  %SCRIPT_NAME% ubuntu:22.04
echo  %SCRIPT_NAME% ubuntu:22.04 --name mydev --user john
echo  %SCRIPT_NAME% ubuntu:22.04 --location D:\wsl
echo  %SCRIPT_NAME% ubuntu:24.04 --target container --name dev -u john --commit localhost/dev:1
echo.
exit /b %_HELP_EXIT%

:: ============================================================
:main
:: ============================================================
set "DOCKER_CMD=docker"
where /q docker.bat
if not errorlevel 1 set "DOCKER_CMD=docker.bat"
set "WSL_CMD=wsl"
where /q wsl.bat
if not errorlevel 1 set "WSL_CMD=wsl.bat"

:: --- Target: how commands reach the distro or container (T_ROOT / T_USER prefix them) ---
set "C2W_TARGET=%ARG_TARGET%"
set "C2W_ENGINE=wsl"
set "T_ROOT=%WSL_CMD% -d %ARG_WSL_NAME% -u root --"
set "T_USER=%WSL_CMD% -d %ARG_WSL_NAME% -u %ARG_WSL_USER% --"
if "%ARG_TARGET%"=="container" call :ct_setup

echo.
echo  container2wsl v%VERSION%
echo  ----------------------------------------
echo  Image    : %ARG_IMAGE%
if "%ARG_TARGET%"=="wsl" echo  WSL Name : %ARG_WSL_NAME%
if "%ARG_TARGET%"=="container" echo  Container: %ARG_WSL_NAME% ^(%C2W_ENGINE%, via %DOCKER_CMD%^)
if defined ARG_COMMIT echo  Commit   : %ARG_COMMIT%
echo  User     : %ARG_WSL_USER%
if "%ARG_TARGET%"=="wsl" echo  Location : %ARG_WSL_LOCATION%\%ARG_WSL_NAME%
if "%ARG_TARGET%"=="container" echo  Records  : %ARG_WSL_LOCATION%\%ARG_WSL_NAME% ^(manifest copy only^)
if "%ARG_TARGET%"=="container" for %%m in (!CT_MOUNT_LIST!) do echo  Mount    : %%~m
if %ARG_BOOTSTRAP_N% geq 1 for /l %%i in (1,1,%ARG_BOOTSTRAP_N%) do echo  Bootstrap: !ARG_BOOTSTRAP_%%i!
if %ARG_POSTSTRAP_N% geq 1 for /l %%i in (1,1,%ARG_POSTSTRAP_N%) do echo  Poststrap: !ARG_POSTSTRAP_%%i!
if defined C2W_PRIVATE_DIRS for %%d in ("!C2W_PRIVATE_DIRS:;=" "!") do echo  Private  : %%~d
if not defined C2W_PRIVATE_DIRS echo  Private  : none (no --private, C2W_PRIVATE_DIRS or sibling .devtools-overlay marker)
if %FORCE%==1 if "%ARG_TARGET%"=="wsl" echo  Force    : yes (overwrite existing distro)
if %FORCE%==1 if "%ARG_TARGET%"=="container" echo  Force    : yes (remove an existing container of that name)
if exist "%C2W_SCRIPT_DIR%lib\manifest.ps1" echo  Manifest : /etc/container2wsl/manifest.jsonl, copy in !ARG_WSL_LOCATION!\!ARG_WSL_NAME!
if not exist "%C2W_SCRIPT_DIR%lib\manifest.ps1" echo  Manifest : off - lib\manifest.ps1 not found next to the script
if %DRY_RUN%==1 echo  Mode     : DRY RUN (no changes will be made)
echo  ----------------------------------------
echo.

if %DRY_RUN%==0 goto :after_dryrun
:: Set built-in variables so dry-run can show expanded commands
set "C2W_NAME=%ARG_WSL_NAME%"
set "C2W_USER=%ARG_WSL_USER%"
set "C2W_IMAGE=%ARG_IMAGE%"
set "C2W_LOCATION=%ARG_WSL_LOCATION%"
if %ARG_BOOTSTRAP_N% geq 1 for /l %%i in (1,1,%ARG_BOOTSTRAP_N%) do call :dryrun_bootstrap "!ARG_BOOTSTRAP_%%i!"
if %ARG_POSTSTRAP_N% geq 1 for /l %%i in (1,1,%ARG_POSTSTRAP_N%) do call :dryrun_poststrap "!ARG_POSTSTRAP_%%i!"
echo [DRY-RUN] All steps skipped.
exit /b 0

:dryrun_bootstrap
if not exist "%~1" (
    echo [DRY-RUN] WARNING: Bootstrap file not found: %~1
    echo.
    exit /b 0
)
if exist "%~1\" (
    echo [DRY-RUN] WARNING: Bootstrap is a folder, not a file: %~1
    echo.
    exit /b 0
)
echo [DRY-RUN] Bootstrap commands from: %~1 (as root)
call :set_strap_dir "%~1"
for /f "usebackq delims= eol=" %%L in ("%~1") do (
    set "_BS_LINE=%%L"
    if not "!_BS_LINE!"=="" if not "!_BS_LINE:~0,1!"=="#" (
        call set "_BS_EXPANDED=!_BS_LINE!"
        echo   !_BS_EXPANDED!
    )
)
echo.
exit /b 0

:dryrun_poststrap
if not exist "%~1" (
    echo [DRY-RUN] WARNING: Poststrap file not found: %~1
    echo.
    exit /b 0
)
if exist "%~1\" (
    echo [DRY-RUN] WARNING: Poststrap is a folder, not a file: %~1
    echo.
    exit /b 0
)
echo [DRY-RUN] Poststrap commands from: %~1 (as %C2W_USER%)
call :set_strap_dir "%~1"
for /f "usebackq delims= eol=" %%L in ("%~1") do (
    set "_BS_LINE=%%L"
    if not "!_BS_LINE!"=="" if not "!_BS_LINE:~0,1!"=="#" (
        call set "_BS_EXPANDED=!_BS_LINE!"
        echo   !_BS_EXPANDED!
    )
)
echo.
exit /b 0

:after_dryrun

:: --- Per-run temp folder: concurrent builds (or a build and the test suite) must not share
:: rendered scripts, stamps or manifests. Removed at the end; folders older than a day left
:: by a build that failed early are swept here.
forfiles /p "%TEMP%" /m c2w-run-* /d -1 /c "cmd /c if @isdir==TRUE rmdir /s /q @path" >nul 2>&1
set "C2W_TMP=%TEMP%\c2w-run-%RANDOM%%RANDOM%"
if exist "%C2W_TMP%\" set "C2W_TMP=%C2W_TMP%-%RANDOM%"
mkdir "%C2W_TMP%" 2>nul

:: --- Manifest bookkeeping (lib\manifest.ps1; skipped when the helper is absent) ---
set "C2W_MANIFEST=0"
if exist "%C2W_SCRIPT_DIR%lib\manifest.ps1" set "C2W_MANIFEST=1"
set "C2W_M_TMP=%C2W_TMP%\c2w_manifest.jsonl"
set "C2W_BUILD_START=%C2W_TMP%\c2w_build_start.txt"
set "C2W_STRAP_START=%C2W_TMP%\c2w_strap_start.txt"
set "C2W_STRAP_SEQ=0"
set "C2W_IMAGE_PULLED=0"
if "%C2W_MANIFEST%"=="1" powershell -noprofile -command "[DateTime]::UtcNow.ToString('o')" > "%C2W_BUILD_START%" 2>nul

:: --- Determine step count ---
set "STEP_COUNT=4"
if "%ARG_TARGET%"=="container" set "STEP_COUNT=3"
if defined ARG_COMMIT set /a STEP_COUNT+=1
if %ARG_BOOTSTRAP_N% geq 1 set /a STEP_COUNT+=1
if %ARG_POSTSTRAP_N% geq 1 set /a STEP_COUNT+=1

:: --- Step 1: Ensure Docker image is available locally ---
call :docker_ensure_image "%ARG_IMAGE%"
if errorlevel 1 (
    echo [ERROR] Could not obtain Docker image: %ARG_IMAGE%
    exit /b 1
)

if "%ARG_TARGET%"=="container" goto :ct_flow

:: --- Step 2: Export image to a tar archive ---
set "EXPORT_TAR=%C2W_TMP%\c2w_%ARG_WSL_NAME%.tar"
call :docker_export_image "%ARG_IMAGE%" "%EXPORT_TAR%"
if errorlevel 1 (
    echo [ERROR] Failed to export Docker image.
    exit /b 1
)

:: --- Step 3: Prepare storage directory ---
set "INSTALL_PATH=%ARG_WSL_LOCATION%\%ARG_WSL_NAME%"
if not exist "%INSTALL_PATH%\" (
    mkdir "%INSTALL_PATH%" 2>nul
    if errorlevel 1 (
        echo [ERROR] Failed to create storage directory: %INSTALL_PATH%
        exit /b 1
    )
    echo       Created: %INSTALL_PATH%
) else (
    echo       Directory exists: %INSTALL_PATH%
)

:: --- Check if distro already exists ---
call :wsl_distro_exists "%ARG_WSL_NAME%"
if !errorlevel! equ 0 (
    if %FORCE%==0 (
        echo [ERROR] WSL distribution '%ARG_WSL_NAME%' already exists. Use --force to overwrite.
        exit /b 1
    )
    call :wsl_force_unregister "%ARG_WSL_NAME%"
    if errorlevel 1 (
        echo [ERROR] Failed to unregister existing distro '%ARG_WSL_NAME%'.
        exit /b 1
    )
)

:: --- Step 4: Import tar as WSL distribution ---
call :wsl_import "%ARG_WSL_NAME%" "%INSTALL_PATH%" "%EXPORT_TAR%"
if errorlevel 1 (
    echo [ERROR] Failed to import WSL distribution.
    exit /b 1
)

:: --- Step 5: Configure default user ---
call :wsl_configure_user "%ARG_WSL_NAME%" "%ARG_WSL_USER%"
if errorlevel 1 (
    echo [ERROR] Failed to configure default user.
    exit /b 1
)

:after_target_setup
:: --- Manifest: source image, command line, requested straps, host ---
call :manifest create

:: --- Step 6 (optional): Run bootstrap commands ---
:: Set built-in variables for bootstrap file expansion.
:: Bootstrap commands can reference these as %C2W_NAME%, %C2W_USER%, etc.
:: Standard environment variables (e.g. %COMPUTERNAME%) also expand.
set "C2W_NAME=%ARG_WSL_NAME%"
set "C2W_USER=%ARG_WSL_USER%"
set "C2W_IMAGE=%ARG_IMAGE%"
set "C2W_LOCATION=%ARG_WSL_LOCATION%"
set "_NEXT_STEP=5"
if "%ARG_TARGET%"=="container" set "_NEXT_STEP=4"
if %ARG_BOOTSTRAP_N% geq 1 (
    set "BOOTSTRAP_STEP=!_NEXT_STEP!"
    set /a _NEXT_STEP+=1
    set "_BS_IDX=0"
    for /l %%i in (1,1,%ARG_BOOTSTRAP_N%) do (
        set /a _BS_IDX+=1
        set "C2W_M_REQ=!ARG_BOOTSTRAP_REQ_%%i!"
        call :wsl_bootstrap "%ARG_WSL_NAME%" "!ARG_BOOTSTRAP_%%i!" !_BS_IDX! %ARG_BOOTSTRAP_N% !BOOTSTRAP_STEP!
        if errorlevel 1 (
            echo [ERROR] Bootstrap failed.
            set "C2W_M_FAILED=bootstrap !_BS_IDX!: !ARG_BOOTSTRAP_REQ_%%i!"
            call :manifest_complete failed
            exit /b 1
        )
    )
)

:: --- Step 7 (optional): Run poststrap commands (as user) ---
if %ARG_POSTSTRAP_N% geq 1 (
    set "POSTSTRAP_STEP=!_NEXT_STEP!"
    set /a _NEXT_STEP+=1
    set "_PS_IDX=0"
    for /l %%i in (1,1,%ARG_POSTSTRAP_N%) do (
        set /a _PS_IDX+=1
        set "C2W_M_REQ=!ARG_POSTSTRAP_REQ_%%i!"
        call :wsl_poststrap "%ARG_WSL_NAME%" "!ARG_POSTSTRAP_%%i!" !_PS_IDX! %ARG_POSTSTRAP_N% !POSTSTRAP_STEP! "%ARG_WSL_USER%"
        if errorlevel 1 (
            echo [ERROR] Poststrap failed.
            set "C2W_M_FAILED=poststrap !_PS_IDX!: !ARG_POSTSTRAP_REQ_%%i!"
            call :manifest_complete failed
            exit /b 1
        )
    )
)

:: --- Cleanup temp tar ---
if exist "%EXPORT_TAR%" del /f /q "%EXPORT_TAR%" >nul 2>&1

set "C2W_M_FAILED="
if "%ARG_TARGET%"=="container" goto :ct_finish
call :manifest_complete ok

:: Stop the distro so the next interactive launch starts fresh and applies
:: /etc/wsl.conf default-user settings deterministically.
call %WSL_CMD% --terminate "%ARG_WSL_NAME%" >nul 2>&1

echo.
echo [SUCCESS] WSL distribution created.
echo           Name   : %ARG_WSL_NAME%
echo           Start  : wsl -d %ARG_WSL_NAME%
if "%C2W_MANIFEST%"=="1" echo           Record : cat /etc/container2wsl/manifest.jsonl  (copy: %INSTALL_PATH%\container2wsl-manifest.jsonl)
echo.
exit /b 0


:: ============================================================
::  RECIPES (--recipe NAME | --recipes)
::  A recipe is a key=value file in recipes\ here (samples) or in a private overlay's: image, name, user,
::  location, bootstraps, poststraps, target, commit, extra (engine and arch are for
::  container2x.sh). It expands into arguments placed BEFORE the ones given here, and the
::  script runs again, so command line arguments win ("last one wins").
:: ============================================================

:recipe_scan
:: Split the command line into --recipe / --recipes and everything else (_RCP_REST).
if "%~1"=="" goto :eof
if "%~1"=="--recipes" (
    set "_RCP_LIST=1"
    shift
    goto :recipe_scan
)
if "%~1"=="--recipe" (
    set "_RCP_SET=1"
    set "_RCP=%~2"
    if not "%~2"=="" shift
    shift
    goto :recipe_scan
)
if "%~1"=="--private" if not "%~2"=="" set "_RCP_PRIV=!_RCP_PRIV!;%~f2"
set "_RCP_REST=!_RCP_REST! %1"
shift
goto :recipe_scan

:recipe_dirs
:: Folders whose recipes\ is searched, ; separated in _RD, in order (a later match wins): this
:: script's own folder (built-in samples such as default), then --private given here, else
:: C2W_PRIVATE_DIRS, else sibling folders with a .devtools-overlay marker (as for the build).
set "_RD=%C2W_SCRIPT_DIR:~0,-1%"
if defined _RCP_PRIV (
    set "_RD=!_RD!!_RCP_PRIV!"
    goto :eof
)
if defined C2W_PRIVATE_DIRS (
    set "_RD=!_RD!;%C2W_PRIVATE_DIRS%"
    goto :eof
)
for /d %%d in ("%C2W_SCRIPT_DIR%..\*") do if exist "%%~fd\.devtools-overlay" set "_RD=!_RD!;%%~fd"
goto :eof

:recipe_list
call :recipe_dirs
echo Recipes ^(name, overlay, image^):
for %%o in ("!_RD:;=" "!") do for %%r in ("%%~o\recipes\*.conf") do (
    set "_IMG="
    for /f "usebackq eol=# tokens=1,* delims==" %%k in ("%%~fr") do if "%%k"=="image" set "_IMG=%%l"
    echo   %%~nr  ^(%%~nxo^)  !_IMG!
)
goto :eof

:recipe_list_exit
call :recipe_list
exit /b 0

:recipe_run
if "%_RCP%"=="" (
    echo [ERROR] --recipe needs a recipe name or a .conf path.
    call :recipe_list
    exit /b 2
)
set "_RF="
for %%f in ("%_RCP%") do set "_RN=%%~nf"
echo "%_RCP%" | findstr /r /c:"[\\/]" /c:"\.conf" >nul 2>&1
if not errorlevel 1 for %%f in ("%_RCP%") do set "_RF=%%~ff"
if defined _RF if not exist "!_RF!" (
    echo [ERROR] Recipe file not found: !_RF!
    exit /b 2
)
if not defined _RF call :recipe_dirs
if not defined _RF if defined _RD for %%o in ("!_RD:;=" "!") do if exist "%%~o\recipes\%_RCP%.conf" set "_RF=%%~o\recipes\%_RCP%.conf"
if not defined _RF (
    echo [ERROR] No recipe "%_RCP%" in docker2wsl\recipes or the recipes folder of any private overlay.
    call :recipe_list
    exit /b 2
)
for %%v in (image name user location bootstraps poststraps extra target commit engine arch) do set "R_%%v="
for /f "usebackq eol=# tokens=1,* delims==" %%k in ("!_RF!") do set "R_%%k=%%l"
if not defined R_image (
    echo [ERROR] Recipe !_RF! has no image= line.
    exit /b 2
)
if not defined R_name set "R_name=!_RN!"
set "_RA=!R_image! -n !R_name!"
if defined R_user set "_RA=!_RA! -u !R_user!"
if defined R_location set "_RA=!_RA! -l "!R_location!""
if defined R_bootstraps for %%b in (!R_bootstraps!) do set "_RA=!_RA! -b %%b"
if defined R_poststraps for %%p in (!R_poststraps!) do set "_RA=!_RA! -p %%p"
if defined R_target set "_RA=!_RA! --target !R_target!"
:: commit= applies only when this build is a container: recipe target=container, C2W_TARGET, or
:: --target container on the command line (--target wsl there turns it off)
if defined R_commit (
    set "_CT=0"
    if /i "!R_target!"=="container" set "_CT=1"
    if not defined R_target if /i "%C2W_TARGET%"=="container" set "_CT=1"
    echo "!_RCP_REST!" | findstr /i /c:"--target container" >nul && set "_CT=1"
    echo "!_RCP_REST!" | findstr /i /c:"--target wsl" >nul && set "_CT=0"
    if "!_CT!"=="1" set "_RA=!_RA! --commit !R_commit!"
)
if defined R_extra set "_RA=!_RA! !R_extra!"
echo container2wsl: recipe !_RF!
echo container2wsl: !_RA!!_RCP_REST!
set "_C2W_FROM_RECIPE=!_RF!"
call "%~f0" !_RA!!_RCP_REST!
exit /b !errorlevel!


:: ============================================================
::  CONTAINER TARGET (--target container): a running docker/podman container instead of a
::  WSL distro. Straps, rendering and the manifest are shared with the WSL target; host
::  folders straps read are bind-mounted at their /mnt/<drive>/... path, so the *_LX
::  variables mean the same thing in both targets.
:: ============================================================

:ct_setup
:: Engine name for the straps, command prefixes, and the list of host folders to mount.
set "C2W_ENGINE=docker"
for /f "usebackq delims=" %%v in (`%DOCKER_CMD% --version 2^>nul`) do echo %%v | findstr /i podman >nul && set "C2W_ENGINE=podman"
set "T_ROOT=%DOCKER_CMD% exec -u root %ARG_WSL_NAME%"
set "T_USER=%DOCKER_CMD% exec -u %ARG_WSL_USER% %ARG_WSL_NAME%"
set "CT_MOUNT_LIST="
call :ct_add_mount "%C2W_SCRIPT_DIR%"
if exist "%C2W_SCRIPT_DIR%..\devtools\" call :ct_add_mount "%C2W_SCRIPT_DIR%..\devtools"
if defined C2W_PRIVATE_DIRS for %%d in ("!C2W_PRIVATE_DIRS:;=" "!") do call :ct_add_mount "%%~d"
if defined C2W_SSH_SOURCE if exist "%C2W_SSH_SOURCE%\" call :ct_add_mount "%C2W_SSH_SOURCE%"
goto :eof

:ct_add_mount
:: %~1 = Windows folder. Appends "C:\x:/mnt/c/x" (quoted) to CT_MOUNT_LIST, no duplicates.
set "_CM=%~f1"
if "!_CM:~-1!"=="\" set "_CM=!_CM:~0,-1!"
call :win2lx "!_CM!" _CM_LX
if defined CT_MOUNT_LIST if not "!CT_MOUNT_LIST:%_CM%:=!"=="!CT_MOUNT_LIST!" goto :eof
set "CT_MOUNT_LIST=!CT_MOUNT_LIST! "!_CM!:!_CM_LX!""
goto :eof

:ct_flow
:: Steps 2-3 for the container target, then back to the shared strap steps.
set "INSTALL_PATH=%ARG_WSL_LOCATION%\%ARG_WSL_NAME%"
if not exist "%INSTALL_PATH%\" mkdir "%INSTALL_PATH%" 2>nul
:: the per-run folder holds the rendered scripts and the manifest: mount it too
call :ct_add_mount "%C2W_TMP%"
set "CT_MOUNTS="
for %%m in (!CT_MOUNT_LIST!) do set "CT_MOUNTS=!CT_MOUNTS! -v "%%~m""
echo [2/%STEP_COUNT%] Starting container '%ARG_WSL_NAME%' from %ARG_IMAGE%...
call %DOCKER_CMD% container inspect %ARG_WSL_NAME% >nul 2>&1
if not errorlevel 1 (
    if %FORCE%==0 (
        echo [ERROR] Container '%ARG_WSL_NAME%' already exists. Use --force to replace it.
        call :manifest_cleanup_tmp
        exit /b 1
    )
    echo       Removing existing container '%ARG_WSL_NAME%'...
    call %DOCKER_CMD% rm -f %ARG_WSL_NAME% >nul 2>&1
)
echo       %DOCKER_CMD% run -d --name %ARG_WSL_NAME% --hostname %ARG_WSL_NAME% --entrypoint sleep!CT_MOUNTS! "%ARG_IMAGE%" infinity
call %DOCKER_CMD% run -d --name %ARG_WSL_NAME% --hostname %ARG_WSL_NAME% --entrypoint sleep!CT_MOUNTS! "%ARG_IMAGE%" infinity >nul
if errorlevel 1 (
    echo [ERROR] %DOCKER_CMD% run failed for %ARG_IMAGE%. The image needs a sleep command ^(coreutils or busybox^).
    call :manifest_cleanup_tmp
    exit /b 1
)
echo       Started. Mounted: !CT_MOUNT_LIST!
echo [3/%STEP_COUNT%] Creating user '%ARG_WSL_USER%'...
call %T_ROOT% useradd -m -s /bin/bash "%ARG_WSL_USER%" >nul 2>&1
call %T_ROOT% usermod -aG sudo "%ARG_WSL_USER%" >nul 2>&1
call %T_ROOT% id "%ARG_WSL_USER%" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not create user '%ARG_WSL_USER%' in the container ^(useradd missing?^).
    call :manifest_cleanup_tmp
    exit /b 1
)
echo       User '%ARG_WSL_USER%' ready.
call :ct_ssh_check
if errorlevel 1 (
    call :manifest_cleanup_tmp
    exit /b 1
)
:: inside the container the ssh source is its mount, not a Windows path (no wslpath there)
if defined C2W_SSH_SOURCE call :win2lx "%C2W_SSH_SOURCE%" C2W_SSH_SOURCE
goto :after_target_setup

:ct_ssh_check
:: ssh-keys checks Windows ACLs with powershell.exe, which a container cannot start. When
:: ssh-keys is requested, run the same check here on the host and tell the strap it was done.
if /i "%C2W_SSH_ACL_CHECK%"=="off" exit /b 0
set "_SK=0"
if %ARG_POSTSTRAP_N% geq 1 for /l %%i in (1,1,%ARG_POSTSTRAP_N%) do if /i "!ARG_POSTSTRAP_REQ_%%i!"=="ssh-keys" set "_SK=1"
if "%_SK%"=="0" exit /b 0
set "_SK_DIRS="
if defined C2W_SSH_SOURCE (set "_SK_DIRS="%C2W_SSH_SOURCE%"") else if defined C2W_PRIVATE_DIRS for %%d in ("!C2W_PRIVATE_DIRS:;=" "!") do if exist "%%~d\ssh\" set "_SK_DIRS=!_SK_DIRS! "%%~d\ssh""
for %%d in (!_SK_DIRS!) do (
    powershell -noprofile -executionpolicy bypass -file "%C2W_SCRIPT_DIR%lib\ssh-source-check.ps1" -Path "%%~d"
    if errorlevel 1 (
        echo [ERROR] ssh-keys: %%~d failed the Windows ACL check above. Refusing.
        exit /b 1
    )
)
set "C2W_SSH_ACL_CHECK=host"
exit /b 0

:ct_finish
:: After the straps: optional commit, then leave the container running.
set "_CT_SHELL=/bin/bash"
for /f "tokens=7 delims=:" %%s in ('%T_ROOT% getent passwd %ARG_WSL_USER% 2^>nul') do set "_CT_SHELL=%%s"
if defined ARG_COMMIT (
    echo [!_NEXT_STEP!/%STEP_COUNT%] Committing container to image %ARG_COMMIT%...
    echo       %DOCKER_CMD% commit --change "ENTRYPOINT []" --change "CMD !_CT_SHELL! -l" --change "USER %ARG_WSL_USER%" --change "WORKDIR /home/%ARG_WSL_USER%" %ARG_WSL_NAME% "%ARG_COMMIT%"
    call %DOCKER_CMD% commit --change "ENTRYPOINT []" --change "CMD !_CT_SHELL! -l" --change "USER %ARG_WSL_USER%" --change "WORKDIR /home/%ARG_WSL_USER%" %ARG_WSL_NAME% "%ARG_COMMIT%" >nul
    if errorlevel 1 (
        echo [ERROR] %DOCKER_CMD% commit failed.
        set "C2W_M_FAILED=commit %ARG_COMMIT%"
        call :manifest_complete failed
        exit /b 1
    )
    echo       Committed. Bind mounts are not part of the image.
)
call :manifest_complete ok
echo.
echo [SUCCESS] Container created and running.
echo           Name   : %ARG_WSL_NAME%
echo           Enter  : %DOCKER_CMD% exec -it -u %ARG_WSL_USER% -w /home/%ARG_WSL_USER% %ARG_WSL_NAME% !_CT_SHELL! -l
if defined ARG_COMMIT echo           Image  : %ARG_COMMIT%  ^(%DOCKER_CMD% run -it --rm %ARG_COMMIT%^)
echo           Remove : %DOCKER_CMD% rm -f %ARG_WSL_NAME%
if "%C2W_MANIFEST%"=="1" echo           Record : c2w-manifest inside the container  ^(copy: %INSTALL_PATH%\container2wsl-manifest.jsonl^)
echo.
exit /b 0

:manifest_cleanup_tmp
if defined C2W_TMP if exist "%C2W_TMP%\" rmdir /s /q "%C2W_TMP%" >nul 2>&1
exit /b 0


:: ============================================================
::  STEP SUBROUTINES
:: ============================================================

:docker_ensure_image
:: Check if image exists locally; pull if not.
:: %~1 = image name
echo [1/%STEP_COUNT%] Checking for local Docker image: %~1
call %DOCKER_CMD% image inspect "%~1" >nul 2>&1
if %errorlevel% equ 0 (
    echo       Found locally.
    exit /b 0
)
echo       Not found locally. Pulling from registry...
call %DOCKER_CMD% pull "%~1"
if errorlevel 1 (
    echo [ERROR] docker pull failed for: %~1
    exit /b 1
)
set "C2W_IMAGE_PULLED=1"
echo       Pull complete.
exit /b 0


:docker_export_image
:: Create a temporary container and export its filesystem to a tar file.
:: %~1 = image name   %~2 = output tar path
echo [2/%STEP_COUNT%] Exporting image to: %~2
set "_TMP_CONTAINER="
for /f "usebackq tokens=*" %%c in (`%DOCKER_CMD% create "%~1" 2^>nul`) do (
    set "_TMP_CONTAINER=%%c"
)
if not defined _TMP_CONTAINER (
    echo [ERROR] docker create failed — could not get container ID.
    exit /b 1
)
call %DOCKER_CMD% export "%_TMP_CONTAINER%" -o "%~2"
set "_EXPORT_RC=%errorlevel%"
call %DOCKER_CMD% rm -f "%_TMP_CONTAINER%" >nul 2>&1
if %_EXPORT_RC% neq 0 (
    echo [ERROR] docker export failed ^(exit %_EXPORT_RC%^).
    exit /b 1
)
echo       Export complete.
exit /b 0


:create_directory
:: Create directory (and parents) if it does not already exist.
:: %~1 = directory path
if not exist "%~1\" (
    mkdir "%~1" 2>nul
    if errorlevel 1 (
        echo [ERROR] Cannot create directory: %~1
        exit /b 1
    )
    echo       Created: %~1
) else (
    echo       Directory exists: %~1
)
exit /b 0


:wsl_import
:: Import a tar archive as a WSL 2 distribution.
:: %~1 = distro name   %~2 = install path   %~3 = tar file
echo [3/%STEP_COUNT%] Importing WSL distribution '%~1'...
set "_WIMPORT_TMP=%C2W_TMP%\c2w_wslimport.tmp"
call %WSL_CMD% --import "%~1" "%~2" "%~3" --version 2 > "%_WIMPORT_TMP%" 2>&1
set "_WIMPORT_RC=%errorlevel%"
:: Detect failure: non-zero exit OR error text in output.
:: wsl --import writes UTF-16 LE; "Error" appears as "E r r o r" in the byte stream.
set "_WIMPORT_FAIL=0"
if %_WIMPORT_RC% neq 0 set "_WIMPORT_FAIL=1"
findstr /c:"E r r o r" "%_WIMPORT_TMP%" >nul 2>&1
if not errorlevel 1 set "_WIMPORT_FAIL=1"
if "%_WIMPORT_FAIL%"=="1" (
    type "%_WIMPORT_TMP%"
    del /f /q "%_WIMPORT_TMP%" >nul 2>&1
    echo [ERROR] wsl --import failed ^(see message above^).
    exit /b 1
)
del /f /q "%_WIMPORT_TMP%" >nul 2>&1
echo       Import complete.
exit /b 0


:wsl_configure_user
:: Create user (if absent) and set as default in /etc/wsl.conf.
:: %~1 = distro name   %~2 = username
echo [4/%STEP_COUNT%] Configuring default user '%~2'...

:: WSL may need a moment after import before accepting commands; retry until ready.
:: WSL returns exit 0 even on failure, so we capture output and check for errors.
set "_WCFG_WAIT=0"
set "_WCFG_TMP=%C2W_TMP%\c2w_wslcfg.tmp"
:wsl_cfg_wait
call %WSL_CMD% -d %~1 -u root -- echo ok > "%_WCFG_TMP%" 2>&1
set "_WCFG_RC=%errorlevel%"
set "_WCFG_READY=1"
if %_WCFG_RC% neq 0 set "_WCFG_READY=0"
findstr /c:"E r r o r" "%_WCFG_TMP%" >nul 2>&1
if not errorlevel 1 set "_WCFG_READY=0"
findstr /c:"no distribution" "%_WCFG_TMP%" >nul 2>&1
if not errorlevel 1 set "_WCFG_READY=0"
if "%_WCFG_READY%"=="0" (
    set /a "_WCFG_WAIT+=1"
    if !_WCFG_WAIT! geq 10 (
        echo [ERROR] Distro '%~1' did not become accessible after import.
        type "%_WCFG_TMP%"
        del /f /q "%_WCFG_TMP%" >nul 2>&1
        exit /b 1
    )
    ping -n 2 127.0.0.1 >nul 2>&1
    goto :wsl_cfg_wait
)
del /f /q "%_WCFG_TMP%" >nul 2>&1

:: Create user — run useradd directly to avoid bash -c quote mangling on Windows.
:: Non-zero exit is ignored; it just means the user already exists.
call %WSL_CMD% -d %~1 -u root -- useradd -m -s /bin/bash "%~2" >nul 2>&1

:: Add to sudo group (ignore failure — sudo group may not exist in this image)
call %WSL_CMD% -d %~1 -u root -- usermod -aG sudo "%~2" >nul 2>&1

:: Write /etc/wsl.conf via a Windows temp file, then copy + fix line endings inside the distro.
set "_WCFG_CONF=%C2W_TMP%\c2w_wsl.conf"
(echo [user]) > "%_WCFG_CONF%"
(echo default=%~2) >> "%_WCFG_CONF%"
call :win2lx "%_WCFG_CONF%" _WCFG_CONF_LX
set "_WCFG_CP_TMP=%C2W_TMP%\c2w_wslcp.tmp"
call %WSL_CMD% -d %~1 -u root -- cp "%_WCFG_CONF_LX%" /etc/wsl.conf > "%_WCFG_CP_TMP%" 2>&1
set "_WCFG_CP_RC=%errorlevel%"
set "_WCFG_CP_FAIL=0"
if %_WCFG_CP_RC% neq 0 set "_WCFG_CP_FAIL=1"
findstr /c:"E r r o r" "%_WCFG_CP_TMP%" >nul 2>&1
if not errorlevel 1 set "_WCFG_CP_FAIL=1"
findstr /c:"No such file" "%_WCFG_CP_TMP%" >nul 2>&1
if not errorlevel 1 set "_WCFG_CP_FAIL=1"
del /f /q "%_WCFG_CP_TMP%" >nul 2>&1
if "%_WCFG_CP_FAIL%"=="1" (
    echo [ERROR] Failed to write /etc/wsl.conf.
    del /f /q "%_WCFG_CONF%" >nul 2>&1
    exit /b 1
)
del /f /q "%_WCFG_CONF%" >nul 2>&1
:: Strip Windows \r from the conf file so WSL can parse it correctly.
call %WSL_CMD% -d %~1 -u root -- sed -i "s/\r//" /etc/wsl.conf >nul 2>&1

:: Restart the distro so wsl.conf takes effect
call %WSL_CMD% --terminate "%~1" >nul 2>&1

echo       Default user set to '%~2'. Run 'wsl -d %~1' to verify.
exit /b 0


:wsl_distro_exists
:: Check if a WSL distribution is already registered.
:: %~1 = distro name
:: Returns exit 0 if found, exit 1 if not found.
set "_WDE_TMP=%C2W_TMP%\c2w_wsllist.tmp"
set "_WDE_ASCII=%C2W_TMP%\c2w_wslascii.tmp"
call %WSL_CMD% --list --quiet > "%_WDE_TMP%" 2>&1
powershell -noprofile -command "Get-Content -Path '%_WDE_TMP%' -Encoding Unicode 2>$null | Out-File -Encoding ascii '%_WDE_ASCII%'" 2>nul
set "_WDE_FOUND=1"
if not exist "%_WDE_ASCII%" goto :wde_cleanup
for /f "usebackq tokens=*" %%n in ("%_WDE_ASCII%") do (
    set "_WDE_NAME=%%n"
    for /l %%i in (1,1,5) do if "!_WDE_NAME:~-1!"==" " set "_WDE_NAME=!_WDE_NAME:~0,-1!"
    if /i "!_WDE_NAME!"=="%~1" set "_WDE_FOUND=0"
)
:wde_cleanup
del /f /q "%_WDE_TMP%" "%_WDE_ASCII%" >nul 2>&1
exit /b %_WDE_FOUND%


:wsl_force_unregister
:: Unregister an existing WSL distribution and verify it's gone.
:: %~1 = distro name
:: Uses UNQUOTED name because wsl --unregister behaves like wsl -d (silently
:: fails with quoted names on some Windows builds).
echo       Unregistering existing distro '%~1'...
set "_WFU_TMP=%C2W_TMP%\c2w_wslunreg.tmp"
call %WSL_CMD% --unregister %~1 > "%_WFU_TMP%" 2>&1
set "_WFU_RC=%errorlevel%"
set "_WFU_FAIL=0"
if %_WFU_RC% neq 0 set "_WFU_FAIL=1"
findstr /c:"E r r o r" "%_WFU_TMP%" >nul 2>&1
if not errorlevel 1 set "_WFU_FAIL=1"
if "%_WFU_FAIL%"=="1" (
    type "%_WFU_TMP%"
    del /f /q "%_WFU_TMP%" >nul 2>&1
    exit /b 1
)
del /f /q "%_WFU_TMP%" >nul 2>&1
:: Verify the distro is actually gone
call :wsl_distro_exists "%~1"
if !errorlevel! equ 0 (
    echo [ERROR] Distro '%~1' still registered after unregister.
    exit /b 1
)
:: Also terminate to ensure no lingering WSL process
call %WSL_CMD% --terminate %~1 >nul 2>&1
echo       Unregistered '%~1'.
exit /b 0


:wsl_bootstrap
:: Run commands from a bootstrap file inside the WSL distro (as root).
:: %~1 = distro name   %~2 = bootstrap file path   %~3 = file index   %~4 = total files   %~5 = step number
if "%~4"=="1" (
    echo [%~5/%STEP_COUNT%] Running bootstrap commands from: %~2
) else (
    echo [%~5/%STEP_COUNT%] Running bootstrap file %~3/%~4: %~2
)
if not exist "%~2" (
    echo [ERROR] Bootstrap file not found: %~2
    exit /b 1
)
if exist "%~2\" (
    echo [ERROR] Bootstrap is a folder, not a file: %~2
    exit /b 1
)
set "_BS_COUNT=0"
set "_BS_TMP=%C2W_TMP%\c2w_bootstrap.tmp"
call :set_strap_dir "%~2"
:: Count commands and display them (with variable expansion for user feedback)
for /f "usebackq delims=" %%L in ("%~2") do (
    set "_BS_LINE=%%L"
    if not "!_BS_LINE!"=="" if not "!_BS_LINE:~0,1!"=="#" (
        set /a _BS_COUNT+=1
        call set "_BS_EXPANDED=!_BS_LINE!"
        echo       [!_BS_COUNT!] !_BS_EXPANDED!
    )
)
:: Use PowerShell to read the bootstrap file, expand %VAR% references
:: (including C2W_* and any standard env vars), strip comments/blanks,
:: prepend "set -e", and write a clean .sh file with Unix line endings.
:: This avoids CMD mangling shell operators (>>, |, &, etc.).
set "_BS_SH=%C2W_TMP%\c2w_bootstrap_cmd.sh"
powershell -noprofile -command ^
  "[IO.File]::WriteAllText('%C2W_STRAP_START%', [DateTime]::UtcNow.ToString('o')); " ^
  "$lines = @('set -e', 'export DEBIAN_FRONTEND=noninteractive'); " ^
  "Get-Content -LiteralPath '%~2' -Encoding UTF8 | ForEach-Object { " ^
  "  $l = $_.TrimEnd(); " ^
  "  if ($l -and -not $l.StartsWith('#')) { " ^
  "    $lines += [Environment]::ExpandEnvironmentVariables($l) " ^
  "  } " ^
  "}; " ^
  "[IO.File]::WriteAllBytes('%_BS_SH%', [Text.Encoding]::UTF8.GetBytes(($lines -join [char]10) + [char]10))" 2>nul
call :win2lx "%_BS_SH%" _BS_SH_LX
:: stdin from nul: WSL would hand the strap this console, and a prompt (apt's tzdata asks for a
:: timezone) would wait unseen because the output goes to a file until the strap ends
call %T_ROOT% bash !_BS_SH_LX! < nul > "%_BS_TMP%" 2>&1
set "_BS_RC=!errorlevel!"
set "_BS_FAIL=0"
if !_BS_RC! neq 0 set "_BS_FAIL=1"
findstr /c:"E r r o r" "%_BS_TMP%" >nul 2>&1
if not errorlevel 1 set "_BS_FAIL=1"
type "%_BS_TMP%"
set "_M_RESULT=ok"
if "!_BS_FAIL!"=="1" set "_M_RESULT=failed"
call :manifest_strap "%~1" bootstrap %~3 "%~2" "%_BS_SH%" "!_BS_SH_LX!" !_BS_COUNT! root !_M_RESULT!
del /f /q "%_BS_TMP%" "%_BS_SH%" >nul 2>&1
if "!_BS_FAIL!"=="1" (
    echo [ERROR] Bootstrap command failed.
    exit /b 1
)
echo       Bootstrap complete ^(!_BS_COUNT! commands executed^).
exit /b 0


:wsl_poststrap
:: Run commands from a poststrap file inside the WSL distro (as user).
:: %~1 = distro name   %~2 = poststrap file path   %~3 = file index   %~4 = total files   %~5 = step number   %~6 = username
if "%~4"=="1" (
    echo [%~5/%STEP_COUNT%] Running poststrap commands from: %~2 (as %~6)
) else (
    echo [%~5/%STEP_COUNT%] Running poststrap file %~3/%~4: %~2 (as %~6)
)
if not exist "%~2" (
    echo [ERROR] Poststrap file not found: %~2
    exit /b 1
)
if exist "%~2\" (
    echo [ERROR] Poststrap is a folder, not a file: %~2
    exit /b 1
)
set "_PS_COUNT=0"
set "_PS_TMP=%C2W_TMP%\c2w_poststrap.tmp"
call :set_strap_dir "%~2"
:: Count commands and display them (with variable expansion for user feedback)
for /f "usebackq delims=" %%L in ("%~2") do (
    set "_PS_LINE=%%L"
    if not "!_PS_LINE!"=="" if not "!_PS_LINE:~0,1!"=="#" (
        set /a _PS_COUNT+=1
        call set "_PS_EXPANDED=!_PS_LINE!"
        echo       [!_PS_COUNT!] !_PS_EXPANDED!
    )
)
:: Use PowerShell to read the poststrap file, expand %VAR% references,
:: strip comments/blanks, prepend "set -e", and write a clean .sh file
:: with Unix line endings. Same as bootstrap but runs as user, not root.
set "_PS_SH=%C2W_TMP%\c2w_poststrap_cmd.sh"
powershell -noprofile -command ^
  "[IO.File]::WriteAllText('%C2W_STRAP_START%', [DateTime]::UtcNow.ToString('o')); " ^
  "$lines = @('set -e', 'export DEBIAN_FRONTEND=noninteractive'); " ^
  "Get-Content -LiteralPath '%~2' -Encoding UTF8 | ForEach-Object { " ^
  "  $l = $_.TrimEnd(); " ^
  "  if ($l -and -not $l.StartsWith('#')) { " ^
  "    $lines += [Environment]::ExpandEnvironmentVariables($l) " ^
  "  } " ^
  "}; " ^
  "[IO.File]::WriteAllBytes('%_PS_SH%', [Text.Encoding]::UTF8.GetBytes(($lines -join [char]10) + [char]10))" 2>nul
call :win2lx "%_PS_SH%" _PS_SH_LX
call %T_USER% bash !_PS_SH_LX! < nul > "%_PS_TMP%" 2>&1
set "_PS_RC=!errorlevel!"
set "_PS_FAIL=0"
if !_PS_RC! neq 0 set "_PS_FAIL=1"
findstr /c:"E r r o r" "%_PS_TMP%" >nul 2>&1
if not errorlevel 1 set "_PS_FAIL=1"
type "%_PS_TMP%"
set "_M_RESULT=ok"
if "!_PS_FAIL!"=="1" set "_M_RESULT=failed"
call :manifest_strap "%~1" poststrap %~3 "%~2" "%_PS_SH%" "!_PS_SH_LX!" !_PS_COUNT! %~6 !_M_RESULT!
del /f /q "%_PS_TMP%" "%_PS_SH%" >nul 2>&1
if "!_PS_FAIL!"=="1" (
    echo [ERROR] Poststrap command failed.
    exit /b 1
)
echo       Poststrap complete ^(!_PS_COUNT! commands executed^).
exit /b 0


:: ============================================================
::  MANIFEST (optional; needs lib\manifest.ps1 next to this script)
::  Windows copy : <location>\<name>\container2wsl-manifest.jsonl
::  In the distro: /etc/container2wsl/manifest.jsonl (JSON Lines)
::                 /etc/container2wsl/straps/NN-kind-name.sh (rendered scripts, root 0600)
::  Never fails the build: errors only print a warning.
:: ============================================================

:manifest
:: %~1 = create, strap or complete. Inputs travel in environment variables
:: (listed in lib\manifest.ps1), so CMD never re-parses user-supplied text.
if not "%C2W_MANIFEST%"=="1" exit /b 0
set "C2W_M_ACTION=%~1"
powershell -noprofile -executionpolicy bypass -file "%C2W_SCRIPT_DIR%lib\manifest.ps1" >nul 2>&1
if errorlevel 1 (
    echo       [WARN] Manifest: could not record '%~1'. The build itself is unaffected.
    exit /b 0
)
call :win2lx "%C2W_M_TMP%" _M_LX
call %T_ROOT% install -D -m 644 "!_M_LX!" /etc/container2wsl/manifest.jsonl >nul 2>&1
if "%~1"=="create" call :manifest_tool
exit /b 0


:manifest_tool
:: Install lib\c2w-manifest (summary report: c2w-manifest / c2w-manifest --short)
:: as /usr/local/bin/c2w-manifest. Copied via TEMP so the /mnt/c path rule above applies,
:: and CRs are stripped in case the checkout has CRLF line endings.
if not exist "%C2W_SCRIPT_DIR%lib\c2w-manifest" exit /b 0
copy /y "%C2W_SCRIPT_DIR%lib\c2w-manifest" "%C2W_TMP%\c2w-manifest" >nul 2>&1
call :win2lx "%C2W_TMP%\c2w-manifest" _MT_LX
call %T_ROOT% install -D -m 755 "!_MT_LX!" /usr/local/bin/c2w-manifest >nul 2>&1
call %T_ROOT% sed -i "s/\r//" /usr/local/bin/c2w-manifest >nul 2>&1
del /f /q "%C2W_TMP%\c2w-manifest" >nul 2>&1
exit /b 0


:set_strap_dir
:: %~1 = strap file. Exposes its folder to the strap as %C2W_STRAP_DIR% (Windows, trailing \)
:: and %C2W_STRAP_DIR_LX%, so straps in a private repo can reach their repo with "..".
set "C2W_STRAP_DIR=%~dp1"
call :win2lx "%~dp1" C2W_STRAP_DIR_LX
goto :eof


:manifest_strap
:: Record one strap run and keep the exact script that ran inside the distro.
:: %~1 = distro  %~2 = bootstrap/poststrap  %~3 = index  %~4 = strap file
:: %~5 = rendered .sh (Windows)  %~6 = rendered .sh (Linux path)  %~7 = commands
:: %~8 = ran as  %~9 = ok/failed
if not "%C2W_MANIFEST%"=="1" exit /b 0
set /a C2W_STRAP_SEQ+=1
set "_MS_SEQ=0!C2W_STRAP_SEQ!"
set "_MS_SEQ=!_MS_SEQ:~-2!"
set "C2W_M_KIND=%~2"
set "C2W_M_INDEX=%~3"
set "C2W_M_SEQ=!C2W_STRAP_SEQ!"
set "C2W_M_PATH=%~4"
set "C2W_M_SH=%~5"
set "C2W_M_COUNT=%~7"
set "C2W_M_AS=%~8"
set "C2W_M_RESULT=%~9"
set "C2W_M_COPY=/etc/container2wsl/straps/!_MS_SEQ!-%~2-%~nx4.sh"
call %T_ROOT% install -D -m 600 "%~6" "!C2W_M_COPY!" >nul 2>&1
call :manifest strap
exit /b 0


:manifest_complete
:: %~1 = ok or failed (C2W_M_FAILED names the failed step)
set "C2W_M_RESULT=%~1"
call :manifest complete
if defined C2W_TMP if exist "%C2W_TMP%\" rmdir /s /q "%C2W_TMP%" >nul 2>&1
exit /b 0
