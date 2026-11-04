@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo 正在启动预算管理，浏览器会自动打开。
echo 手机访问：同一 Wi-Fi 下打开本窗口里显示的「手机」地址。
start "" http://127.0.0.1:8765
node serve.mjs
pause
