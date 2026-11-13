@echo off
chcp 65001 >nul
echo ========================================================
echo   Auok 浏览器 - 正在打包 MSIX 与 EXE (v1.1.16+24)
echo ========================================================
echo.

cd /d "%~dp0"
echo [1/2] 正在执行: dart run msix:create ...
echo.

call dart run msix:create
if errorlevel 1 goto :fail

echo.
echo [2/2] 正在生成独立可执行文件 auto_browser.exe 至下载文件夹 ...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0package_exe.ps1"
if errorlevel 1 goto :fail

echo.
echo ========================================================
echo   [打包成功] 安装包与可执行文件已输出至下载文件夹:
echo   1. MSIX 安装包: C:\Users\79277\Downloads\auto_browser.msix
echo   2. EXE 程序文件: C:\Users\79277\Downloads\auto_browser.exe
echo ========================================================
goto :end

:fail
echo.
echo ========================================================
echo   [打包遇到问题] 请查看上方控制台错误日志
echo ========================================================

:end
echo.
if "%~1" neq "--no-pause" pause
