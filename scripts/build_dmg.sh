#!/bin/bash
# FloatSwitch dmg パッケージ作成スクリプト
# 使い方: ./scripts/build_dmg.sh
#
# 前提: brew install create-dmg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
XCODE_PROJECT="$PROJECT_DIR/FloatSwitch/FloatSwitch.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="FloatSwitch"
DMG_DIR="$BUILD_DIR/dmg"

# バージョン取得（Info.plist から）
VERSION=$(xcodebuild -project "$XCODE_PROJECT" -scheme "$APP_NAME" -showBuildSettings 2>/dev/null \
    | grep "MARKETING_VERSION" | head -1 | awk '{print $3}')
VERSION="${VERSION:-1.0.0}"

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_OUTPUT="$BUILD_DIR/$DMG_NAME"

echo "=== FloatSwitch DMG Builder ==="
echo "Version: $VERSION"
echo ""

# 1. クリーンビルド
echo "[1/4] Release ビルド中..."
xcodebuild -project "$XCODE_PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -arch arm64 -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    clean build 2>&1 | tail -5

# ビルド成果物のパスを取得
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "エラー: $APP_NAME.app が見つかりません"
    exit 1
fi

echo "  ビルド完了: $APP_PATH"

# 2. DMG 用ステージングディレクトリ
echo "[2/4] ステージング..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"

# 3. DMG 作成
echo "[3/4] DMG 作成中..."
rm -f "$DMG_OUTPUT"

if command -v create-dmg &>/dev/null; then
    # create-dmg がある場合: 見栄えの良い DMG を作成
    # create-dmg はアンマウント失敗時に exit 1 を返すが DMG 自体は作れている場合がある
    # --no-internet-enable で余計なネットワーク処理を省く
    create-dmg \
        --volname "$APP_NAME" \
        --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 190 \
        --icon "Applications" 450 190 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 450 190 \
        --no-internet-enable \
        "$DMG_OUTPUT" \
        "$DMG_DIR"
    CREATE_DMG_EXIT=$?

    # アンマウント失敗で残った場合に強制デタッチ
    if [ $CREATE_DMG_EXIT -ne 0 ]; then
        echo "  create-dmg が非ゼロで終了 (code=$CREATE_DMG_EXIT)、マウント残りをクリーンアップ..."
        sleep 2
        hdiutil info 2>/dev/null | grep -B5 "$APP_NAME" | grep "^/dev" | awk '{print $1}' | while read dev; do
            hdiutil detach "$dev" -force 2>/dev/null || true
        done
        # 中間ファイル (rw.*.dmg) から最終 DMG を作り直す
        RW_DMG=$(find "$BUILD_DIR" -name "rw.*.$DMG_NAME" -type f 2>/dev/null | head -1)
        if [ -n "$RW_DMG" ] && [ ! -f "$DMG_OUTPUT" ]; then
            echo "  中間 DMG から最終 DMG を変換中..."
            hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_OUTPUT" -ov
            rm -f "$RW_DMG"
        fi
    fi
else
    # create-dmg がない場合: hdiutil で基本的な DMG を作成
    echo "  (create-dmg が未インストールのため hdiutil を使用)"
    echo "  見栄えの良い DMG にするには: brew install create-dmg"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_DIR" \
        -ov \
        -format UDZO \
        "$DMG_OUTPUT"
fi

# 4. 完了
echo "[4/4] クリーンアップ..."
rm -rf "$DMG_DIR"

if [ -f "$DMG_OUTPUT" ]; then
    DMG_SIZE=$(du -h "$DMG_OUTPUT" | awk '{print $1}')
    echo ""
    echo "=== 完了 ==="
    echo "DMG: $DMG_OUTPUT"
    echo "サイズ: $DMG_SIZE"
    echo ""
    echo "※ このビルドは署名されていません。"
    echo "  配布時は Developer ID での署名・公証が必要です。"
else
    echo "エラー: DMG の作成に失敗しました"
    exit 1
fi
