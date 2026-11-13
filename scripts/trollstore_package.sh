#!/usr/bin/env bash
# TrollStore 打包脚本：把编译出的 DYYY.dylib 注入应用包，重签名后直接安装。
# 用法:
#   ./scripts/trollstore_package.sh <应用.ipa> <dylib路径> [输出.ipa]
# 依赖（macOS）: optool (brew install optool 或源码编译)、ldid (brew install ldid)
# 依赖（Linux/CI）: optool、ldid 可执行文件在 PATH
set -euo pipefail

SRC_IPA="${1:?用法: $0 <应用.ipa> <dylib> [输出.ipa]}"
DYLIB="${2:?缺少 dylib 路径}"
OUT_IPA="${3:-$(basename "${SRC_IPA%.ipa")}_DYYY.ipa}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v optool >/dev/null || { echo "缺少 optool: brew install optool"; exit 1; }
command -v ldid   >/dev/null || { echo "缺少 ldid:   brew install ldid";   exit 1; }

echo "[1/5] 解压 IPA"
unzip -q "$SRC_IPA" -d "$WORK"

APP_DIR="$(find "$WORK/Payload" -maxdepth 1 -name "*.app" | head -1)"
[ -n "$APP_DIR" ] || { echo "未找到 .app"; exit 1; }
EXEC_NAME="$(plutil -extract CFBundleExecutable raw "$APP_DIR/Info.plist")"
EXEC_PATH="$APP_DIR/$EXEC_NAME"
echo "[2/5] 主可执行: $EXEC_NAME ($(basename "$APP_DIR"))"

echo "[3/5] 注入 dylib 到 Frameworks/"
cp "$DYLIB" "$APP_DIR/Frameworks/DYYY.dylib"
optool install -c load -p "@executable_path/Frameworks/DYYY.dylib" -t "$EXEC_PATH" >/dev/null

echo "[4/5] 重签名（ad-hoc，TrollStore 安装要求无 AMFI 限制签名）"
ENT="$WORK/ent.plist"
cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>platform-application</key><true/>
    <key>com.apple.private.skip-library-validation</key><true/>
    <key>com.apple.security.get-task-allow</key><true/>
</dict>
</plist>
PLIST
# 先签内层（framework/dylib），再签主程序与 app 本体
find "$APP_DIR/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 |
  while IFS= read -r -d '' item; do ldid -S "$item" 2>/dev/null || ldid -S"$ENT" "$item"; done
for f in "$APP_DIR"/*.dylib; do [ -e "$f" ] && ldid -S "$f"; done
if [ -d "$APP_DIR/Frameworks" ]; then
  find "$APP_DIR/Frameworks" -type f -perm +111 -exec ldid -S {} + 2>/dev/null || true
fi
ldid -S"$ENT" "$EXEC_PATH"
ldid -S "$APP_DIR" 2>/dev/null || true
# 扩展（appex）逐个重签
find "$APP_DIR/PlugIns" -name "*.appex" -print0 2>/dev/null |
  while IFS= read -r -d '' appex; do
    exe="$(plutil -extract CFBundleExecutable raw "$appex/Info.plist" 2>/dev/null || true)"
    [ -n "$exe" ] && ldid -S "$appex/$exe" || true
  done

echo "[5/5] 打包输出 $OUT_IPA"
OUT_ABS="$(cd "$(dirname "$OUT_IPA")" && pwd)/$(basename "$OUT_IPA")"
( cd "$WORK" && zip -q -r -X "$OUT_ABS" Payload )
echo "完成: $OUT_ABS —— TrollStore 直接安装即可"
