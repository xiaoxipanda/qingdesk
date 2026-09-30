#!/bin/bash
set -euo pipefail
task_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="$task_root/dist/轻桌.app"
swift build -c release --package-path "$task_root"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$task_root/.build/release/DesktopWorkbench" "$app_path/Contents/MacOS/DesktopWorkbench"
cp "$task_root/.build/release/workbench-mcp" "$app_path/Contents/MacOS/workbench-mcp"
cp "$task_root/assets/Info.plist" "$app_path/Contents/Info.plist"
swift "$task_root/scripts/make-icon.swift" "$task_root/.build/AppIcon.iconset" "$task_root/assets/QingDeskIcon.png"
iconutil -c icns "$task_root/.build/AppIcon.iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.desktop-workbench.mcp "$app_path/Contents/MacOS/workbench-mcp"
codesign --force --sign - --identifier local.desktop-workbench \
  --requirements '=designated => identifier "local.desktop-workbench"' "$app_path"
codesign --verify --deep --strict "$app_path"
python3 "$task_root/scripts/package-app.py" "$app_path" "$task_root/dist/QingDesk-macOS.zip"
printf 'Built: %s\n' "$app_path"
