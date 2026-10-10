#!/bin/zsh
# Build the PaneSpace application bundle.
#
# With no environment set this reproduces the previous hard-coded behaviour:
# version 0.1.2, build 3, ad-hoc signature. Release automation overrides
# everything through the environment, so local development is unchanged:
#
#   PANESPACE_VERSION        CFBundleShortVersionString (e.g. 0.2.0-beta.1)
#   PANESPACE_BUILD          CFBundleVersion            (e.g. 20001)
#   PANESPACE_SIGN_IDENTITY  codesign identity; unset or "-" signs ad-hoc
#   PANESPACE_SIGN_KEYCHAIN  keychain to search for the identity (CI uses a
#                            temporary one; unset uses the default search list)
#   PANESPACE_ED_PUBLIC_KEY  base64 32-byte Ed25519 public key -> SUPublicEDKey
#   PANESPACE_APPCAST_URL    https appcast URL -> SUFeedURL; required together
#                            with the public key
#   PANESPACE_APPCAST_ALLOW_LOCALHOST
#                            test-only: allow an http://127.0.0.1 feed. Never set
#                            this in CI.
#   PANESPACE_THIN_FRAMEWORK  set to 0 to keep the framework universal
#
# The host bundle is always signed with hardened runtime and exactly one
# entitlement, scripts/PaneSpace.entitlements. See the comment above sign_host.
#
# Sparkle 2 is linked from SwiftPM but `swift build` only links it: the framework
# is not copied into a bundle layout and the main binary has no rpath that would
# find it there. Both steps are done by hand below, then the result is signed
# inside-out. See docs/adr/0011-in-app-updates.md.
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
app_dir="$project_dir/dist/PaneSpace.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
frameworks_dir="$contents_dir/Frameworks"
plist_path="$contents_dir/Info.plist"
resources_dir="$contents_dir/Resources"

bundle_version="${PANESPACE_VERSION:-0.1.2}"
bundle_build="${PANESPACE_BUILD:-3}"
sign_identity="${PANESPACE_SIGN_IDENTITY:--}"
sign_keychain="${PANESPACE_SIGN_KEYCHAIN:-}"
public_ed_key="${PANESPACE_ED_PUBLIC_KEY:-}"
thin_framework="${PANESPACE_THIN_FRAMEWORK:-1}"

if [[ -n "$public_ed_key" ]]; then
    # Sparkle reads SUPublicEDKey as a base64 32-byte Ed25519 key. A wrong length
    # would only fail at update time on a user's machine, so reject it here.
    if [[ ! "$public_ed_key" =~ '^[A-Za-z0-9+/]{43}=$' ]]; then
        print -u2 "error: PANESPACE_ED_PUBLIC_KEY must be a base64 32-byte Ed25519 public key"
        exit 1
    fi
fi

cd "$project_dir"
swift build -c release

rm -rf "$app_dir"
mkdir -p "$macos_dir"
cp "$build_dir/release/PaneSpace" "$macos_dir/PaneSpace"
mkdir -p "$resources_dir"
cp -R "$project_dir/Sources/PaneSpaceApp/Resources/zh-Hans.lproj" "$resources_dir/"
cp "$project_dir/Assets/PaneSpace.icns" "$resources_dir/PaneSpace.icns"

plutil -create xml1 "$plist_path"
plutil -insert CFBundleDevelopmentRegion -string en "$plist_path"
plutil -insert CFBundleExecutable -string PaneSpace "$plist_path"
plutil -insert CFBundleIdentifier -string org.panespace.app "$plist_path"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$plist_path"
plutil -insert CFBundleIconFile -string PaneSpace.icns "$plist_path"
plutil -insert CFBundleName -string PaneSpace "$plist_path"
plutil -insert CFBundleLocalizations -json '["en", "zh-Hans"]' "$plist_path"
plutil -insert CFBundlePackageType -string APPL "$plist_path"
plutil -insert CFBundleShortVersionString -string "$bundle_version" "$plist_path"
plutil -insert CFBundleVersion -string "$bundle_build" "$plist_path"
plutil -insert LSMinimumSystemVersion -string 26.0 "$plist_path"
plutil -insert NSHighResolutionCapable -bool true "$plist_path"
plutil -insert NSDesktopFolderUsageDescription -string "PaneSpace needs access to browse and manage items on your Desktop." "$plist_path"
plutil -insert NSDocumentsFolderUsageDescription -string "PaneSpace needs access to browse and manage items in your Documents folder." "$plist_path"
plutil -insert NSDownloadsFolderUsageDescription -string "PaneSpace needs access to browse and manage items in your Downloads folder." "$plist_path"
plutil -insert NSNetworkVolumesUsageDescription -string "PaneSpace needs access to browse and manage items on connected network volumes." "$plist_path"
plutil -insert NSRemovableVolumesUsageDescription -string "PaneSpace needs access to browse and manage items on connected removable volumes." "$plist_path"

if [[ -n "$public_ed_key" ]]; then
    plutil -insert SUPublicEDKey -string "$public_ed_key" "$plist_path"
    # Sparkle 2 reads the appcast from SUFeedURL. There is deliberately no
    # localhost fallback: a build that ships SUPublicEDKey but no reachable feed
    # would show a permanently failing update check, so the URL must be supplied
    # explicitly. Only https is accepted, because the feed decides which update is
    # offered and a plaintext feed can be tampered with.
    #
    # PANESPACE_APPCAST_ALLOW_LOCALHOST=1 relaxes the scheme check to permit a
    # local appcast served by the end-to-end test. It must never be set in CI:
    # release.yml does not, and shipping a release that trusts a plaintext feed
    # would defeat the EdDSA verification the rest of this script sets up.
    feed_url="${PANESPACE_APPCAST_URL:-}"
    if [[ -z "$feed_url" ]]; then
        print -u2 "error: PANESPACE_APPCAST_URL is required when PANESPACE_ED_PUBLIC_KEY is set"
        exit 1
    fi
    allow_localhost="${PANESPACE_APPCAST_ALLOW_LOCALHOST:-0}"
    if [[ "$feed_url" != https://* ]]; then
        # Anchored, and the path must be present. A prefix test on the bare host
        # would also accept http://127.0.0.1.evil.example/ and
        # http://user@127.0.0.1@evil.example/, both of which resolve to a
        # plaintext host of someone else's choosing. Only the loopback literal,
        # an optional numeric port, and a path are allowed.
        if [[ "$allow_localhost" == "1" && "$feed_url" =~ '^http://127\.0\.0\.1(:[0-9]{1,5})?/' ]]; then
            print -u2 "warning: PANESPACE_APPCAST_ALLOW_LOCALHOST=1 -- this build trusts a plaintext local feed"
            print -u2 "         and must never be published or released"
        else
            print -u2 "error: PANESPACE_APPCAST_URL must be an https URL"
            exit 1
        fi
    fi
    plutil -insert SUFeedURL -string "$feed_url" "$plist_path"
    # Sparkle only checks its own defaults for these; declaring them here makes the
    # shipped defaults explicit and overridable by the update preferences UI.
    plutil -insert SUEnableAutomaticChecks -bool true "$plist_path"
    plutil -insert SUAutomaticallyUpdate -bool false "$plist_path"
    plutil -insert SUScheduledCheckInterval -integer 86400 "$plist_path"
    # The feed is on a fixed public URL, so sign it too: an unsigned feed can have
    # its channel tags and minimum-system-version edited without touching the
    # update signature.
    plutil -insert SURequireSignedFeed -bool true "$plist_path"
    plutil -insert SUVerifyUpdateBeforeExtraction -bool true "$plist_path"
fi

# Embed Sparkle.framework from the SwiftPM build products. `swift build` links
# @rpath/Sparkle.framework but copies nothing, so the manual assembly has to place
# the framework under Contents/Frameworks and add the matching
# @executable_path/../Frameworks rpath to the main binary.
sparkle_framework="$build_dir/release/Sparkle.framework"
if [[ ! -d "$sparkle_framework" ]]; then
    print -u2 "error: Sparkle.framework was not produced by the build; the app cannot start without it"
    exit 1
fi
mkdir -p "$frameworks_dir"
rm -rf "$frameworks_dir/Sparkle.framework"
ditto "$sparkle_framework" "$frameworks_dir/Sparkle.framework"

sparkle_bin="$frameworks_dir/Sparkle.framework/Versions/Current"

# PaneSpace is not sandboxed, and the XPC services are opt-in: Sparkle consults
# SUEnableInstallerLauncherService / SUEnableDownloaderService (SPUXPCServiceIsEnabled)
# and falls back to in-process helpers when they are absent. This bundle sets
# neither, so the services are never reachable and are dead weight: 408 K and two
# more nested bundles to sign. The glob qualifier (N) makes a non-matching pattern
# expand to nothing instead of failing the script under `setopt nomatch` -- which
# is what would happen if this were ever run against a build without them.
xpc_services="$sparkle_bin/XPCServices"
if [[ -d "$xpc_services" ]]; then
    xpc_bytes=$(du -sk "$xpc_services" | awk '{print $1}')
    rm -rf "$xpc_services"
    print "Removed XPCServices (${xpc_bytes}K): not sandboxed, and the SUEnable*Service keys are unset"
fi

# The framework ships as a universal binary. PaneSpace's own artifact is arm64
# (release.yml names the archive -macos-arm64), so the x86_64 half of the
# framework can never be loaded and is only size. Thinning happens before signing
# because lipo rewrites the Mach-O the signature covers.
if [[ "$thin_framework" == "1" ]]; then
    # Every Mach-O inside the framework, not just the main one: the nested helpers
    # are separate binaries and codesign verifies each of them.
    while IFS= read -r binary; do
        archs="$(lipo -archs "$binary" 2>/dev/null || true)"
        if [[ " $archs " == *" x86_64 "* ]]; then
            lipo -thin arm64 "$binary" -o "$binary.thin"
            mv "$binary.thin" "$binary"
        fi
    done < <(find "$frameworks_dir/Sparkle.framework" -type f -perm +111 ! -name '*.dylib' 2>/dev/null)
    print "Thinned Sparkle.framework to arm64"
fi

# Check first: install_name_tool exits non-zero when the rpath is already present,
# which is not a failure. Adding it blindly and ignoring the error would also hide
# a genuine tool failure, so the existing entry is detected instead and a real
# error still aborts the build.
#
# Every check below reads its tool's output into a variable first and greps the
# variable, never `tool | grep -q`. Under `set -o pipefail` that idiom is a coin
# flip, not a test: `grep -q` stops at the first match and closes the pipe, the
# tool dies on SIGPIPE with 141, pipefail turns that into a failed pipeline, and
# the assertion reports a perfectly good bundle as broken. Measured on this
# machine, `codesign -dvv <app> | grep -q 'flags=.*runtime'` failed 10 times out
# of 200 -- about one build in twenty, which on CI is a red run that nobody can
# reproduce.
host_rpaths="$(otool -l "$macos_dir/PaneSpace")"
host_loads="$(otool -L "$macos_dir/PaneSpace")"
if [[ "$host_rpaths" != *"path @executable_path/../Frameworks"* ]]; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$macos_dir/PaneSpace"
    host_rpaths="$(otool -l "$macos_dir/PaneSpace")"
fi
# Confirm the load command resolves, rather than trusting that the rpath was added:
# without it dyld reports the missing Sparkle at launch, long after the build.
if [[ "$host_loads" != *@rpath/Sparkle.framework* ]]; then
    print -u2 "error: the main binary does not link Sparkle.framework"
    exit 1
fi

# The host bundle IS signed with hardened runtime (-o runtime), carrying one
# entitlement: com.apple.security.cs.disable-library-validation, from
# scripts/PaneSpace.entitlements.
#
# Hardened runtime enables library validation by default, which requires every
# loaded library to have the same Team ID as the process or be signed by Apple.
# A self-signed certificate and an ad-hoc signature both produce
# "TeamIdentifier=not set", so with runtime on and no entitlement the check can
# never pass and the app dies at launch:
#
#   dyld: Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
#     Reason: code signature in .../Sparkle.framework/.../Sparkle not valid for
#     use in process: mapping process and mapped file (non-platform) have
#     different Team IDs
#
# That failure is invisible to codesign -- every verify passes on the broken
# bundle -- which is why the packaged app is launched in CI rather than only
# verified, and why the entitlement list is asserted against the signature
# below instead of being assumed from the flags.
#
# The entitlement is the minimum that makes the runtime flag usable here. It
# switches off exactly one check, the one that cannot pass without a real Team
# ID, and keeps the rest: no dylib injection through the environment, no JIT,
# no unsigned executable memory. It is also the narrowest grant that can be
# made, so it is asserted to be the ONLY entitlement the host carries -- a
# second key here would be a new capability nobody had asked for.
#
# ADR 0011 §2b records the measurements behind this and what changes if
# PaneSpace ever moves to a real Developer ID.

# Set before the signing functions run: they read `keychain_args` at call time, and under
# `set -u` an unset array is an error rather than an empty list. Declaring it next to the
# functions would be too late -- the nested helpers are signed first.
keychain_args=()
if [[ -n "$sign_keychain" ]]; then
    keychain_args=(--keychain "$sign_keychain")
fi

entitlements_file="$project_dir/scripts/PaneSpace.entitlements"
if [[ ! -f "$entitlements_file" ]]; then
    print -u2 "error: $entitlements_file is missing"
    print -u2 "       the host needs disable-library-validation to run with hardened runtime"
    exit 1
fi

# What the host is allowed to carry is written out here rather than taken from
# the entitlements file. That file is editable text: the post-signature check
# below asks "does the signature match the file", and a second key added to the
# file would be signed, would match, and would quietly hand the host a
# capability nobody reviewed. Pinning the grant in the script means the
# entitlements a reader approves are the only ones a build can produce -- adding
# a capability has to be a visible edit to this list, not a silent edit to a
# plist. The value is pinned with the key, because disable-library-validation set
# to false would pass every check here and still die at launch. Checked before
# anything is signed, so an over-broad file never reaches a signature at all.
PaneSpaceENTITLEMENTS_KEYS=(
    com.apple.security.cs.disable-library-validation
)
grants_dir="$(mktemp -d)"
trap 'rm -rf "$grants_dir"' EXIT
{
    print -r -- '<?xml version="1.0" encoding="UTF-8"?>'
    print -r -- '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    print -r -- '<plist version="1.0">'
    print -r -- '<dict>'
    for key in "${PaneSpaceENTITLEMENTS_KEYS[@]}"; do
        print -r -- "	<key>$key</key>"
        print -r -- '	<true/>'
    done
    print -r -- '</dict>'
    print -r -- '</plist>'
} | plutil -convert xml1 -o - - > "$grants_dir/approved.plist"
plutil -convert xml1 -o - "$entitlements_file" > "$grants_dir/declared.plist"
if ! cmp -s "$grants_dir/approved.plist" "$grants_dir/declared.plist"; then
    print -u2 "error: $entitlements_file does not match the grant in this script"
    print -u2 "       the script grants exactly: ${PaneSpaceENTITLEMENTS_KEYS[*]}"
    print -u2 "       granting another capability means editing that list deliberately"
    print -u2 "       declared:"
    plutil -p "$entitlements_file" >&2
    exit 1
fi

sign_host() {
    local target="$1"
    # The entitlements file is passed explicitly rather than inherited: codesign
    # takes --preserve-metadata=entitlements from the old signature, which for a
    # rebuilt bundle is whatever the previous build happened to carry.
    if [[ "$sign_identity" == "-" ]]; then
        codesign --force --sign - --timestamp=none \
            -o runtime --entitlements "$entitlements_file" "$target"
    else
        codesign --force --sign "$sign_identity" --timestamp=none \
            -o runtime --entitlements "$entitlements_file" \
            $keychain_args "$target"
    fi
}

# Sparkle's nested helpers ship signed ad-hoc with hardened runtime, and Autoupdate
# carries an application-identifier entitlement it needs for its XPC channel with
# the host app. Re-signing them without those two things silently drops them, so
# both are preserved explicitly:
#   --preserve-metadata=entitlements  keeps the upstream entitlements blob
#   -o runtime                        keeps the hardened runtime flag
# These helpers are separate processes whose load commands reference only system
# frameworks, so hardened runtime costs them nothing here: they never load
# Sparkle.framework, and library validation has no non-platform library to
# reject. The host is the opposite case (see sign_host), which is why the two
# functions differ.
sign_one() {
    local target="$1"
    if [[ "$sign_identity" == "-" ]]; then
        codesign --force --sign - --timestamp=none \
            -o runtime --preserve-metadata=entitlements "$target"
    else
        codesign --force --sign "$sign_identity" --timestamp=none \
            -o runtime --preserve-metadata=entitlements \
            $keychain_args "$target"
    fi
}

# Innermost first: the installer executable and the progress agent inside the
# framework, then the framework itself, then the host bundle. Autoupdate is a bare
# executable rather than a bundle, and it is the process that actually replaces the
# app, so leaving it ad-hoc would mean the step that touches the installation is
# the one piece not covered by our identity.
nested_targets=(
    "$sparkle_bin/Autoupdate"
    "$sparkle_bin/XPCServices/"*.xpc(N)
    "$sparkle_bin/Updater.app"
)
for nested in $nested_targets; do
    [[ -e "$nested" ]] || continue
    print "Signing $(basename "$nested")"
    sign_one "$nested"
done
print "Signing Sparkle.framework"
sign_one "$frameworks_dir/Sparkle.framework"

if [[ "$sign_identity" == "-" ]]; then
    print "Signing ad-hoc (-)"
else
    print "Signing with identity: $sign_identity"
fi
# Hardened runtime + exactly the entitlements in PaneSpaceENTITLEMENTS_KEYS below,
# which is asserted against scripts/PaneSpace.entitlements. Point codesign
# straight at the requested keychain instead of editing the user's keychain
# search list.
sign_host "$app_dir"

codesign --verify --strict --verbose=2 "$app_dir"
# AGENTS.md requires the --deep form too; it is the check that would catch a
# framework that was signed after its host or left unsigned entirely.
codesign --verify --deep --strict "$app_dir"

# The flags and the entitlements are asserted rather than assumed: they are the
# two halves of one decision, and only the combination is launchable. Runtime
# without disable-library-validation kills the app at launch; the entitlement
# without the flag would be a silently degraded build that passes every check
# above. Both halves are read back out of the signature, because a valid
# signature is not a launchable one.
host_flags="$(codesign -dvv "$app_dir" 2>&1)"
if [[ "$host_flags" != *'flags='*'runtime'* ]]; then
    print -u2 "error: host bundle is not signed with hardened runtime"
    print -u2 "       without the flag the disable-library-validation entitlement does nothing"
    print -u2 "       codesign -dvv reported: $host_flags"
    exit 1
fi
# `codesign -d --entitlements -` prints the blob as it is stored in the
# signature, which is not the same byte sequence as the file: codesign rewrites
# the DOCTYPE and drops the whitespace. Both sides are therefore run through
# `plutil -convert xml1` first, so the comparison is on canonical plist text
# rather than on formatting. What is asserted is "the host carries exactly what
# this file says", including that nothing else crept in -- a grep for the one
# key the file happens to hold would pass on a build that also carries a second
# capability nobody asked for. The file was already pinned against
# PaneSpaceENTITLEMENTS_KEYS before anything was signed, so this comparison
# closes the remaining gap: that what ended up signed is what was declared.
host_entitlements="$(codesign -d --entitlements - --xml "$app_dir" 2>/dev/null \
    | plutil -convert xml1 -o - - 2>/dev/null || true)"
expected_entitlements="$(plutil -convert xml1 -o - "$entitlements_file")"
if [[ -z "$host_entitlements" ]]; then
    print -u2 "error: the host bundle carries no entitlements"
    print -u2 "       expected exactly what $entitlements_file declares"
    exit 1
fi
if [[ "$host_entitlements" != "$expected_entitlements" ]]; then
    print -u2 "error: the host bundle's entitlements do not match $entitlements_file"
    print -u2 "       signed with:"
    print -u2 "       $host_entitlements"
    print -u2 "       expected:"
    print -u2 "       $expected_entitlements"
    exit 1
fi
print "Host carries hardened runtime and only $(basename "$entitlements_file")"

# A nested helper left ad-hoc would still pass the checks above, because an ad-hoc
# signature is valid on its own -- but ad-hoc is precisely the failure mode here:
# Sparkle ships Autoupdate ad-hoc, so a script that skipped it would leave the
# process that replaces the application outside the release identity while still
# looking fine.
#
# The check is on the designated requirement, not on codesign's "Authority=" line:
# that line is printed from the trust cache and is not a reliable indicator -- a
# self-signed certificate imported with -A does print an Authority=, while a
# certificate that is present but not yet trusted prints none, and both states
# differ from "never signed". The DR is always reported, and it is the only one of
# the two produced from the signature itself rather than the trust cache.
#
# The DR must be checked for a certificate clause, but *which* clause depends on
# the certificate, so both forms are accepted:
#     ... and certificate leaf  = H"…"   leaf is not a CA
#     ... and certificate root  = H"…"   leaf is a CA / there is a root in the chain
# Self-signed development certificates land in the first form even though they are
# their own root, so matching "certificate root" alone would reject every correctly
# signed build made with one -- the exact misreport this assertion was written to
# avoid. What must never appear is the ad-hoc form,
#     ... or cdhash H"…" or cdhash H"…"
# which is the failure being guarded against.
if [[ "$sign_identity" != "-" ]]; then
    for helper in \
        "$sparkle_bin/Autoupdate" \
        "$sparkle_bin/Updater.app" \
        "$sparkle_bin/XPCServices/"*.xpc(N)
    do
        [[ -e "$helper" ]] || continue
        # codesign prefixes the requirement with "# " when it is the default
        # requirement, so the match cannot be anchored to "^designated" without
        # discarding the very line the error message wants to quote.
        helper_dr="$(codesign -d -r- "$helper" 2>&1 | grep -i 'designated')"
        if [[ "$helper_dr" != *"certificate leaf"* \
           && "$helper_dr" != *"certificate root"* ]]; then
            print -u2 "error: $(basename "$helper") is not signed with the release identity"
            print -u2 "       (an ad-hoc signature would leave the installer unsigned in effect)"
            print -u2 "       designated requirement: ${helper_dr:-<none>}"
            exit 1
        fi
    done
    print "Nested Sparkle helpers carry the release identity"
fi
print "Built $app_dir ($bundle_version, build $bundle_build)"
