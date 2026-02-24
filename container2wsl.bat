@echo off
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
::    --bootstrap, -b <file>  Run commands from file after setup (repeatable)
::    --force,    -f          Overwrite existing WSL distro with same name
::    --dry-run               Parse and print config, do not execute
::    --help,     -h          Show this help
::
::  Bootstrap variables (use %VAR% syntax in bootstrap files):
::    %C2W_NAME%       WSL distro name
::    %C2W_USER%       Default Linux user
::    %C2W_IMAGE%      Docker image name
::    %C2W_LOCATION%   WSL storage root path
::    (plus any standard environment variables)
:: ============================================================

set "VERSION=1.0.0"
set "SCRIPT_NAME=%~n0"

:: --- Defaults ---
set "DEFAULT_STORAGE=C:\wsl-storage"
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
if "%~2"=="--force" goto :arg_bootstrap_invalid
if "%~2"=="-f" goto :arg_bootstrap_invalid
set /a ARG_BOOTSTRAP_N+=1
set "ARG_BOOTSTRAP_!ARG_BOOTSTRAP_N!=%~2"
shift
shift
goto :parse_args

:arg_bootstrap_invalid
echo [ERROR] Missing value for option: %~1
echo.
goto :show_help_error

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
if not defined ARG_WSL_USER     set "ARG_WSL_USER=%DEFAULT_USER%"
if not defined ARG_WSL_LOCATION set "ARG_WSL_LOCATION=%DEFAULT_STORAGE%"

:: --- Derive WSL name from image if not supplied ---
if not defined ARG_WSL_NAME (
    set "ARG_WSL_NAME=%ARG_IMAGE%"
    set "ARG_WSL_NAME=!ARG_WSL_NAME::=-!"
    set "ARG_WSL_NAME=!ARG_WSL_NAME:/=-!"
    set "ARG_WSL_NAME=!ARG_WSL_NAME:\=-!"
)

goto :main

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
echo  --bootstrap, -b FILE Run commands from FILE after setup (repeatable)
echo  --force,    -f       Overwrite existing WSL distro with same name
echo  --dry-run            Show resolved config without executing
echo  --help,     -h       Show this help
echo.
echo Examples:
echo  %SCRIPT_NAME% ubuntu:22.04
echo  %SCRIPT_NAME% ubuntu:22.04 --name mydev --user john
echo  %SCRIPT_NAME% ubuntu:22.04 --location D:\wsl
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

echo.
echo  container2wsl v%VERSION%
echo  ----------------------------------------
echo  Image    : %ARG_IMAGE%
echo  WSL Name : %ARG_WSL_NAME%
echo  User     : %ARG_WSL_USER%
echo  Location : %ARG_WSL_LOCATION%\%ARG_WSL_NAME%
if %ARG_BOOTSTRAP_N% geq 1 for /l %%i in (1,1,%ARG_BOOTSTRAP_N%) do echo  Bootstrap: !ARG_BOOTSTRAP_%%i!
if %FORCE%==1 echo  Force    : yes (overwrite existing distro)
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
echo [DRY-RUN] All steps skipped.
exit /b 0

:dryrun_bootstrap
if not exist "%~1" (
    echo [DRY-RUN] WARNING: Bootstrap file not found: %~1
    echo.
    exit /b 0
)
echo [DRY-RUN] Bootstrap commands from: %~1
for /f "usebackq delims=" %%L in ("%~1") do (
    set "_BS_LINE=%%L"
    if not "!_BS_LINE!"=="" if not "!_BS_LINE:~0,1!"=="#" (
        call set "_BS_EXPANDED=!_BS_LINE!"
        echo   !_BS_EXPANDED!
    )
)
echo.
exit /b 0

:after_dryrun

:: --- Determine step count ---
set "STEP_COUNT=4"
if %ARG_BOOTSTRAP_N% geq 1 set "STEP_COUNT=5"

:: --- Step 1: Ensure Docker image is available locally ---
call :docker_ensure_image "%ARG_IMAGE%"
if errorlevel 1 (
    echo [ERROR] Could not obtain Docker image: %ARG_IMAGE%
    exit /b 1
)

:: --- Step 2: Export image to a tar archive ---
set "EXPORT_TAR=%TEMP%\c2w_%ARG_WSL_NAME%.tar"
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
if %errorlevel% equ 0 (
    if %FORCE%==0 (
        echo [ERROR] WSL distribution '%ARG_WSL_NAME%' already exists. Use --force to overwrite.
        exit /b 1
    )
    echo       Unregistering existing distro '%ARG_WSL_NAME%'...
    call %WSL_CMD% --unregister "%ARG_WSL_NAME%" >nul 2>&1
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

:: --- Step 6 (optional): Run bootstrap commands ---
:: Set built-in variables for bootstrap file expansion.
:: Bootstrap commands can reference these as %C2W_NAME%, %C2W_USER%, etc.
:: Standard environment variables (e.g. %COMPUTERNAME%) also expand.
set "C2W_NAME=%ARG_WSL_NAME%"
set "C2W_USER=%ARG_WSL_USER%"
set "C2W_IMAGE=%ARG_IMAGE%"
set "C2W_LOCATION=%ARG_WSL_LOCATION%"
if %ARG_BOOTSTRAP_N% geq 1 (
    set "_BS_IDX=0"
    for /l %%i in (1,1,%ARG_BOOTSTRAP_N%) do (
        set /a _BS_IDX+=1
        call :wsl_bootstrap "%ARG_WSL_NAME%" "!ARG_BOOTSTRAP_%%i!" !_BS_IDX! %ARG_BOOTSTRAP_N%
        if errorlevel 1 (
            echo [ERROR] Bootstrap failed.
            exit /b 1
        )
    )
)

:: --- Cleanup temp tar ---
if exist "%EXPORT_TAR%" del /f /q "%EXPORT_TAR%" >nul 2>&1

echo.
echo [SUCCESS] WSL distribution created.
echo           Name   : %ARG_WSL_NAME%
echo           Start  : wsl -d %ARG_WSL_NAME%
echo.
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
set "_WIMPORT_TMP=%TEMP%\c2w_wslimport.tmp"
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
set "_WCFG_TMP=%TEMP%\c2w_wslcfg.tmp"
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
set "_WCFG_CONF=%TEMP%\c2w_wsl.conf"
(echo [user]) > "%_WCFG_CONF%"
(echo default=%~2) >> "%_WCFG_CONF%"
set "_WCFG_CONF_LX=%_WCFG_CONF:\=/%"
set "_WCFG_CONF_LX=%_WCFG_CONF_LX:C:/=/mnt/c/%"
set "_WCFG_CONF_LX=%_WCFG_CONF_LX:c:/=/mnt/c/%"
set "_WCFG_CP_TMP=%TEMP%\c2w_wslcp.tmp"
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
set "_WDE_TMP=%TEMP%\c2w_wsllist.tmp"
set "_WDE_ASCII=%TEMP%\c2w_wslascii.tmp"
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


:wsl_bootstrap
:: Run commands from a bootstrap file inside the WSL distro.
:: %~1 = distro name   %~2 = bootstrap file path   %~3 = file index   %~4 = total files
if "%~4"=="1" (
    echo [5/%STEP_COUNT%] Running bootstrap commands from: %~2
) else (
    echo [5/%STEP_COUNT%] Running bootstrap file %~3/%~4: %~2
)
if not exist "%~2" (
    echo [ERROR] Bootstrap file not found: %~2
    exit /b 1
)
set "_BS_COUNT=0"
set "_BS_TMP=%TEMP%\c2w_bootstrap.tmp"
for /f "usebackq delims=" %%L in ("%~2") do (
    set "_BS_LINE=%%L"
    if not "!_BS_LINE!"=="" if not "!_BS_LINE:~0,1!"=="#" (
        set /a _BS_COUNT+=1
        :: Expand %VAR% references (C2W_NAME, C2W_USER, env vars, etc.)
        call set "_BS_EXPANDED=!_BS_LINE!"
        echo       [!_BS_COUNT!] !_BS_EXPANDED!
        call %WSL_CMD% -d %~1 -u root -- !_BS_EXPANDED! > "%_BS_TMP%" 2>&1
        set "_BS_RC=!errorlevel!"
        set "_BS_FAIL=0"
        if !_BS_RC! neq 0 set "_BS_FAIL=1"
        findstr /c:"E r r o r" "%_BS_TMP%" >nul 2>&1
        if not errorlevel 1 set "_BS_FAIL=1"
        if "!_BS_FAIL!"=="1" (
            type "%_BS_TMP%"
            del /f /q "%_BS_TMP%" >nul 2>&1
            echo [ERROR] Bootstrap command failed: !_BS_EXPANDED!
            exit /b 1
        )
        type "%_BS_TMP%"
        del /f /q "%_BS_TMP%" >nul 2>&1
    )
)
echo       Bootstrap complete ^(!_BS_COUNT! commands executed^).
exit /b 0
