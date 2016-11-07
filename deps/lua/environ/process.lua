local utils  = require "environ.utils"
local core   = require "environ.core"


-- Note 1 about `*_win` functions.
-- This functions use WinAPI and ignores any CRT.
-- So it allows get variables set in differend module
-- even if this module use different or static CRT.
-- But it also means that `os.getenv` may returns different
-- result and some C mudules will use this value.
-- Also it means that use `setenv_win` is quite useless
-- because this value will be invisiable for any C mudule
-- unless it also uses WinAPI.
--
-- Note 2 about `*_win` functions.
-- Windows hase environment variables started with `=` e.g.
-- `=Exitcode`, `=C:`. CRT versions does not returns such values.
--
-- Note about expand function.
-- There exists `expand_win` but I think better use 
-- custom function so it can be used same syntax on all
-- platforms.
--

local getenv   = core.get_win or core.get
local expenv   = utils.build_expand(getenv)
local setenv   = function(key, value, expand)
  if value and expand then
    value = expenv(value)
  end
  return core.set(key, value)
end
local environ_ = core.environ_win or core.environ
local environ  = function (upper)
  if not environ_ then return nil, 'not supported' end
  
  local t, r = environ_(), {}

  for _, str in ipairs(t) do
    local k, v = utils.split_first(str, '=', true, 2)
    if upper then k = string.upper(k) end
    r[k] = v
  end

  return r
end
local enum     = function () return next, environ() end

local process = {
  getenv  = getenv;
  setenv  = setenv;
  expand  = expenv;
  environ = environ;
  enum    = enum;

  update  = update;
}

process.ENV = utils.make_env_map(process)

require "environ".process = process

return process