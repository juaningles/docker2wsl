@echo off
setlocal enabledelayedexpansion
:: ============================================================
::  test_07_container.bat  — --target container (docker/podman) tests
::
::  docker mock only: the container target never calls wsl.
:: ============================================================

set "SCRIPT=%~dp0..\container2wsl.bat"
set "OUT=%C2W_TMPDIR%\container_out.txt"
set "PATH=%C2W_TMPDIR%;%MOCKS_DIR%;%PATH%"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1
:: a wsl mock that fails loudly, so any wsl call in the container flow shows up
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1
call :reset_mocks

:: ============================================================
::  1. Argument validation
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m --target and --commit validation
call "%SCRIPT%" ubuntu:24.04 --target bogus --dry-run > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "target-bad: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "must be wsl or container" "target-bad: message"
call "%SCRIPT%" ubuntu:24.04 --commit localhost/x:1 --dry-run > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "commit-wsl: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "needs --target container" "commit-wsl: message"
call "%SCRIPT%" ubuntu:24.04 --target > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "target-missing-value: non-zero exit"

:: ============================================================
::  2. Dry run shows the container plan and mounts
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m container dry run
call "%SCRIPT%" ubuntu:24.04 --target container -n %C2W_TEST_ID%-ctdry -u tester --commit localhost/ct:1 --dry-run > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "ct-dry: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Container: %C2W_TEST_ID%-ctdry" "ct-dry: container name shown"
call "%HELPERS%" assert_output_contains "%OUT%" "Commit   : localhost/ct:1" "ct-dry: commit target shown"
call "%HELPERS%" assert_output_contains "%OUT%" "Mount    :" "ct-dry: bind mounts listed"
call "%HELPERS%" assert_output_not_contains "%OUT%" "WSL Name" "ct-dry: no WSL name line"
:: C2W_TARGET from the environment is the default for --target
set "C2W_TARGET=container"
call "%SCRIPT%" ubuntu:24.04 -n %C2W_TEST_ID%-ctenv --dry-run > "%OUT%" 2>&1
set "C2W_TARGET="
call "%HELPERS%" assert_output_contains "%OUT%" "Container: %C2W_TEST_ID%-ctenv" "ct-env: C2W_TARGET=container picks the container target"

:: ============================================================
::  3. Build: run with mounts, user, straps through docker exec, no wsl
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m container build with straps
call :reset_mocks
set "C2W_MOCK_LOG=%C2W_TMPDIR%\ct_calls.log"
if exist "%C2W_MOCK_LOG%" del /f /q "%C2W_MOCK_LOG%"
set "_BS=%C2W_TMPDIR%\ct_boot.txt"
(echo echo root-step) > "%_BS%"
set "_PS=%C2W_TMPDIR%\ct_post.txt"
(echo echo user-step %%C2W_TARGET%%) > "%_PS%"
call "%SCRIPT%" ubuntu:24.04 --target container -n %C2W_TEST_ID%-ct -u tester -b "%_BS%" -p "%_PS%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "ct-build: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "run -d --name %C2W_TEST_ID%-ct --hostname %C2W_TEST_ID%-ct --entrypoint sleep -v" "ct-build: docker run with name, hostname, sleep entrypoint and mounts"
call "%HELPERS%" assert_output_contains "%OUT%" "/mnt/" "ct-build: folders mounted at their /mnt path"
call "%HELPERS%" assert_output_contains "%OUT%" "User 'tester' ready" "ct-build: user created"
call "%HELPERS%" assert_output_contains "%OUT%" "exec -u root %C2W_TEST_ID%-ct" "ct-build: bootstrap runs as root via docker exec"
call "%HELPERS%" assert_output_contains "%OUT%" "exec -u tester %C2W_TEST_ID%-ct" "ct-build: poststrap runs as the user via docker exec"
call "%HELPERS%" assert_output_contains "%OUT%" "user-step container" "ct-build: C2W_TARGET expanded into straps"
call "%HELPERS%" assert_output_contains "%OUT%" "Container created and running" "ct-build: success message"
call "%HELPERS%" assert_output_not_contains "%OUT%" "MOCK wsl" "ct-build: no wsl calls"
call "%HELPERS%" assert_output_not_contains "%OUT%" "commit --change" "ct-build: no commit without --commit"

:: ============================================================
::  4. Existing container: refuse, --force replaces; --commit
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m existing container and commit
call :reset_mocks
set "C2W_MOCK_CT_EXISTS=1"
call "%SCRIPT%" ubuntu:24.04 --target container -n %C2W_TEST_ID%-ctex > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "ct-exists: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "already exists. Use --force" "ct-exists: refuses without --force"
call "%SCRIPT%" ubuntu:24.04 --target container -n %C2W_TEST_ID%-ctex --force --commit localhost/ct-test:1 > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "ct-force: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Removing existing container" "ct-force: removes the old container"
call "%HELPERS%" assert_output_contains "%OUT%" "commit --change" "ct-commit: docker commit called"
call "%HELPERS%" assert_output_contains "%OUT%" "ENTRYPOINT []" "ct-commit: sleep entrypoint reset"
call "%HELPERS%" assert_output_contains "%OUT%" "localhost/ct-test:1" "ct-commit: image tag passed"

:: ============================================================
::  5. Failures: run and commit
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m container run and commit failures
call :reset_mocks
set "C2W_MOCK_RUN_FAIL=1"
call "%SCRIPT%" ubuntu:24.04 --target container -n %C2W_TEST_ID%-ctrf > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "ct-run-fail: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "run failed for" "ct-run-fail: message"
call :reset_mocks
set "C2W_MOCK_COMMIT_FAIL=1"
call "%SCRIPT%" ubuntu:24.04 --target container -n %C2W_TEST_ID%-ctcf --commit localhost/x:1 > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "ct-commit-fail: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "commit failed" "ct-commit-fail: message"

:: ============================================================
::  6. Straps that do not apply in a container skip themselves
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m WSL-only straps skip in a container
call :reset_mocks
call "%SCRIPT%" ubuntu:24.04 --target container -n %C2W_TEST_ID%-ctskip -b systemd-enable -p podman-machine > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "ct-skip: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "wsl.conf is WSL-only" "ct-skip: systemd-enable skip message"
call "%HELPERS%" assert_output_contains "%OUT%" "not applicable in a container" "ct-skip: podman-machine skip message"

endlocal & set "C2W_PASS=%C2W_PASS%"& set "C2W_FAIL=%C2W_FAIL%"
goto :eof

:reset_mocks
set "C2W_MOCK_IMAGE_EXISTS=1"
set "C2W_MOCK_PULL_FAIL=0"
set "C2W_MOCK_CT_EXISTS=0"
set "C2W_MOCK_RUN_FAIL=0"
set "C2W_MOCK_EXEC_FAIL=0"
set "C2W_MOCK_COMMIT_FAIL=0"
set "C2W_MOCK_WSL_BASH_FAIL=0"
set "C2W_MOCK_LOG="
exit /b 0
