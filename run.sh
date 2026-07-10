#!/bin/bash
echo "Building Claude Spinner..."
xcodebuild -scheme "claude spinner" build | xcbeautify
killall "claude spinner" 2>/dev/null
echo "Launching app..."
open "/Users/home/Library/Developer/Xcode/DerivedData/claude_spinner-hbrhhtxpzvnhjnfsmxizfybdsven/Build/Products/Debug/claude spinner.app"
