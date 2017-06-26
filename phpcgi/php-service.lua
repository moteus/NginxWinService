local Service = require "LuaService"
local uv      = require "lluv"
local env     = require "environ.process"
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

-- Allows Log stderr to logfle.
-- Works only for USE_SINGLE_PORT = false
local PHP_LOG_STDERR = false

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

local PHP_ENV = {
  PATH=PHP_PATH..";%PATH%";

  -- List of ipv4 addresses of FastCGI clients which are allowed to connect
  FCGI_WEB_SERVER_ADDRS="127.0.0.1";

  -- number of PHP children to spawn
  PHP_FCGI_CHILDREN="0";

  -- number of request before php-process will be restarted
  PHP_FCGI_MAX_REQUESTS="500";

  -- backlog value for `listen` function
  -- PHP_FCGI_BACKLOG = "128";

  -- some PHP `constants`
  PHP_BIN    = PHP_PATH .. [[\php.exe]];
  PHP_BINARY = PHP_PATH .. [[\php.exe]];
  PHPBIN     = PHP_PATH .. [[\php.exe]];

  PHP_BINDIR = PHP_PATH .. [[\]];
  PHP_DIR    = PHP_PATH .. [[\]];
  PHPDIR     = PHP_PATH .. [[\]];

  PHP_INI    = PHP_PATH .. [[\]] .. PHP_INI;
  PHPRC      = PHP_PATH;
}

----------------------------------------------------------------------------------------------
-- CONFIG END
----------------------------------------------------------------------------------------------

local log do
  local stdout_writer
  if not Service.RUN_AS_SERVICE then
    stdout_writer = require 'log.writer.stdout'.new()
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

for k, v in pairs(PHP_ENV) do env.setenv(k, v, true) end

local function P(read, write, pipe)
  local ioflags = 0
  if read  then ioflags = ioflags + uv.READABLE_PIPE end
  if write then ioflags = ioflags + uv.WRITABLE_PIPE end
  if ioflags ~= 0 then
    if not pipe then
      pipe = uv.pipe()
      ioflags = ioflags + uv.CREATE_PIPE
    else
      ioflags = ioflags + uv.INHERIT_STREAM
    end
  end

  return {
    stream = pipe,
    flags  = ioflags + uv.PROCESS_DETACHED
  }
end

local Processes = {}

local stderrs = {}
local function php_cgi_port(port)
  if Service.check_stop(0) then return end

  local IGNORE = {flags = uv.IGNORE}

  log.info("starting php_cgi on port: %s ...", port)

  local stderr, stderr_started
  if PHP_LOG_STDERR then
    stderr = stderrs[port]
    stderr_started = not not stderr
    if not stderr then stderr = P(false, true) end
    stderrs[port] = stderr
  end

  local process, pid

  process, pid = uv.spawn({
    file = PHP_PATH .. "\\" .. PHP_APP,
    args = {"-b", port, "-c", PHP_INI},
    cwd  = PHP_PATH,
    stdio = {IGNORE, IGNORE, stderr or IGNORE},
  }, function(self, err, code, signal)
    Processes[self] = nil

    if err then
      log.error("can not run php-cgi process: %s", tostring(err))
    else
      log.info('process: %d stopped with code: %d sig: %d', pid, code, signal)
    end

    if code ~= 0 then
      log.warning('unexpected terminate process: %d code: %d sig: %d', pid, code, signal)
    end

    if Service.check_stop(0) then return end

    log.info('restarting php_cgi process')
    uv.defer(php_cgi_port, port)
  end)

  if process then
    log.info("started php_cgi on port: %s pid: %d", port, pid)
    Processes[process] = true
  end

  if stderr and not stderr_started then
    log.info("starting read stderr for %s", port)
    stderr.stream:start_read(function(self, err, data)
      if err and err:name() == 'EOF' then
        return
      end
      if err then log.error('PHP::STDERR %s', tostring(err)) end
      if data then log.info('PHP::STDERR %s', data) end
    end)
    stderr.stream:unref()
  end
end

local function php_cgi_sock(s)
  if Service.check_stop(0) then return end

  log.info("starting php_cgi on file: %s ...", tostring(s))

  local process, pid
  process, pid = uv.spawn({
    file = PHP_PATH .. "\\" .. PHP_APP,
    args = {"-c", PHP_INI},
    cwd  = PHP_PATH,
    -- We have to pass invalid handles to stdout and stderr
    -- so we can not capture stderr in this mode
    stdio = {s, -1, -1},
  }, function(self, err, code, signal)
    Processes[self] = nil

    if err then
      log.error("can not run php-cgi process: %s", tostring(err))
    else
      log.info('process: %d stopped with code: %d sig: %d', pid, code, signal)
    end

    if code ~= 0 then
      log.warning('unexpected terminate process: %d code: %d sig: %d', pid, code, signal)
    end

    if Service.check_stop(0) then
      s:close()
      return
    end

    log.info('restarting php_cgi process')
    uv.defer(php_cgi_sock, s)
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
