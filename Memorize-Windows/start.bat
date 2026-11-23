@echo off
chcp 65001 >nul
rem 用默认浏览器打开 Memorize（无需任何依赖）
start "" "%~dp0index.html"
