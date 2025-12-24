#!/bin/bash

# 设置错误时退出
set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_DIR="$(pwd)"

DIST_NAME="output_html"
TEMP_DIR=".temp_source"
CACHE_NM=".temp_nm_cache"
INPUT_FILE="$1"

# 检查输入参数
if [ -z "$INPUT_FILE" ]; then
    echo "[ERROR] Please provide the zip file path as an argument."
    echo "Usage: ./build.sh path/to/gemini_export.zip"
    exit 1
fi

echo "[1/9] Cleaning workspace..."

# 缓存 node_modules
if [ -d "$TEMP_DIR/node_modules" ]; then
    echo "...Caching existing dependencies..."
    rm -rf "$CACHE_NM"
    mv "$TEMP_DIR/node_modules" "$CACHE_NM"
fi

# 清理目录
rm -rf "$TEMP_DIR"
rm -rf "$DIST_NAME"

mkdir -p "$TEMP_DIR"

# 恢复 node_modules
if [ -d "$CACHE_NM" ]; then
    echo "...Restoring dependencies..."
    mv "$CACHE_NM" "$TEMP_DIR/node_modules"
fi

echo "[2/9] Unzipping..."
unzip -o -q "$INPUT_FILE" -d "$TEMP_DIR"

cd "$TEMP_DIR"

echo "[3/9] Configuring Tailwind v3..."
if [ -f "$SCRIPT_DIR/tailwind.config.js" ]; then
    echo "...Copying provided tailwind.config.js into project..."
    cp -f "$SCRIPT_DIR/tailwind.config.js" "tailwind.config.js"
else
    echo "...No local tailwind.config.js found; generating default..."
    cat <<EOF > tailwind.config.js
module.exports = {
  content: ["./src/*.{js,jsx,ts,tsx}", "./*.html"],
  theme: { extend: {} },
  plugins: [],
}
EOF
fi

# 创建 .postcssrc
cat <<EOF > .postcssrc
{
  "plugins": {
    "tailwindcss": {}
  }
}
EOF

# 创建 tailwind_entry.css
cat <<EOF > tailwind_entry.css
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

echo "[4/9] Processing HTML..."

# 定义跨平台 sed 函数
safe_sed() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

HTML_FILE="index.html"

# HTML 处理
safe_sed 's|<script.*src=".*cdn.tailwindcss.com.*"></script>||g' "$HTML_FILE"
safe_sed 's|<link.*href=".*index.css".*>||g' "$HTML_FILE"
safe_sed 's|</head>|<link rel="stylesheet" href="./tailwind_entry.css"></head>|g' "$HTML_FILE"
safe_sed 's|src="/|src="./|g' "$HTML_FILE"
safe_sed 's|href="/|href="./|g' "$HTML_FILE"

if [ ! -f "index.tsx" ] && [ -f "src/index.tsx" ]; then
    safe_sed 's|src="./index.tsx"|src="./src/index.tsx"|g' "$HTML_FILE"
fi

echo "[5/9] Verifying HTML integrity..."
if grep -q "cdn.tailwindcss.com" "$HTML_FILE"; then
    echo ">>> WARNING: Tailwind CDN link found! Cleanup might be incomplete."
fi
if ! grep -q "tailwind_entry.css" "$HTML_FILE"; then
    echo ">>> WARNING: Local CSS link was NOT injected."
fi

echo "[6/9] Installing/Checking dependencies..."
# 依然需要 npm，但通常 npm 独立于 node 命令存在于 path 中
npm install react react-dom tailwindcss@3 postcss autoprefixer --silent --no-audit

echo "[7/9] Building with Parcel..."
npx parcel build index.html --dist-dir "../$DIST_NAME" --public-url ./ --no-source-maps

cd ..

echo "[8/9] Injecting Info Header..."
DIST_INDEX="$DIST_NAME/index.html"

if [ -f "$DIST_INDEX" ]; then
    META_NAME="Parametric 3D Tomato"
    META_DESC=""
    
    # === 修改处：使用 grep/sed 替代 node 解析 JSON ===
    if [ -f "$TEMP_DIR/metadata.json" ]; then
        # 提取 name (查找 "name": "Value" 模式)
        # 使用 sed 匹配双引号内的内容
        found_name=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TEMP_DIR/metadata.json")
        if [ -n "$found_name" ]; then META_NAME="$found_name"; fi

        # 提取 description
        found_desc=$(sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TEMP_DIR/metadata.json")
        if [ -n "$found_desc" ]; then META_DESC="$found_desc"; fi
    fi

    # 读取 header 模板
    HEADER_CONTENT=""
    if [ -f "$SCRIPT_DIR/header" ]; then
        # 读取文件内容到变量
        HEADER_CONTENT=$(cat "$SCRIPT_DIR/header")
        # === 修改处：使用 Bash 字符串替换替代 node/sed ===
        # 将 {{NAME}} 替换为 $META_NAME
        HEADER_CONTENT="${HEADER_CONTENT//\{\{NAME\}\}/$META_NAME}"
        # 将 {{DES}} 替换为 $META_DESC
        HEADER_CONTENT="${HEADER_CONTENT//\{\{DES\}\}/$META_DESC}"
    fi

    # 注入到文件头部
    if ! head -n 1 "$DIST_INDEX" | grep -q "^\s*<!--"; then
        echo "$HEADER_CONTENT" | cat - "$DIST_INDEX" > "${DIST_INDEX}.tmp" && mv "${DIST_INDEX}.tmp" "$DIST_INDEX"
    fi
fi

echo "[9/9] Creating zip archive of the output folder..."
ZIP_FILE="$DIST_NAME/GBB_PRODUCT.zip"
rm -f "$ZIP_FILE"
cd "$DIST_NAME"
zip -r -q "GBB_PRODUCT.zip" ./*
cd ..

echo "[DONE] Output folder: $DIST_NAME"