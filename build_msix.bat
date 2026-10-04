@echo off
chcp 65001 >nul
echo ========================================================
echo   Auok 浏览器 - 正在打包 MSIX 安装包 (v1.1.7+15)
echo ========================================================
echo.

cd /d "%~dp0"
echo 正在执行: dart run msix:create ...
echo.

call dart run msix:create

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================================
    echo   [打包成功] MSIX 安装包已输出至 Downloads 目录:
    echo   C:\Users\79277\Downloads\Auok.msix
    echo ========================================================
) else (
    echo.
    echo ========================================================
    echo   [打包遇到问题] 请查看上方控制台错误日志
    echo ========================================================
)

echo.
pause
