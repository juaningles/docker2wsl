@echo off
setlocal enabledelayedexpansion
:: ============================================================
::  test_01_args.bat  — Argument parsing tests
::
::  Uses --dry-run so the script parses and prints config
::  without touching Docker or WSL.
:: ============================================================

set "SCRIPT=%~dp0..\container2wsl.bat"
set "OUT=%C2W_TMPDIR%\args_out.txt"

:: ---- Test: no arguments → shows help, exit 1 ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m no arguments shows help and exits non-zero
call "%SCRIPT%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "no-args: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "Usage:" "no-args: output contains Usage:"

:: ---- Test: --help flag → shows help, exit 1 ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m --help flag
call "%SCRIPT%" --help > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "--help: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "Usage:" "--help: output contains Usage:"
call "%HELPERS%" assert_output_contains "%OUT%" "--name" "--help: output mentions --name"
call "%HELPERS%" assert_output_contains "%OUT%" "--user" "--help: output mentions --user"
call "%HELPERS%" assert_output_contains "%OUT%" "--location" "--help: output mentions --location"

:: ---- Test: -h flag → shows help ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m -h flag
call "%SCRIPT%" -h > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "-h: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "Usage:" "-h: output contains Usage:"

:: ---- Test: image only, default name/user/location in dry-run ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m image only, dry-run shows defaults
call "%SCRIPT%" ubuntu:22.04 --dry-run > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "image-only dry-run: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "ubuntu:22.04" "image-only: image in output"
call "%HELPERS%" assert_output_contains "%OUT%" "ubuntu-22.04" "image-only: derived WSL name (: -> -)"
call "%HELPERS%" assert_output_contains "%OUT%" "wsluser" "image-only: default user"
call "%HELPERS%" assert_output_contains "%OUT%" "wsl-storage" "image-only: default storage path"
call "%HELPERS%" assert_output_contains "%OUT%" "DRY RUN" "image-only: dry-run label shown"

:: ---- Test: custom --name ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m custom --name
call "%SCRIPT%" ubuntu:22.04 --name mydev --dry-run > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "mydev" "--name: custom name appears"
call "%HELPERS%" assert_output_not_contains "%OUT%" "ubuntu-22.04" "--name: derived name NOT used"

:: ---- Test: custom -n shorthand ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m -n shorthand
call "%SCRIPT%" ubuntu:22.04 -n shortdev --dry-run > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "shortdev" "-n: shorthand name appears"

:: ---- Test: custom --user ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m custom --user
call "%SCRIPT%" ubuntu:22.04 --user alice --dry-run > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "alice" "--user: custom user appears"
call "%HELPERS%" assert_output_not_contains "%OUT%" "wsluser" "--user: default NOT used"

:: ---- Test: custom --location ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m custom --location
call "%SCRIPT%" ubuntu:22.04 --location "D:\my wsl" --dry-run > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "D:\my wsl" "--location: custom path appears"

:: ---- Test: image with / and : → correct name derivation ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m image name derivation (slashes and colons)
call "%SCRIPT%" myrepo/myimage:latest --dry-run > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "myrepo-myimage-latest" "name derivation: / and : become -"

:: ---- Test: --force shown in dry-run ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m --force shown in dry-run
call "%SCRIPT%" ubuntu:22.04 --force --dry-run > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "--force dry-run: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Force" "--force dry-run: Force label shown"

:: ---- Test: unknown flag → help + exit 1 ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m unknown flag exits non-zero
call "%SCRIPT%" ubuntu:22.04 --bogus-flag > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "unknown-flag: non-zero exit"

:: ============================================================
::  Bootstrap path resolution tests (--dry-run, no mocks)
:: ============================================================

:: ---- Test: bare bootstrap name resolves to script_dir\bootstraps\ ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bare bootstrap name resolves via script dir
call "%SCRIPT%" ubuntu:22.04 --dry-run -b sudo > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "resolve-bare: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "bootstraps\sudo" "resolve-bare: resolved to bootstraps\sudo"
call "%HELPERS%" assert_output_contains "%OUT%" "NOPASSWD" "resolve-bare: sudo commands listed"

:: ---- Test: multiple bare names all resolve ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m multiple bare bootstrap names resolve
call "%SCRIPT%" ubuntu:22.04 --dry-run -b zsh -b devtools > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "resolve-multi-bare: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "chsh" "resolve-multi-bare: zsh commands listed"
call "%HELPERS%" assert_output_contains "%OUT%" "jq" "resolve-multi-bare: devtools commands listed"

:: ---- Test: bare name that doesn't exist warns ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m nonexistent bare bootstrap name warns in dry-run
call "%SCRIPT%" ubuntu:22.04 --dry-run -b totally_bogus_bootstrap > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "resolve-bogus: exit 0 (dry-run)"
call "%HELPERS%" assert_output_contains "%OUT%" "WARNING" "resolve-bogus: warning shown for missing file"

:: ---- Test: mix of bare name and explicit path ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m mixed bare and explicit bootstrap paths
set "_BS_FILE=%C2W_TMPDIR%\bootstrap_explicit.txt"
(echo echo explicit_cmd) > "%_BS_FILE%"
call "%SCRIPT%" ubuntu:22.04 --dry-run -b sudo -b "%_BS_FILE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "resolve-mixed: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "NOPASSWD" "resolve-mixed: bare sudo resolved"
call "%HELPERS%" assert_output_contains "%OUT%" "explicit_cmd" "resolve-mixed: explicit path works"

:: ---- Test: bootstraps\ prefix resolves from different CWD ----
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m bootstraps\name resolves from different CWD
pushd "%TEMP%"
call "%SCRIPT%" ubuntu:22.04 --dry-run -b bootstraps\systemd-enable > "%OUT%" 2>&1
set "_RC=%errorlevel%"
popd
call "%HELPERS%" assert_exit_zero "%_RC%" "resolve-subdir: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "systemd=true" "resolve-subdir: systemd-enable commands listed"

endlocal & set "C2W_PASS=%C2W_PASS%"& set "C2W_FAIL=%C2W_FAIL%"
