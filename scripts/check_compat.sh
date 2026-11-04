#!/usr/bin/env bash
# 抖音版本兼容性预检：把仓库全部 %hook 目标类在砸壳 AwemeCore 二进制里过一遍，
# 输出缺失清单。换新抖音版本先跑这个，再决定改哪里。
# 用法: ./scripts/check_compat.sh <AwemeCore路径>
#   AwemeCore 从砸壳 IPA 里解出：unzip -j 抖音.ipa "Payload/*.app/Frameworks/AwemeCore.framework/AwemeCore"
set -euo pipefail

BIN="${1:?用法: $0 <AwemeCore 二进制路径>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$BIN" ] || { echo "文件不存在: $BIN"; exit 1; }

echo "== 提取 hook 目标类 =="
grep -hoE '^%hook [A-Za-z0-9_.]+' "$REPO"/*.xm | sed 's/^%hook //' | sort -u > /tmp/dyyy_hooks_all.txt
TOTAL=$(wc -l < /tmp/dyyy_hooks_all.txt)
echo "共 $TOTAL 个 hook 目标"

echo "== 存在性扫描（点号名与 mangled 名都算） =="
MISSING=0
> /tmp/dyyy_missing.txt
while read -r c; do
  # Logos 占位别名（Group 动态绑定）跳过
  [ "$c" = "HOOK_TARGET_OWNER_CLASS" ] && continue
  if grep -aqF "$c" "$BIN"; then
    continue
  fi
  # 下划线别名：查点号形式与基础类名（mangled 名含基础类名子串）
  FOUND=0
  case "$c" in
    *_*)
      base="${c##*_}"
      grep -aqF "$base" "$BIN" && FOUND=1
      grep -aqF "${c//_/.}" "$BIN" && FOUND=1
      ;;
  esac
  if [ "$FOUND" -eq 0 ]; then
    echo "$c" >> /tmp/dyyy_missing.txt
    MISSING=$((MISSING+1))
  fi
done < /tmp/dyyy_hooks_all.txt

echo
if [ "$MISSING" -eq 0 ]; then
  echo "✅ 全部 hook 目标在该抖音版本存在"
else
  echo "⚠️  缺失 $MISSING 个（旧版占位别名可能误报，人工核对）："
  cat /tmp/dyyy_missing.txt
fi
