---@class BLTNotificationsManager : BLTModule
---@field new fun(self):BLTNotificationsManager
BLTNotificationsManager = BLTNotificationsManager or blt_class(BLTModule)
BLTNotificationsManager.__type = "BLTNotificationsManager"

function BLTNotificationsManager:init()
	---@diagnostic disable-next-line: undefined-field
	BLTNotificationsManager.super.init(self)

	self._notifications = {}
	self._uid = 1000
end

function BLTNotificationsManager:_get_uid()
	local uid = self._uid
	self._uid = uid + 1
	return uid
end

function BLTNotificationsManager:_get_notification(uid)
	for i, data in ipairs(self._notifications) do
		if data.id == uid then
			return self._notifications[i], i
		end
	end
	return nil, -1
end

---Gets the ordered table of all notifications currently being displayed
---@return table @Table containing notification data
function BLTNotificationsManager:get_notifications()
	return self._notifications
end

---Adds a notification to the manager, and shows it on the notifications UI
---@param parameters table @Table containing data for the notification
---@return number @ID of the added notification
function BLTNotificationsManager:add_notification(parameters)
	-- Create and store the notification
	local id = self:_get_uid()
	local data = {
		id = id,
		title = parameters.title or "No Title",
		text = parameters.text or "",
		icon = parameters.icon,
		icon_texture_rect = parameters.icon_texture_rect,
		color = parameters.color,
		priority = parameters.priority or (id * -1),
		callback = parameters.callback
	}
	table.insert(self._notifications, data)

	-- Add the notification immediately if the gui is visible
	local notifications = managers.menu_component and managers.menu_component:blt_notifications_gui()
	if notifications then
		notifications:add_notification(data)
	end

	return data.id
end

---Removes the notification with the specified ID
---@param uid number @ID of the notification that should be removed
function BLTNotificationsManager:remove_notification(uid)
	-- Remove the notification
	local _, idx = self:_get_notification(uid)
	if idx > 0 then
		table.remove(self._notifications, idx)

		-- Update the ui
		local notifications = managers.menu_component and managers.menu_component:blt_notifications_gui()
		if notifications then
			notifications:remove_notification(uid)
		end
	end
end
