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

echo [1/9] Cleaning workspace...

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

echo [2/9] Unzipping...
:: 使用 -Force 覆盖可能存在的冲突
powershell -Command "Expand-Archive -Path '%~1' -DestinationPath '%TEMP_DIR%' -Force"

cd "%TEMP_DIR%"

echo [3/9] Configuring Tailwind v3...
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

echo [4/9] Processing HTML...
set "PS_CMD=$h=Get-Content 'index.html' -Raw -Encoding UTF8;"
set "PS_CMD=!PS_CMD! $h=$h -replace '<script\s+src=\".*cdn.tailwindcss.com.*\"></script>','';"
set "PS_CMD=!PS_CMD! $h=$h -replace '<link\s+.*href=\".*index.css\".*>','';"
set "PS_CMD=!PS_CMD! $h=$h -replace '</head>','<link rel=\"stylesheet\" href=\"./tailwind_entry.css\"></head>';"
set "PS_CMD=!PS_CMD! $h=$h -replace 'src=\"/','src=\"./';"
set "PS_CMD=!PS_CMD! $h=$h -replace 'href=\"/','href=\"./';"
set "PS_CMD=!PS_CMD! if(!(Test-Path 'index.tsx') -and (Test-Path 'src/index.tsx')){$h=$h.Replace('src=\"./index.tsx\"','src=\"./src/index.tsx\"')};"
set "PS_CMD=!PS_CMD! Set-Content 'index.html' $h -Encoding UTF8;"
powershell -Command "!PS_CMD!"

echo [5/9] Verifying HTML integrity...
:: --- 新增检查步骤 ---
powershell -Command "$c = Get-Content 'index.html' -Raw; if ($c -match 'cdn.tailwindcss.com') { Write-Warning '>>> WARNING: Tailwind CDN link found! Cleanup might be incomplete.' }; if ($c -notmatch 'tailwind_entry.css') { Write-Warning '>>> WARNING: Local CSS link was NOT injected.' }"

echo [6/9] Installing/Checking dependencies...
:: 因为保留了 node_modules，这一步通常是秒过
call npm install react react-dom tailwindcss@3 postcss autoprefixer --silent --no-audit

echo [7/9] Building with Parcel...
call npx parcel build index.html --dist-dir ../%DIST_NAME% --public-url ./ --no-source-maps

cd ..
echo [8/9] Injecting Info Header...
if exist "%DIST_NAME%\index.html" (
    rem generate header from template file `%~dp0header`, replace placeholders from metadata.json in %TEMP_DIR%
    powershell -Command "if(Test-Path '%TEMP_DIR%\metadata.json'){ $m=Get-Content -Path '%TEMP_DIR%\metadata.json' -Raw | ConvertFrom-Json; $n=$m.name; $d=$m.description } else { $n='Parametric 3D Tomato'; $d=''; }; $tpl = Get-Content -Path '%~dp0header' -Raw -Encoding UTF8; $tpl = $tpl -replace '\{\{NAME\}\}',$n; $tpl = $tpl -replace '\{\{DES\}\}',$d; Set-Content -Path '%DIST_NAME%\_gbb_header.tmp' -Value $tpl -Encoding UTF8"
    powershell -Command "$c = Get-Content -Path '%DIST_NAME%\index.html' -Raw -Encoding UTF8; if($c -notmatch '^[\s\r\n]*<!--') { $h = Get-Content -Path '%DIST_NAME%\_gbb_header.tmp' -Raw -Encoding UTF8; Set-Content -Path '%DIST_NAME%\index.html' -Value ($h + $c) -Encoding UTF8 }"
    if exist "%DIST_NAME%\_gbb_header.tmp" del "%DIST_NAME%\_gbb_header.tmp"
    powershell -Command "$p='%DIST_NAME%\index.html'; $c=Get-Content $p -Raw; $c=$c.Trim([char]65279); $e=New-Object System.Text.UTF8Encoding $false; [System.IO.File]::WriteAllText($p, $c, $e)"
)

echo [9/9] Creating zip archive of the output folder...
powershell -Command "if(Test-Path '%DIST_NAME%\%DIST_NAME%.zip'){Remove-Item '%DIST_NAME%\%DIST_NAME%.zip' -Force}; Compress-Archive -Path '%DIST_NAME%\*' -DestinationPath '%DIST_NAME%\GBB_PRODUCT.zip' -Force"

echo [DONE] Output folder: %DIST_NAME%
start %DIST_NAME%
:: 移除 pause，脚本将自动退出