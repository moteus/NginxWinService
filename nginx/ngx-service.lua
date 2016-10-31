-- nginx can restart workers byself so we should monitor only root process
-- If it crash then we need close all childs and restart nginx
----------------------------------------------------------------------------------

local Service = require "LuaService"
local uv      = require "lluv"
local psapi   = require "pdh.psapi"
local path    = require "path"
local date    = require "date"

local NGINX_PATH = Service.PATH .. "\\.."

local NGINX_APP  = "nginx.exe"

local CFG = "conf/nginx.conf"

local ENV = {
  PATH = NGINX_PATH .. ';' .. os.getenv('PATH'),
}

local env = {} for k, v in pairs(ENV) do
  env[#env+1] = k..'='..v
end

local Processes = {}

local function kill_childs(root_pid)
  local process = psapi.process()
  psapi.enum_processes(function(i, pid)
    if process:open(pid) then
      local parent_pid = process:parent_pid()
      process:close()
      if root_pid == parent_pid then uv.kill(pid) end
    end
  end)
  process:destroy()
end

local function nginx_start(cfg)
  cfg = cfg or CFG
  print("Start nginx with config:" .. cfg)
  local process, pid
  process, pid = uv.spawn({
    file = NGINX_PATH .. "\\" .. NGINX_APP,
    args = {"-c", cfg},
    cwd  = NGINX_PATH,
    env  = env,
  }, function(self, err, code, signal)
    kill_childs(pid)
    if not Service.check_stop(0) then
      print('restarting ...')
      uv.timer():start(5000, function()
        nginx_start(port)
      end)
    end
    Processes[self] = nil
  end)

  if process then Processes[process] = true end
end

local function nginx_signal(sig)
  local process = uv.spawn({
    file = NGINX_PATH .. "\\" .. NGINX_APP,
    args = {"-s", sig},
    cwd  = NGINX_PATH,
    env  = env,
  }, function(self, err, code, signal)
    print(sig .. ":", self, err, code, signal)
    Processes[self] = nil
  end)

  if process then Processes[process] = true end
end

local function nginx_stop()
  return nginx_signal('stop')
end

local function rename_log(P)
  local p, b = path.split(P)
  local new = path.join(p, path.splitext(b) .. '.' .. date():fmt('%F_%H%M%S') .. '.log')
  local ok, err = path.rename(P, new)
  print(string.format("rename `%s` to `%s` : %s", P, new, ok and 'ok' or tostring(err)))
end

local function nginx_rotate()
  path.each(path.join(NGINX_PATH, 'logs', '*access.log'), rename_log)
  path.each(path.join(NGINX_PATH, 'logs', '*error.log'), rename_log)
  return nginx_signal('reopen')
end

nginx_start()

-- rotate timer (check each 10 minuts. rotate onece a day)
local LAST_ROTATE = date():fmt('%F')

uv.timer():start(10 * 60 * 1000, function()
  local now = date():fmt('%F')
  if LAST_ROTATE ~= now then
    LAST_ROTATE = now
    nginx_rotate()
  end
end):unref()

local function StopService()
  print('stopping...')

  Service.stop()

  nginx_stop()

  uv.timer():start(30000, function()

    for process in pairs(Processes) do
      process:kill()
      Processes[process] = nil
    end

    uv.timer():start(30000, function()
      uv.stop()
    end):unref()

  end):unref()
end

if not Service.RUN_AS_SERVICE then
  print('reg signals')
  uv.signal():start(uv.SIGINT,   StopService):unref()
  uv.signal():start(uv.SIGBREAK, StopService):unref()
else
  print('start service')
  uv.timer():start(10000, 10000, function(self)
    if Service.check_stop(0) then
      self:close()
      StopService()
    end
  end)
end

uv.run()
