#!/bin/bash

# Helper script to create a new release of Nostur
# Requires xcrun and notarytool
# Also requires a valid Apple Developer account and a notarytool profile named "Nostur"

# To make a new release: 
# 1. Set the new version number in Config.xcconfig and run Product -> Archive in Xcode
# 2. Open Xcode Organizer, select the archive and click Distribute App
# 3. Export Nostur.ipa
# 4. Then run this script: ./make_new_release.sh

read -r -p "Enter the path to the exported Nostur.ipa: " ipa_path

if [ ! -f "$ipa_path" ]; then
    echo "Error: IPA '$ipa_path' does not exist"
    exit 1
fi

# Ask for version number
read -r -p "Enter the version number (e.g., 1.18.1): " version

# Resolve the export directory before creating temporary files
ipa_name="$(basename "$ipa_path")"
export_dir="$(cd "$(dirname "$ipa_path")" && pwd)" || {
    echo "Error: Failed to resolve the IPA directory"
    exit 1
}
ipa_path="$export_dir/$ipa_name"
dmg_path="$export_dir/Nostur-${version}.dmg"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/nostur-release.XXXXXX")" || {
    echo "Error: Failed to create a temporary directory"
    exit 1
}
trap 'rm -rf "$work_dir"' EXIT

echo "Extracting Nostur.app from IPA..."
ditto -x -k "$ipa_path" "$work_dir/extracted" || {
    echo "Error: Failed to extract '$ipa_path'"
    exit 1
}

app_path="$work_dir/extracted/Payload/Nostur.app"
if [ ! -d "$app_path" ]; then
    echo "Error: Payload/Nostur.app was not found in '$ipa_path'"
    exit 1
fi

# Stage the app and Applications shortcut without modifying the signed app.
mkdir "$work_dir/dmg-root" || exit 1
ditto "$app_path" "$work_dir/dmg-root/Nostur.app" || {
    echo "Error: Failed to stage Nostur.app"
    exit 1
}
ln -s /Applications "$work_dir/dmg-root/Applications" || exit 1

# Execute the release steps
echo "Creating DMG..."
hdiutil create \
    -volname "Nostur" \
    -srcfolder "$work_dir/dmg-root" \
    -format UDZO \
    -ov \
    "$dmg_path" || {
    echo "Error: Failed to create the DMG"
    exit 1
}

echo "Signing DMG..."
codesign --force --sign "Developer ID Application" --timestamp "$dmg_path" || {
    echo "Error: Failed to sign the DMG"
    exit 1
}

cd "$export_dir" || {
    echo "Error: Failed to change to export directory '$export_dir'"
    exit 1
}

echo "Submitting to notarytool..."
xcrun notarytool submit "Nostur-${version}.dmg" --keychain-profile "Nostur" --wait

echo "Stapling DMG..."
xcrun stapler staple "Nostur-${version}.dmg"

echo "Validating DMG..."
xcrun stapler validate "Nostur-${version}.dmg"

echo "Process completed for version ${version}"
