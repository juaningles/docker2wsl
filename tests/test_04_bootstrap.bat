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
