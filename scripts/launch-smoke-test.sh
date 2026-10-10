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
# entitlements, and the same probe is first injected into a tiny non-hardened
# executable as a positive control. A negative result only means something
# if the probe is known to work. Both controls run dyld-injection-target.c,
# which has no constructor of its own, so the marker can only come from a
# real injection -- see the note at the top of that file.
#
# (4) also has a negative control: the same target signed with hardened
# runtime and the host's own entitlements, which is the host's configuration
# minus the bundle. If the probe gets in there, this machine is not enforcing
# the DYLD restriction and the host tells us nothing -- on a hosted runner
# that has happened, where the product was fine and the runner simply does not
# strip DYLD_* from hardened processes. That case is reported as skipped, with
# the reason, rather than failed or, worse, quietly dropped. The other four
# checks stay hard.
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

# ---------------------------------------------------------------------------
# Read the host's actual entitlements, and refuse the two that would make the
# rest of this script lie.
#
# This has to come before the controls, not after. The skip branch below is
# reached only when the negative control could be injected, and it reads that
# as "this machine does not enforce the restriction". If the bundle itself
# carries allow-dyld-environment-variables, then a control injected says
# nothing about the machine -- it just says the bundle's own configuration lets
# DYLD_* through -- and a host that was injected for that reason would be
# reported as a skipped pass. That is the exact defect check (4) exists to
# catch. get-task-allow is refused for the same reason: it is a debugger
# entitlement and it has no business on a shipped bundle.
#
# So the host is checked up front, on its own signature, and a bundle carrying
# either key fails here without reaching any branch. That holds no matter what
# the controls say, and no matter which entitlements the controls were signed
# with -- which is why the controls do not take their entitlements from a file
# at all.
#
# Read into a variable and matched there rather than piped into grep: under
# `set -o pipefail` a `codesign | grep -q` that finds nothing is indistinguishable
# from codesign itself failing.
#
# A failed read is itself a failure, not a clean result. This `if` used to have
# no else branch, so a codesign that could not read the signature took the
# check block out of the run entirely: no error, no message, straight on to the
# injection tests. On a machine that enforces the restriction the bundle still
# failed later, which made the hole look closed; on the runner this whole
# exercise is about, the control and the host would both be injected and the
# run would exit 0 having reported nothing. That is the B5 path with a
# different door, so the read has to succeed before the check means anything.
# A host with no entitlements at all is not that case: codesign exits 0 and
# prints nothing, which passes the key checks below on an empty string.
if ! host_entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)"; then
    fail "could not read the host's entitlements" \
        "without them this script cannot rule out a bundle that accepts DYLD_* by design" \
        "a host with no entitlements is fine; codesign returns 0 with empty output, so this is a read failure"
fi
if [[ "$host_entitlements" == *com.apple.security.cs.allow-dyld-environment-variables* ]]; then
    fail "the host carries com.apple.security.cs.allow-dyld-environment-variables" \
        "this bundle would accept DYLD_INSERT_LIBRARIES by design; it is not the build this smoke test can vouch for" \
        "this is checked before the injection tests on purpose: otherwise a permissive host is let off by the branch that reports a non-enforcing machine"
fi
if [[ "$host_entitlements" == *com.apple.security.get-task-allow* ]]; then
    fail "the host carries com.apple.security.get-task-allow" \
        "a debugger entitlement does not belong on a shipped bundle"
fi
print "Host entitlements do not weaken the DYLD restriction"

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
# The load-time probe, plus the two controls that give it meaning.
# ---------------------------------------------------------------------------

probe_dylib="$workdir/probe.dylib"
# `xcrun --sdk macosx` rather than a bare `clang`: the latter picks up whatever
# SDK `xcode-select` happens to point at, which on a machine with the Command
# Line Tools installed alongside Xcode is a different (and often mismatched) SDK.
xcrun --sdk macosx clang -dynamiclib -o "$probe_dylib" \
    "$project_dir/scripts/dyld-injection-probe.c"

# Same source for both controls; only the signature differs. See
# scripts/dyld-injection-target.c for why this cannot be the probe source.
#
# The negative control is signed with hardened runtime and exactly one
# entitlement, disable-library-validation, written out here rather than read
# from scripts/PaneSpace.entitlements. Two reasons, both about what the
# control is allowed to say:
#
# The entitlement itself. Hardened runtime turns on library validation by
# default, so an unsigned probe dylib is refused on that basis alone and the
# control is refused whether or not this machine strips DYLD_*. On a runner
# that does not enforce the restriction, a control signed with no entitlements
# at all would still read as "refused", the smoke test would take that as a
# hardening failure, and it would fail a perfectly good build -- turning the
# one case the control exists to catch into a false alarm.
# disable-library-validation removes that confound: it is exactly what lets
# the host load the probe if DYLD_* ever did reach it, so from here on the only
# gate left is the DYLD strip itself.
#
# The source of the file. When the control was signed with the host's own
# entitlements file, a bundle that had been widened to carry
# allow-dyld-environment-variables produced an injected control, the skip
# branch took over, and a bundle that accepts DYLD_* by design exited 0. A
# control signed from a fixed set generated here can never be widened by
# editing a file, so the only thing that can inject it is a machine that does
# not enforce the restriction. The host is checked separately above, which
# covers the same ground for the bundle itself.
control_target="$workdir/probe-control"
runtime_target="$workdir/probe-runtime-control"
control_entitlements="$workdir/control.entitlements"
cat > "$control_entitlements" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS
xcrun --sdk macosx clang -o "$control_target" \
    "$project_dir/scripts/dyld-injection-target.c"
cp "$control_target" "$runtime_target"
if ! codesign --force --options runtime \
    --entitlements "$control_entitlements" \
    --sign - "$runtime_target" 2>/dev/null; then
    fail "could not sign the negative control with hardened runtime" \
        "without it the control cannot say whether this machine enforces the restriction"
fi

run_control() {
    local target="$1" marker="$2"
    rm -f "$marker"
    PANESPACE_INJECTION_MARKER="$marker" \
    DYLD_INSERT_LIBRARIES="$probe_dylib" \
        "$target" > /dev/null 2>&1
    [[ -f "$marker" ]]
}

# Positive control: no hardened runtime, so the injection must land. If this
# fails the probe is broken and the host result below would prove nothing.
if ! run_control "$control_target" "$workdir/control.marker"; then
    fail "the injection probe did not run in a non-hardened process" \
        "DYLD_INSERT_LIBRARIES is ignored here, so a negative result from the app below would prove nothing"
fi
print "Positive control: DYLD_INSERT_LIBRARIES works on a non-hardened process"

# Negative control: identical code, hardened runtime, and one entitlement
# (disable-library-validation) generated above. On a machine that enforces the
# restriction this must be refused, and that is what makes the host's refusal a
# statement about the host.
if run_control "$runtime_target" "$workdir/runtime.marker"; then
    runtime_enforced=false
    print "Negative control: hardened runtime WITH only disable-library-validation WAS injected"
else
    runtime_enforced=true
    print "Negative control: injection refused by hardened runtime, as expected"
fi

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
    if [[ "$runtime_enforced" == "true" ]]; then
        fail "DYLD_INSERT_LIBRARIES was honoured" \
            "the host carries allow-dyld-environment-variables, or hardened runtime is not actually on it" \
            "a binary with hardened runtime and the same entitlements refused the same injection on this machine"
    fi
    # The control says this machine does not strip DYLD_* from hardened
    # processes, so the host's result is not evidence about the host. That is a
    # property of the runner, not of the bundle, and failing here would report a
    # packaging defect that does not exist. The build-app.sh assertions still
    # refuse to produce a bundle without the runtime flag or with the allow-dyld
    # entitlement, so this is the only check that goes soft, and only on a host
    # that has already shown it does not enforce the rule.
    print "skipped: this machine does not enforce hardened-runtime DYLD restrictions"
    print "         the negative control -- hardened runtime, only"
    print "         disable-library-validation -- accepted the same injection, so"
    print "         this host's result says nothing about PaneSpace. build-app.sh"
    print "         still asserts the runtime flag, and the check at the top of"
    print "         this script refuses allow-dyld-environment-variables."
else
    print "DYLD_INSERT_LIBRARIES is ignored"
    if [[ "$runtime_enforced" == "false" ]]; then
        # The host is stricter than the control, which is not a failure, but it
        # is not what the control predicted either and it is worth saying so
        # rather than leaving a reader to assume the control ran as designed.
        print "note: the negative control was injectable while this host was not,"
        print "      so the host is more restricted than the control measures."
        print "      The host's own entitlements were checked above and carry"
        print "      nothing that widens DYLD, so this pass stands."
    fi
fi

kill "$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true
app_pid=""

print "Launch smoke test passed: $app"