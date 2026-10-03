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
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
app_dir="$project_dir/dist/PaneSpace.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
plist_path="$contents_dir/Info.plist"
resources_dir="$contents_dir/Resources"

bundle_version="${PANESPACE_VERSION:-0.1.2}"
bundle_build="${PANESPACE_BUILD:-3}"
sign_identity="${PANESPACE_SIGN_IDENTITY:--}"
sign_keychain="${PANESPACE_SIGN_KEYCHAIN:-}"
public_ed_key="${PANESPACE_ED_PUBLIC_KEY:-}"

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
fi

# Sign inside-out without --deep. The bundle holds a single executable and no
# nested frameworks or plug-ins, so a plain outer signature is already correct and
# --deep would only mask a future signing-order mistake.
if [[ "$sign_identity" == "-" ]]; then
    print "Signing ad-hoc (-)"
    codesign --force --sign - --timestamp=none "$app_dir"
else
    print "Signing with identity: $sign_identity"
    # Point codesign straight at the requested keychain instead of editing the
    # user's keychain search list.
    keychain_args=()
    if [[ -n "$sign_keychain" ]]; then
        keychain_args=(--keychain "$sign_keychain")
    fi
    codesign --force --sign "$sign_identity" --timestamp=none $keychain_args "$app_dir"
fi

codesign --verify --strict --verbose=2 "$app_dir"
print "Built $app_dir ($bundle_version, build $bundle_build)"
