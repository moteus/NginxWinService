local Service = require "LuaService"
local uv      = require "lluv"
local winapi  = require "winapi"
local ut      = require "lluv.utils"
local LogLib  = require "log"

----------------------------------------------------------------------------------------------
-- CONFIG BEGIN
----------------------------------------------------------------------------------------------

local LOG_LEVEL = 'info'

local LOG_FILE  = {
  log_dir        = "./logs",
  log_name       = "php-service.log",
  max_size       = 10 * 1024 * 1024,
  close_file     = false,
  flush_interval = 1,
  reuse          = true,
}

local PHP_PATH  = Service.PATH .. "\\.."

local PHP_APP   = "php-cgi.exe"

local PHP_INI   = "php.ini-development"

local USE_SINGLE_PORT = false

-- this is run multiple php-cgi processed wich share same address/port
-- (USE_SINGLE_PORT = true)
local BIND_HOST = '127.0.0.1:9000'

local SPAWN_COUNT = 4

-- this is run multiple php-cgi processed and each process use its own address/port
-- (USE_SINGLE_PORT = false)
local PORTS = {
  '127.0.0.1:9001',
  '127.0.0.1:9002',
  '127.0.0.1:9003',
  '127.0.0.1:9004',
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

local ENV = setmetatable({}, {
  __index = function(self, key) return os.getenv(key) end;
  __newindex = function(self, key, value) winapi.setenv(key, value) end;
})

-- winapi has bug which leads to AV when try set too long env variable
-- ENV.PATH                  = PHP_PATH .. ';' .. ENV.PATH
ENV.PHP_FCGI_CHILDREN     = 0
ENV.PHP_FCGI_MAX_REQUESTS = 500

local Processes = {}

local function php_cgi_port(port)
  log.info("starting php_cgi on port: %s ...", port)

  local process, pid

  process, pid = uv.spawn({
    file = PHP_PATH .. "\\" .. PHP_APP,
    args = {"-b", port, "-c", PHP_INI},
    cwd  = PHP_PATH,
  }, function(self, err, code, signal)
    log.info('process: %d stopped with code: %d sig: %d', pid, code, signal)

    if code ~= 0 then
      log.warning('unexpected terminate process: %d code: %d sig: %d', pid, code, signal)
    end

    if not Service.check_stop(0) then
      log.info('restarting php_cgi process')
      uv.defer(php_cgi_port, port)
    end

    Processes[self] = nil
  end)

  if process then
    log.info("started php_cgi on port: %s pid: %d", port, pid)
    Processes[process] = true
  end
end

local function php_cgi_sock(s)
  log.info("starting php_cgi on file: %s ...", tostring(s))

  local process, pid
  process, pid = uv.spawn({
    file = PHP_PATH .. "\\" .. PHP_APP,
    args = {"-c", PHP_INI},
    cwd  = PHP_PATH,
    stdio = {s, -1, -1},
  }, function(self, err, code, signal)
    log.info('process: %d stopped with code: %d sig: %d', pid, code, signal)

    if code ~= 0 then
      log.warning('unexpected terminate process: %d code: %d sig: %d', pid, code, signal)
    end

    if not Service.check_stop(0) then
      log.info('restarting php_cgi process')
      uv.defer(php_cgi_sock, s)
    else
      s:close()
    end
    Processes[self] = nil
  end)

  if process then Processes[process] = true end
end

local function fcgi_listen(host, port)
  assert(uv.os_handle, 'this version of lluv library does not support OS Handles as stdio')
  local socket  = require "socket"
  local s = assert(socket.bind(host, port))
  local h = uv.os_handle(s:getfd(), true)
  s:close()
  return h
end

if USE_SINGLE_PORT then

local host, port = ut.split_first(BIND_HOST, ':', true)

if not port then host, port = '127.0.0.1', host end

log.info("start listen %s:%s", host, port)

local s = fcgi_listen(host, port)

for i = 1, SPAWN_COUNT do
  php_cgi_sock(s)
end

else

for _, port in ipairs(PORTS) do
  php_cgi_port(port)
end

end

local function StopService()
  log.info('stopping...')
  Service.stop()

  for process in pairs(Processes) do
    process:kill()
    Processes[process] = nil
  end

  uv.timer():start(30000, function()
    uv.stop()
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
      self:stop()
      StopService()
    end
  end)
end

uv.run()

log.info('stopped')
