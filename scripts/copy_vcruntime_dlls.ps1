# copy_vcruntime_dlls.ps1
#
# 用途：把 MSVC（VC++）运行库 DLL 复制到 Flutter Windows 构建产物目录，
#       实现微软支持的"应用本地部署（app-local deployment）"，
#       使发布包能在**未安装 VC++ Redistributable 的干净 Windows** 上直接运行
#       （否则会出现"找不到 MSVCP140.dll / VCRUNTIME140.dll"报错）。
#
# 何时需要：每次 `flutter build windows --release`（或 --debug）之后执行一次。
#           构建产物目录会被重新生成，运行库 DLL 需要重新复制。
#
# 用法：
#   pwsh scripts/copy_vcruntime_dlls.ps1
#   pwsh scripts/copy_vcruntime_dlls.ps1 -TargetDir "build\windows\x64\runner\Debug"

param(
    [string]$TargetDir = "build\windows\x64\runner\Release"
)

$ErrorActionPreference = "Stop"

# 解析目标目录（相对路径按脚本所在仓库根目录解析）
if (-not [System.IO.Path]::IsPathRooted($TargetDir)) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $TargetDir = Join-Path $repoRoot $TargetDir
}

if (-not (Test-Path $TargetDir)) {
    Write-Host "❌ 目标目录不存在: $TargetDir" -ForegroundColor Red
    Write-Host "   请先执行 flutter build windows --release" -ForegroundColor Yellow
    exit 1
}

# 搜索 Visual Studio 2019 / 2022 的 VC 运行库目录
$searchRoots = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022",
    "$env:ProgramFiles\Microsoft Visual Studio\2022"
) | Where-Object { Test-Path $_ }

$crtDirs = @()
foreach ($root in $searchRoots) {
    $crtDirs += Get-ChildItem $root -Recurse -Directory -Filter "Microsoft.VC14*.CRT" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\' }
}

if ($crtDirs.Count -eq 0) {
    Write-Host "❌ 未找到 Visual Studio 的 VC 运行库目录（Microsoft.VC14*.CRT）" -ForegroundColor Red
    Write-Host "   请确认已安装 Visual Studio 的「使用 C++ 的桌面开发」工作负载" -ForegroundColor Yellow
    exit 1
}

# 取版本号最新的一份（按父目录名排序，如 14.29.30133 < 14.40.xxxxx）
$crtDir = $crtDirs | Sort-Object { (Split-Path (Split-Path $_.FullName -Parent) -Leaf) } -Descending | Select-Object -First 1
Write-Host "运行库来源: $($crtDir.FullName)"

# 复制 release 版 DLL（跳过 *d.dll 调试版）
$copied = @()
Get-ChildItem $crtDir.FullName -Filter "*.dll" |
    Where-Object { $_.Name -notmatch 'd\.dll$' } |
    ForEach-Object {
        Copy-Item $_.FullName -Destination $TargetDir -Force
        $copied += $_.Name
    }

if ($copied.Count -eq 0) {
    Write-Host "❌ 未复制任何 DLL" -ForegroundColor Red
    exit 1
}

Write-Host "✅ 已复制 $($copied.Count) 个 VC++ 运行库 DLL 到 $TargetDir" -ForegroundColor Green
$copied | ForEach-Object { Write-Host "   - $_" }

# 附加发布素材：WebView2 运行时引导程序 + 使用说明
# 引导程序不入库（1.8MB 二进制），缺失时从微软官方地址自动下载
$packagingDir = Join-Path $PSScriptRoot "packaging"
if (-not (Test-Path $packagingDir)) {
    New-Item -ItemType Directory -Path $packagingDir -Force | Out-Null
}

$webview2Exe = Join-Path $packagingDir "MicrosoftEdgeWebview2Setup.exe"
$webview2Url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"  # Evergreen Bootstrapper（官方）
if (-not (Test-Path $webview2Exe)) {
    Write-Host "正在下载 WebView2 运行时引导程序（约 1.8MB，官方地址）..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $webview2Url -OutFile $webview2Exe -UseBasicParsing
        Write-Host "✅ 下载完成: $webview2Exe" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  下载失败（可手动下载后放入 scripts/packaging/）：$webview2Url" -ForegroundColor Yellow
        Write-Host "    注意：AnxReader 依赖 Microsoft Edge WebView2 渲染书籍。" -ForegroundColor Yellow
    }
}

if (Test-Path $webview2Exe) {
    Copy-Item $webview2Exe -Destination $TargetDir -Force
    Write-Host "   - MicrosoftEdgeWebview2Setup.exe（WebView2 运行时·发布素材）" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  缺少 MicrosoftEdgeWebview2Setup.exe，未安装 WebView2 的系统将无法运行" -ForegroundColor Yellow
}

$readmeTemplate = Join-Path $packagingDir "使用说明.txt"
if (Test-Path $readmeTemplate) {
    Copy-Item $readmeTemplate -Destination $TargetDir -Force
    Write-Host "   - 使用说明.txt（发布素材）" -ForegroundColor Green
}

Write-Host ""
Write-Host "提示：AnxReader 依赖 Microsoft Edge WebView2；未预装该运行时的系统需先运行包内" -ForegroundColor Cyan
Write-Host "      MicrosoftEdgeWebview2Setup.exe，再打开 anx_reader.exe。" -ForegroundColor Cyan
Write-Host "提示：现在可以打包发布（zip / Inno Setup 安装器）。" -ForegroundColor Cyan
