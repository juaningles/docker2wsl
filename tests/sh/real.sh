#!/usr/bin/env bash
# tests/sh/real.sh - real end-to-end builds with container2x.sh, one suite per engine.
#   bash tests/sh/real.sh                 every engine that works here; the rest print SKIP
#   bash tests/sh/real.sh apple podman    only these
# A suite runs only where its engine works:
#   apple   macOS with Apple's container CLI and its service running (container system start)
#   podman  "podman info" answers
#   docker  "docker info" answers and docker is not podman in disguise (podman-docker)
# Each suite builds c2x-real-<engine> from ubuntu:24.04 with real straps and a throwaway private
# overlay and ssh key, checks the result inside the container, commits it, and removes everything
# afterwards, also on failure. Needs network access (packages, uv, devtools from GitHub when no
# devtools clone sits next to docker2wsl). Takes a few minutes per engine.
# Scratch files live in tests/sh/.real-tmp (gitignored), inside the repo: the engine must see
# every bind-mounted folder, which also holds for podman remote when the repo is on a shared path.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../.." && pwd -P)
C2X="$ROOT/container2x.sh"
IMAGE="${C2X_REAL_IMAGE:-docker.io/library/ubuntu:24.04}"
ENGINES=("$@"); [ ${#ENGINES[@]} -gt 0 ] || ENGINES=(apple podman docker)
PASS=0 FAIL=0 SKIP=0 RAN=0
ok()  { PASS=$((PASS+1)); printf '      \033[92mPASS\033[0m %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '      \033[91mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/           /'; }
skip(){ SKIP=$((SKIP+1)); printf '   \033[90mSKIP\033[0m %s\n' "$1"; }

available() {   # $1 = engine; prints the reason and fails when it cannot run here
  case "$1" in
    apple)
      [ "$(uname -s)" = Darwin ] || { echo "not macOS"; return 1; }
      command -v container >/dev/null 2>&1 || { echo "Apple container CLI not installed (github.com/apple/container)"; return 1; }
      container system status >/dev/null 2>&1 || { echo "container service not running (container system start)"; return 1; } ;;
    podman)
      command -v podman >/dev/null 2>&1 || { echo "podman not installed"; return 1; }
      podman info >/dev/null 2>&1 || { echo "podman does not answer (podman info)"; return 1; } ;;
    docker)
      command -v docker >/dev/null 2>&1 || { echo "docker not installed"; return 1; }
      if docker --version 2>/dev/null | grep -qi podman; then echo "docker is podman here (podman-docker); covered by the podman suite"; return 1; fi
      docker info >/dev/null 2>&1 || { echo "docker does not answer (docker info)"; return 1; } ;;
    *) echo "unknown engine"; return 1 ;;
  esac
}

# the suite being run, for cleanup (also from the EXIT trap when a run is interrupted)
eng= E= name= img= tmp=
cleanup() {
  [ -n "$name" ] || return 0
  if [ "$eng" = apple ]; then container delete --force "$name" >/dev/null 2>&1; container image delete --force "$img" >/dev/null 2>&1
  else "$E" rm -f "$name" >/dev/null 2>&1; "$E" rmi -f "$img" >/dev/null 2>&1; fi
  rm -rf "$tmp"
  return 0
}
trap 'cleanup; rmdir "$HERE/.real-tmp" 2>/dev/null' EXIT
trap 'exit 130' INT TERM
x() { "$E" exec -u tester "$name" bash -lc "$1" 2>&1; }

suite() {
  eng="$1"
  case "$eng" in apple) E=container ;; *) E=$eng ;; esac
  name="c2x-real-$eng"; img="localhost/c2x-real-$eng:1"
  tmp="$HERE/.real-tmp/$eng"
  printf '   \033[33mreal:\033[0m %s (%s)\n' "$eng" "$("$E" --version 2>/dev/null | head -1)"
  RAN=$((RAN+1))
  cleanup; mkdir -p "$tmp"
  suite_body
  cleanup; name=
}

suite_body() {
  local ov="$tmp/c2x-real-overlay" out="$tmp/build.log"
  mkdir -p "$ov/ssh" "$tmp/run" "$tmp/records"

  # throwaway overlay: a git repo with a shell file and a test key pair
  touch "$ov/.devtools-overlay"; mkdir -p "$ov/shell"
  echo "alias c2xreal='echo c2x-real-ok'" > "$ov/shell/c2xreal.sh"
  ssh-keygen -q -t ed25519 -N '' -C c2x-real -f "$ov/ssh/id_c2x_real" >/dev/null 2>&1 || printf 'not-a-real-key\n' > "$ov/ssh/id_c2x_real"
  printf 'Host c2x-real\n  HostName 127.0.0.1\n  IdentityFile ~/.ssh/id_c2x_real\n' > "$ov/ssh/config"
  printf 'ssh/*\n' > "$ov/.gitignore"
  chmod 700 "$ov/ssh"; chmod 600 "$ov/ssh/id_c2x_real"
  git -C "$ov" init -q && git -C "$ov" add -A && git -C "$ov" -c user.name=c2x -c user.email=c2x@example.invalid commit -q -m test
  # a /mnt folder (WSL drvfs) keeps no Unix modes; its Windows ACL check is covered by the bat tests
  case "$ov" in /mnt/*) export C2W_SSH_ACL_CHECK=off ;; *) unset C2W_SSH_ACL_CHECK ;; esac

  local straps=(-b sudo -b devtools -b k8s-tools -p uv -p devtools-shell -p devtools-overlay -p ssh-keys)
  local arch=(); [ "$eng" = apple ] && arch=(--arch arm64)
  C2X_RUN_ROOT="$tmp/run" C2W_LOCATION="$tmp/records" bash "$C2X" "$IMAGE" --engine "$eng" ${arch[@]+"${arch[@]}"} \
    -n "$name" -u tester --private "$ov" "${straps[@]}" --commit "$img" > "$out" 2>&1
  local rc=$?
  if [ $rc = 0 ]; then ok "$eng: build with 7 straps and --commit"; else bad "$eng: build with 7 straps and --commit" "$(tail -25 "$out")"; return; fi

  local v
  v=$(x 'id -un'); [ "$v" = tester ] && ok "$eng: runs as tester" || bad "$eng: runs as tester" "$v"
  x 'sudo -n true' >/dev/null && ok "$eng: passwordless sudo" || bad "$eng: passwordless sudo"
  v=$(x 'kubectl version --client 2>&1 | head -1; helm version --short') && ok "$eng: kubectl and helm run ($(echo "$v" | tr '\n' ' '))" || bad "$eng: kubectl and helm run" "$v"
  v=$(x 'uname -m'); [ "$eng" = apple ] && { [ "$v" = aarch64 ] && ok "$eng: arm64 userland" || bad "$eng: arm64 userland" "$v"; }
  x 'test -x ~/devtools/install.sh' >/dev/null && ok "$eng: devtools installed" || bad "$eng: devtools installed"
  x 'test -L ~/devtools/overlays/c2x-real-overlay' >/dev/null && ok "$eng: overlay linked into devtools" || bad "$eng: overlay linked into devtools" "$(x 'ls -la ~/devtools/overlays')"
  v=$(x 'stat -c %a ~/.ssh ~/.ssh/id_c2x_real | tr "\n" " "'); [ "$v" = "700 600 " ] && ok "$eng: ~/.ssh 700, key 600" || bad "$eng: ~/.ssh 700, key 600" "$v"
  v=$(x 'grep -c "^# ---- from /" ~/.ssh/config'); [ "$v" = 1 ] && ok "$eng: ssh config header names its source folder" || bad "$eng: ssh config header names its source folder" "$(x 'grep "^# ----" ~/.ssh/config')"
  v=$(x 'c2w-manifest'); echo "$v" | grep -q "7 requested, 7 ran: 7 ok, 0 failed" && ok "$eng: c2w-manifest lists 7 straps ok" || bad "$eng: c2w-manifest lists 7 straps ok" "$v"
  # Apple's run prints "[n/6] ..." progress lines too: keep only the command's last output line
  if [ "$eng" = apple ]; then v=$(container run --rm --entrypoint /bin/sh "$img" -c 'id -un' 2>&1 | grep -v '^\[[0-9]/[0-9]\]' | tail -1)
  else v=$("$E" run --rm --entrypoint /bin/sh "$img" -c 'id -un' 2>&1); fi
  [ "$v" = tester ] && ok "$eng: committed image starts as tester" || bad "$eng: committed image starts as tester" "$v"
  C2X_RUN_ROOT="$tmp/run" C2W_LOCATION="$tmp/records" bash "$C2X" "$IMAGE" --engine "$eng" ${arch[@]+"${arch[@]}"} -n "$name" > "$out" 2>&1
  [ $? != 0 ] && grep -q "already exists" "$out" && ok "$eng: second build without --force refuses" || bad "$eng: second build without --force refuses" "$(tail -5 "$out")"
  C2X_RUN_ROOT="$tmp/run" C2W_LOCATION="$tmp/records" bash "$C2X" "$IMAGE" --engine "$eng" ${arch[@]+"${arch[@]}"} -n "$name" -u tester --force > "$out" 2>&1
  [ $? = 0 ] && ok "$eng: --force rebuilds" || bad "$eng: --force rebuilds" "$(tail -10 "$out")"
}

for _t in container podman docker; do
  _p=$(command -v "$_t" 2>/dev/null) || continue
  if grep -q 'tests/sh/mock-engine' "$_p" 2>/dev/null; then
    echo "[ERROR] real.sh: $_p is the test mock (tests/sh/mock-engine), not a real engine. Run real.sh with the normal PATH." >&2
    exit 1
  fi
done

echo " container2x.sh real builds ($IMAGE)"
for eng in "${ENGINES[@]}"; do
  reason=$(available "$eng") && suite "$eng" || { [ -n "$reason" ] && skip "$eng: $reason"; }
done
echo
printf ' Real: %d passed, %d failed, %d engine(s) skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$RAN" = 0 ] && echo " No engine was available here, so nothing ran for real."
[ "$FAIL" = 0 ]
