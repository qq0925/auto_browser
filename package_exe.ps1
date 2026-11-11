$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$releaseDir = Join-Path $scriptDir 'build\windows\x64\runner\Release'
$exeTarget = Join-Path $releaseDir 'auto_browser.exe'

if (-not (Test-Path $exeTarget)) {
    Write-Host "未找到 Release 构建产物，正在执行: flutter build windows --release ..."
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter release build failed with exit code $LASTEXITCODE"
        exit 1
    }
}

$downloadsDir = 'C:\Users\79277\Downloads'
if (-not (Test-Path $downloadsDir)) {
    $downloadsDir = Join-Path $env:USERPROFILE 'Downloads'
}
$outExe = Join-Path $downloadsDir 'auto_browser.exe'

$tempDir = Join-Path $env:TEMP ('auok_pack_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    $stageDir = Join-Path $tempDir 'stage'
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

    # 复制 Release 文件 (排除 msix 文件)
    Get-ChildItem -Path $releaseDir -Exclude '*.msix' | Copy-Item -Destination $stageDir -Recurse -Force

    $zipPath = Join-Path $tempDir 'payload.zip'
    Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -Force

    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
    $csPath = Join-Path $tempDir 'Launcher.cs'
    
    $csCode = @"
using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Diagnostics;

class Program {
    [STAThread]
    static void Main(string[] args) {
        try {
            string appDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "AuokBrowser",
                "v1.1.15_23_$stamp"
            );
            string exePath = Path.Combine(appDir, "auto_browser.exe");
            if (!File.Exists(exePath)) {
                if (Directory.Exists(appDir)) {
                    Directory.Delete(appDir, true);
                }
                Directory.CreateDirectory(appDir);
                string zipPath = Path.Combine(appDir, "payload.zip");
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
                using (FileStream fs = File.Create(zipPath)) {
                    s.CopyTo(fs);
                }
                ZipFile.ExtractToDirectory(zipPath, appDir);
                File.Delete(zipPath);
            }
            ProcessStartInfo psi = new ProcessStartInfo(exePath);
            psi.WorkingDirectory = appDir;
            psi.UseShellExecute = true;
            Process.Start(psi);
        } catch (Exception) {}
    }
}
"@

    [System.IO.File]::WriteAllText($csPath, $csCode, [System.Text.Encoding]::UTF8)

    $csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) {
        $csc = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }
    $ico = Join-Path $scriptDir 'windows\runner\resources\app_icon.ico'

    & $csc /nologo /target:winexe "/out:$outExe" /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll "/win32icon:$ico" "/resource:$zipPath,payload.zip" "$csPath"

    if ($LASTEXITCODE -ne 0) {
        Write-Error "csc.exe 编译失败，退出码: $LASTEXITCODE"
        exit 1
    }

}
finally {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
