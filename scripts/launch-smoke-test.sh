#!/bin/zsh
# Launch the packaged PaneSpace app and assert that it actually runs.
#
# `codesign --verify` cannot see this class of failure. A bundle whose host
# carries hardened runtime without `disable-library-validation` verifies
# cleanly -- every codesign check passes -- and then dyld refuses to map
# Sparkle.framework and the app is dead on arrival:
#
#   dyld: Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
#     Reason: code signature in .../Sparkle not valid for use in process:
#     mapping process and mapped file (non-platform) have different Team IDs
#
# So the check is a launch, not a signature inspection. Four things are
# asserted, each of which has its own failure mode:
#
#   1. the process is still alive after the wait (default 10s)
#   2. nothing dyld-shaped was written to its output
#   3. Sparkle.framework is actually mapped into the process
#   4. DYLD_INSERT_LIBRARIES is ignored -- the host has hardened runtime and
#      no `allow-dyld-environment-variables`, so dyld strips DYLD_* before
#      it maps anything
#
# (4) is checked with a real injected library rather than by reading the
# entitlements, and the same probe is first injected into a tiny unsigned
# executable as a positive control. A negative result only means something
# if the probe is known to work.
#
# The binary is launched directly rather than through `open`, so the
# captured output belongs to this process and its exit status is the app's
# own. It needs a window server: an AppKit app launched with no Aqua session
# dies with "FAILED TO establish the default connection to the WindowServer",
# which is an environment problem rather than a packaging one, so the script
# says so instead of reporting it as a broken bundle.
#
# Usage: scripts/launch-smoke-test.sh [app-bundle] [seconds]
set -euo pipefail

project_dir="${0:A:h:h}"
app="${1:-$project_dir/dist/PaneSpace.app}"
seconds="${2:-10}"
executable="$app/Contents/MacOS/PaneSpace"

fail() {
    print -u2 "error: $1"
    shift
    for line in "$@"; do
        print -u2 "       $line"
    done
    exit 1
}

[[ -x "$executable" ]] || fail "no executable at $executable" "build the app first: make app"

# A GUI session is a precondition, not something this script can substitute
# for. Checking it here turns an opaque WindowServer crash into one line that
# says what is wrong with the runner.
if [[ "$(launchctl managername 2>/dev/null || print none)" != "Aqua" ]]; then
    fail "this host has no Aqua session, so a GUI app cannot be launched" \
        "the smoke test needs a runner with a window server; it is not a packaging failure"
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/panespace-launch-smoke.XXXXXX")"
app_pid=""

cleanup() {
    if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
    fi
    rm -rf "$workdir"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# The load-time probe, plus the positive control that proves it works.
# ---------------------------------------------------------------------------

probe_dylib="$workdir/probe.dylib"
probe_control="$workdir/probe-control"
# `xcrun --sdk macosx` rather than a bare `clang`: the latter picks up whatever
# SDK `xcode-select` happens to point at, which on a machine with the Command
# Line Tools installed alongside Xcode is a different (and often mismatched) SDK.
xcrun --sdk macosx clang -dynamiclib -o "$probe_dylib" \
    "$project_dir/scripts/dyld-injection-probe.c"
xcrun --sdk macosx clang -o "$probe_control" \
    "$project_dir/scripts/dyld-injection-probe.c"

control_marker="$workdir/control.marker"
PANESPACE_INJECTION_MARKER="$control_marker" \
DYLD_INSERT_LIBRARIES="$probe_dylib" \
    "$probe_control"
if [[ ! -f "$control_marker" ]]; then
    fail "the injection probe did not run in an unsigned process" \
        "DYLD_INSERT_LIBRARIES is ignored here, so a negative result from the app below would prove nothing"
fi
print "Positive control: DYLD_INSERT_LIBRARIES works on an unsigned process"

# ---------------------------------------------------------------------------
# Launch the packaged bundle and watch what happens to it.
# ---------------------------------------------------------------------------

launch_log="$workdir/launch.log"
"$executable" > "$launch_log" 2>&1 &
app_pid=$!

sleep "$seconds"

if ! kill -0 "$app_pid" 2>/dev/null; then
    # `set -e` would abort on a non-zero wait before the status could be read,
    # and `status` is itself read-only in zsh ($status is the last exit code).
    exit_code=0
    wait "$app_pid" 2>/dev/null || exit_code=$?
    print -u2 -- "--- output from the app ---"
    sed 's/^/       /' "$launch_log"
    print -u2 -- "--- end of output ---"
    fail "the app exited with code ${exit_code} before the ${seconds}s mark" \
        "a bundle that cannot stay alive is not shippable, whatever codesign says"
fi
print "Survived ${seconds}s"

# dyld writes its complaints to stderr, which is captured above. The patterns
# are the ones this failure mode has actually produced, plus a catch-all for
# anything else dyld refuses.
if grep -Eq 'dyld:|Library not loaded|not valid for use in process|failed to map' "$launch_log"; then
    print -u2 -- "--- output from the app ---"
    sed 's/^/       /' "$launch_log"
    print -u2 -- "--- end of output ---"
    fail "dyld reported a load failure; the app was never really running" \
        "this is the failure codesign --verify cannot see"
fi
print "No dyld errors in the app's output"

# Sparkle is linked at load time, so it is mapped whether or not the updater
# ever manages to start. Its absence means the framework was not loaded at all,
# which is the state every one of these checks was written to catch.
lsof -p "$app_pid" > "$workdir/lsof.txt" 2>/dev/null || true
if ! grep -q 'Frameworks/Sparkle\.framework/' "$workdir/lsof.txt"; then
    fail "Sparkle.framework is not mapped into the running process" \
        "the host would have been dead on launch if dyld had complained; check the signature flags"
fi
print "Sparkle.framework is loaded"

kill "$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true
app_pid=""

# ---------------------------------------------------------------------------
# Same bundle, with a library pushed at it.
# ---------------------------------------------------------------------------

injected_marker="$workdir/injected.marker"
injected_log="$workdir/injected.log"
PANESPACE_INJECTION_MARKER="$injected_marker" \
DYLD_INSERT_LIBRARIES="$probe_dylib" \
    "$executable" > "$injected_log" 2>&1 &
app_pid=$!

sleep 5

if ! kill -0 "$app_pid" 2>/dev/null; then
    print -u2 -- "--- output from the app ---"
    sed 's/^/       /' "$injected_log"
    print -u2 -- "--- end of output ---"
    fail "the app died when DYLD_INSERT_LIBRARIES was set" \
        "a hardened-runtime host that cannot start under a stray DYLD_* is not the build we meant to ship"
fi

if [[ -f "$injected_marker" ]]; then
    fail "DYLD_INSERT_LIBRARIES was honoured" \
        "the host carries allow-dyld-environment-variables, or hardened runtime is not actually on it"
fi
print "DYLD_INSERT_LIBRARIES is ignored"

kill "$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true
app_pid=""

print "Launch smoke test passed: $app"