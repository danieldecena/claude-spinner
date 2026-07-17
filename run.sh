#!/bin/bash
set -e

echo "Building Claude Spinner..."

# Check if xcodebuild is functional (requires full Xcode, not just CommandLineTools)
if xcodebuild -version &>/dev/null; then
    echo "Using xcodebuild..."
    xcodebuild -scheme "claude spinner" build | xcbeautify
    # Derive the built .app path from build settings so it survives the
    # DerivedData hash changing (it's keyed on the project path, not fixed).
    app=$(xcodebuild -scheme "claude spinner" -configuration Debug -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')
    killall "claude spinner" 2>/dev/null || true
    echo "Launching $app..."
    open "$app"
else
    echo "xcodebuild not available or CommandLineTools selected. Falling back to swiftc..."
    # Glob, not a hand-kept list: "claude spinner/" is a synchronized root group,
    # so a new source file auto-joins the Xcode target with no pbxproj edit. A
    # literal list silently rots behind that — SetupInstaller.swift was added and
    # never listed here, which left this whole branch unable to compile.
    xcrun --sdk macosx swiftc -O -o claude-spinner "claude spinner"/*.swift
    
    if [ -d "/Applications/claude spinner.app" ]; then
        echo "Copying built binary to /Applications/claude spinner.app..."
        cp claude-spinner "/Applications/claude spinner.app/Contents/MacOS/claude spinner"
        echo "Re-signing application..."
        codesign --force --deep --sign - "/Applications/claude spinner.app"
        killall "claude spinner" 2>/dev/null || true
        echo "Launching app..."
        open "/Applications/claude spinner.app"
    else
        echo "Error: /Applications/claude spinner.app not found. Please install the app bundle first."
        exit 1
    fi
fi
