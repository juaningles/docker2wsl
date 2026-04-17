@echo off
setlocal enabledelayedexpansion
:: ============================================================
::  test_05_poststrap.bat  — Poststrap feature tests
::
::  Both docker and wsl mocks are active.
::  Poststrap runs commands as the created user (not root).
:: ============================================================

set "SCRIPT=%~dp0..\container2wsl.bat"
set "OUT=%C2W_TMPDIR%\poststrap_out.txt"

:: Prepend mocks directory so mock docker/wsl are found first
set "PATH=%C2W_TMPDIR%;%MOCKS_DIR%;%PATH%"

:: Place docker mock (always succeeds)
set "C2W_MOCK_IMAGE_EXISTS=1"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1

:: ---- Helper: reset mock vars ----
call :reset_mocks 2>nul

:: ============================================================
::  1. Poststrap succeeds with two commands
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m poststrap succeeds with two commands
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_PS_FILE=%C2W_TMPDIR%\poststrap_ok.txt"
(echo whoami) > "%_PS_FILE%"
(echo echo hello) >> "%_PS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psok --poststrap "%_PS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "poststrap-ok: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "whoami" "poststrap-ok: first command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "echo hello" "poststrap-ok: second command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "Poststrap complete" "poststrap-ok: completion message"

:: ============================================================
::  2. Poststrap file not found
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m poststrap file not found
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psnf --poststrap "%C2W_TMPDIR%\nonexistent_ps.txt" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "poststrap-notfound: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "ERROR" "poststrap-notfound: error message shown"

:: ============================================================
::  3. Poststrap command fails
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m poststrap command fails
call :reset_mocks 2>nul
set "C2W_MOCK_WSL_BASH_FAIL=1"
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_PS_FILE=%C2W_TMPDIR%\poststrap_fail.txt"
(echo bad-command) > "%_PS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psfail --poststrap "%_PS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "poststrap-fail: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "ERROR" "poststrap-fail: error message shown"

:: ============================================================
::  4. Poststrap shown in dry-run
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m poststrap shown in dry-run
call :reset_mocks 2>nul

set "_PS_FILE=%C2W_TMPDIR%\poststrap_dry.txt"
(echo echo hello from user) > "%_PS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psdry --dry-run --poststrap "%_PS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "poststrap-dryrun: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Poststrap" "poststrap-dryrun: poststrap mentioned in output"
call "%HELPERS%" assert_output_contains "%OUT%" "echo hello from user" "poststrap-dryrun: command listed"
call "%HELPERS%" assert_output_contains "%OUT%" "wsluser" "poststrap-dryrun: shows default user"

:: ============================================================
::  5. Poststrap skips comments and empty lines
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m poststrap skips comments and empty lines
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_PS_FILE=%C2W_TMPDIR%\poststrap_comments.txt"
(echo # This is a comment) > "%_PS_FILE%"
(echo.) >> "%_PS_FILE%"
(echo whoami) >> "%_PS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-pscmt --poststrap "%_PS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "poststrap-comments: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "whoami" "poststrap-comments: real command runs"
call "%HELPERS%" assert_output_not_contains "%OUT%" "This is a comment" "poststrap-comments: comment not executed"
call "%HELPERS%" assert_output_contains "%OUT%" "1 commands" "poststrap-comments: only 1 command counted"

:: ============================================================
::  6. Multiple poststrap files processed in order
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m multiple poststrap files processed in order
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_PS_FILE1=%C2W_TMPDIR%\poststrap_multi1.txt"
set "_PS_FILE2=%C2W_TMPDIR%\poststrap_multi2.txt"
(echo echo first) > "%_PS_FILE1%"
(echo echo second) > "%_PS_FILE2%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psmulti -p "%_PS_FILE1%" -p "%_PS_FILE2%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "multi-poststrap: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "echo first" "multi-poststrap: first file command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "echo second" "multi-poststrap: second file command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "file 1/2" "multi-poststrap: file 1/2 header shown"
call "%HELPERS%" assert_output_contains "%OUT%" "file 2/2" "multi-poststrap: file 2/2 header shown"

:: ============================================================
::  7. Second poststrap file fails, stops execution
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m second poststrap file fails stops execution
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_PS_FILE1=%C2W_TMPDIR%\poststrap_stopok.txt"
(echo echo ok) > "%_PS_FILE1%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psstop -p "%_PS_FILE1%" -p "%C2W_TMPDIR%\nonexistent_psstop.txt" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "multi-psstop: non-zero exit on missing second file"
call "%HELPERS%" assert_output_contains "%OUT%" "ERROR" "multi-psstop: error message shown"

:: ============================================================
::  8. Poststrap variable expansion (C2W_NAME, C2W_USER)
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m poststrap variable expansion
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_PS_FILE=%C2W_TMPDIR%\poststrap_vars.txt"
> "%_PS_FILE%" echo echo hello %%C2W_NAME%% %%C2W_USER%%

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psvar --user testuser --poststrap "%_PS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "ps-var-expand: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "%C2W_TEST_ID%-psvar" "ps-var-expand: C2W_NAME expanded in output"
call "%HELPERS%" assert_output_contains "%OUT%" "testuser" "ps-var-expand: C2W_USER expanded in output"

:: ============================================================
::  9. Variables expanded in dry-run
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m poststrap variables expanded in dry-run
call :reset_mocks 2>nul

set "_PS_FILE=%C2W_TMPDIR%\poststrap_vardry.txt"
> "%_PS_FILE%" echo echo user is %%C2W_USER%%

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psvdry --user dryuser --dry-run --poststrap "%_PS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "ps-var-dryrun: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "dryuser" "ps-var-dryrun: C2W_USER expanded in dry-run output"

:: ============================================================
::  10. Poststrap displays username in header
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m poststrap displays username in header
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_PS_FILE=%C2W_TMPDIR%\poststrap_user.txt"
(echo whoami) > "%_PS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psuser --user alice --poststrap "%_PS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "ps-user-header: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "as alice" "ps-user-header: shows (as alice) in output"

:: ============================================================
::  11. Bootstrap and poststrap both run in correct order
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bootstrap and poststrap both run in order
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_BS_FILE=%C2W_TMPDIR%\combo_bootstrap.txt"
set "_PS_FILE=%C2W_TMPDIR%\combo_poststrap.txt"
(echo apt-get update) > "%_BS_FILE%"
(echo echo hello user) > "%_PS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-pscombo -b "%_BS_FILE%" -p "%_PS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "combo: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "combo: bootstrap ran"
call "%HELPERS%" assert_output_contains "%OUT%" "Poststrap complete" "combo: poststrap ran"
call "%HELPERS%" assert_output_contains "%OUT%" "apt-get update" "combo: bootstrap command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "echo hello user" "combo: poststrap command shown"

:: ============================================================
::  12. Poststrap -p shorthand works
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m -p shorthand works
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

set "_PS_FILE=%C2W_TMPDIR%\poststrap_shorthand.txt"
(echo echo shorthand) > "%_PS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psshort -p "%_PS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "ps-shorthand: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Poststrap complete" "ps-shorthand: completion message"

:: ============================================================
::  13. Poststrap shown in config banner
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m poststrap shown in config banner
call :reset_mocks 2>nul

set "_PS_FILE=%C2W_TMPDIR%\poststrap_banner.txt"
(echo echo test) > "%_PS_FILE%"

call "%SCRIPT%" ubuntu:22.04 --name %C2W_TEST_ID%-psban --dry-run -p "%_PS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "ps-banner: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Poststrap:" "ps-banner: Poststrap: label in config"

:: ============================================================
::  14. Homebrew built-in bootstrap
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m homebrew built-in bootstrap
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-homebrew --bootstrap "%~dp0..\bootstraps\homebrew" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "homebrew: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Bootstrap complete" "homebrew: bootstrap complete message"
call "%HELPERS%" assert_output_contains "%OUT%" "build-essential" "homebrew: build-essential shown"
call "%HELPERS%" assert_output_contains "%OUT%" "/home/linuxbrew/.linuxbrew" "homebrew: linuxbrew prefix setup shown"
call "%HELPERS%" assert_output_contains "%OUT%" "chown -R" "homebrew: prefix ownership fix shown"
call "%HELPERS%" assert_output_contains "%OUT%" "Homebrew" "homebrew: Homebrew install command shown"

:: ============================================================
::  15. powerlevel10k built-in poststrap
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m powerlevel10k built-in poststrap
call :reset_mocks 2>nul
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1

call "%SCRIPT%" ubuntu:latest --name %C2W_TEST_ID%-powerlevel10k --poststrap powerlevel10k > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "powerlevel10k: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Poststrap complete" "powerlevel10k: poststrap complete message"
call "%HELPERS%" assert_output_contains "%OUT%" "omz-install.sh" "powerlevel10k: oh-my-zsh install command shown"
call "%HELPERS%" assert_output_contains "%OUT%" "powerlevel10k" "powerlevel10k: theme install shown"

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
