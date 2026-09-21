#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${CONFIGURATION:-release}
output_dir=${OUTPUT_DIR:-"$project_dir/dist"}
app_name="SlimBlade Bootleg Driver"
app_dir="$output_dir/$app_name.app"

cd "$project_dir"
swift build --configuration "$configuration" --product SlimBladeBootlegDriver
binary_dir=$(swift build --configuration "$configuration" --show-bin-path)

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/SlimBladeBootlegDriver" "$app_dir/Contents/MacOS/"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
chmod 755 "$app_dir/Contents/MacOS/SlimBladeBootlegDriver"

# Ad-hoc signing gives local builds a stable code identity. Distributors can
# replace this with a Developer ID signature and notarization.
/usr/bin/codesign --force --sign - --timestamp=none "$app_dir"
echo "$app_dir"
