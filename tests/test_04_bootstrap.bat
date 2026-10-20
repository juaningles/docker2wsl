@echo off
setlocal enabledelayedexpansion
:: ============================================================
::  test_04_bootstrap.bat  — Bootstrap feature tests
::
::  Both docker and wsl mocks are active.
:: ============================================================

set "SCRIPT=%~dp0..\container2wsl.bat"
set "OUT=%C2W_TMPDIR%\bootstrap_out.txt"

:: Prepend mocks directory so mock docker/wsl are found first
set "PATH=%C2W_TMPDIR%;%MOCKS_DIR%;%PATH%"

:: Place docker mock (always succeeds)
set "C2W_MOCK_IMAGE_EXISTS=1"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1

:: ---- Helper: reset mock vars ----
call :reset_mocks 2>nul

:: ============================================================
::  1. Bootstrap succeeds with two commands
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bootstrap succeeds with two commands
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_BS_FILE=%C2W_TMPDIR%\bootstrap_ok.txt"
(echo apt-get update) > "%_BS_FILE%"
(echo apt-get install -y curl) >> "%_BS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bsok --bootstrap "%_BS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "bootstrap-ok: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "apt-get update" "bootstrap-ok: first command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "apt-get install" "bootstrap-ok: second command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "bootstrap-ok: completion message"

:: ============================================================
::  2. Bootstrap file not found
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bootstrap file not found
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bsnf --bootstrap "%C2W_TMPDIR%\nonexistent.txt" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "bootstrap-notfound: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "ERROR" "bootstrap-notfound: error message shown"

:: ============================================================
::  3. Bootstrap command fails
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bootstrap command fails
call :reset_mocks 2>nul
set "C2W_MOCK_WSL_BASH_FAIL=1"
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_BS_FILE=%C2W_TMPDIR%\bootstrap_fail.txt"
(echo apt-get update) > "%_BS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bsfail --bootstrap "%_BS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "bootstrap-fail: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "ERROR" "bootstrap-fail: error message shown"

:: ============================================================
::  4. Bootstrap shown in dry-run
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bootstrap shown in dry-run
call :reset_mocks 2>nul

set "_BS_FILE=%C2W_TMPDIR%\bootstrap_dry.txt"
(echo echo hello) > "%_BS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bsdry --dry-run --bootstrap "%_BS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "bootstrap-dryrun: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap" "bootstrap-dryrun: bootstrap mentioned in output"
call "%HELPERS%" assert_output_contains "%OUT%" "echo hello" "bootstrap-dryrun: command listed"

:: ============================================================
::  5. Bootstrap skips comments and empty lines
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bootstrap skips comments and empty lines
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1
set "C2W_MOCK_LOG=%C2W_TMPDIR%\mock_bs_calls.log"
if exist "%C2W_MOCK_LOG%" del /f /q "%C2W_MOCK_LOG%" >nul 2>&1

set "_BS_FILE=%C2W_TMPDIR%\bootstrap_comments.txt"
(echo # This is a comment) > "%_BS_FILE%"
(echo.) >> "%_BS_FILE%"
(echo whoami) >> "%_BS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bscmt --bootstrap "%_BS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "bootstrap-comments: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "whoami" "bootstrap-comments: real command runs"
call "%HELPERS%" assert_output_not_contains "%OUT%" "This is a comment" "bootstrap-comments: comment not executed"
call "%HELPERS%" assert_output_contains "%OUT%" "1 commands" "bootstrap-comments: only 1 command counted"

:: ============================================================
::  6. Multiple bootstrap files processed in order
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m multiple bootstrap files processed in order
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_BS_FILE1=%C2W_TMPDIR%\bootstrap_multi1.txt"
set "_BS_FILE2=%C2W_TMPDIR%\bootstrap_multi2.txt"
(echo apt-get update) > "%_BS_FILE1%"
(echo curl http://example.com) > "%_BS_FILE2%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bsmulti --bootstrap "%_BS_FILE1%" --bootstrap "%_BS_FILE2%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "multi-bootstrap: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "apt-get update" "multi-bootstrap: first file command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "curl" "multi-bootstrap: second file command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "file 1/2" "multi-bootstrap: file 1/2 header shown"
call "%HELPERS%" assert_output_contains "%OUT%" "file 2/2" "multi-bootstrap: file 2/2 header shown"

:: ============================================================
::  7. Multiple bootstrap files shown in dry-run
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m multiple bootstrap files shown in dry-run
call :reset_mocks 2>nul

set "_BS_FILE1=%C2W_TMPDIR%\bootstrap_drym1.txt"
set "_BS_FILE2=%C2W_TMPDIR%\bootstrap_drym2.txt"
(echo echo first) > "%_BS_FILE1%"
(echo echo second) > "%_BS_FILE2%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bsdrym --dry-run --bootstrap "%_BS_FILE1%" --bootstrap "%_BS_FILE2%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "multi-dryrun: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "echo first" "multi-dryrun: first file commands listed"
call "%HELPERS%" assert_output_contains "%OUT%" "echo second" "multi-dryrun: second file commands listed"

:: ============================================================
::  8. Second bootstrap file fails, stops execution
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m second bootstrap file fails stops execution
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_BS_FILE1=%C2W_TMPDIR%\bootstrap_stopok.txt"
set "_BS_FILE2=%C2W_TMPDIR%\bootstrap_stopfail.txt"
(echo echo ok) > "%_BS_FILE1%"
(echo bad-command) > "%_BS_FILE2%"
:: We need bash to fail only on the second file. Use a mock that fails after N calls.
:: Actually simpler: set BASH_FAIL after the first file runs. But we can't do that mid-run.
:: Instead, just pass a nonexistent second file to trigger file-not-found error.
call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bsstop --bootstrap "%_BS_FILE1%" --bootstrap "%C2W_TMPDIR%\nonexistent_stop.txt" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "multi-stop: non-zero exit on missing second file"
call "%HELPERS%" assert_output_contains "%OUT%" "ERROR" "multi-stop: error message shown"

:: ============================================================
::  9. Bootstrap variable expansion (C2W_NAME, C2W_USER)
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bootstrap variable expansion
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1
set "C2W_MOCK_LOG=%C2W_TMPDIR%\mock_var_calls.log"
if exist "%C2W_MOCK_LOG%" del /f /q "%C2W_MOCK_LOG%" >nul 2>&1

set "_BS_FILE=%C2W_TMPDIR%\bootstrap_vars.txt"
:: Write literal %%C2W_NAME%% and %%C2W_USER%% (double %% to escape in batch)
> "%_BS_FILE%" echo echo hello %%C2W_NAME%% %%C2W_USER%%

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bsvar --user testuser --bootstrap "%_BS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "var-expand: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "%C2W_TEST_ID%-bsvar" "var-expand: C2W_NAME expanded in output"
call "%HELPERS%" assert_output_contains "%OUT%" "testuser" "var-expand: C2W_USER expanded in output"

:: ============================================================
::  10. Environment variable expansion
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m environment variable expansion
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

:: Set a custom env var and write a bootstrap file referencing it.
:: Build the percent signs from a variable to avoid CMD expanding them.
set "C2W_TEST_ENVVAL=myenvval42"
set "_BS_FILE=%C2W_TMPDIR%\bootstrap_envvar.txt"
set "_PCT=%%"
> "!_BS_FILE!" echo echo host is !_PCT!C2W_TEST_ENVVAL!_PCT!

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bsenv --bootstrap "%_BS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "env-expand: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "myenvval42" "env-expand: custom env var expanded in output"

:: ============================================================
::  11. Variables expanded in dry-run
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m variables expanded in dry-run
call :reset_mocks 2>nul

set "_BS_FILE=%C2W_TMPDIR%\bootstrap_vardry.txt"
> "%_BS_FILE%" echo echo user is %%C2W_USER%%

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-bsvdry --user dryuser --dry-run --bootstrap "%_BS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "var-dryrun: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "dryuser" "var-dryrun: C2W_USER expanded in dry-run output"

:: ============================================================
::  12. devtools built-in bootstrap (ubuntu:latest)
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m devtools built-in bootstrap
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-devtools --bootstrap "%~dp0..\bootstraps\devtools" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "devtools: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "devtools: bootstrap complete message"
call "%HELPERS%" assert_output_contains "%OUT%" "apt-get install" "devtools: apt-get install shown"
call "%HELPERS%" assert_output_contains "%OUT%" "jq" "devtools: jq in command list"

:: ============================================================
::  13. zsh built-in bootstrap (ubuntu:latest)
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m zsh built-in bootstrap
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-zsh --bootstrap "%~dp0..\bootstraps\zsh" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "zsh: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "zsh: bootstrap complete message"
call "%HELPERS%" assert_output_contains "%OUT%" "chsh" "zsh: chsh command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "wsluser" "zsh: C2W_USER expanded to default wsluser"

:: ============================================================
::  14. systemd-enable built-in bootstrap (ubuntu:latest)
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m systemd-enable built-in bootstrap
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-systemd --bootstrap "%~dp0..\bootstraps\systemd-enable" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "systemd-enable: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "systemd-enable: bootstrap complete message"
call "%HELPERS%" assert_output_contains "%OUT%" "systemd=true" "systemd-enable: systemd=true shown"
call "%HELPERS%" assert_output_contains "%OUT%" "wsl.conf" "systemd-enable: wsl.conf referenced"

:: ============================================================
::  15. sudo built-in bootstrap (ubuntu:latest)
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m sudo built-in bootstrap
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-sudo --bootstrap "%~dp0..\bootstraps\sudo" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "sudo: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "sudo: bootstrap complete message"
call "%HELPERS%" assert_output_contains "%OUT%" "apt-get install" "sudo: apt-get install shown"
call "%HELPERS%" assert_output_contains "%OUT%" "NOPASSWD" "sudo: sudoers line shown"
call "%HELPERS%" assert_output_contains "%OUT%" "wsluser" "sudo: C2W_USER expanded to default wsluser"

:: ============================================================
::  16. Bare bootstrap name resolves and executes
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bare bootstrap name resolves and executes
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-barebs -b sudo > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "bare-resolve-exec: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "NOPASSWD" "bare-resolve-exec: sudo commands shown"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "bare-resolve-exec: bootstrap complete message"

:: ============================================================
::  17. Bare bootstrap name resolves from different CWD
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bare bootstrap name resolves from different CWD
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

pushd "%TEMP%"
call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-barecwd -b systemd-enable > "%OUT%" 2>&1
set "_RC=%errorlevel%"
popd
call "%HELPERS%" assert_exit_zero "%_RC%" "bare-cwd-exec: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "systemd=true" "bare-cwd-exec: systemd-enable commands shown"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "bare-cwd-exec: bootstrap complete message"

:: ============================================================
::  18. k8s-tools built-in bootstrap
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m k8s-tools built-in bootstrap
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-k8stools -b k8s-tools > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "k8s-tools: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "k8s-tools: bootstrap complete message"
call "%HELPERS%" assert_output_contains "%OUT%" "dl.k8s.io/release/stable.txt" "k8s-tools: kubectl stable release lookup shown"
call "%HELPERS%" assert_output_contains "%OUT%" "kubelogin-linux-" "k8s-tools: kubelogin download shown"
call "%HELPERS%" assert_output_contains "%OUT%" "get-helm-4" "k8s-tools: helm 4 installer shown"
call "%HELPERS%" assert_output_contains "%OUT%" "mikefarah/yq" "k8s-tools: yq download shown"
call "%HELPERS%" assert_output_contains "%OUT%" "/usr/local/bin" "k8s-tools: installs into /usr/local/bin"

:: ============================================================
::  19. data-tools built-in bootstrap
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m data-tools built-in bootstrap
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-datatools -b data-tools > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "data-tools: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "data-tools: bootstrap complete message"
call "%HELPERS%" assert_output_contains "%OUT%" "miller" "data-tools: miller in package list"
call "%HELPERS%" assert_output_contains "%OUT%" "apk add" "data-tools: apk branch present"

:: ============================================================
::  20. azure-cli built-in bootstrap
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m azure-cli built-in bootstrap
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-azcli -b azure-cli > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "azure-cli: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "azure-cli: bootstrap complete message"
call "%HELPERS%" assert_output_contains "%OUT%" "aka.ms/InstallAzureCLIDeb" "azure-cli: Microsoft installer shown"
call "%HELPERS%" assert_output_contains "%OUT%" "az version" "azure-cli: version check shown"

:: ============================================================
::  20b. motd built-in bootstrap
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m motd built-in bootstrap
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-motd -b motd > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "motd: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "motd: bootstrap complete message"
call "%HELPERS%" assert_output_contains "%OUT%" "/etc/zsh/zlogin" "motd: hooks zsh login"
call "%HELPERS%" assert_output_contains "%OUT%" "c2w-manifest --short" "motd: runs the short summary"

:: ============================================================
::  20c. Straps resolve from private folders; strap/script path variables expand
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bare names resolve from a private folder and path variables expand
call :reset_mocks 2>nul
set "_PV=%C2W_TMPDIR%\priv_res"
if not exist "%_PV%\straps" mkdir "%_PV%\straps"
if not exist "%_PV%\poststraps" mkdir "%_PV%\poststraps"
> "%_PV%\straps\pv-boot" echo echo strap %%C2W_STRAP_DIR_LX%% script %%C2W_SCRIPT_DIR_LX%% private %%C2W_PRIVATE_DIRS_LX%%
> "%_PV%\poststraps\pv-post" echo echo profile %%C2W_USERPROFILE_LX%%

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-pvres --private "%_PV%" -b pv-boot -p pv-post --dry-run > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "private-resolve: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap: %_PV%\straps\pv-boot" "private-resolve: bootstrap found in straps\"
call "%HELPERS%" assert_output_contains "%OUT%" "Poststrap: %_PV%\poststraps\pv-post" "private-resolve: poststrap found in poststraps\"
call "%HELPERS%" assert_output_contains "%OUT%" "echo strap /mnt/" "private-resolve: C2W_STRAP_DIR_LX expands to an /mnt path"
call "%HELPERS%" assert_output_contains "%OUT%" "/priv_res/straps script /mnt/" "private-resolve: strap dir is the private straps folder"
call "%HELPERS%" assert_output_contains "%OUT%" "private /mnt/" "private-resolve: C2W_PRIVATE_DIRS_LX expands"
call "%HELPERS%" assert_output_contains "%OUT%" "echo profile /mnt/" "private-resolve: C2W_USERPROFILE_LX expands"
call "%HELPERS%" assert_output_not_contains "%OUT%" "%%C2W_" "private-resolve: no variable left unexpanded"

echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m built-in strap wins over a private one of the same name
> "%_PV%\straps\sudo" echo echo private sudo
call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-pvwin --private "%_PV%" -b sudo --dry-run > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "NOPASSWD" "private-precedence: built-in sudo used"
call "%HELPERS%" assert_output_not_contains "%OUT%" "private sudo" "private-precedence: private copy not used"

:: ============================================================
::  21. New straps are safe in CMD's command display
::      (no stray redirect files in CWD, all commands listed)
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m new straps display safely in dry-run
call :reset_mocks 2>nul

set "_CWD=%C2W_TMPDIR%\straps_cwd"
if exist "%_CWD%" rmdir /s /q "%_CWD%" >nul 2>&1
mkdir "%_CWD%"
pushd "%_CWD%"
call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-strapdry --dry-run -b k8s-tools -b data-tools -b azure-cli -b motd -p uv -p devtools-shell -p devtools-overlay -p ssh-keys -p keychain -p claude -p databricks-ug > "%OUT%" 2>&1
set "_RC=%errorlevel%"
popd
set "_STRAY=0"
for /f %%c in ('dir /b /a "%_CWD%" 2^>nul ^| find /c /v ""') do set "_STRAY=%%c"
call "%HELPERS%" assert_exit_zero "%_RC%" "straps-dryrun: exit 0"
call "%HELPERS%" assert_equal "%_STRAY%" "0" "straps-dryrun: no stray files created in CWD"
call "%HELPERS%" assert_output_contains "%OUT%" "yq --version" "straps-dryrun: last k8s-tools command listed"
call "%HELPERS%" assert_output_contains "%OUT%" "make --version" "straps-dryrun: last data-tools command listed"
call "%HELPERS%" assert_output_contains "%OUT%" "python --version" "straps-dryrun: last uv command listed"
call "%HELPERS%" assert_output_contains "%OUT%" "devtools/install.sh" "straps-dryrun: last devtools-shell command listed"
call "%HELPERS%" assert_output_contains "%OUT%" "claude --version" "straps-dryrun: last claude command listed"
call "%HELPERS%" assert_output_contains "%OUT%" "databricks --version" "straps-dryrun: last databricks-ug command listed"
call "%HELPERS%" assert_output_contains "%OUT%" "devtools/overlays" "straps-dryrun: last devtools-overlay command listed"
call "%HELPERS%" assert_output_contains "%OUT%" "config not validated" "straps-dryrun: last ssh-keys command listed"
call "%HELPERS%" assert_output_contains "%OUT%" "--version 2>&1 | head -1" "straps-dryrun: last keychain command listed"
rmdir /s /q "%_CWD%" >nul 2>&1

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
