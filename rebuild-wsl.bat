@echo off
REM rebuild-wsl.bat - build from a recipe: container2wsl.bat --recipe NAME [args...]
REM   rebuild-wsl                        list the recipes in the private overlays
REM   rebuild-wsl NAME [args...]         build <private overlay>\recipes\NAME.conf; args override
REM   rebuild-wsl NAME --target container   the same recipe as a running docker/podman container
REM Recipes and their keys: README "Recipes". Run from an elevated cmd or PowerShell.
if "%~1"=="" (
    call "%~dp0container2wsl.bat" --recipes
    exit /b
)
call "%~dp0container2wsl.bat" --recipe %*
exit /b
