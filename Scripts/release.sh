#!/usr/bin/env bash
set -euo pipefail

# 仅由 GitHub Actions 发布流水线调用，禁止本地手动发布。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${RELEASE_VERSION:?请设置 RELEASE_VERSION（如 0.1.0）}"
TAG="${RELEASE_TAG:-v${VERSION}}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
DERIVED_DATA="$ROOT_DIR/DerivedData"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> 生成 Xcode 工程..."
xcodegen generate

echo "==> 编译 Release 版本（v${VERSION} / build ${BUILD_NUMBER}）..."
xcodebuild \
  -project mac_tool.xcodeproj \
  -scheme mac_tool \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release/mac_tool.app"

echo "==> 校验应用和小组件的版本与架构..."
for BUNDLE_PATH in "$APP_PATH" "$APP_PATH/Contents/PlugIns/MacToolWidgets.appex"; do
  INFO_PLIST="$BUNDLE_PATH/Contents/Info.plist"
  BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
  BUNDLE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
  if [[ "$BUNDLE_VERSION" != "$VERSION" || "$BUNDLE_BUILD" != "$BUILD_NUMBER" ]]; then
    echo "错误：${BUNDLE_PATH##*/} 版本为 ${BUNDLE_VERSION} / ${BUNDLE_BUILD}，预期 ${VERSION} / ${BUILD_NUMBER}" >&2
    exit 1
  fi

  EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
  ARCHITECTURES="$(xcrun lipo -archs "$BUNDLE_PATH/Contents/MacOS/$EXECUTABLE")"
  if [[ "$ARCHITECTURES" != "arm64" ]]; then
    echo "错误：${BUNDLE_PATH##*/} 架构为 ${ARCHITECTURES}，预期 arm64" >&2
    exit 1
  fi
done

DMG_NAME="mac_tool-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGE_DIR="$DIST_DIR/dmg-stage"

mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> 打包 ${DMG_NAME}..."
hdiutil create \
  -volname "mac_tool ${VERSION}" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
rm -rf "$STAGE_DIR"

DMG_LENGTH="$(stat -f%z "$DMG_PATH")"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
DOWNLOAD_URL="https://github.com/sadlll/mac_tool/releases/download/${TAG}/${DMG_NAME}"

SIGN_UPDATE="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
ED_SIGNATURE=""

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "==> 使用 Sparkle EdDSA 签名安装包..."
  SIGN_OUTPUT="$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$DMG_PATH")"
  ED_SIGNATURE="$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  if [[ -z "$ED_SIGNATURE" ]]; then
    echo "错误：未能从 sign_update 输出中解析 sparkle:edSignature" >&2
    exit 1
  fi
elif [[ "${DRY_RUN:-false}" == "true" ]]; then
  echo "==> Dry-run 模式未提供 SPARKLE_PRIVATE_KEY，跳过 EdDSA 签名"
  ED_SIGNATURE="DRY_RUN_PLACEHOLDER"
else
  echo "错误：正式发布必须配置 GitHub Actions Secret SPARKLE_PRIVATE_KEY" >&2
  exit 1
fi

APPCAST_PATH="$DIST_DIR/appcast.xml"
cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>mac_tool Updates</title>
    <link>https://github.com/sadlll/mac_tool/releases</link>
    <description>mac_tool 稳定版更新频道</description>
    <language>zh-Hans</language>
    <item>
      <title>mac_tool ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${DMG_LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIGNATURE}" />
    </item>
  </channel>
</rss>
EOF

echo "==> 生成产物："
ls -lh "$DMG_PATH" "$APPCAST_PATH"
