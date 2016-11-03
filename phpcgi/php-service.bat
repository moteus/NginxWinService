@echo off && setlocal
set lua_cpath=!\\lua\\?.dll
set lua_path=!\\lua\\?.lua
set lua_init=
start "PHPcgi for Window" lua51.exe php-service.lua