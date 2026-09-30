#!/bin/bash
set -euo pipefail
task_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$task_root/.build/desktop-fixtures"
mkdir -p "$fixture_dir"
swiftc -parse-as-library "$task_root/Tests/Fixtures/WindowFixture.swift" -o "$fixture_dir/WindowFixture" -framework AppKit
for side in left right; do
  if [[ "$side" == left ]]; then label="Workbench Test Left"; else label="Workbench Test Right"; fi
  bundle="$fixture_dir/$label.app"
  mkdir -p "$bundle/Contents/MacOS"
  cp "$fixture_dir/WindowFixture" "$bundle/Contents/MacOS/WindowFixture"
  cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$label</string>
<key>CFBundleIdentifier</key><string>local.desktop-workbench.test.$side</string>
<key>CFBundleExecutable</key><string>WindowFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
  codesign --force --sign - "$bundle"
done
printf 'Test fixtures: %s\n' "$fixture_dir"
