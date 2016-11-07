----------------------------------------------------------------------
-- Реализует функции для работы с переменными окружения через реестр 
----------------------------------------------------------------------

local utils = require "environ.utils"
local reg   = require "environ.win32.reg"
local core  = require "environ.core"

local type, assert, pcall, pairs = 
      type, assert, pcall, pairs 

local function get_env_type(value)
  if nil ~= string.find(value, '%', 1, true) then
    return reg.EXPAND_SZ
  end
  return reg.SZ
end

---
-- Environment function
--
local PATHS = {
  user      = [[HKEY_CURRENT_USER\Environment]];
  sys       = [[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment]];
  volatile  = [[HKEY_CURRENT_USER\Volatile Environment]];
}

local function get_raw_env(path, name)
  path = assert(PATHS[string.lower(path)])
  return reg.get_key(path, name)
end

local function set_raw_env(path, name, value, normalize)
  path = assert(PATHS[string.lower(path)])
  if value then
    if normalize then
      value = utils.normalize(value)
    end
    return reg.set_key(path, name, value, get_env_type(value))
  end
  return reg.del_key(path, name)
end

local function del_raw_env(path, name)
  path = assert(PATHS[string.lower(path)])
  return reg.del_key(path, name)
end

local function get_raw_env_t(path, upper)
  path = assert(PATHS[string.lower(path)])
  local t = reg.get_keys(path)
  local result = {}
  for k, v in pairs(t) do
    if upper then
      k = string.upper(k)
    end
    result[string.upper(k)] = v.value
  end
  return result
end

local function make_module(path)
  local setenv = function(key, value, normalize)
    return set_raw_env(path, key, value, normalize)
  end

  local getenv = function(key)
    return get_raw_env(path, key)
  end

  local environ = function(upper)
    return get_raw_env_t(path, upper)
  end

  local expenv = utils.build_expand(getenv)

  local update = core.update_win or function() end

  local enum   = function () return next, environ() end

  local env = {
    environ     = environ;
    getenv      = getenv;
    setenv      = setenv;
    update      = update;
    enum        = enum;
  }

  env.ENV = utils.make_env_map(env)
  return env
end

return {
  make_module = make_module
}
