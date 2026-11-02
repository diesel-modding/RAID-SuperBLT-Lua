--Doesn't exist on Raid so we are adding it manually
_next_update_funcs = _next_update_funcs or {}
function call_on_next_update(func, optional_key)
	if not optional_key then
		table.insert(_next_update_funcs, func)
	else
		local key = optional_key == true and func or optional_key
		_next_update_funcs[key] = func
	end
end

function call_next_update_functions()
	local current = _next_update_funcs
	_next_update_funcs = {}

	for key, func in pairs(current) do
		-- an error must not drop the functions that are still queued
		BLT:SafeCall("call_on_next_update '" .. tostring(key) .. "'", func)
	end
end

Hooks:PostHook(Setup, "update", "BLTSetupUpdate", function(self)
	call_next_update_functions()
end)