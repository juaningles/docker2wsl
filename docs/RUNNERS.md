# Runners: one set of straps, three places to run them

The straps in `bootstraps/` and `poststraps/`, the private overlays and the recipes are shared by
three ways of building:

| runner | host | result | engines |
|---|---|---|---|
| `container2wsl.bat` (default, `--target wsl`) | Windows | a WSL distro | docker or podman to fetch the image, then `wsl --import` |
| `container2wsl.bat --target container` | Windows | a running container, optionally committed to an image | docker or podman (the devtools `docker.bat` shim runs podman) |
| `container2x.sh` | macOS, Linux (also inside WSL) | a running container, optionally committed to an image | docker, podman, or Apple `container` (macOS on Apple silicon) |

A strap written for one runs unchanged in the others. Anything a strap cannot do in a container
checks `C2W_TARGET` and skips itself (`systemd-enable`, `podman-machine`).

## The contract every runner keeps

**Rendering.** Before a strap runs, the runner turns it into a shell script:
- drops blank lines and lines starting with `#` (a `#` after leading blanks stays),
- trims trailing blanks,
- expands `%NAME%` only when `NAME` is a defined variable, and leaves everything else exactly as
  written: an undefined `%NAME%`, a lone `%`, and `%%` (which stays two characters),
- prepends `set -e` and writes LF line endings.

container2wsl.bat does this with PowerShell `ExpandEnvironmentVariables`, container2x.sh with awk.
So in a strap, a literal percent sign is written as one `%` (`stat -c %a`, `printf '%s'`), never `%%`.

**Variables.** Every runner sets these before rendering (and exports them for container2x.sh):

| variable | meaning |
|---|---|
| `C2W_NAME`, `C2W_USER`, `C2W_IMAGE`, `C2W_LOCATION` | name, user, image, records/storage root |
| `C2W_TARGET` | `wsl` or `container` |
| `C2W_ENGINE` | `wsl`, `docker`, `podman` or `apple` |
| `C2W_SCRIPT_DIR`, `C2W_SCRIPT_DIR_LX` | the runner's folder, as the host sees it and as the target sees it |
| `C2W_PRIVATE_DIRS`, `C2W_PRIVATE_DIRS_LX` | private overlay folders (`;` list on Windows, `:` list on macOS/Linux; `_LX` is always a `:` list) |
| `C2W_STRAP_DIR`, `C2W_STRAP_DIR_LX` | folder of the strap being run |
| `C2W_USERPROFILE_LX` | the host user's home, as the target sees it |
| `C2W_SSH_ACL_CHECK` | `host` when the runner already checked the ssh source's Windows ACLs |

`*_LX` paths are valid **inside** the target. On Windows they are `/mnt/<drive>/...`; on macOS and
Linux they are the host path itself.

**Paths into a container.** A container sees host folders only through bind mounts. The container
runners mount each folder a strap may read at its `*_LX` path: the runner's folder, the `devtools`
clone next to it, every private overlay, `C2W_SSH_SOURCE`, and the per-run folder that holds the
rendered scripts and the manifest. Straps therefore use the same paths in a distro and in a
container. Mounts are not part of a committed image.

When the engine runs on another machine (podman remote from WSL, a Docker context, a VM), those
folders must exist there too. From WSL with the `podman-machine` poststrap, keep the repos under
`/mnt/c` and point `C2X_RUN_ROOT` at a `/mnt/c` folder.

**Users and commands.** Bootstraps run as root, poststraps as `C2W_USER`. WSL uses
`wsl -d NAME -u USER -- bash script`; containers use `<engine> exec -u USER NAME bash script`.
Both give a non-login shell with `HOME` set. `USER` is unset under `exec`, so straps use `$HOME`
and `$(id -un)`, not `$USER`.

**Manifest.** The same JSON Lines records (`create`, one `strap` per strap, `complete`) go to
`/etc/container2wsl/manifest.jsonl` in the target, with the exact rendered scripts in
`/etc/container2wsl/straps/`, and a copy on the host under `C2W_LOCATION/NAME/`. `c2w-manifest`
reads both kinds. Container records add `distro.target`, `distro.engine` and `distro.commit`.

**Recipes.** `--recipe NAME` (both runners) reads `<private overlay>/recipes/NAME.conf` from the
same overlay folders the build detects, turns it into arguments placed before the command line's,
and runs the runner again with them. Keys and rules: README "Recipes". `rebuild-wsl.bat` and
`rebuild-container` in the repo root are shorthands for `--recipe`. The manifest records the recipe
as `command.recipe`.

## Container specifics

- The container starts with `--entrypoint sleep ... infinity` so `exec` has something to attach to.
  The image needs a `sleep` (coreutils or busybox).
- `--commit IMAGE:TAG` resets that: the image gets an empty entrypoint, `CMD <user's shell> -l`,
  `USER` and `WORKDIR /home/USER`. docker and podman do it with `commit --change`. Apple's
  `container commit` has no `--change`, so container2x.sh commits to a temporary tag and runs a
  three-line `container build`; if that build fails, the image keeps the `sleep` entrypoint and the
  runner says so.
- Apple containers default to arm64 images; `--arch amd64` runs x86 images through Rosetta.
- `ssh-keys`: the Windows ACL check needs `powershell.exe`, which a container cannot start, so the
  runner does it on the host and renders `C2W_SSH_ACL_CHECK=host`. Other sources get the usual
  700 / 600 mode checks; container2x.sh checks the folder mode on the host first.
- Bind-mounted files show up owned by root (podman) or another uid, so owner-only files such as keys
  are read through `sudo cat`: build with `-b sudo`, as for WSL.
