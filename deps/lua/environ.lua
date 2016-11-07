local Environment = setmetatable({
  _NAME = 'environ';
  _VERSION = '0.1.0-dev';
}, {__index = function(self, name)
  local mod = require ("environ." .. name)
  self[name] = mod
  return mod
end})

return Environment