@echo off && setlocal
set lua_cpath=!\\lua\\?.dll
set lua_path=!\\lua\\?.lua
set lua_init=
start "nginx for Windows" lua51.exe ngx-service.lua