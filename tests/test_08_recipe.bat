@echo off
setlocal enabledelayedexpansion
:: ============================================================
::  test_08_recipe.bat  — --recipe / --recipes and the rebuild-wsl wrapper (--dry-run, no mocks)
:: ============================================================

set "SCRIPT=%~dp0..\container2wsl.bat"
set "WRAP=%~dp0..\rebuild-wsl.bat"
set "OUT=%C2W_TMPDIR%\recipe_out.txt"
set "C2W_PRIVATE_DIRS="
set "C2W_TARGET="

:: two throwaway overlays with recipes
set "_OA=%C2W_TMPDIR%\rcp_a"
set "_OB=%C2W_TMPDIR%\rcp_b"
if not exist "%_OA%\recipes" mkdir "%_OA%\recipes"
if not exist "%_OB%\recipes" mkdir "%_OB%\recipes"
(
echo # dev - test recipe
echo image=ubuntu:24.04
echo user=rcpuser
echo bootstraps=sudo zsh
echo poststraps=uv
echo commit=localhost/rcp:1
) > "%_OA%\recipes\%C2W_TEST_ID%-dev.conf"
(echo image=alpine:3.19) > "%_OA%\recipes\%C2W_TEST_ID%-dup.conf"
(echo image=debian:12) > "%_OB%\recipes\%C2W_TEST_ID%-dup.conf"
(
echo image=ubuntu:24.04
echo target=container
) > "%_OB%\recipes\%C2W_TEST_ID%-ct.conf"
(echo user=nobody) > "%_OB%\recipes\%C2W_TEST_ID%-noimage.conf"

echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m --recipes lists the recipes
call "%SCRIPT%" --recipes --private "%_OA%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "recipes-list: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "%C2W_TEST_ID%-dev  (rcp_a)  ubuntu:24.04" "recipes-list: name, overlay and image"

echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m --recipe applies the recipe's defaults
call "%SCRIPT%" --recipe %C2W_TEST_ID%-dev --private "%_OA%" --dry-run > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_zero "%_RC%" "recipe: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "container2wsl: recipe %_OA%\recipes\%C2W_TEST_ID%-dev.conf" "recipe: recipe file shown"
call "%HELPERS%" assert_output_contains "%OUT%" "WSL Name : %C2W_TEST_ID%-dev" "recipe: name defaults to the file name"
call "%HELPERS%" assert_output_contains "%OUT%" "User     : rcpuser" "recipe: user= applied"
call "%HELPERS%" assert_output_contains "%OUT%" "bootstraps\zsh" "recipe: bootstraps= applied"
call "%HELPERS%" assert_output_contains "%OUT%" "poststraps\uv" "recipe: poststraps= applied"
call "%HELPERS%" assert_output_not_contains "%OUT%" "Commit   :" "recipe: commit= ignored for a WSL build"

echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m command line overrides the recipe
call "%SCRIPT%" --recipe %C2W_TEST_ID%-dev --private "%_OA%" -n %C2W_TEST_ID%-other -u someone --dry-run > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "WSL Name : %C2W_TEST_ID%-other" "recipe-override: -n wins"
call "%HELPERS%" assert_output_contains "%OUT%" "User     : someone" "recipe-override: -u wins"
call "%SCRIPT%" --recipe %C2W_TEST_ID%-dev --private "%_OA%" --target container --dry-run > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "Container: %C2W_TEST_ID%-dev" "recipe-container: --target container builds a container"
call "%HELPERS%" assert_output_contains "%OUT%" "Commit   : localhost/rcp:1" "recipe-container: commit= applies to a container build"

echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m target= in the recipe, last overlay wins, path form
call "%SCRIPT%" --recipe %C2W_TEST_ID%-ct --private "%_OB%" --dry-run > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "Container: %C2W_TEST_ID%-ct" "recipe-target: target=container in the recipe"
set "C2W_PRIVATE_DIRS=%_OA%;%_OB%"
call "%SCRIPT%" --recipe %C2W_TEST_ID%-dup --dry-run > "%OUT%" 2>&1
set "C2W_PRIVATE_DIRS="
call "%HELPERS%" assert_output_contains "%OUT%" "Image    : debian:12" "recipe-dup: the overlay listed last wins"
call "%SCRIPT%" --recipe "%_OA%\recipes\%C2W_TEST_ID%-dup.conf" --dry-run > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "Image    : alpine:3.19" "recipe-path: a .conf path is used as given"

echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m recipe errors
call "%SCRIPT%" --recipe %C2W_TEST_ID%-none --private "%_OA%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "recipe-missing: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "No recipe" "recipe-missing: message"
call "%HELPERS%" assert_output_contains "%OUT%" "Recipes (name, overlay, image)" "recipe-missing: lists the recipes"
call "%SCRIPT%" --recipe %C2W_TEST_ID%-noimage --private "%_OB%" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "recipe-noimage: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "has no image= line" "recipe-noimage: message"
call "%SCRIPT%" --recipe "%C2W_TMPDIR%\nope.conf" > "%OUT%" 2>&1
set "_RC=%errorlevel%"
call "%HELPERS%" assert_exit_nonzero "%_RC%" "recipe-badpath: non-zero exit"
call "%HELPERS%" assert_output_contains "%OUT%" "Recipe file not found" "recipe-badpath: message"

echo    %C2W_ESC%[33mtest:%C2W_ESC%[0m rebuild-wsl wrapper
call "%WRAP%" --private "%_OA%" > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "No recipe" "wrapper: a first argument that is not a recipe name is reported"
set "C2W_PRIVATE_DIRS=%_OA%"
call "%WRAP%" > "%OUT%" 2>&1
call "%HELPERS%" assert_output_contains "%OUT%" "%C2W_TEST_ID%-dev  (rcp_a)" "wrapper: no arguments lists the recipes"
call "%WRAP%" %C2W_TEST_ID%-dev -n %C2W_TEST_ID%-w --dry-run > "%OUT%" 2>&1
set "_RC=%errorlevel%"
set "C2W_PRIVATE_DIRS="
call "%HELPERS%" assert_exit_zero "%_RC%" "wrapper: exit 0"
call "%HELPERS%" assert_output_contains "%OUT%" "WSL Name : %C2W_TEST_ID%-w" "wrapper: forwards the recipe and overrides"

endlocal & set "C2W_PASS=%C2W_PASS%"& set "C2W_FAIL=%C2W_FAIL%"
goto :eof
