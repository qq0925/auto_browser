@echo off
chcp 65001 >nul
echo ========================================================
echo   Auok 浏览器 - 正在打包 MSIX 与 EXE (v1.1.15+23)
echo ========================================================
echo.

cd /d "%~dp0"
echo [1/2] 正在执行: dart run msix:create ...
echo.

call dart run msix:create

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ========================================================
    echo   [MSIX 打包遇到问题] 请查看上方控制台错误日志
    echo ========================================================
    echo.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [2/2] 正在生成独立可执行文件 Auok.exe 至下载文件夹 ...

if not exist "build\windows\x64\runner\Release\auto_browser.exe" (
    call flutter build windows --release
) else if not exist "build\windows\x64\runner\Release\flutter_windows.dll" (
    call flutter build windows --release
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $releaseDir = Join-Path (Get-Location) 'build\windows\x64\runner\Release'; $downloadsDir = 'C:\Users\79277\Downloads'; if (-not (Test-Path $downloadsDir)) { $downloadsDir = Join-Path $env:USERPROFILE 'Downloads' }; $outExe = Join-Path $downloadsDir 'Auok.exe'; $tempDir = Join-Path $env:TEMP ('auok_pack_' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $tempDir -Force | Out-Null; $stageDir = Join-Path $tempDir 'stage'; New-Item -ItemType Directory -Path $stageDir -Force | Out-Null; Get-ChildItem -Path $releaseDir -Exclude '*.msix' | Copy-Item -Destination $stageDir -Recurse -Force; $zipPath = Join-Path $tempDir 'payload.zip'; Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -Force; $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString(); $csPath = Join-Path $tempDir 'Launcher.cs'; $csLines = @('using System;', 'using System.IO;', 'using System.IO.Compression;', 'using System.Reflection;', 'using System.Diagnostics;', 'class Program {', '  [STAThread] static void Main(string[] args) {', '    try {', '      string appDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), \"AuokBrowser\", \"v1.1.15_23_' + $stamp + '\");', '      string exePath = Path.Combine(appDir, \"auto_browser.exe\");', '      if (!File.Exists(exePath)) {', '        if (Directory.Exists(appDir)) Directory.Delete(appDir, true);', '        Directory.CreateDirectory(appDir);', '        string zipPath = Path.Combine(appDir, \"payload.zip\");', '        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(\"payload.zip\"))', '        using (FileStream fs = File.Create(zipPath)) { s.CopyTo(fs); }', '        ZipFile.ExtractToDirectory(zipPath, appDir);', '        File.Delete(zipPath);', '      }', '      ProcessStartInfo psi = new ProcessStartInfo(exePath);', '      psi.WorkingDirectory = appDir;', '      psi.UseShellExecute = true;', '      Process.Start(psi);', '    } catch (Exception) {}', '  }', '}'); Set-Content -Path $csPath -Value ($csLines -join [Environment]::NewLine) -Encoding UTF8; $csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'; $ico = Join-Path (Get-Location) 'windows\runner\resources\app_icon.ico'; & $csc /nologo /target:winexe \"/out:$outExe\" /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll \"/win32icon:$ico\" \"/resource:$zipPath,payload.zip\" \"$csPath\"; Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue;"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================================
    echo   [打包成功] 安装包与可执行文件已输出至下载文件夹:
    echo   1. MSIX 安装包: C:\Users\79277\Downloads\Auok.msix
    echo   2. EXE 程序文件: C:\Users\79277\Downloads\Auok.exe
    echo ========================================================
) else (
    echo.
    echo ========================================================
    echo   [打包遇到问题] 请查看上方控制台错误日志
    echo ========================================================
)

echo.
pause
