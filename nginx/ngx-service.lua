-- nginx can restart workers byself so we should monitor only root process
-- If it crash then we need close all childs and restart nginx
----------------------------------------------------------------------------------

local Service = require "LuaService"
local uv      = require "lluv"
local psapi   = require "pdh.psapi"
local path    = require "path"
local date    = require "date"
local LogLib  = require "log"

----------------------------------------------------------------------------------------------
-- CONFIG BEGIN
----------------------------------------------------------------------------------------------

local LOG_LEVEL = 'info'

local LOG_FILE  = {
  log_dir        = "./logs",
  log_name       = "ngx-service.log",
  max_size       = 10 * 1024 * 1024,
  close_file     = false,
  flush_interval = 1,
  reuse          = true,
}

local NGINX_PATH = Service.PATH .. "\\.."

local NGINX_APP  = "nginx.exe"

local NGINX_CFG = "conf/nginx.conf"

local ENV = {
  PATH = NGINX_PATH .. ';' .. os.getenv('PATH'),
}

----------------------------------------------------------------------------------------------
-- CONFIG END
----------------------------------------------------------------------------------------------

local log do
  local stdout_writer
  if not Service.RUN_AS_SERVICE then
    stdout_writer = require 'log.writer.console.color'.new()
  end

  local writer = require "log.writer.list".new(
    require 'log.writer.file'.new(LOG_FILE),
    stdout_writer
  )

  local formatter = require "log.formatter.mix".new(
    require "log.formatter.pformat".new()
  )

  log = require "log".new( LOG_LEVEL or "info", writer, formatter)
end

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
  if Service.check_stop(0) then return end

  cfg = cfg or NGINX_CFG
  log.info("Start nginx with config: %s", cfg)
  local process, pid
  process, pid = uv.spawn({
    file = NGINX_PATH .. "\\" .. NGINX_APP,
    args = {"-c", cfg},
    cwd  = NGINX_PATH,
    env  = env,
  }, function(self, err, code, signal)
    Processes[self] = nil

    if err then
      log.error("can not run process: %s", tostring(err))
    else
      log.info('process: %d stopped with code: %d sig: %d', pid, code, signal)
    end

    if code ~= 0 then
      log.warning('unexpected terminate process: %d code: %d sig: %d', pid, code, signal)
    end

    if Service.check_stop(0) then return end

    kill_childs(pid)

    log.info('restarting nginx main process')
    uv.timer():start(5000, function()
      nginx_start(cfg)
    end)
  end)

  if process then Processes[process] = true end
end

local function nginx_signal(sig)
  log.info('send nginx signal: %s', sig)
  local process = uv.spawn({
    file = NGINX_PATH .. "\\" .. NGINX_APP,
    args = {"-s", sig},
    cwd  = NGINX_PATH,
    env  = env,
  }, function(self, err, code, signal)
    Processes[self] = nil
    if err then
      log.error("can not send nginx signal: %s", tostring(err))
    else
      log.info('nginx signal: %s code: %d signal: %d', sig, code, signal)
    end
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
  log.info("rename `%s` to `%s` : %s", P, new, ok and 'ok' or tostring(err))
end

local function nginx_rotate()
  path.each(path.join(NGINX_PATH, 'logs', '*access.log'), rename_log)
  path.each(path.join(NGINX_PATH, 'logs', '*error.log'), rename_log)
  return nginx_signal('reopen')
end

nginx_start()

local ROTATE_MASK = '%F'

-- rotate timer (check each 10 minuts. rotate onece a day)
local LAST_ROTATE = date():fmt(ROTATE_MASK)

uv.timer():start(0, 10 * 60 * 1000, function()
  local now = date():fmt(ROTATE_MASK)
  if LAST_ROTATE ~= now then
    LAST_ROTATE = now
    nginx_rotate()
  end
end):unref()

local function StopService()
  log.info('stopping...')

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
  log.info('run as application')
  uv.signal():start(uv.SIGINT,   StopService):unref()
  uv.signal():start(uv.SIGBREAK, StopService):unref()
else
  log.info('run as service')
  uv.timer():start(10000, 10000, function(self)
    if Service.check_stop(0) then
      self:close()
      StopService()
    end
  end)
end

uv.run()
