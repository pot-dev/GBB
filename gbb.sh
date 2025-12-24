#!/bin/bash

# 设置错误时退出
set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_DIR="$(pwd)"

# Match gbb.bat naming and behavior
DIST_NAME=".output_html"
TEMP_DIR=".temp_source"
CACHE_NM=".temp_nm_cache"
PRODUCT_DIR="output"
INPUT_FILE="$1"

# 检查输入参数
if [ -z "$INPUT_FILE" ]; then
    echo "[ERROR] Please provide the zip file path as an argument."
    echo "Usage: ./gbb.sh path/to/gemini_export.zip"
    exit 1
fi

echo "[1/9] Cleaning workspace..."

# 缓存 node_modules（如果有）
if [ -d "$TEMP_DIR/node_modules" ]; then
    echo "...Caching existing dependencies..."
    rm -rf "$CACHE_NM" || true
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
if [ -f "$SCRIPT_DIR/template/tailwind.config.js" ]; then
    echo "...Copying provided tailwind.config.js into project..."
    cp -f "$SCRIPT_DIR/template/tailwind.config.js" "tailwind.config.js"
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
else
    echo "[WARN] No index.html found in the unzipped package."
fi

echo "[5/9] Verifying HTML integrity..."
if [ -f "$HTML_FILE" ]; then
    if grep -q "cdn.tailwindcss.com" "$HTML_FILE"; then
        echo ">>> WARNING: Tailwind CDN link found! Cleanup might be incomplete."
    fi
    if ! grep -q "tailwind_entry.css" "$HTML_FILE"; then
        echo ">>> WARNING: Local CSS link was NOT injected."
    fi
fi

echo "[6/9] Installing/Checking dependencies..."
npm install react react-dom tailwindcss@3 postcss autoprefixer --silent --no-audit || true

echo "[7/9] Building with Parcel..."
npx parcel build index.html --dist-dir "../$DIST_NAME" --public-url ./ --no-source-maps

cd ..

echo "[8/9] Injecting Info Header..."
DIST_INDEX="$DIST_NAME/index.html"

if [ -f "$DIST_INDEX" ]; then
    META_NAME="GBB Exported Page"
    META_DESC=""

    if [ -f "$TEMP_DIR/metadata.json" ]; then
        found_name=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TEMP_DIR/metadata.json") || true
        if [ -n "$found_name" ]; then META_NAME="$found_name"; fi
        found_desc=$(sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TEMP_DIR/metadata.json") || true
        if [ -n "$found_desc" ]; then META_DESC="$found_desc"; fi
    fi

    # 读取 header 模板
    HEADER_CONTENT=""
    if [ -f "$SCRIPT_DIR/template/header" ]; then
        HEADER_CONTENT=$(cat "$SCRIPT_DIR/template/header")
        HEADER_CONTENT="${HEADER_CONTENT//\{\{NAME\}\}/$META_NAME}"
        HEADER_CONTENT="${HEADER_CONTENT//\{\{DES\}\}/$META_DESC}"
        # write temporary header file to be consistent with .bat behavior
        echo "$HEADER_CONTENT" > "$DIST_NAME/_gbb_header.tmp"
    fi

    # Prepend header if file does not already start with a comment
    if ! head -n 1 "$DIST_INDEX" | grep -q "^\s*<!--"; then
        if [ -f "$DIST_NAME/_gbb_header.tmp" ]; then
            cat "$DIST_NAME/_gbb_header.tmp" "$DIST_INDEX" > "${DIST_INDEX}.tmp" && mv "${DIST_INDEX}.tmp" "$DIST_INDEX"
            rm -f "$DIST_NAME/_gbb_header.tmp"
        fi
    fi
fi

echo "[9/9] Creating product ZIP as in gbb.bat..."
# use source zip name as product name
source_name="$(basename "$INPUT_FILE")"
source_name="${source_name%.*}"
name="${source_name/_gbb/}"

EXE_DIR="$PRODUCT_DIR/$name"
ZIP_ARCHIVE="$EXE_DIR/gbb_html.pot.zip"

mkdir -p "$EXE_DIR"

# create zip archive of the output folder (match .bat behavior: contents zipped)
rm -f "$ZIP_ARCHIVE" || true
if command -v zip >/dev/null 2>&1; then
    (cd "$DIST_NAME" && zip -r -q "$PWD/../$ZIP_ARCHIVE" ./*) || true
else
    # fallback: use python to create archive
    python3 - <<PY
import shutil
shutil.make_archive(r"$EXE_DIR/gbb_html.pot","zip",r"$DIST_NAME")
PY
fi

echo "[10/9] Packaging it as a Executable (Electron)..."
APP_DIR="$TEMP_DIR/app"

if [ -d "$APP_DIR" ]; then rm -rf "$APP_DIR"; fi
mkdir -p "$APP_DIR"

echo "...Copying built web files into packaging workspace ($APP_DIR)..."
cp -r "$DIST_NAME"/. "$APP_DIR"/ || true

echo "...Writing Electron entry files (main.js, package.json) if template exists..."
if [ -f "$SCRIPT_DIR/template/main.js" ]; then
    cp -f "$SCRIPT_DIR/template/main.js" "$APP_DIR/main.js"
fi

cat > "$APP_DIR/package.json" <<EOF
{
  "name": "gbb-electron-app",
  "version": "1.0.0",
  "main": "main.js",
  "scripts": { "start": "electron ." }
}
EOF

echo "...Installing dependencies in the packaging workspace (this may take a minute)..."
cd "$APP_DIR"
npm install --save-dev electron electron-builder --no-audit --silent || echo "npm install (electron) failed or was skipped"

echo "...Running electron-builder to produce a Windows app (if available)..."
# build for current os only (mac/linux)
# identify os
OS_TYPE="$(uname | tr '[:upper:]' '[:lower:]')"
if [ "$OS_TYPE" == "darwin" ]; then
    TARGET_OS="mac"
elif [ "$OS_TYPE" == "linux" ]; then
    TARGET_OS="linux"
else
    TARGET_OS="win"
fi
npx electron-builder --$TARGET_OS --publish never || echo "electron-builder failed or was skipped"
cd ..

echo "...Packaging succeeded (if electron-builder ran). Copying builder output into product dir..."
if [ -d "$APP_DIR/dist" ]; then
    cp -r "$APP_DIR/dist" "$EXE_DIR/" || true
fi

echo "Done. Output folder: $DIST_NAME  Product folder: $EXE_DIR  Zip: $ZIP_ARCHIVE"