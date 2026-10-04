#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
BUILDER="$REPO_ROOT/scripts/build_android.py"

fail() {
  printf 'build_android_armv7: %s\n' "$*" >&2
  exit 2
}

[[ -f "$BUILDER" ]] || fail "project builder not found: $BUILDER"
command -v python3 >/dev/null 2>&1 || fail 'python3 is required.'

if [[ $# -eq 1 && ( "$1" == '-h' || "$1" == '--help' ) ]]; then
  printf '%s\n' \
    'Build the all-sources Android ARMv7 Release APK.' \
    'Defaults: --abi armeabi-v7a --all-sources; extra builder options are forwarded.' \
    'The underlying --abi option is append-only, so another --abi adds an additional ABI.' \
    ''
  exec python3 "$BUILDER" --help
fi

command -v flutter >/dev/null 2>&1 || fail 'Flutter must be installed and available on PATH.'
command -v go >/dev/null 2>&1 || fail 'Go 1.24.1 or newer must be installed and available on PATH.'
command -v java >/dev/null 2>&1 || fail 'JDK 17 must be installed and java must be available on PATH.'

GO_VERSION_LINE="$(go version 2>/dev/null)" || fail 'could not determine the Go version.'
if ! python3 - "$GO_VERSION_LINE" <<'PY'
import re
import sys

match = re.search(r'\bgo(\d+)\.(\d+)(?:\.(\d+))?', sys.argv[1])
if not match:
    print(f'Could not parse Go version: {sys.argv[1]}', file=sys.stderr)
    raise SystemExit(1)
found = tuple(int(part or 0) for part in match.groups())
if found < (1, 24, 1):
    print(f'Go 1.24.1 or newer is required; found {sys.argv[1]}', file=sys.stderr)
    raise SystemExit(1)
PY
then
  exit 2
fi

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "$SDK_ROOT" ]] || fail 'Set ANDROID_HOME or ANDROID_SDK_ROOT to the Android SDK directory.'
[[ -d "$SDK_ROOT" ]] || fail "Android SDK directory does not exist: $SDK_ROOT"
[[ -d "$SDK_ROOT/platforms/android-36" ]] || fail 'Android SDK Platform 36 is required.'
NDK_ROOT="${ANDROID_NDK_HOME:-$SDK_ROOT/ndk/28.2.13676358}"
[[ -d "$NDK_ROOT" ]] || fail "Android NDK not found: $NDK_ROOT (install 28.2.13676358 or set ANDROID_NDK_HOME)."

case "$(uname -s)" in
  Linux) NDK_HOST=linux-x86_64 ;;
  Darwin) NDK_HOST=darwin-x86_64 ;;
  *) fail 'This wrapper supports Linux and macOS build hosts.' ;;
esac
NDK_COMPILER="$NDK_ROOT/toolchains/llvm/prebuilt/$NDK_HOST/bin/armv7a-linux-androideabi26-clang"
[[ -x "$NDK_COMPILER" ]] || fail "Android API 26 ARMv7 NDK compiler not found or not executable: $NDK_COMPILER"

cd "$REPO_ROOT"
exec python3 "$BUILDER" --abi armeabi-v7a --all-sources "$@"
