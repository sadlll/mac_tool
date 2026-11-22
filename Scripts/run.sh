#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> 生成 Xcode 工程..."
xcodegen generate

echo "==> 编译 mac_tool..."
xcodebuild \
  -project mac_tool.xcodeproj \
  -scheme mac_tool \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build

APP_PATH="$ROOT_DIR/DerivedData/Build/Products/Debug/mac_tool.app"

echo "==> 结束旧进程并启动新编译版本..."
pkill -x mac_tool || true
open -n "$APP_PATH"
