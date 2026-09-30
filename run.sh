#!/bin/bash
set -euo pipefail

echo "Building Claude Spinner..."

beautify() {
    if command -v xcbeautify >/dev/null; then
        xcbeautify
    else
        cat
    fi
}

# Check if xcodebuild is functional (requires full Xcode, not just CommandLineTools)
if xcodebuild -version &>/dev/null; then
    echo "Using xcodebuild..."
    xcodebuild -scheme "claude spinner" build | beautify
    # Derive the built .app path from build settings so it survives the
    # DerivedData hash changing (it's keyed on the project path, not fixed).
    app=$(xcodebuild -scheme "claude spinner" -configuration Debug -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')
    if [ -z "$app" ] || [ "$app" = "/" ]; then
        echo "error: could not resolve BUILT_PRODUCTS_DIR / FULL_PRODUCT_NAME" >&2
        exit 1
    fi
    # Checked before the rm below: a path the build never produced would
    # otherwise delete the installed copy and leave nothing in its place.
    if [ ! -d "$app" ]; then
        echo "error: $app was not built" >&2
        exit 1
    fi
    killall "claude spinner" 2>/dev/null || true
    # Install over /Applications too: a login item relaunches that copy, and
    # when only DerivedData was updated it ran a two-week-old build (2026-09-29).
    echo "Installing to /Applications/claude spinner.app..."
    # Copy beside it first: a ditto that fails (disk full, permissions) then
    # stops set -e before the old copy is removed.
    rm -rf "/Applications/claude spinner.app.new"
    ditto "$app" "/Applications/claude spinner.app.new"
    rm -rf "/Applications/claude spinner.app"
    mv "/Applications/claude spinner.app.new" "/Applications/claude spinner.app"
    echo "Launching /Applications/claude spinner.app..."
    open "/Applications/claude spinner.app"
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
