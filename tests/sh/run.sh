#!/usr/bin/env bash
# tests/sh/run.sh - tests for container2x.sh (macOS / Linux runner).
#   tests/sh/run.sh           mock suite: every engine (docker, podman, apple) with a fake CLI
#   tests/sh/run.sh --real    mock suite, then tests/sh/real.sh: real builds with each engine
#                             that works here (others report SKIP)
# Exit code: 0 when nothing failed. Needs bash, awk, sed, grep; no container engine for the mocks.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../.." && pwd -P)
C2X="$ROOT/container2x.sh"
PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); printf '      \033[92mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '      \033[91mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '           %s\n' "$2"; }
t()    { printf '   \033[33mtest:\033[0m %s\n' "$1"; }
has()  { if grep -qF -- "$2" "$1"; then ok "$3"; else bad "$3" "not found: $2"; fi; }
hasnt(){ if grep -qF -- "$2" "$1"; then bad "$3" "found but should not be: $2"; else ok "$3"; fi; }
rc0()  { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "exit $1"; fi; }
rcn()  { if [ "$1" != 0 ]; then ok "$2"; else bad "$2" "exit 0"; fi; }

# the environment real.sh must get back: no mock engines on PATH, none of the mock variables
ORIG_PATH="$PATH"
# resolved (pwd -P): on macOS mktemp gives /var/..., a symlink to /private/var/..., and the runner
# prints resolved paths
TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
for n in docker podman container; do cp "$HERE/mock-engine" "$BIN/$n"; chmod +x "$BIN/$n"; done
export PATH="$BIN:$PATH" C2X_MOCK_LOG="$TMP/calls.log" C2W_LOCATION="$TMP/records" C2X_RUN_ROOT="$TMP/run"
unset C2W_PRIVATE_DIRS C2W_SSH_SOURCE C2W_ENGINE C2W_SSH_ACL_CHECK
OUT="$TMP/out.txt"
reset() { : > "$C2X_MOCK_LOG"; unset C2X_MOCK_EXISTS C2X_MOCK_RUN_FAIL C2X_MOCK_STRAP_FAIL C2X_MOCK_COMMIT_FAIL C2X_MOCK_BUILD_FAIL C2X_MOCK_NAME; rm -rf "$TMP/scripts"; mkdir -p "$TMP/scripts"; export C2X_MOCK_SCRIPTS="$TMP/scripts"; }
c2x() { bash "$C2X" "$@" > "$OUT" 2>&1; }

# a private overlay with one strap and an ssh folder, plus two plain strap files
PRIV="$TMP/my-overlay"; mkdir -p "$PRIV/straps" "$PRIV/ssh"; touch "$PRIV/.devtools-overlay"
printf '# overlay strap\necho overlay %%C2W_STRAP_DIR_LX%%\n' > "$PRIV/straps/hello"
printf 'k' > "$PRIV/ssh/id_test"; chmod 700 "$PRIV/ssh"; chmod 600 "$PRIV/ssh/id_test"
BS="$TMP/boot.txt"; printf '# comment dropped\n\necho root %%C2W_USER%% %%C2W_TARGET%%   \necho keep %%NOT_DEFINED_X%% and %%%%a and 100%%\n' > "$BS"
PS="$TMP/post.txt"; printf 'echo user %%C2W_ENGINE%%\n' > "$PS"

echo " container2x.sh tests (mock engines)"

t "arguments"
c2x --help; rc0 $? "help: exit 0"; has "$OUT" "--engine E" "help: lists --engine"
c2x; rcn $? "no image: non-zero exit"; has "$OUT" "An image is required" "no image: message"
c2x ubuntu:24.04 --engine bogus; rcn $? "bad engine: non-zero exit"; has "$OUT" "docker, podman or apple" "bad engine: message"
c2x ubuntu:24.04 -n; rcn $? "missing value: non-zero exit"
c2x ubuntu:24.04 -b no-such-strap --engine docker --dry-run; rcn $? "unknown strap: non-zero exit"; has "$OUT" "Bootstrap not found: no-such-strap" "unknown strap: message"

t "dry run renders straps like container2wsl.bat"
reset
c2x ubuntu:24.04 --engine podman -n dry1 -u tester -b "$BS" -p "$PS" --private "$PRIV" -p hello --dry-run
rc0 $? "dry: exit 0"
has "$OUT" "Container: dry1 (podman, via podman)" "dry: container and engine shown"
has "$OUT" "Private  : $PRIV" "dry: --private folder used"
has "$OUT" "Mount    : $PRIV" "dry: private folder mounted"
has "$OUT" "Mount    : $ROOT" "dry: runner folder mounted"
has "$OUT" "echo root tester container" "dry: %C2W_USER% and %C2W_TARGET% expanded, trailing blanks trimmed"
has "$OUT" "echo keep %NOT_DEFINED_X% and %%a and 100%" "dry: undefined %NAME% and %% left unchanged"
hasnt "$OUT" "comment dropped" "dry: comment lines dropped"
has "$OUT" "echo user podman" "dry: %C2W_ENGINE% expanded"
has "$OUT" "echo overlay $PRIV/straps" "dry: bare name resolved from the overlay's straps/, %C2W_STRAP_DIR_LX% set"
has "$OUT" "--hostname dry1" "dry: podman run gets --hostname"
if [ -s "$C2X_MOCK_LOG" ] && grep -qv -- '--version' "$C2X_MOCK_LOG"; then bad "dry: no engine calls" "$(cat "$C2X_MOCK_LOG")"; else ok "dry: no engine calls"; fi

for eng in docker podman; do
  t "$eng build"
  reset
  c2x ubuntu:24.04 --engine $eng -n b-$eng -u tester -b "$BS" -p "$PS" --private "$PRIV"
  rc0 $? "$eng: exit 0"
  has "$C2X_MOCK_LOG" "$eng run -d --name b-$eng --hostname b-$eng --entrypoint sleep -v $ROOT:$ROOT" "$eng: run with name, hostname, sleep entrypoint, same-path mounts"
  has "$C2X_MOCK_LOG" "-v $PRIV:$PRIV" "$eng: overlay mounted"
  has "$C2X_MOCK_LOG" "$eng exec -u root b-$eng useradd -m -s /bin/bash tester" "$eng: user created as root"
  has "$C2X_MOCK_LOG" "$eng exec -u root b-$eng bash" "$eng: bootstrap runs as root"
  has "$C2X_MOCK_LOG" "$eng exec -u tester b-$eng bash" "$eng: poststrap runs as the user"
  if [ "$(head -1 "$TMP"/scripts/01-bootstrap-boot.txt.sh 2>/dev/null)" = "set -e" ]; then ok "$eng: rendered script starts with set -e"; else bad "$eng: rendered script starts with set -e"; fi
  hasnt "$C2X_MOCK_LOG" "$eng commit" "$eng: no commit without --commit"
  M="$TMP/records/b-$eng/container2wsl-manifest.jsonl"
  if [ -f "$M" ]; then ok "$eng: manifest written"; else bad "$eng: manifest written" "$M"; fi
  if sh "$ROOT/lib/c2w-manifest" -f "$M" > "$TMP/report.txt" 2>&1; then ok "$eng: c2w-manifest reads it"; else bad "$eng: c2w-manifest reads it" "$(cat "$TMP/report.txt")"; fi
  has "$TMP/report.txt" "2 requested, 2 ran: 2 ok, 0 failed" "$eng: manifest records both straps ok"
  has "$TMP/report.txt" "ok in" "$eng: manifest complete record ok"
  has "$OUT" "Container created and running" "$eng: success message"
  has "$OUT" "Enter  : $eng exec -it -u tester -w /home/tester b-$eng /usr/bin/zsh -l" "$eng: enter command uses the user's login shell"
done

t "podman --commit resets the sleep entrypoint"
reset
c2x ubuntu:24.04 --engine podman -n c1 -u tester --commit localhost/c1:1
rc0 $? "commit: exit 0"
has "$C2X_MOCK_LOG" "podman commit --change ENTRYPOINT [] --change CMD /usr/bin/zsh -l --change USER tester --change WORKDIR /home/tester c1 localhost/c1:1" "commit: entrypoint, cmd, user, workdir set"

t "apple engine"
reset
c2x ubuntu:24.04 --engine apple --arch arm64 -n a1 -u tester -p "$PS" --commit localhost/a1:1
rc0 $? "apple: exit 0"
has "$C2X_MOCK_LOG" "container list --all --quiet" "apple: exists check via list --all --quiet"
has "$C2X_MOCK_LOG" "container run -d --name a1 --arch arm64 --entrypoint sleep -v" "apple: run with --arch, no --hostname"
hasnt "$C2X_MOCK_LOG" "--hostname" "apple: no --hostname flag"
has "$C2X_MOCK_LOG" "container exec -u tester a1 bash" "apple: poststrap via container exec"
has "$C2X_MOCK_LOG" "container commit a1 localhost/c2x-commit:a1-" "apple: commit to a temporary image"
has "$C2X_MOCK_LOG" "container build -t localhost/a1:1 -f" "apple: build sets entrypoint, user, workdir"
has "$OUT" "Remove : container delete --force a1" "apple: remove hint uses delete --force"
reset; export C2X_MOCK_BUILD_FAIL=1
c2x ubuntu:24.04 --engine apple -n a2 --commit localhost/a2:1
rc0 $? "apple build fallback: exit 0"
has "$OUT" "still starts 'sleep infinity'" "apple build fallback: warns about the entrypoint"
reset; export C2X_MOCK_EXISTS=1 C2X_MOCK_NAME=a3
c2x ubuntu:24.04 --engine apple -n a3 --force
rc0 $? "apple force: exit 0"
has "$C2X_MOCK_LOG" "container delete --force a3" "apple force: delete --force"

t "existing container, failures"
reset; export C2X_MOCK_EXISTS=1
c2x ubuntu:24.04 --engine docker -n e1
rcn $? "exists: non-zero exit"; has "$OUT" "already exists. Use --force" "exists: refuses"
c2x ubuntu:24.04 --engine docker -n e1 --force
rc0 $? "force: exit 0"; has "$C2X_MOCK_LOG" "docker rm -f e1" "force: removes the old container"
reset; export C2X_MOCK_RUN_FAIL=1
c2x ubuntu:24.04 --engine docker -n f1
rcn $? "run fail: non-zero exit"; has "$OUT" "run failed for ubuntu:24.04" "run fail: message"
reset; export C2X_MOCK_STRAP_FAIL=1
c2x ubuntu:24.04 --engine docker -n f2 -b "$BS" -p "$PS"
rcn $? "strap fail: non-zero exit"; has "$OUT" "Bootstrap failed: bootstrap 1" "strap fail: names the strap"
sh "$ROOT/lib/c2w-manifest" -f "$TMP/records/f2/container2wsl-manifest.jsonl" > "$TMP/report.txt" 2>&1
has "$TMP/report.txt" "FAILED at bootstrap 1" "strap fail: manifest records the failure"
reset; export C2X_MOCK_COMMIT_FAIL=1
c2x ubuntu:24.04 --engine docker -n f3 --commit localhost/f3:1
rcn $? "commit fail: non-zero exit"; has "$OUT" "commit failed" "commit fail: message"

t "ssh-keys host checks"
reset
chmod 755 "$PRIV/ssh"
c2x ubuntu:24.04 --engine docker -n s1 --private "$PRIV" -p ssh-keys
rcn $? "ssh mode: non-zero exit for a 755 ssh folder"; has "$OUT" "needs 700" "ssh mode: message"
chmod 700 "$PRIV/ssh"
c2x ubuntu:24.04 --engine docker -n s2 --private "$PRIV" -p ssh-keys
rc0 $? "ssh mode: 700 folder accepted"

t "WSL-only straps skip themselves"
reset
c2x ubuntu:24.04 --engine docker -n w1 -b systemd-enable -p podman-machine --dry-run
has "$OUT" 'TARGET="container"' "skip: C2W_TARGET rendered into the straps"
has "$OUT" "wsl.conf is WSL-only" "skip: systemd-enable checks the target"
has "$OUT" "not applicable in a container" "skip: podman-machine checks the target"

t "recipes (--recipe / --recipes, rebuild-container)"
reset
RA="$TMP/rcp_a"; RB="$TMP/rcp_b"; mkdir -p "$RA/recipes" "$RB/recipes"
printf '# dev\nimage=ubuntu:24.04\nuser=rcpuser\nbootstraps=sudo\npoststraps=uv\nengine=podman\narch=arm64\ncommit=localhost/rcp:1\n' > "$RA/recipes/dev.conf"
printf 'image=alpine:3.19\n' > "$RA/recipes/dup.conf"; printf 'image=debian:12\n' > "$RB/recipes/dup.conf"
printf 'user=nobody\n' > "$RB/recipes/noimage.conf"
c2x --recipes --private "$RA"; rc0 $? "recipes: list exit 0"
has "$OUT" "dev          (rcp_a)  ubuntu:24.04" "recipes: name, overlay and image"
c2x --recipe dev --private "$RA" --dry-run; rc0 $? "recipe: exit 0"
has "$OUT" "container2x: recipe $RA/recipes/dev.conf" "recipe: recipe file shown"
has "$OUT" "Container: dev (podman, via podman)" "recipe: name from the file, engine= applied"
has "$OUT" "User     : rcpuser" "recipe: user= applied"
has "$OUT" "Image    : ubuntu:24.04 (arm64)" "recipe: arch= applied"
has "$OUT" "Commit   : localhost/rcp:1" "recipe: commit= applied"
has "$OUT" "Bootstrap: $ROOT/bootstraps/sudo" "recipe: bootstraps= applied"
c2x --recipe dev --private "$RA" -n other --engine docker -u someone --dry-run
has "$OUT" "Container: other (docker, via docker)" "recipe override: -n and --engine win"
has "$OUT" "User     : someone" "recipe override: -u wins"
C2W_PRIVATE_DIRS="$RA:$RB" c2x --recipe dup --engine docker --dry-run
has "$OUT" "Image    : debian:12" "recipe dup: the overlay listed last wins"
c2x --recipe "$RA/recipes/dup.conf" --engine docker --dry-run
has "$OUT" "Image    : alpine:3.19" "recipe path: a .conf path is used as given"
c2x --recipe none --private "$RA"; rcn $? "recipe missing: non-zero exit"; has "$OUT" "No recipe" "recipe missing: message"
c2x --recipe noimage --private "$RB"; rcn $? "recipe noimage: non-zero exit"; has "$OUT" "has no image= line" "recipe noimage: message"
c2x --recipe; rcn $? "recipe no value: non-zero exit"
c2x --recipe dev --private "$RA" --engine docker -n r1
rc0 $? "recipe build: exit 0"
sh "$ROOT/lib/c2w-manifest" -f "$TMP/records/r1/container2wsl-manifest.jsonl" > "$TMP/report.txt" 2>&1
has "$TMP/report.txt" "Recipe    $RA/recipes/dev.conf" "recipe build: manifest records the recipe"
c2x --recipes --private "$RA"
has "$OUT" "default      ($(basename "$ROOT"))" "builtin: default sample listed from this repo's recipes/"
c2x --recipe default --private "$RA" --engine docker --dry-run; rc0 $? "builtin: --recipe default exit 0"
has "$OUT" "container2x: recipe $ROOT/recipes/default.conf" "builtin: default.conf used"
has "$OUT" "Poststrap: $ROOT/poststraps/devtools-overlay" "builtin: its straps resolve"
printf 'image=busybox:1.36
' > "$RB/recipes/default.conf"
c2x --recipe default --private "$RB" --engine docker --dry-run
has "$OUT" "Image    : busybox:1.36" "builtin: an overlay recipe of the same name wins"
rm -f "$RB/recipes/default.conf"
C2W_PRIVATE_DIRS="$RA" bash "$ROOT/rebuild-container" > "$OUT" 2>&1
has "$OUT" "dev          (rcp_a)" "rebuild-container: no arguments lists the recipes"
C2W_PRIVATE_DIRS="$RA" bash "$ROOT/rebuild-container" dev -n w1 --dry-run > "$OUT" 2>&1
rc0 $? "rebuild-container: exit 0"; has "$OUT" "Container: w1 (podman" "rebuild-container: forwards the recipe and overrides"

echo
printf ' Assertions: %d passed, %d failed\n' "$PASS" "$FAIL"
RC=0; [ "$FAIL" = 0 ] || RC=1
if [ "${1:-}" = --real ]; then
  echo
  ( export PATH="$ORIG_PATH"
    unset C2X_MOCK_LOG C2X_MOCK_SCRIPTS C2X_MOCK_EXISTS C2X_MOCK_NAME C2X_MOCK_RUN_FAIL C2X_MOCK_STRAP_FAIL \
          C2X_MOCK_COMMIT_FAIL C2X_MOCK_BUILD_FAIL C2W_LOCATION C2X_RUN_ROOT C2W_PRIVATE_DIRS
    bash "$HERE/real.sh" ) || RC=1
fi
exit $RC
