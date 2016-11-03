local service = service

local string = require "string"

local dirsep, pathsep = string.match(package.config, "^(.)%s+(.)")

local function remove_dir_end(str)
  return (string.gsub(str, '[\\/]+$', ''))
end

local function norm_path(p)
  p = string.gsub(p, '[\\/]', dirsep)
  if pathsep == ':' then
    p = string.gsub(p, ';', pathsep)
  end
  return p
end

local function prequire(mod)
  local ok, err = pcall(require, mod)
  if not ok then return nil, err end
  return err, mod
end

local function load_config(file, env)
  local fn
  if setfenv then
    fn = assert(loadfile(file))
    setfenv(fn, env)
  else
    fn = assert(loadfile(file, "bt", env))
  end
  return fn()
end

local Service = {} do

Service.RUN_AS_SERVICE = not not service

Service.print = service and service.print or print

Service.name  = service and service.name or "LuaService console"

-- this function was need because LuaService does not stop service after 
-- Lua script done. But now it fixed.
Service.exit  = function() end

Service.PATH  = service and service.path

if not Service.PATH then
  local lfs = require "lfs"
  Service.PATH = lfs.currentdir()
end

Service.PATH = remove_dir_end(Service.PATH)

Service.sleep = service and service.sleep

if not Service.sleep then repeat
  local m
  m = prequire "socket"
  if m then Service.sleep = function(s) m.sleep(s/1000) end; break; end
  m = prequire "lzmq.timer"
  if m then Service.sleep = m.sleep; break; end
  m = prequire "winapi"
  if m then Service.sleep = m.sleep; break; end
until true end

-- Load service config
if not Service.RUN_AS_SERVICE then repeat
  local config = load_config(Service.PATH .. dirsep .. 'init.lua', {})
  if not config then break end

  Service.name = config.name or Service.name

  local lua_path, lua_cpath = config.lua_path, config.lua_cpath

  if lua_path then
    lua_path = norm_path(lua_path)
    lua_path = string.gsub(lua_path, '!', Service.PATH or '')
    if string.find(lua_path, "^@") then
      package.path = string.sub(lua_path, 2)
    else
      package.path = lua_path .. pathsep .. package.path
    end
  end

  if lua_cpath then
    lua_cpath = norm_path(lua_cpath)
    lua_cpath = string.gsub(lua_cpath, '!', Service.PATH or '')
    if string.find(lua_cpath, "^@") then
      package.cpath = string.sub(lua_cpath, 2)
    else
      package.cpath = lua_cpath .. pathsep .. package.cpath
    end
  end
until true end

-------------------------------------------------------------------------------
-- Implement basic main loop
do

local STOP_FLAG = false

function Service.check_stop(stime, scount)
  if stime == 0 then
    scount = 1
  end

  stime  = stime  or lsrv.stime  or 1000
  scount = scount or lsrv.scount or 1

  for i = 1, scount do
    if STOP_FLAG or (service and service.stopping()) then 
      STOP_FLAG = true
      return STOP_FLAG
    end
    if stime > 0 then
      Service.sleep(stime)
    end
  end

  return false
end

function Service.stop()
  STOP_FLAG = true
end

function Service.run(main, stime, scount)
  stime  = Service.stime  or stime  or 5000
  scount = Service.scount or scount or 10*2
  while true do
    if Service.check_stop(stime, scount) then
      break
    end
    main()
  end
end

end
-------------------------------------------------------------------------------

end

return Service