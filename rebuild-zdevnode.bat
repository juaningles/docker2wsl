@echo off
REM rebuild-zdevnode.bat - build the zdevnode WSL distro with the standard straps.
REM Extra arguments are passed through after the defaults, and the last one wins, e.g.:
REM   rebuild-zdevnode -n zdev                 different distro name
REM   rebuild-zdevnode -n zdev -u alice        different name and user
REM   rebuild-zdevnode --force                 replace an existing zdevnode
REM   rebuild-zdevnode -n zdev --dry-run       show what would run
REM Run from an elevated cmd.
setlocal
call "%~dp0container2wsl.bat" juaningles/devnode:noble -n zdevnode -u juan ^
  -b sudo -b systemd-enable -b zsh -b homebrew -b k8s-tools -b data-tools -b azure-cli ^
  -p powerlevel10k -p uv -p devtools-shell -p claude -p databricks-ug %*
exit /b %ERRORLEVEL%
