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
WIDGET_PATH="$APP_PATH/Contents/PlugIns/MacToolWidgets.appex"

echo "==> 结束旧进程并注册小组件扩展..."
pkill -x MacToolWidgets || true
pkill -x mac_tool || true
pluginkit -r "$WIDGET_PATH" >/dev/null 2>&1 || true
pluginkit -a "$WIDGET_PATH" >/dev/null 2>&1 || true

echo "==> 启动新编译版本..."
open -n "$APP_PATH"
