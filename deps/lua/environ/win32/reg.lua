local winreg = require"winreg"
local string = require "string"

local function get_int_valtype(type_name)
  if type(type_name) == 'number' then
    return type_name
  end
  return assert(({
    ["sz"]        = 1;  -- A null-terminated string string 
    ["expand_sz"] = 2;  -- A null-terminated string that contains unexpanded references to environment variables, for example "%PATH%" string 
    ["binary"]    = 3;  -- Binary data in any form string 
    ["dword"]     = 4;  -- A 32-bit number number 
    ["multi_sz"]  = 7;  -- 
  })[string.lower(type_name)])
end

---
-- Registry function
--
local get_reg_key,set_reg_key,del_reg_key,get_reg_keys
do

function regopen(k, mode)
  mode = mode or 'r'
  return winreg.openkey(k, mode)
end

function get_reg_key(path, key)
  local ok, hkey = pcall(regopen, path)
  local result, type
  if ok and hkey then
    for name in hkey:enumvalue() do
      if string.upper(key) == string.upper(name) then
        result, type = hkey:getvalue(name)
      end
    end
    hkey:close()
    return result, type
  end
  return nil, hkey
end

function set_reg_key(path, key, value, value_type)
  assert(value ~= nil)
  local v, vt = get_reg_key(path, key)

  -- we can change either type or value or both
  if v ~= nil and v == value and (value_type == nil or get_int_valtype(value_type) == get_int_valtype(vt)) then
    return v, vt
  end

  if value_type == nil then
    value_type = vt
  end

  local ok, hkey = pcall(regopen, path, 'w')
  if ok and hkey then
    local ok, err = pcall(hkey.setvalue, hkey, key, value, value_type)
    hkey:close()
    if not ok then
      return nil, err
    end
    return true
  end
  return nil, hkey or 'can not open: `' .. path .. '` for write'
end

function del_reg_key(path, key)
  local v, vt = get_reg_key(path, key)
  if v == nil then
    return vt == nil, vt 
  end
  local ok, hkey = pcall(regopen, path, 'w')
  if ok and hkey then
    local ok, err = pcall(hkey.deletevalue, hkey, key)
    hkey:close()
    if not ok then
      return nil, err
    end
  end
  return true
end

function get_reg_keys(path)
  local ok, hkey = pcall(regopen, path)
  local result = {}
  if ok and hkey then
    for name in hkey:enumvalue() do
      local value, type = hkey:getvalue(name)
      result[name] = {value = value; type = type}
    end
    hkey:close()
  end
  return result
end

end

return {
  set_key  = set_reg_key;
  get_key  = get_reg_key;
  del_key  = del_reg_key;
  get_keys = get_reg_keys;

  SZ        = get_int_valtype("sz");
  EXPAND_SZ = get_int_valtype("expand_sz");
  BINARY    = get_int_valtype("binary");
  DWORD     = get_int_valtype("dword");
  MULTI_SZ  = get_int_valtype("multi_sz");
}