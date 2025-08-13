#!/bin/bash

# Steps:
# Download ffmpeg source (instructions written for v7.0.3)
# Enter paths beloww
# Run this script, it will compile ffmpeg with everything disabled except things needed to convert opus.webm to aac.m4a
# Make manual corrections in the generated .plist (see below)

# Paths
FFMPEG_DIR="~/ffmpeg"
OUTPUT_DIR="~/ffmpeg/build"
XCFRAMEWORK_DIR="~/ffmpeg/ffmpeg-xcframework"

# Architectures and platforms
IOS_ARCHS=("arm64")
SIMULATOR_ARCHS=("arm64")
CATALYST_ARCHS=("arm64" "x86_64")

# FFmpeg configuration flags
CONFIG_FLAGS=(
    "--disable-everything"
    "--disable-videotoolbox"
    "--disable-audiotoolbox"
    "--disable-hwaccels"
    "--disable-decoder=aac"
    "--disable-iconv"
    "--disable-bzlib"
    "--disable-zlib"
    "--disable-programs"
    "--disable-doc"
    "--disable-avdevice"
    "--disable-swscale"
    "--disable-postproc"
    "--disable-avfilter"
    "--disable-network"
    "--enable-protocol=file"
    "--enable-static"
    "--disable-shared"
    "--enable-pic"
    "--enable-optimizations"
    "--disable-debug"
    "--enable-demuxer=matroska"
    "--enable-decoder=opus"
    "--enable-encoder=aac"
    "--enable-muxer=mp4"
    "--enable-swresample"
)

# Clean output directories
echo "Cleaning output directories..."
rm -rf "$OUTPUT_DIR"
rm -rf "$XCFRAMEWORK_DIR"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$XCFRAMEWORK_DIR"

# Build function
build_ffmpeg() {
    local platform=$1
    local arch=$2
    local sdk=$3
    local output_path="$OUTPUT_DIR/$platform-$arch"
    local prefix="$output_path"

    echo "Building FFmpeg for $platform-$arch..."

    mkdir -p "$output_path"
    cd "$FFMPEG_DIR"

    local extra_cflags=""
    local extra_ldflags=""
    local platform_flags=""
    local cc="clang"
    local cxx="clang++"

    case $platform in
        "iphoneos")
            platform_flags="--enable-cross-compile --target-os=darwin --arch=$arch --sysroot=$(xcrun --sdk $sdk --show-sdk-path)"
            extra_cflags="-arch $arch -miphoneos-version-min=15.5"
            extra_ldflags="-arch $arch -miphoneos-version-min=15.5"
            ;;
        "iphonesimulator")
            platform_flags="--enable-cross-compile --target-os=darwin --arch=$arch --sysroot=$(xcrun --sdk $sdk --show-sdk-path)"
            extra_cflags="-arch $arch -mios-simulator-version-min=15.5"
            extra_ldflags="-arch $arch -mios-simulator-version-min=15.5"
            ;;
        "maccatalyst")
            if [ "$arch" = "arm64" ]; then
                platform_flags="--enable-cross-compile --target-os=darwin --arch=$arch --sysroot=$(xcrun --sdk iphoneos --show-sdk-path)"
                extra_cflags="-arch $arch -miphoneos-version-min=15.5 -target $arch-apple-ios15.5-macabi -iframework $(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks"
                extra_ldflags="-arch $arch -miphoneos-version-min=15.5 -target $arch-apple-ios15.5-macabi -iframework $(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks"
            else
                platform_flags="--enable-cross-compile --target-os=darwin --arch=$arch --sysroot=$(xcrun --sdk macosx --show-sdk-path)"
                extra_cflags="-arch $arch -miphoneos-version-min=15.5 -target $arch-apple-ios15.5-macabi -iframework $(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks"
                extra_ldflags="-arch $arch -miphoneos-version-min=15.5 -target $arch-apple-ios15.5-macabi -iframework $(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks"
            fi
            ;;
    esac

    ./configure \
        ${CONFIG_FLAGS[@]} \
        $platform_flags \
        --prefix="$prefix" \
        --cc="$cc" \
        --cxx="$cxx" \
        --extra-cflags="$extra_cflags" \
        --extra-ldflags="$extra_ldflags" > "$output_path/configure.log" 2>&1 || {
            echo "Configure failed for $platform-$arch. Check $output_path/configure.log"
            exit 1
        }

    make clean
    make -j$(sysctl -n hw.ncpu) || exit 1
    make install || exit 1

    # Merge all static libs into one
    mkdir -p "$output_path/lib"
    libtool -static -o "$output_path/lib/libffmpeg.a" $output_path/lib/*.a || exit 1

    # Copy headers to shared include (once)
    if [ ! -d "$OUTPUT_DIR/shared-include" ]; then
        mkdir -p "$OUTPUT_DIR/shared-include"
        cp -r "$output_path/include/." "$OUTPUT_DIR/shared-include/"
    fi

    cd -
}

# Build for iOS
for arch in "${IOS_ARCHS[@]}"; do
    build_ffmpeg "iphoneos" "$arch" "iphoneos"
done

# Build for iOS Simulator
for arch in "${SIMULATOR_ARCHS[@]}"; do
    build_ffmpeg "iphonesimulator" "$arch" "iphonesimulator"
done

# Build for Mac Catalyst
for arch in "${CATALYST_ARCHS[@]}"; do
    build_ffmpeg "maccatalyst" "$arch" "iphoneos"
done

# Create fat lib for Mac Catalyst
mkdir -p "$OUTPUT_DIR/maccatalyst-fat/lib"
lipo -create \
    $(for arch in "${CATALYST_ARCHS[@]}"; do echo "$OUTPUT_DIR/maccatalyst-$arch/lib/libffmpeg.a"; done) \
    -output "$OUTPUT_DIR/maccatalyst-fat/lib/libffmpeg.a" || exit 1

# Create XCFramework
echo "Creating XCFramework..."
xcodebuild -create-xcframework \
    -library "$OUTPUT_DIR/iphoneos-arm64/lib/libffmpeg.a" -headers "$OUTPUT_DIR/shared-include" \
    -library "$OUTPUT_DIR/iphonesimulator-arm64/lib/libffmpeg.a" -headers "$OUTPUT_DIR/shared-include" \
    -library "$OUTPUT_DIR/maccatalyst-fat/lib/libffmpeg.a" -headers "$OUTPUT_DIR/shared-include" \
    -output "$XCFRAMEWORK_DIR/webm_to_m4a_ffmpeg.xcframework" || exit 1

# Fix Info.plist for Mac Catalyst
echo "Fixing Info.plist for Mac Catalyst..."
PLIST="$XCFRAMEWORK_DIR/webm_to_m4a_ffmpeg.xcframework/Info.plist"
/usr/libexec/PlistBuddy -c "Set :AvailableLibraries:0:SupportedPlatform ios" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :AvailableLibraries:0:SupportedPlatformVariant string maccatalyst" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :AvailableLibraries:0:LibraryIdentifier macos-arm64_x86_64" "$PLIST"

# .plist might be incorrect, manually check and fix, it needs:
#  LibraryIdentifier - SupportedArchitectures - SupportedPlatform - SupportedPlatformVariant
#  ios-arm64 - arm64 - ios -
#  ios-arm64-simulator - arm64 - ios - simulator
#  ios-arm64_x86_64-maccatalyst - [arm64, x86_64] - ios - maccatalyst

echo "✅ XCFramework created successfully at $XCFRAMEWORK_DIR/webm_to_m4a_ffmpeg.xcframework"
