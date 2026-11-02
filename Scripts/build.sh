#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo '需要 XcodeGen：请先安装 https://github.com/yonaskolb/XcodeGen' >&2
  exit 1
fi
xcodegen generate
xcodebuild -project Selecta.xcodeproj -scheme Selecta -configuration Release \
  -derivedDataPath "$project_dir/.build/DerivedData" build
mkdir -p build
ditto .build/DerivedData/Build/Products/Release/Selecta.app build/Selecta.app
codesign --verify --deep --strict build/Selecta.app
echo "应用已生成：$project_dir/build/Selecta.app"
