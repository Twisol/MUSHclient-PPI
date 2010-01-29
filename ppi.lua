local PPI_list = {}

local myID = GetPluginID()
local myPPI = {}

local params_id  = function(id) return "PPIparams_" .. id  end
local method_id  = function(id) return "PPImethod_" .. id  end
local returns_id = function(id) return "PPIreturns_" .. id end

local request_id = function(id) return "PPI_" .. id .. "_REQUEST" end
local cleanup_id = function(id) return "PPI_" .. id .. "_CLEANUP" end


local function request(id, func_name, ...)
  -- Prepare the arguments
  local params = {...}
  
  ArrayCreate(params_id(id))
  
  for i=1,#params do
    ArraySet(params_id(id), tostring(i), tostring(params[i]))
  end

  SetVariable(params_id(id), ArrayExport(params_id(id), "|"))
  ArrayDelete(params_id(id))
  
  -- Call the method
  SetVariable(method_id(id), func_name)
  CallPlugin(id, request_id(id), myID)
  
  -- Clean up the arguments
  DeleteVariable(params_id(id))
  DeleteVariable(method_id(id))
  
  -- Gather the return values
  local returns = {}
  
  ArrayCreate(returns_id(id))
  ArrayImport(returns_id(id), GetPluginVariable(id, returns_id(myID)), "|")
  
  for k,v in pairs(ArrayList(returns_id(id))) do
    returns[tonumber(k)] = v
  end
  ArrayDelete(returns_id(id))
  
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
    local thunk = new_thunk(PPI_list[tbl].id, idx)
    tbl[idx] = thunk
    return thunk
  end,
}

local PPI = {
  -- Used to retreive a PPI for a specified plugin.
  Load = function(plugin_id)
    if not IsPluginInstalled(plugin_id) then
      return false
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
  ArrayCreate(params_id(id))
  ArrayImport(params_id(id), GetPluginVariable(id, params_id(myID)), "|")
  
  local params = {}
  for k,v in pairs(ArrayList(params_id(id))) do
    params[tonumber(k)] = v
  end
  ArrayDelete(params_id(id))
  
  local func_name = GetPluginVariable(id, method_id(myID))
  local func = myPPI[func_name]
  if not func then
    return
  end
  
  local returns = {func(unpack(params))}
  ArrayCreate(returns_id(id))
  
  for i=1,#returns do
    ArraySet(returns_id(id), tostring(i), tostring(returns[i]))
  end

  SetVariable(returns_id(id), ArrayExport(returns_id(id), "|"))
  ArrayDelete(returns_id(id))
end

-- Return value cleaner
_G[cleanup_id(myID)] = function(id)
  DeleteVariable(returns_id(id))
end

return PPI