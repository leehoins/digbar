#!/bin/bash
# DigBar 릴리즈 스크립트
# 사용법: ./scripts/release.sh 1.1.0
set -e

VERSION=$1
if [ -z "$VERSION" ]; then
    echo "사용법: $0 <버전> (예: $0 1.1.0)"
    exit 1
fi

BUILD_NUM=$(date +%Y%m%d%H%M)
ARCHIVE_PATH="build/DigBar.xcarchive"
EXPORT_PATH="build/export"
ZIP_PATH="build/DigBar.zip"

echo "▶ 버전 $VERSION (build $BUILD_NUM) 릴리즈 빌드 시작..."

# Info.plist 버전 업데이트
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" Info.plist

# 아카이브 빌드
xcodebuild archive \
    -project DigBar.xcodeproj \
    -scheme DigBar \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# .app 추출 및 zip
APP_PATH=$(find "$ARCHIVE_PATH/Products" -name "DigBar.app" | head -1)
mkdir -p build/export
cp -R "$APP_PATH" "$EXPORT_PATH/DigBar.app"
cd build/export && zip -r "../DigBar.zip" DigBar.app && cd ../..

echo "✅ 빌드 완료: $ZIP_PATH"
echo ""
echo "다음 단계:"
echo "  1. Sparkle generate_appcast 로 서명 생성:"
echo "     ~/.sparkle/bin/generate_appcast build/ --ed-key-file ~/.sparkle/sparkle_private_key"
echo "  2. appcast.xml GitHub에 push"
echo "  3. build/DigBar.zip GitHub Releases에 v$VERSION 태그로 업로드"
