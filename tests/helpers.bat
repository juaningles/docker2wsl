@echo off
setlocal enabledelayedexpansion
:: ============================================================
::  tests\helpers.bat  — Assertion library for container2wsl tests
::
::  Call this file with the assertion name as the first argument:
::    CALL "%HELPERS%" assert_equal "actual" "expected" "description"
::
::  Shared counters (must be initialised by run_tests.bat):
::    C2W_PASS  — cumulative pass count
::    C2W_FAIL  — cumulative fail count
::
::  Each assertion prints a PASS/FAIL line and updates the counters.
:: ============================================================

:: Capture parameters into delayed-expansion-safe variables so that
:: characters like ) in descriptions never break if/else blocks.
set "_P2=%~2"
set "_P3=%~3"
set "_P4=%~4"

if "%~1"=="assert_equal"               goto :assert_equal
if "%~1"=="assert_not_equal"           goto :assert_not_equal
if "%~1"=="assert_not_empty"           goto :assert_not_empty
if "%~1"=="assert_empty"               goto :assert_empty
if "%~1"=="assert_exit_zero"           goto :assert_exit_zero
if "%~1"=="assert_exit_nonzero"        goto :assert_exit_nonzero
if "%~1"=="assert_file_exists"         goto :assert_file_exists
if "%~1"=="assert_file_not_exists"     goto :assert_file_not_exists
if "%~1"=="assert_output_contains"     goto :assert_output_contains
if "%~1"=="assert_output_not_contains" goto :assert_output_not_contains
echo %C2W_ESC%[91m  [HELPERS ERROR] Unknown assertion: %~1%C2W_ESC%[0m
set "_RESULT=FAIL"
goto :done

:: ============================================================
:assert_equal
if "!_P2!"=="!_P3!" (set "_RESULT=PASS") else set "_RESULT=FAIL"
if "!_RESULT!"=="PASS" echo       %C2W_ESC%[92mPASS%C2W_ESC%[0m !_P4!
if "!_RESULT!"=="FAIL" echo       %C2W_ESC%[91mFAIL%C2W_ESC%[0m !_P4!
if "!_RESULT!"=="FAIL" echo         %C2W_ESC%[90mExpected : !_P3!%C2W_ESC%[0m
if "!_RESULT!"=="FAIL" echo         %C2W_ESC%[90mActual   : !_P2!%C2W_ESC%[0m
goto :done

:: ============================================================
:assert_not_equal
if not "!_P2!"=="!_P3!" (set "_RESULT=PASS") else set "_RESULT=FAIL"
if "!_RESULT!"=="PASS" echo       %C2W_ESC%[92mPASS%C2W_ESC%[0m !_P4!
if "!_RESULT!"=="FAIL" echo       %C2W_ESC%[91mFAIL%C2W_ESC%[0m !_P4!
if "!_RESULT!"=="FAIL" echo         %C2W_ESC%[90mBoth values are: !_P2!%C2W_ESC%[0m
goto :done

:: ============================================================
:assert_not_empty
if not "!_P2!"=="" (set "_RESULT=PASS") else set "_RESULT=FAIL"
if "!_RESULT!"=="PASS" echo       %C2W_ESC%[92mPASS%C2W_ESC%[0m !_P3!
if "!_RESULT!"=="FAIL" echo       %C2W_ESC%[91mFAIL%C2W_ESC%[0m !_P3! - expected non-empty value
goto :done

:: ============================================================
:assert_empty
if "!_P2!"=="" (set "_RESULT=PASS") else set "_RESULT=FAIL"
if "!_RESULT!"=="PASS" echo       %C2W_ESC%[92mPASS%C2W_ESC%[0m !_P3!
if "!_RESULT!"=="FAIL" echo       %C2W_ESC%[91mFAIL%C2W_ESC%[0m !_P3! - expected empty, got: !_P2!
goto :done

:: ============================================================
:assert_exit_zero
if "!_P2!"=="0" (set "_RESULT=PASS") else set "_RESULT=FAIL"
if "!_RESULT!"=="PASS" echo       %C2W_ESC%[92mPASS%C2W_ESC%[0m !_P3!
if "!_RESULT!"=="FAIL" echo       %C2W_ESC%[91mFAIL%C2W_ESC%[0m !_P3! - expected exit 0, got: !_P2!
goto :done

:: ============================================================
:assert_exit_nonzero
if not "!_P2!"=="0" (set "_RESULT=PASS") else set "_RESULT=FAIL"
if "!_RESULT!"=="PASS" echo       %C2W_ESC%[92mPASS%C2W_ESC%[0m !_P3!
if "!_RESULT!"=="FAIL" echo       %C2W_ESC%[91mFAIL%C2W_ESC%[0m !_P3! - expected non-zero exit, got 0
goto :done

:: ============================================================
:assert_file_exists
if exist "!_P2!" (set "_RESULT=PASS") else set "_RESULT=FAIL"
if "!_RESULT!"=="PASS" echo       %C2W_ESC%[92mPASS%C2W_ESC%[0m !_P3!
if "!_RESULT!"=="FAIL" echo       %C2W_ESC%[91mFAIL%C2W_ESC%[0m !_P3! - file not found: !_P2!
goto :done

:: ============================================================
:assert_file_not_exists
if not exist "!_P2!" (set "_RESULT=PASS") else set "_RESULT=FAIL"
if "!_RESULT!"=="PASS" echo       %C2W_ESC%[92mPASS%C2W_ESC%[0m !_P3!
if "!_RESULT!"=="FAIL" echo       %C2W_ESC%[91mFAIL%C2W_ESC%[0m !_P3! - file should not exist: !_P2!
goto :done

:: ============================================================
:assert_output_contains
findstr /c:"!_P3!" "!_P2!" >nul 2>&1
if !errorlevel! equ 0 (set "_RESULT=PASS") else set "_RESULT=FAIL"
if "!_RESULT!"=="PASS" echo       %C2W_ESC%[92mPASS%C2W_ESC%[0m !_P4!
if "!_RESULT!"=="FAIL" echo       %C2W_ESC%[91mFAIL%C2W_ESC%[0m !_P4! - string not found: !_P3!
goto :done

:: ============================================================
:assert_output_not_contains
findstr /c:"!_P3!" "!_P2!" >nul 2>&1
if !errorlevel! neq 0 (set "_RESULT=PASS") else set "_RESULT=FAIL"
if "!_RESULT!"=="PASS" echo       %C2W_ESC%[92mPASS%C2W_ESC%[0m !_P4!
if "!_RESULT!"=="FAIL" echo       %C2W_ESC%[91mFAIL%C2W_ESC%[0m !_P4! - string found but should not be: !_P3!
goto :done

:: ============================================================
:done
:: Propagate counters and result back through endlocal
if "!_RESULT!"=="PASS" (
    endlocal & set /a C2W_PASS+=1
) else (
    endlocal & set /a C2W_FAIL+=1
)
exit /b 0
