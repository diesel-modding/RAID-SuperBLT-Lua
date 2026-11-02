DelayedCalls = DelayedCalls or {}
DelayedCalls._calls = DelayedCalls._calls or {}
DelayedCalls._remove_queue = DelayedCalls._remove_queue or {}

Hooks:Add("MenuUpdate", "MenuUpdate_Queue", function(t, dt)
	DelayedCalls:Update(t, dt)
end)

Hooks:Add("GameSetupUpdate", "GameSetupUpdate_Queue", function(t, dt)
	DelayedCalls:Update(t, dt)
end)

function DelayedCalls:Update(time, deltaTime)
	local calls = self._calls
	self._calls = {}

	for k, v in pairs(calls) do
		v.currentTime = v.currentTime + deltaTime
		if self._remove_queue[k] then
			-- Remove call if it has been queued for removal
			self._remove_queue[k] = nil
		elseif v.currentTime > v.timeToWait then
			if v.functionCall then
				-- an error must not drop the calls that are still waiting in this update
				BLT:SafeCall("DelayedCall '" .. tostring(k) .. "'", v.functionCall)
			end
		else
			-- If a call with that id already exists, it has been added during call iteration
			-- If that is the case, prefer the existing one (new call overrides old)
			self._calls[k] = self._calls[k] or v
		end
	end
end

---Adds a function to be automatically called after a set delay
---If a call with the same id already exists, it will be replaced
---@param id string @Unique name for this delayed call
---@param time number @Time in seconds to call the specified function after
---@param func function @Function to call after the time runs out
function DelayedCalls:Add(id, time, func)
	local queuedFunc = {
		functionCall = func,
		timeToWait = time,
		currentTime = 0
	}
	self._remove_queue[id] = nil -- fix: prevents newly added call from instantly getting deleted, if it WAS queued just before adding a new one
	self._calls[id] = queuedFunc
end

---Removes a scheduled call that hasn't been called yet
---@param id string @Name of the delayed call to remove
function DelayedCalls:Remove(id)
	self._remove_queue[id] = true
end
