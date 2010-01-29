local PPI_list = setmetatable({}, {__mode = "k"})

-- Takes a table and returns all values at numeric indices.
-- Example:
--  Input: {1, 2, 3, "5", "7", "10"}
--  Returns: 1, 2, 3, "5", "7", "10"
local function ExplodeParams(tbl)
  local param = table.remove(tbl, 1)
  if #tbl > 0 then
    return param, ExplodeParams(tbl)
  else
    return param
  end
end

-- A 'thunk' is a delayed resolver function.
local function new_thunk(id, func_name)
  return function(...)
    local params = {...}
    
    -- Prepare the arguments
    for i=1,#params do
      SetVariable("param" .. i .. "_" .. id, tostring(params[i]))
    end
    
    -- Call the method
    SetVariable("method_" .. id, func_name)
    CallPlugin(id, "PPI_" .. id .. "_PPI", GetPluginID())
    
    -- Clean up the arguments
    for i=1,#params do
      DeleteVariable("param" .. i .. "_" .. id)
    end
    
    -- Gather the return values
    local returns = {}
    local i = 1
    while GetPluginVariable(id, "return" .. i .. "_" .. GetPluginID()) ~= nil do
      table.insert(returns, GetPluginVariable(id, "return" .. i .. "_" .. GetPluginID()))
      i = i + 1
    end
    
    -- Have the other plugin clean up the return values
    CallPlugin(id, "PPI_" .. id .. "_PPI_CLEAN", GetPluginID())
    
    return ExplodeParams(returns)
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
    local myPPI = PPI_list[GetPluginID()]
    myPPI[name] = func
  end,
}

-- create a PPI for this plugin
myPPI = {}
PPI_list[myPPI] = {id = GetPluginID()}
PPI_list[GetPluginID()] = myPPI

-- PPI request resolver
_G["PPI_" .. GetPluginID() .. "_PPI"] = function(id)
  local myPPI = PPI_list[GetPluginID()]
  local myID = PPI_list[myPPI].id
  if not myPPI then
    return
  end
  
  local params = {}
  local i = 1
  while GetPluginVariable(id, "param" .. i .. "_" .. myID) ~= nil do
    table.insert(params, GetPluginVariable(id, "param" .. i .. "_" .. myID))
    i = i + 1
  end
  
  local func_name = GetPluginVariable(id, "method_" .. myID)
  local func = myPPI[func_name]
  if not func then
    return
  end
  
  local returns = {func(ExplodeParams(params))}
  for i=1, #returns do
    SetVariable("return" .. i .. "_" .. id, tostring(returns[i]))
  end
end

-- Return value cleaner
_G["PPI_" .. GetPluginID() .. "_PPI_CLEAN"] = function(id)
  local i = 1
  while GetVariable("return" .. i .. "_" .. id) ~= nil do
    DeleteVariable("return" .. i .. "_" .. id)
    i = i + 1
  end
end

return PPI