#!/bin/bash
# Build a Developer ID signed, notarized and stapled copy of the app into
# build/notarized/. Needs the "Developer ID Application" certificate in the login
# keychain and a notarytool profile (default "notary"; override with
# NOTARY_PROFILE), created once with `xcrun notarytool store-credentials`.
set -euo pipefail
cd "$(dirname "$0")"

team=877MLS29T9
profile="${NOTARY_PROFILE:-notary}"
out=build/notarized
archive="$out/claude spinner.xcarchive"
app="$out/claude spinner.app"
zip="$out/claude spinner.zip"

beautify() {
    if command -v xcbeautify >/dev/null; then xcbeautify; else cat; fi
}

rm -rf "$out"
mkdir -p "$out"

echo "Archiving (Release)..."
xcodebuild -scheme "claude spinner" -configuration Release \
    -archivePath "$archive" archive | beautify

cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$team</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF

echo "Exporting with Developer ID..."
xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist "$out/ExportOptions.plist" -exportPath "$out" | beautify

# notarytool takes a zip, and ditto keeps the bundle's symlinks and xattrs intact.
ditto -c -k --keepParent "$app" "$zip"

echo "Submitting to the notary service (waits for the verdict)..."
# --wait exits 0 on an Invalid verdict too, so the status line is what decides.
# A failed submit (bad profile, dropped connection) still prints its output, so
# the submission id survives for `notarytool info`.
rc=0
result=$(xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait) || rc=$?
echo "$result"
if [ "$rc" -ne 0 ] || ! grep -q '^ *status: Accepted' <<<"$result"; then
    id=$(awk '/^ *id:/{print $2; exit}' <<<"$result")
    echo "error: notarization not accepted (notarytool exit $rc)" >&2
    if [ -n "$id" ]; then
        xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || true
    else
        echo "error: no submission id in the output above" >&2
    fi
    exit 1
fi

xcrun stapler staple "$app"
# Re-zip so the shareable archive carries the stapled ticket.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

echo "Gatekeeper's view:"
spctl --assess --type execute -vv "$app"
xcrun stapler validate "$app"
echo "Done: $app"
