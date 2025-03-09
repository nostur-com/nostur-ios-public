#!/bin/bash

# Helper script to create a new release of Nostur
# Requires create-dmg, xcrun, and notarytool to be installed
# Also requires a valid Apple Developer account and a notarytool profile named "Nostur"

# To make a new release: 
# 1. Set the new version number in Config.xcconfig and run Product -> Archive in Xcode
# 2. Open Xcode Organizer, select the archive and click Distribute App
# 3. Choose Custom, Direct Distribution, Export, Automatically manage signing
# 4. Then run this script: ./make_new_release.sh

# Ask for the path to cd into
read -p "Enter the path to the exported Nostur.app: " target_path

# Check if the path exists
if [ ! -d "$target_path" ]; then
    echo "Error: Directory '$target_path' does not exist"
    exit 1
fi

# Ask for version number
read -p "Enter the version number (e.g., 1.18.1): " version

# Change to the specified directory
cd "$target_path" || {
    echo "Error: Failed to change to directory '$target_path'"
    exit 1
}

# Execute the release steps
echo "Creating DMG..."
create-dmg 'Nostur.app'

echo "Renaming DMG..."
mv "Nostur ${version}.dmg" "Nostur-${version}.dmg"

echo "Submitting to notarytool..."
xcrun notarytool submit "Nostur-${version}.dmg" --keychain-profile "Nostur" --wait

echo "Stapling DMG..."
xcrun stapler staple "Nostur-${version}.dmg"

echo "Validating DMG..."
xcrun stapler validate "Nostur-${version}.dmg"

echo "Process completed for version ${version}"