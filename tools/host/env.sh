# Windows hosts (Git Bash / MSYS): set SDKROOT so tests/host/check-*.py can
# compile production Swift with the swift.org toolchain. Source it once:
#   . tools/host/env.sh
# macOS and Linux hosts need nothing; this file is a no-op there.
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*)
    for sdk in $(ls -d "$LOCALAPPDATA"/Programs/Swift/Platforms/*/Windows.platform/Developer/SDKs/Windows.sdk 2>/dev/null | sort -V -r); do
        SDKROOT="$(cygpath -w "$sdk")"; export SDKROOT; echo "SDKROOT=$SDKROOT"; break
    done
    [ -n "$SDKROOT" ] || echo "No Windows.sdk found; install Swift from swift.org" >&2
    ;;
esac
