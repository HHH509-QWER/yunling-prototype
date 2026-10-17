@echo off
chcp 65001 >nul
rem 《蕴灵印》—— 双击这个文件 = 用 Godot 4.7.2 打开本工程的编辑器
rem 用 %~dp0 定位，工程挪到哪都还能用；不要改成 gu_tools 里那两个 4.4 的 exe。
start "" "%~dp0..\gu_tools\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." --editor