@echo off
chcp 65001 >nul
title Auok 浏览器 - PC版调试控制台
echo ========================================================
echo   Auok 浏览器 - 正在启动 Windows PC 端调试
echo ========================================================
echo.

cd /d "%~dp0"
echo 正在执行: flutter run -d windows ...
echo.
echo [调试快捷提示]
echo   - 在本窗口输入 r : 热重载 (Hot Reload)
echo   - 在本窗口输入 R : 热重启 (Hot Restart)
echo   - 在本窗口输入 h : 帮助菜单
echo   - 在本窗口输入 q : 退出调试并关闭窗口
echo ========================================================
echo.

call flutter run -d windows

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ========================================================
    echo   [启动遇到异常] 请查看上方错误日志
    echo ========================================================
    echo.
    pause
)
