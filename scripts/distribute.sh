#!/bin/bash
set -euo pipefail

###############################################################################
#  WallpaperAutoUploadTool 打包分发脚本
#  Build + Sign + Notarize + DMG
#
#  用法:
#    ./scripts/distribute.sh              # 交互式，一键分发
#    ./scripts/distribute.sh --check-only # 只检查环境，不做构建
#    ./scripts/distribute.sh --setup      # 只打印环境指导
#
#  先决条件:
#    1. Apple Developer Program（$99/年） https://developer.apple.com/programs/
#    2. 开发者证书已安装到钥匙串（见下文指引）
#    3. App Store Connect API Key（推荐）或 Apple ID + 专用密码
#
#  首次使用流程:
#    ./scripts/distribute.sh --setup       # 只打印环境指导和检查项目配置
###############################################################################

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="WallpaperAutoUploadTool"
PROJECT="WallpaperAutoUploadTool.xcodeproj"
CONFIGURATION="Release"

BUNDLE_ID="com.boyyang.WallpaperAutoUploadTool"
ARCHIVE_PATH="$PROJECT_DIR/dist/WallpaperAutoUploadTool.xcarchive"
EXPORT_DIR="$PROJECT_DIR/dist/Export"
DMG_PATH="$PROJECT_DIR/dist/WallpaperAutoUploadTool.dmg"
APP_NAME="WallpaperAutoUploadTool.app"

# --------------- 颜色输出 ---------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
fatal() { error "$@"; exit 1; }

# ============================================================================
#  步骤 0：环境检查
# ============================================================================

check_environment() {
    echo ""
    info "=========== 环境检查 ==========="

    # 自动检测 Xcode
    if ! xcodebuild -version &>/dev/null; then
        for dir in /Applications/Xcode.app /Applications/Xcode-beta.app; do
            if [[ -x "$dir/Contents/Developer/usr/bin/xcodebuild" ]]; then
                export DEVELOPER_DIR="$dir/Contents/Developer"
                info "检测到 Xcode，自动设置 DEVELOPER_DIR=$DEVELOPER_DIR"
                break
            fi
        done
    fi

    if ! xcodebuild -version &>/dev/null; then
        fatal "xcodebuild 不可用，请安装 Xcode"
    fi
    XCODE_VER=$(xcodebuild -version | head -1)
    ok "Xcode: $XCODE_VER"

    if [[ ! -d "$PROJECT_DIR/$PROJECT" ]]; then
        fatal "项目文件 $PROJECT 未找到"
    fi
    ok "项目文件存在"

    # 签名证书
    IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" || true)
    if [[ -z "$IDENTITIES" ]]; then
        warn "未找到 Developer ID Application 证书"
        echo ""
        echo "  请先完成以下步骤:"
        echo "    1. 打开 https://developer.apple.com/account 登录并加入 Apple Developer Program"
        echo "    2. 在 Certificates 页面申请 'Developer ID Application' 证书"
        echo "    3. 下载并双击安装到钥匙串"
        echo "    4. 再次运行此脚本"
        echo ""
    else
        ok "Developer ID 证书已就绪"
        echo "$IDENTITIES" | while IFS= read -r line; do
            echo "       $(echo "$line" | sed 's/^[^"]*"//; s/"$//')"
        done
    fi

    # 项目签名配置检查
    echo ""
    info "项目签名配置 (pbxproj 中的 target buildSettings):"
    grep -E "(CODE_SIGN_STYLE|DEVELOPMENT_TEAM|ENABLE_APP_SANDBOX|ENABLE_HARDENED_RUNTIME) " "$PROJECT_DIR/$PROJECT/project.pbxproj" || true

    # 自动签名模式检查
    if grep -qE "CODE_SIGN_STYLE = Automatic" "$PROJECT_DIR/$PROJECT/project.pbxproj" 2>/dev/null; then
        ok "签名模式: Automatic (Xcode 自动管理证书)"
    fi

    # Hardened Runtime
    if grep -qE "ENABLE_HARDENED_RUNTIME = YES" "$PROJECT_DIR/$PROJECT/project.pbxproj" 2>/dev/null; then
        ok "Hardened Runtime 已启用 (公证要求)"
    else
        warn "Hardened Runtime 未启用 (公证要求必须启用)"
    fi

    # notarytool 检查
    if xcrun notarytool --version &>/dev/null; then
        ok "notarytool 可用"
    else
        warn "notarytool 不可用 (需要 Xcode 13+ 或 Command Line Tools)"
    fi

    # App Store Connect API Key 检查
    if [[ -f ~/private_keys/AuthKey_*.p8 ]] 2>/dev/null; then
        ok "App Store Connect API Key 已找到"
    fi
}

# ============================================================================
#  步骤 1：Clean + Archive
# ============================================================================

archive() {
    echo ""
    info "=========== 构建归档 ==========="

    rm -rf "$ARCHIVE_PATH"
    mkdir -p "$PROJECT_DIR/dist"

    info "正在编译 Release 版本..."
    if command -v xcbeautify &>/dev/null; then
        xcodebuild archive \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -archivePath "$ARCHIVE_PATH" \
            | xcbeautify
    else
        xcodebuild archive \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -archivePath "$ARCHIVE_PATH"
    fi

    if [[ ! -d "$ARCHIVE_PATH" ]]; then
        fatal "归档失败"
    fi
    ok "归档完成: $ARCHIVE_PATH"
}

# ============================================================================
#  步骤 2：导出（Developer ID 分发）
# ============================================================================

export_app() {
    echo ""
    info "=========== 导出 .app ==========="

    rm -rf "$EXPORT_DIR"
    mkdir -p "$EXPORT_DIR"

    EXPORT_OPTS="$EXPORT_DIR/exportOptions.plist"
    cat > "$EXPORT_OPTS" <<-PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

    info "正在导出 Developer ID 签名的 .app..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTS"

    if [[ ! -d "$EXPORT_DIR/$APP_NAME" ]]; then
        fatal "导出失败 — 请检查签名证书"
    fi
    ok "导出成功: $EXPORT_DIR/$APP_NAME"
}

# ============================================================================
#  步骤 3：验证签名
# ============================================================================

verify_signature() {
    echo ""
    info "=========== 验证签名 ==========="

    codesign --verify --deep --strict -v "$EXPORT_DIR/$APP_NAME" 2>&1 || \
        warn "签名验证发现问题（但可能不影响分发）"

    spctl --assess --verbose=4 "$EXPORT_DIR/$APP_NAME" 2>&1 || \
        warn "Gatekeeper 评估未通过（提交公证后会修复）"
}

# ============================================================================
#  步骤 4：公证（Notarization）
# ============================================================================

notarize() {
    echo ""
    info "=========== 提交公证 ==========="

    # 打包 .app 为 .zip（notarytool 要求）
    info "正在打包 .app 为 .zip..."
    ZIP_PATH="$EXPORT_DIR/WallpaperAutoUploadTool.zip"
    ditto -c -k --keepParent "$EXPORT_DIR/$APP_NAME" "$ZIP_PATH"

    # 尝试从 ~/private_keys 读取 App Store Connect API Key
    AUTH_KEY=$(ls ~/private_keys/AuthKey_*.p8 2>/dev/null | head -1 || true)

    if [[ -n "$AUTH_KEY" ]]; then
        KEY_ID=$(basename "$AUTH_KEY" | sed 's/AuthKey_//;s/\.p8//')
        info "使用 App Store Connect API Key: $KEY_ID"
        xcrun notarytool submit "$ZIP_PATH" \
            --key "$AUTH_KEY" \
            --key-id "$KEY_ID" \
            --issuer "$(security find-generic-password -a "$KEY_ID" -w 2>/dev/null || echo 'YOUR_ISSUER_ID')" \
            --wait \
            --timeout 10m \
            2>&1 | tee /dev/stderr | grep -E "status|id:" || true
    else
        warn "未找到 App Store Connect API Key"
        warn "请使用 Apple ID 方式进行公证:"
        echo ""
        echo "  xcrun notarytool submit \"$ZIP_PATH\" \\"
        echo "    --apple-id \"your@apple.id\" \\"
        echo "    --team-id \"52D2N3R5W8\" \\"
        echo "    --password \"@keychain:AC_PASSWORD\" \\"
        echo "    --wait"
        echo ""
        warn "请先创建 app-specific password: https://appleid.apple.com/account/manage"
        echo "然后添加到钥匙串: xcrun notarytool store-credentials WallpaperNotary --apple-id ... --team-id 52D2N3R5W8"

        # 如果已经存了凭证
        if xcrun notarytool history --keychain-profile "WallpaperNotary" &>/dev/null; then
            info "发现已保存的公证凭证 WallpaperNotary，正在提交..."
            xcrun notarytool submit "$ZIP_PATH" \
                --keychain-profile "WallpaperNotary" \
                --wait \
                --timeout 10m
        fi
    fi

    # 清理 zip
    rm -f "$ZIP_PATH"
}

# ============================================================================
#  步骤 5：钉票（Staple）
# ============================================================================

staple() {
    echo ""
    info "=========== 钉票 ==========="

    xcrun stapler staple "$EXPORT_DIR/$APP_NAME" && \
        ok "公证票据已钉入 .app" || \
        warn "钉票失败（可能公证尚未完成）"

    # 再次验证
    spctl --assess --verbose=4 "$EXPORT_DIR/$APP_NAME" 2>&1 | head -5
}

# ============================================================================
#  步骤 6：打包 DMG
# ============================================================================

make_dmg() {
    echo ""
    info "=========== 创建 DMG ==========="

    rm -f "$DMG_PATH"

    DMG_TMP=$(mktemp -d)
    cp -R "$EXPORT_DIR/$APP_NAME" "$DMG_TMP/"
    ln -s /Applications "$DMG_TMP/Applications"

    hdiutil create -volname "WallpaperAutoUploadTool" \
        -srcfolder "$DMG_TMP" \
        -ov -format UDZO \
        -imagekey zlib-level=9 \
        "$DMG_PATH"

    rm -rf "$DMG_TMP"

    if [[ -f "$DMG_PATH" ]]; then
        ok "DMG 创建成功: $DMG_PATH"
    else
        fatal "DMG 创建失败"
    fi
}

# ============================================================================
#  帮助信息
# ============================================================================

print_guide() {
    echo ""
    echo "==================== 分发指南 ===================="
    echo ""
    echo " 1. 加入 Apple Developer Program (\$99/年)"
    echo "    https://developer.apple.com/programs/"
    echo ""
    echo " 2. 申请 Developer ID Application 证书"
    echo "    developer.apple.com → Certificates → + → Developer ID Application"
    echo "    下载并双击安装到钥匙串"
    echo ""
    echo " 3. 创建 App Store Connect API Key（推荐，免密码交互）"
    echo "    appstoreconnect.apple.com → 用户和访问 → 密钥 → +"
    echo "    下载 .p8 文件放到 ~/private_keys/"
    echo ""
    echo "    或创建 app-specific password + 保存到钥匙串:"
    echo "    https://appleid.apple.com/account/manage → App-Specific Passwords"
    echo "    xcrun notarytool store-credentials WallpaperNotary \\"
    echo "      --apple-id \"your@email.com\" \\"
    echo "      --team-id \"52D2N3R5W8\""
    echo ""
    echo " 4. 运行完整分发流程:"
    echo "    ./scripts/distribute.sh"
    echo ""
    echo " 5. 分发产物"
    echo "    DMG: $DMG_PATH"
    echo "    或直接分发: $EXPORT_DIR/$APP_NAME (需要先 zip)"
    echo ""
    echo "======================================================"
}

# ============================================================================
#  Main
# ============================================================================

main() {
    echo ""
    echo "  ┌─────────────────────────────────────┐"
    echo "  │   WallpaperAutoUploadTool 打包脚本   │"
    echo "  └─────────────────────────────────────┘"
    echo ""

    case "${1:-}" in
        --check-only)
            check_environment
            exit 0
            ;;
        --setup)
            print_guide
            exit 0
            ;;
        --help|-h)
            echo "用法: $0 [--check-only|--setup|--help]"
            exit 0
            ;;
    esac

    check_environment
    archive
    export_app
    verify_signature

    echo ""
    warn "是否继续提交公证? (y/n)"
    echo "  公证需要联网，且首次使用可能需要配置 API Key 或 Apple ID"
    read -r CONTINUE
    if [[ "$CONTINUE" == "y" || "$CONTINUE" == "Y" ]]; then
        notarize
        staple
    else
        warn "跳过公证。签名的 .app 仍可在本地使用，但分发给其他 Mac 会触发 Gatekeeper 警告"
    fi

    make_dmg

    echo ""
    ok "============ 全部完成 ============"
    echo ""
    echo "  DMG:  $DMG_PATH"
    echo "  .app: $EXPORT_DIR/$APP_NAME"
    echo ""
    echo "  分发给用户后，他们只需:"
    echo "    1. 打开 DMG"
    echo "    2. 拖 WallpaperAutoUploadTool.app 到 Applications"
    echo "    3. 首次启动时在 系统设置 → 隐私与安全性 中允许运行"
    echo ""

    print_guide
}

main "$@"
