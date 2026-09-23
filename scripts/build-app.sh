#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
app_dir="$project_dir/dist/PaneSpace.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
plist_path="$contents_dir/Info.plist"
resources_dir="$contents_dir/Resources"

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
plutil -insert CFBundleShortVersionString -string 0.1.0 "$plist_path"
plutil -insert CFBundleVersion -string 1 "$plist_path"
plutil -insert LSMinimumSystemVersion -string 26.0 "$plist_path"
plutil -insert NSHighResolutionCapable -bool true "$plist_path"
plutil -insert NSDesktopFolderUsageDescription -string "PaneSpace needs access to browse and manage items on your Desktop." "$plist_path"
plutil -insert NSDocumentsFolderUsageDescription -string "PaneSpace needs access to browse and manage items in your Documents folder." "$plist_path"
plutil -insert NSDownloadsFolderUsageDescription -string "PaneSpace needs access to browse and manage items in your Downloads folder." "$plist_path"
plutil -insert NSNetworkVolumesUsageDescription -string "PaneSpace needs access to browse and manage items on connected network volumes." "$plist_path"
plutil -insert NSRemovableVolumesUsageDescription -string "PaneSpace needs access to browse and manage items on connected removable volumes." "$plist_path"

codesign --force --deep --sign - "$app_dir"
echo "Built $app_dir"
