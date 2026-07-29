#!/bin/bash
#
# Build script for AppFileManager IPA
#
# Prerequisites:
# - macOS with Xcode 15+ installed
# - Apple Developer account (free tier works for sideloading)
#
# Usage:
#   ./build.sh                    # Build with default settings
#   ./build.sh --team-id YOUR_ID  # Build with specific team ID
#   ./build.sh --release          # Build release configuration
#
# The IPA will be output to ./build/AppFileManager.ipa
#

set -euo pipefail

TEAM_ID="${TEAM_ID:-}"
CONFIGURATION="Debug"
EXPORT_METHOD="ad-hoc"
OUTPUT_DIR="./build"

while [[ $# -gt 0 ]]; do
    case $1 in
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        --release)
            CONFIGURATION="Release"
            shift
            ;;
        --export-method)
            EXPORT_METHOD="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=== AppFileManager Build ==="
echo "Configuration: $CONFIGURATION"
echo "Team ID: ${TEAM_ID:-'(default from Xcode)'}"
echo "Export Method: $EXPORT_METHOD"

# Clean previous build
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Build with xcodebuild
echo "=== Building AppFileManager ==="
xcodebuild \
    -project AppFileManager.xcodeproj \
    -scheme AppFileManager \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -arch arm64 \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    clean build \
    -derivedDataPath "$OUTPUT_DIR/DerivedData" \
    | tee "$OUTPUT_DIR/build.log"

# Find the built .app
APP_PATH=$(find "$OUTPUT_DIR/DerivedData" -name "AppFileManager.app" -type d 2>/dev/null | head -1)

if [ -z "${APP_PATH:-}" ]; then
    echo "ERROR: Could not find AppFileManager.app in build output"
    exit 1
fi

echo "=== Found app at: $APP_PATH ==="

# Create IPA using xcodebuild -exportArchive or just zip the .app
echo "=== Creating IPA ==="

# Create Payload directory (standard IPA format)
mkdir -p "$OUTPUT_DIR/Payload"
cp -r "$APP_PATH" "$OUTPUT_DIR/Payload/AppFileManager.app"

# Zip as IPA
cd "$OUTPUT_DIR"
zip -r -q AppFileManager.ipa Payload
cd -

echo "=== IPA created at: $OUTPUT_DIR/AppFileManager.ipa ==="
echo "=== Build successful! ==="
