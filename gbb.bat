@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "DIST_NAME=output_html"
set "TEMP_DIR=.temp_source"
set "CACHE_NM=.temp_nm_cache"

if "%~1" == "" (
    echo [ERROR] Drag and drop your zip file here. 你应该将Gemini的压缩包用此bat打开，而不是直接启动脚本。
    pause
    exit /b
)

echo [1/7] Cleaning workspace...

if exist "%TEMP_DIR%\node_modules" (
    echo ...Caching existing dependencies...
    move "%TEMP_DIR%\node_modules" "%CACHE_NM%" >nul
)

if exist "%TEMP_DIR%" rd /s /q "%TEMP_DIR%"
if exist "%DIST_NAME%" rd /s /q "%DIST_NAME%"

md "%TEMP_DIR%"
if exist "%CACHE_NM%" (
    echo ...Restoring dependencies...
    move "%CACHE_NM%" "%TEMP_DIR%\node_modules" >nul
)

echo [2/7] Unzipping...
:: 使用 -Force 覆盖可能存在的冲突
powershell -Command "Expand-Archive -Path '%~1' -DestinationPath '%TEMP_DIR%' -Force"

cd "%TEMP_DIR%"

echo [3/7] Configuring Tailwind v3...
if exist "%~dp0tailwind.config.js" (
    echo ...Copying provided tailwind.config.js into project...
    copy /Y "%~dp0tailwind.config.js" "tailwind.config.js" >nul
) else (
    echo ...No local tailwind.config.js found; generating default...
    (
    echo module.exports = {
    echo   content: ["./src/*.{js,jsx,ts,tsx}", "./*.html"],
    echo   theme: { extend: {} },
    echo   plugins: [],
    echo }
    ) > tailwind.config.js
)

(
echo {
echo   "plugins": {
echo     "tailwindcss": {}
echo   }
echo }
) > .postcssrc

(
echo @tailwind base;
echo @tailwind components;
echo @tailwind utilities;
) > tailwind_entry.css

echo [4/7] Processing HTML...
set "PS_CMD=$h=Get-Content 'index.html' -Raw -Encoding UTF8;"
set "PS_CMD=!PS_CMD! $h=$h -replace '<script\s+src=\".*cdn.tailwindcss.com.*\"></script>','';"
set "PS_CMD=!PS_CMD! $h=$h -replace '<link\s+.*href=\".*index.css\".*>','';"
set "PS_CMD=!PS_CMD! $h=$h -replace '</head>','<link rel=\"stylesheet\" href=\"./tailwind_entry.css\"></head>';"
set "PS_CMD=!PS_CMD! $h=$h -replace 'src=\"/','src=\"./';"
set "PS_CMD=!PS_CMD! $h=$h -replace 'href=\"/','href=\"./';"
set "PS_CMD=!PS_CMD! if(!(Test-Path 'index.tsx') -and (Test-Path 'src/index.tsx')){$h=$h.Replace('src=\"./index.tsx\"','src=\"./src/index.tsx\"')};"
set "PS_CMD=!PS_CMD! Set-Content 'index.html' $h -Encoding UTF8;"
powershell -Command "!PS_CMD!"

echo [5/7] Verifying HTML integrity...
:: --- 新增检查步骤 ---
powershell -Command "$c = Get-Content 'index.html' -Raw; if ($c -match 'cdn.tailwindcss.com') { Write-Warning '>>> WARNING: Tailwind CDN link found! Cleanup might be incomplete.' }; if ($c -notmatch 'tailwind_entry.css') { Write-Warning '>>> WARNING: Local CSS link was NOT injected.' }"

echo [6/7] Installing/Checking dependencies...
:: 因为保留了 node_modules，这一步通常是秒过
call npm install react react-dom tailwindcss@3 postcss autoprefixer --silent --no-audit

echo [7/7] Building with Parcel...
call npx parcel build index.html --dist-dir ../%DIST_NAME% --public-url ./ --no-source-maps

cd ..
echo [DONE] Output folder: %DIST_NAME%
start %DIST_NAME%
:: 移除 pause，脚本将自动退出