#!/bin/bash
# 不需要 Xcode，只用命令行工具（xcode-select --install）编译出 FloatPlan.app
#   ./build.sh            只编译本机架构（快）
#   ./build.sh universal  同时编译 Apple 芯片 + Intel（发布用）
set -euo pipefail
cd "$(dirname "$0")"

APP="build/FloatPlan.app"
BIN="$APP/Contents/MacOS/FloatPlan"
MIN_OS="13.0"

if [[ "${1:-}" == "universal" ]]; then
  ARCHS=(arm64 x86_64)
else
  ARCHS=("$(uname -m)")
fi

rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

SLICES=()
for arch in "${ARCHS[@]}"; do
  echo "→ 编译 $arch"
  swiftc -O -swift-version 5 \
    -target "${arch}-apple-macos${MIN_OS}" \
    -o "build/obj/FloatPlan-$arch" \
    Sources/*.swift
  SLICES+=("build/obj/FloatPlan-$arch")
done

if [[ ${#SLICES[@]} -gt 1 ]]; then
  lipo -create "${SLICES[@]}" -output "$BIN"
else
  cp "${SLICES[0]}" "$BIN"
fi

cp Info.plist "$APP/Contents/Info.plist"

# 本机签名（ad-hoc）。没有付费开发者账号时只能这样，用户首次打开需手动放行
codesign --force --sign - "$APP" >/dev/null

echo "✅ 编译完成：${APP}（$(lipo -archs "$BIN")）"
