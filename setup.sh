#!/bin/bash
set -e

echo "🚀 DigBar 프로젝트 설정 시작..."

# Check Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode를 먼저 설치해주세요: https://developer.apple.com/xcode/"
    exit 1
fi

# Install xcodegen if needed
if ! command -v xcodegen &> /dev/null; then
    echo "📦 xcodegen 설치 중..."
    if command -v brew &> /dev/null; then
        brew install xcodegen
    else
        echo "❌ Homebrew가 필요합니다: https://brew.sh"
        exit 1
    fi
fi

echo "🔨 Xcode 프로젝트 생성 중..."
xcodegen generate

echo "✅ 완료! DigBar.xcodeproj 파일을 Xcode로 열어주세요."
echo ""
echo "다음 단계:"
echo "  1. open DigBar.xcodeproj"
echo "  2. Signing & Capabilities에서 Team 선택"
echo "  3. ⌘R 로 빌드 및 실행"
