local utils = require "environ.utils"

local env

if utils.IS_WINDOWS then

env = require "environ.win32.system".make_module('user')

end

if not env then error('unsupported system') end

require "environ".user = env

return env
