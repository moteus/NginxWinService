local Service = require "LuaService"
local uv      = require "lluv"
local winapi  = require "winapi"

local PHP_PATH = Service.PATH .. "\\.."

local PHP_APP  = "php-cgi.exe"

local PHP_INI  = "php.ini-development"

local PORTS = {
  '9001',
  '9002',
  '9003',
  '9004',
  --- '9005',
  --- '9006',
  --- '9007',
  --- '9008',
  --- '9009',
  --- '9010',
}

local ENV = setmetatable({}, {
  __index = function(self, key) return os.getenv(key) end;
  __newindex = function(self, key, value) winapi.setenv(key, value) end;
})

ENV.PATH                  = PHP_PATH .. ';' .. ENV.PATH
ENV.PHP_FCGI_CHILDREN     = 0
ENV.PHP_FCGI_MAX_REQUESTS = 500

local Processes = {}

local function php_cgi(port)
  print("Start php_cgi on port:" .. port)

  local process = uv.spawn({
    file = PHP_PATH .. "\\" .. PHP_APP,
    args = {"-b", "127.0.0.1:" .. port, "-c", PHP_INI},
    cwd  = PHP_PATH,
  }, function(self, err, code, signal)
    print(self, err, code, signal)
    if not Service.check_stop(0) then
      print('restarting ' .. port .. "...")
      uv.defer(php_cgi, port)
    end
    Processes[self] = nil
  end)

  if process then Processes[process] = true end
end

for _, port in ipairs(PORTS) do
  php_cgi(port)
end

local function StopService()
  print('stopping...')
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
  print('reg signals')
  uv.signal():start(uv.SIGINT,   StopService):unref()
  uv.signal():start(uv.SIGBREAK, StopService):unref()
else
  uv.timer():start(10000, 10000, function(self)
    if Service.check_stop(0) then
      self:stop()
      StopService()
    end
  end)
end

uv.run()
