@echo off
setlocal enabledelayedexpansion
:: ============================================================
::  test_06_manifest.bat  — Build manifest (lib\manifest.ps1)
::
::  Both mocks are active. Distros are stored under %C2W_TMPDIR%\store,
::  and tests\manifest_summary.ps1 turns the JSON Lines manifest into
::  quote-free key=value lines (and proves every line parses).
:: ============================================================

set "SCRIPT=%~dp0..\container2wsl.bat"
set "OUT=%C2W_TMPDIR%\manifest_out.txt"
set "SUM=%C2W_TMPDIR%\manifest_summary.txt"
set "STORE=%C2W_TMPDIR%\store"
set "SUMMARIZE=powershell -noprofile -executionpolicy bypass -file "%~dp0manifest_summary.ps1""
set "INSPECT=%C2W_TMPDIR%\inspect.json"

set "PATH=%C2W_TMPDIR%;%MOCKS_DIR%;%PATH%"
copy /y "%MOCKS_DIR%\docker.bat" "%C2W_TMPDIR%\docker.bat" >nul 2>&1
copy /y "%MOCKS_DIR%\wsl.bat" "%C2W_TMPDIR%\wsl.bat" >nul 2>&1
> "%INSPECT%" echo [{"Id":"sha256:1111aaaa","RepoTags":["ubuntu:24.04"],"RepoDigests":["docker.io/library/ubuntu@sha256:2222bbbb"],"Created":"2026-10-01T10:00:00Z","Os":"linux","Architecture":"amd64","Size":123}]

:: ============================================================
::  1. Full build: manifest has create, one record per strap, complete
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m manifest records image, command line, straps and result
call :reset_mocks 2>nul
set "C2W_MOCK_INSPECT_FILE=%INSPECT%"
set "C2W_MOCK_LOG=%C2W_TMPDIR%\mock_mf1.log"
if exist "%C2W_MOCK_LOG%" del /f /q "%C2W_MOCK_LOG%" >nul 2>&1
set "_N=%C2W_TEST_ID%-mf1"

pushd "%TEMP%"
call "%SCRIPT%" ubuntu:24.04 -n %_N% -u alice -l "%STORE%" -b sudo -p uv > "%OUT%" 2>&1
set "_RC=%errorlevel%"
popd
set "_MF=%STORE%\%_N%\container2wsl-manifest.jsonl"
%SUMMARIZE% "%_MF%" "%SUM%" >nul 2>&1
call "%HELPERS%" assert_exit_zero "%_RC%" "mf-full: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Manifest : /etc/container2wsl/manifest.jsonl" "mf-full: banner names the manifest"
call "%HELPERS%" assert_output_contains "%OUT%" "Record : cat /etc/container2wsl/manifest.jsonl" "mf-full: success message points at it"
call "%HELPERS%" assert_file_exists "%_MF%" "mf-full: Windows copy written next to the distro"
call "%HELPERS%" assert_output_contains "%SUM%" "parse=ok" "mf-full: every line is valid JSON"
call "%HELPERS%" assert_output_contains "%SUM%" "events=create,strap,strap,complete" "mf-full: create, 2 straps, complete"
call "%HELPERS%" assert_output_contains "%SUM%" "command=container2wsl.bat ubuntu:24.04 -n %_N% -u alice" "mf-full: original command line"
call "%HELPERS%" assert_output_contains "%SUM%" "image.id=sha256:1111aaaa" "mf-full: image id"
call "%HELPERS%" assert_output_contains "%SUM%" "image.digests=docker.io/library/ubuntu@sha256:2222bbbb" "mf-full: registry digest"
call "%HELPERS%" assert_output_contains "%SUM%" "image.digests.isarray=True" "mf-full: digests stay a JSON array"
call "%HELPERS%" assert_output_contains "%SUM%" "image.pulled=False" "mf-full: local image not pulled"
call "%HELPERS%" assert_output_contains "%SUM%" "distro.user=alice" "mf-full: distro user"
call "%HELPERS%" assert_output_contains "%SUM%" "distro.os.isnull=True" "mf-full: unknown os is null, not {}"
call "%HELPERS%" assert_output_contains "%SUM%" "bootstrap.requested=sudo" "mf-full: requested bootstrap name kept"
call "%HELPERS%" assert_output_contains "%SUM%" "poststrap.requested=uv" "mf-full: requested poststrap name kept"
call "%HELPERS%" assert_output_contains "%SUM%" "strap1=bootstrap sudo ok as=root copy=/etc/container2wsl/straps/01-bootstrap-sudo.sh sha=True rsha=True" "mf-full: bootstrap record"
call "%HELPERS%" assert_output_contains "%SUM%" "strap2=poststrap uv ok as=alice copy=/etc/container2wsl/straps/02-poststrap-uv.sh sha=True rsha=True" "mf-full: poststrap record"
call "%HELPERS%" assert_output_contains "%SUM%" "complete=ok failed=" "mf-full: complete ok"
call "%HELPERS%" assert_output_contains "%C2W_MOCK_LOG%" "/etc/container2wsl/manifest.jsonl" "mf-full: manifest copied into the distro"
call "%HELPERS%" assert_output_contains "%C2W_MOCK_LOG%" "install -D -m 600" "mf-full: rendered scripts kept root-only"
call "%HELPERS%" assert_output_contains "%C2W_MOCK_LOG%" "/usr/local/bin/c2w-manifest" "mf-full: c2w-manifest summary command installed"

:: ============================================================
::  2. Pulled image is flagged
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m manifest flags a pulled image
call :reset_mocks 2>nul
set "C2W_MOCK_IMAGE_EXISTS=0"
set "_N=%C2W_TEST_ID%-mf2"
call "%SCRIPT%" ubuntu:24.04 -n %_N% -l "%STORE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
%SUMMARIZE% "%STORE%\%_N%\container2wsl-manifest.jsonl" "%SUM%" >nul 2>&1
call "%HELPERS%" assert_exit_zero "%_RC%" "mf-pulled: exit 0"
call "%HELPERS%" assert_output_contains "%SUM%" "image.pulled=True" "mf-pulled: pulled=true"
call "%HELPERS%" assert_output_contains "%SUM%" "events=create,complete" "mf-pulled: no straps, create + complete"

:: ============================================================
::  3. A failing strap is recorded, with the failed step
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m manifest records a failed build
call :reset_mocks 2>nul
set "_N=%C2W_TEST_ID%-mf3"
call "%SCRIPT%" ubuntu:24.04 -n %_N% -l "%STORE%" -b sudo -p "%C2W_TMPDIR%\missing_ps" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
%SUMMARIZE% "%STORE%\%_N%\container2wsl-manifest.jsonl" "%SUM%" >nul 2>&1
call "%HELPERS%" assert_exit_nonzero "%_RC%" "mf-failed: non-zero exit"
call "%HELPERS%" assert_output_contains "%SUM%" "events=create,strap,complete" "mf-failed: bootstrap recorded, then complete"
call "%HELPERS%" assert_output_contains "%SUM%" "complete=failed failed=poststrap 1:" "mf-failed: names the failed step"

:: ============================================================
::  4. --force keeps the previous build's manifest
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m --force keeps the previous manifest
call :reset_mocks 2>nul
set "_N=%C2W_TEST_ID%-mf1"
set "C2W_MOCK_WSL_DISTRO_EXISTS=%_N%"
if exist "%C2W_TMPDIR%\c2w_mock_unregistered.flag" del /f /q "%C2W_TMPDIR%\c2w_mock_unregistered.flag" >nul 2>&1
call "%SCRIPT%" ubuntu:24.04 -n %_N% -l "%STORE%" --force > "%OUT%" 2>&1
set "_RC=%errorlevel%"
set "C2W_MOCK_WSL_DISTRO_EXISTS="
if exist "%C2W_TMPDIR%\c2w_mock_unregistered.flag" del /f /q "%C2W_TMPDIR%\c2w_mock_unregistered.flag" >nul 2>&1
%SUMMARIZE% "%STORE%\%_N%\container2wsl-manifest.jsonl" "%SUM%" >nul 2>&1
call "%HELPERS%" assert_exit_zero "%_RC%" "mf-force: exit 0"
call "%HELPERS%" assert_file_exists "%STORE%\%_N%\container2wsl-manifest.prev.jsonl" "mf-force: previous manifest kept as .prev.jsonl"
call "%HELPERS%" assert_output_contains "%SUM%" "distro.replaced=True" "mf-force: replaced_existing=true"
call "%HELPERS%" assert_output_contains "%SUM%" "events=create,complete" "mf-force: new manifest starts fresh"

:: ============================================================
::  5. Dry run writes nothing
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m dry run writes no manifest
call :reset_mocks 2>nul
set "_N=%C2W_TEST_ID%-mf5"
call "%SCRIPT%" ubuntu:24.04 -n %_N% -l "%STORE%" -b sudo --dry-run > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "mf-dryrun: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Manifest : /etc/container2wsl/manifest.jsonl" "mf-dryrun: banner names the manifest"
call "%HELPERS%" assert_file_not_exists "%STORE%\%_N%\container2wsl-manifest.jsonl" "mf-dryrun: no manifest written"

:: ============================================================
::  6. Without lib\manifest.ps1 the single-file script still works
:: ============================================================
echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m script without the helper builds and skips the manifest
call :reset_mocks 2>nul
set "_SOLO=%C2W_TMPDIR%\solo"
if not exist "%_SOLO%" mkdir "%_SOLO%"
copy /y "%SCRIPT%" "%_SOLO%\container2wsl.bat" >nul 2>&1
set "_N=%C2W_TEST_ID%-mf6"
call "%_SOLO%\container2wsl.bat" ubuntu:24.04 -n %_N% -l "%STORE%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "mf-nolib: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "Manifest : off" "mf-nolib: banner says manifest is off"
call "%HELPERS%" assert_output_not_contains "%OUT%" "WARN" "mf-nolib: no warnings"
call "%HELPERS%" assert_file_not_exists "%STORE%\%_N%\container2wsl-manifest.jsonl" "mf-nolib: no manifest written"

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
set "C2W_MOCK_INSPECT_FILE="
set "C2W_MOCK_LOG="
exit /b 0
