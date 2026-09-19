#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
app_dir="$project_dir/dist/PaneSpace.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
plist_path="$contents_dir/Info.plist"

cd "$project_dir"
swift build -c release

rm -rf "$app_dir"
mkdir -p "$macos_dir"
cp "$build_dir/release/PaneSpace" "$macos_dir/PaneSpace"

plutil -create xml1 "$plist_path"
plutil -insert CFBundleDevelopmentRegion -string en "$plist_path"
plutil -insert CFBundleExecutable -string PaneSpace "$plist_path"
plutil -insert CFBundleIdentifier -string org.panespace.app "$plist_path"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$plist_path"
plutil -insert CFBundleName -string PaneSpace "$plist_path"
plutil -insert CFBundlePackageType -string APPL "$plist_path"
plutil -insert CFBundleShortVersionString -string 0.1.0 "$plist_path"
plutil -insert CFBundleVersion -string 1 "$plist_path"
plutil -insert LSMinimumSystemVersion -string 26.0 "$plist_path"
plutil -insert NSHighResolutionCapable -bool true "$plist_path"

codesign --force --deep --sign - "$app_dir"
echo "Built $app_dir"
