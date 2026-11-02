_G.Hooks = Hooks or {}
Hooks._registered_hooks = Hooks._registered_hooks or {}
Hooks._function_hooks = Hooks._function_hooks or {}
Hooks._call_depth = Hooks._call_depth or 0
Hooks._compact_pending = Hooks._compact_pending or false

--------------------------------------------------------------------------------
-- Error isolation
-- An error in one mod's hook must not keep the others (or the game function) from running.
-- Errors are logged with a traceback, the same error is only logged once every few seconds,
-- since hooks like updates would otherwise flood the log every frame.

local ERROR_LOG_INTERVAL = 5
local ERROR_LOG_MAX_ENTRIES = 200
local last_logged = {}
local last_logged_count = 0

local function error_handler(err)
	return debug.traceback(tostring(err), 2)
end

-- the description of the failed call is only built when an error happens (these run every frame)
local function report_error(kind, a, b, err)
	local now = os.clock()
	local what = (b ~= nil) and string.format("%s '%s' (%s)", kind, tostring(a), tostring(b)) or string.format("%s '%s'", kind, tostring(a))
	-- only the message (first line) identifies an error, the traceback differs with the call site
	local key = what .. "|" .. tostring(err):match("^[^\n]*"):sub(1, 300)
	local last = last_logged[key]
	if last and now - last < ERROR_LOG_INTERVAL then
		return
	end
	if not last then
		if last_logged_count >= ERROR_LOG_MAX_ENTRIES then
			last_logged = {}
			last_logged_count = 0
		end
		last_logged_count = last_logged_count + 1
	end
	last_logged[key] = now
	BLT:Log(LogLevel.ERROR, string.format("[Hooks] Error in %s: %s", what, tostring(err)))
end

local function finish_safe_call(kind, a, b, ok, ...)
	if not ok then
		report_error(kind, a, b, (...))
	end
	return ok, ...
end

---Calls `func` in protected mode, errors are logged
---@param what string @Description for the log
---@param func function
---@param ... any @Arguments for `func`
---@return boolean @`false` if `func` raised an error
---@return any ... @The return values of `func`
function BLT:SafeCall(what, func, ...)
	return finish_safe_call("call", what, nil, blt.xpcall(func, error_handler, ...))
end

-- calls a hook function protected, returns its return values as a table, or nil if it raised an error
local function call_packed(kind, a, b, func, ...)
	local results = { finish_safe_call(kind, a, b, blt.xpcall(func, error_handler, ...)) }
	if not results[1] then
		return nil
	end
	return { unpack(results, 2, table.maxn(results)) }
end

-- Hooks can be removed while a hook is being called (also by the called function itself),
-- so a removal during a call only marks the entry and the lists are cleaned up afterwards.
local function end_call(self)
	self._call_depth = self._call_depth - 1
	if self._call_depth == 0 and self._compact_pending then
		self._compact_pending = false
		for _, list in pairs(self._registered_hooks) do
			if type(list) == "table" then
				for i = #list, 1, -1 do
					if list[i].removed then
						table.remove(list, i)
					end
				end
			end
		end
	end
end

---Registers a hook so that functions can be added to it, and later called
---@param key string @Unique hook name
function Hooks:RegisterHook(key)
	self._registered_hooks[key] = self._registered_hooks[key] or {}
end

---Registers a hook so that functions can be added to it, and later called
---Functionally the same as `Hooks:RegisterHook`
---@param key string @Unique hook name
function Hooks:Register(key)
	self:RegisterHook(key)
end

---Adds a function call to a hook, so that it will be called when the hook is called
---@param key string @Name of the hook to be called on
---@param id string @Unique name for this specific function call
---@param func function @The function to call with the hook
function Hooks:AddHook(key, id, func)
	self._registered_hooks[key] = self._registered_hooks[key] or {}
	-- Update existing hook
	for k, v in pairs(self._registered_hooks[key]) do
		if v.id == id then
			v.func = func
			v.removed = nil
			return
		end
	end
	-- Add new hook, if id doesn't exist
	local tbl = {
		id = id,
		func = func
	}
	table.insert(self._registered_hooks[key], tbl)
end

---Adds a function call to a hook, so that it will be called when the hook is called
---Functionally the same as `Hooks:AddHook`
---@param key string @Name of the hook to be called on
---@param id string @Unique name for this specific function call
---@param func function @Function to call with the hook
function Hooks:Add(key, id, func)
	self:AddHook(key, id, func)
end

---Removes a hook, so that it will not call any functions
---@param key string @Name of the hook to remove
function Hooks:UnregisterHook(key)
	self._registered_hooks[key] = nil
end

---Removes a hook, so that it will not call any functions
---Functionally the same as `Hooks:UnregisterHook`
---@param key string @Name of the hook to remove
function Hooks:Unregister(key)
	self:UnregisterHook(key)
end

---Removes a hooked function call with the specified id to prevent it from being called
---@param id string @Name of the function call to remove
function Hooks:Remove(id)
	for _, list in pairs(self._registered_hooks) do
		if type(list) == "table" then
			for i = #list, 1, -1 do
				local entry = list[i]
				if entry.id == id then
					if self._call_depth > 0 then
						entry.removed = true
						entry.func = nil
						self._compact_pending = true
					else
						table.remove(list, i)
					end
				end
			end
		end
	end
end

---Calls a specified hook, and all of its hooked functions
---An error in a hooked function is logged and does not stop the other functions
---@param key string @Name of the hook to call
---@param ... any @Arguments to pass to the hooked functions
function Hooks:Call(key, ...)
	local list = self._registered_hooks[key]
	if not list then
		return
	end

	self._call_depth = self._call_depth + 1
	-- functions added while the hook is being called are called as well
	local i = 1
	while true do
		local v = list[i]
		if not v then
			break
		end
		if type(v.func) == "function" then
			finish_safe_call("hook", key, v.id, blt.xpcall(v.func, error_handler, ...))
		end
		i = i + 1
	end
	end_call(self)
end

---Calls a specified hook and returns the first non nil value(s) returned by a hooked function
---An error in a hooked function is logged and does not stop the other functions
---@param key string @Name of the hook to call
---@param ... any @Arguments to pass to the hooked functions
---@return any ... @The value(s) returned by a hooked function
function Hooks:ReturnCall(key, ...)
	local list = self._registered_hooks[key]
	if not list then
		return
	end

	self._call_depth = self._call_depth + 1
	local i = 1
	while true do
		local v = list[i]
		if not v then
			break
		end
		if type(v.func) == "function" then
			local r = call_packed("hook", key, v.id, v.func, ...)
			if r and r[1] ~= nil then
				end_call(self)
				return unpack(r, 1, table.maxn(r))
			end
		end
		i = i + 1
	end
	end_call(self)
end

---Hooks a function to be called before the specified function on a specified object
---If `pre_call` returns anything, it will be used if neither the original function nor any hooks coming after this one return anything
---@param object any @Object for the hooked function to be called on
---@param func string @Name of the function on `object` to run `pre_call` before
---@param id string @Unique name for this prehook
---@param pre_call function @Function to be called before `func` on `object`
function Hooks:PreHook(object, func, id, pre_call)
	if not object or type(object[func]) ~= "function" or type(pre_call) ~= "function" then
		BLT:Log(LogLevel.ERROR, string.format("[Hooks] Could not pre hook function '%s' (%s)", tostring(func), tostring(id)))
		return
	end

	if not self:_ChkCreateTableStructure(object, func) then
		for k, v in pairs(self._function_hooks[object][func].overrides.pre) do
			if v.id == id then
				return
			end
		end
	end

	local func_tbl = {
		id = id,
		func = pre_call
	}
	table.insert(self._function_hooks[object][func].overrides.pre, func_tbl)
end

---Removes a prehook and prevents it from being run
---If `object` is provided, only that object is affected; otherwise all objects are processed.
---@param id string @Name of the prehook to remove
---@param object table? @Object to remove the prehook from
function Hooks:RemovePreHook(id, object)
	for hooked_object_i, hooked_object in pairs(self._function_hooks) do
		if not object or hooked_object_i == object then
			for func_i, func in pairs(hooked_object) do
				for override_i, override in ipairs(func.overrides.pre) do
					if override.id == id then
						table.remove(func.overrides.pre, override_i)
					end
				end
			end
		end
	end
end

---Hooks a function to be called after the specified function on a specified object
---If `post_call` returns anything, it will override the return value(s) of the original function and other hooks coming before this one
---@param object any @Object for the hooked function to be called on
---@param func string @Name of the function on `object` to run `post_call` after
---@param id string @Unique name for this posthook
---@param post_call function @Function to be called after `func` on `object`
function Hooks:PostHook(object, func, id, post_call)
	if not object or type(object[func]) ~= "function" or type(post_call) ~= "function" then
		BLT:Log(LogLevel.ERROR, string.format("[Hooks] Could not post hook function '%s' (%s)", tostring(func), tostring(id)))
		return
	end

	if not self:_ChkCreateTableStructure(object, func) then
		for k, v in pairs(self._function_hooks[object][func].overrides.post) do
			if v.id == id then
				return
			end
		end
	end

	local func_tbl = {
		id = id,
		func = post_call
	}
	table.insert(self._function_hooks[object][func].overrides.post, func_tbl)
end

---Removes a posthook and prevents it from being run
---If `object` is provided, only that object is affected; otherwise all objects are processed.
---@param id string @Name of the posthook to remove
---@param object table? @Object to remove the posthook from
function Hooks:RemovePostHook(id, object)
	for hooked_object_i, hooked_object in pairs(self._function_hooks) do
		if not object or hooked_object_i == object then
			for func_i, func in pairs(hooked_object) do
				for override_i, override in ipairs(func.overrides.post) do
					if override.id == id then
						table.remove(func.overrides.post, override_i)
					end
				end
			end
		end
	end
end

---Overrides a function completely while keeping existing hooks to it intact
---@param object any @Object of the function to override
---@param func string @Name of the function on `object` override
---@param override function @Function to replace the original function `func` with
function Hooks:OverrideFunction(object, func, override)
	if not object or type(override) ~= "function" then
		BLT:Log(LogLevel.ERROR, string.format("[Hooks] Could not override function '%s'", tostring(func)))
		return
	end

	if not self._function_hooks[object] or not self._function_hooks[object][func] then
		object[func] = override
	else
		self._function_hooks[object][func].original = override
	end
end

---Returns the current original function of an object
---@param object any @Object of the function to get
---@param func string @Name of the function on `object` to get
---@return function @Original function `func` of `object`
function Hooks:GetFunction(object, func)
	if not self._function_hooks[object] or not self._function_hooks[object][func] then
		return object[func]
	else
		return self._function_hooks[object][func].original
	end
end

---Returns the return value(s) of the currently running hook
---@return any ... @Any amount of return values of the current hook
function Hooks:GetReturn()
	if self._current_function_hook and self._current_function_hook.returns then
		return unpack(Hooks._current_function_hook.returns)
	end
end

-- Helper to create the hooks table structure and function override
function Hooks:_ChkCreateTableStructure(object, func)
	if self._function_hooks[object] == nil then
		self._function_hooks[object] = {}
	end

	if self._function_hooks[object][func] then
		return
	end

	self._function_hooks[object][func] = {
		original = object[func],
		overrides = {
			pre = {},
			post = {}
		}
	}

	object[func] = function(...)
		local function_hook = self._function_hooks[object][func]
		local hook_return

		-- a call of the same function from within a hook must not touch the returns of this call,
		-- and returns of an earlier call must not leak into this one
		local outer_returns = function_hook.returns
		function_hook.returns = nil

		-- Call prehooks (errors are logged, the other hooks and the original function still run)
		for k, v in ipairs(function_hook.overrides.pre) do
			self._current_function_hook = function_hook
			hook_return = call_packed("prehook of", func, v.id, v.func, ...)
			if hook_return and next(hook_return) then
				function_hook.returns = hook_return
			end
		end

		-- Call original function
		hook_return = { function_hook.original(...) }
		if next(hook_return) then
			function_hook.returns = hook_return
		end

		-- Call posthooks
		for k, v in ipairs(function_hook.overrides.post) do
			self._current_function_hook = function_hook
			hook_return = call_packed("posthook of", func, v.id, v.func, ...)
			if hook_return and next(hook_return) then
				function_hook.returns = hook_return
			end
		end

		hook_return = function_hook.returns
		function_hook.returns = outer_returns

		if hook_return then
			return unpack(hook_return)
		end
	end

	return true
end
