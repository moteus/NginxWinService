return {
  tracelevel = 7,
  name         = "ngingxwin";
  display_name = "nginx for Windows";
  script       = "ngx-service.lua",
  lua_cpath    = '!\\lua\\?.dll',
  lua_path     = '!\\lua\\?.lua',
  lua_init     = '',
}
