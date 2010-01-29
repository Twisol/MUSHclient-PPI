local __V_MAJOR, __V_MINOR, __V_PATCH = 1, 1, 0
local __VERSION = string.format("%d.%d.%d", __V_MAJOR, __V_MINOR, __V_PATCH)

local PPI_list = {}

local myID = GetPluginID()
local myPPI = {}

local array_id   = function(id)      return "PPIarray_" .. id   end
local params_id  = function(id)      return "PPIparams_" .. id  end
local method_id  = function(id)      return "PPImethod_" .. id  end

local request_id  = function(id) return "PPI_" .. id .. "_REQUEST"  end
local cleanup_id  = function(id) return "PPI_" .. id .. "_CLEANUP"  end
local supports_id = function(id) return "PPI_" .. id .. "_SUPPORTS" end


function serialize(params, params_list)
  if not params_list then
    local params_list = {}
    serialize(params, params_list)
    
    local list = {}
    for k,v in ipairs(params_list) do
      list[k] = v
    end
    return list
  end
  
  if params_list[params] then
    return params_list[params]
  end
  
  local index = #params_list + 1
  params_list[params] = index
  params_list[index] = true
  
  local id = array_id(index)
  ArrayCreate(id)
  
  for k,v in pairs(params) do
    local key = nil
    if type(k) == "string" then
      key = "s:" .. k
    elseif type(k) == "number" then
      key = "n:" .. k
    end
    
    if key then
      local value = "z:~"
      
      if type(v) == "string" then
        value = "s:" .. v
      elseif type(v) == "number" then
        value = "n:" .. v
      elseif type(v) == "boolean" then
        value = "b:" .. (v and "1" or "0")
      elseif type(v) == "table" then
        value = "t:" .. serialize(v, params_list)
      end
      
      ArraySet(id, key, value)
    end
  end
  
  params_list[index] = ArrayExport(id, "|")
  ArrayDelete(id)
  
  return index
end

function deserialize(data_list, index, state)
  if not index or not state then
    return deserialize(data_list, 1, {})
  end
  
  if state[index] then
    return state[index]
  end
  
  local tbl = {}
  state[index] = tbl
  
  local id = array_id(index)
  ArrayCreate(id)
  ArrayImport(id, data_list[index], "|")
  
  for k,v in pairs(ArrayList(id)) do
    local key_type = k:sub(1,1)
    local key = nil
    
    if key_type == "s" then
      key = k:sub(3)
    elseif key_type == "n" then
      key = tonumber(k:sub(3))
    end
    
    if key then
      local item_type = v:sub(1,1)
      local item = v:sub(3)
      
      if item_type == "s" then
        tbl[key] = item
      elseif item_type == "n" then
        tbl[key] = tonumber(item)
      elseif item_type == "b" then
        tbl[key] = ((item == "1") and true or false)
      elseif item_type == "t" then
        tbl[key] = deserialize(data_list, tonumber(item), state)
      else
        tbl[key] = nil
      end
    end
  end
  
  ArrayDelete(id)
  
  return tbl
end

local function request(id, func_name, ...)
  -- Prepare the arguments
  local params = {...}
  for k,v in ipairs(serialize(params)) do
    SetVariable(params_id(id) .. "_" .. k, v)
  end
  
  -- Call the method
  SetVariable(method_id(id), func_name)
  CallPlugin(id, request_id(id), myID)
  
  -- Gather the return values
  local returns = {}
  local i = 1
  while GetPluginVariable(id, params_id(myID) .. "_" .. i) do
    returns[i] = GetPluginVariable(id, params_id(myID) .. "_" .. i)
    i = i + 1
  end
  returns = deserialize(returns)
  
  -- Have the other plugin clean up its return values
  CallPlugin(id, cleanup_id(id), myID)
  
  return unpack(returns)
end

-- A 'thunk' is a delayed resolver function.
local function new_thunk(id, func_name)
  return function(...)
    return request(id, func_name, ...)
  end
end

-- If the requested function hasn't yet had a thunk created,
-- create a new thunk and return it.
local PPI_meta = {
  __index = function(tbl, idx)
    local id = PPI_list[tbl].id
    
    -- Check if the method is supported, first.
    SetVariable(method_id(id), idx)
    CallPlugin(id, supports_id(id), myID)
    
    if GetPluginVariable(id, method_id(myID)) ~= "true" then
      CallPlugin(id, cleanup_id(id), myID)
      return nil
    end
    DeleteVariable(method_id(id))

    -- If it's supported, create a thunk.
    local thunk = new_thunk(id, idx)
    tbl[idx] = thunk
    return thunk
  end,
}

local PPI = {
  __V = __VERSION,
  __V_MAJOR = __V_MAJOR,
  __V_MINOR = __V_MINOR,
  __V_PATCH = __V_PATCH,
  
  -- Used to retreive a PPI for a specified plugin.
  Load = function(plugin_id)
    if not IsPluginInstalled(plugin_id) then
      return nil, "not_installed"
    elseif not PluginSupports(plugin_id, request_id(plugin_id)) then
      return nil, "no_ppi"
    end
    
    local tbl = PPI_list[plugin_id]
    if not tbl then
      tbl = setmetatable({}, PPI_meta)
      PPI_list[tbl] = {id = plugin_id}
      PPI_list[plugin_id] = tbl
    end
    return tbl
  end,
  
  -- Used by a plugin to expose methods to other plugins
  -- through its own PPI.
  Expose = function(name, func)
    myPPI[name] = (func and func or _G[name])
  end,
}

-- PPI request resolver
_G[request_id(myID)] = function(id)
  -- Get requested method
  local func = myPPI[GetPluginVariable(id, method_id(myID))]
  if not func then
    return
  end
  
  -- Deserialize parameters
  local params = {}
  local i = 1
  while GetPluginVariable(id, params_id(myID) .. "_" .. i) do
    params[i] = GetPluginVariable(id, params_id(myID) .. "_" .. i)
    i = i + 1
  end
  params = deserialize(params)
  
  -- Tell other plugin to clean up
  CallPlugin(id, cleanup_id(id), myID)
  
  -- Call method, return values
  local returns = {func(unpack(params))}
  for k,v in ipairs(serialize(returns)) do
    SetVariable(params_id(id) .. "_" .. k, v)
  end
end

-- method/params/returns cleaner
_G[cleanup_id(myID)] = function(id)
  local i = 1
  while GetVariable(params_id(id) .. "_" .. i) do
    DeleteVariable(params_id(id) .. "_" .. i)
    i = i + 1
  end
  DeleteVariable(method_id(id))
end

-- Does this plugin support a given method?
_G[supports_id(myID)] = function(id)
  local func = myPPI[GetPluginVariable(id, method_id(myID))]
  SetVariable(method_id(id), func and "true" or "false")
end

return PPI