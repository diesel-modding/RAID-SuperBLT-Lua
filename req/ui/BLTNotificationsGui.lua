---@class BLTNotificationsGui
---@field new fun(self, ws, fullscreen_ws, node):BLTNotificationsGui
---@field translate fun(self, string, upper_case)
---@field super table
---@field _root_panel table
BLTNotificationsGui = BLTNotificationsGui or blt_class(RaidGuiBase)
BLTNotificationsGui.BACKGROUND = "backgrounds_chat_bg"
BLTNotificationsGui.DOWNLOADS_ICON = "teammate_interact_fill_large"

local padding = 10

-- a swipe is running, shared by all instances so it must be reset whenever one can no longer finish it
local animating = false

-- Copied from NewHeistsGui
local SPOT_W = 32
local SPOT_H = 8
local BAR_W = 32
local BAR_H = 6
local BAR_X = math.round((SPOT_W - BAR_W) / 2)
local BAR_Y = 0
local TIME_PER_PAGE = 6
local CHANGE_TIME = 0.5

local small_font = BLT.fonts.small.font
local medium_font = BLT.fonts.medium.font
local large_font = BLT.fonts.large.font

local small_font_size = BLT.fonts.small.font_size
local medium_font_size = BLT.fonts.medium.font_size
local large_font_size = BLT.fonts.large.font_size

function BLTNotificationsGui:init(ws, fullscreen_ws, node)
	self._buttons = {}
	self._next_time = Application:time() + TIME_PER_PAGE

	self._current = 0
	self._notifications = {}
	self._notifications_count = 0
	self._uid = 1000

	BLTNotificationsGui.super.init(self, ws, fullscreen_ws, node, "blt_notifications")
	self._root_panel.ctrls = self._root_panel.ctrls or {}
end

function BLTNotificationsGui:_layout()
	self._enabled = true
	animating = false

	-- Get player profile panel
	local profile_panel = managers.menu_component._player_profile_gui and
		managers.menu_component._player_profile_gui._panel

	-- Create panels
	self._object = self._root_panel:panel({
		layer = 50,
		x = profile_panel and profile_panel:x() or 0,
		w = profile_panel and profile_panel:w() or 524,
		h = 128
	})

	self._object:set_bottom(profile_panel and profile_panel:y() or self._root_panel:h() - 90)

	self._content_panel = self._object:panel({
		h = self._object:h() * 0.8
	})

	self._buttons_panel = self._object:panel({
		h = self._object:h() * 0.2
	})
	self._buttons_panel:set_top(self._content_panel:h())

	-- Background
	self._content_panel:bitmap({
		name = "background",
		texture = tweak_data.gui.icons[BLTNotificationsGui.BACKGROUND].texture,
		texture_rect = tweak_data.gui.icons[BLTNotificationsGui.BACKGROUND].texture_rect,
		layer = -1,
		w = self._content_panel:w(),
		h = self._content_panel:h(),
	})

	-- Setup notification buttons
	self._bar = self._buttons_panel:bitmap({
		halign = "grow",
		valign = "grow",
		wrap_mode = "wrap",
		x = BAR_X,
		y = BAR_Y,
		w = BAR_W,
		h = BAR_H
	})
	self:set_bar_width(BAR_W, true)
	self._bar:set_visible(false)

	-- Downloads notification
	self._downloads_panel = self._object:panel({
		name = "downloads",
		w = 48,
		h = 48,
		layer = 100
	})
	self._downloads_panel:bitmap({
		texture = tweak_data.gui.icons[BLTNotificationsGui.DOWNLOADS_ICON].texture,
		texture_rect = tweak_data.gui.icons[BLTNotificationsGui.DOWNLOADS_ICON].texture_rect,
		w = self._downloads_panel:w(),
		h = self._downloads_panel:h(),
		color = tweak_data.gui.colors.raid_gold,
		alpha = 1,
	})
	self._downloads_count = self._downloads_panel:text({
		font_size = medium_font_size,
		font = medium_font,
		layer = 10,
		color = tweak_data.gui.colors.raid_white,
		text = "2",
		align = "center",
		vertical = "center"
	})
	self._downloads_panel:set_visible(false)

	-- Move other panels to fit the downloads notification in nicely
	self._object:set_w(self._object:w() + 24)
	self._object:set_h(self._object:h() + 24)
	self._object:set_top(self._object:top() - 24)
	self._content_panel:set_top(self._content_panel:top() + 24)
	self._buttons_panel:set_top(self._buttons_panel:top() + 24)

	self._downloads_panel:set_right(self._object:w())
	self._downloads_panel:set_top(0)

	-- Add notifications that have already been registered
	for _, notif in ipairs(BLT.Notifications:get_notifications()) do
		self:add_notification(notif)
	end

	-- Check for updates when creating the notification UI as we show the check here
	BLT.Mods:RunAutoCheckForUpdates()
end

function BLTNotificationsGui:_rec_round_object(object)
	local x, y, w, h = object:shape()
	object:set_shape(math.round(x), math.round(y), math.round(w), math.round(h))
	if object.children then
		for i, d in ipairs(object:children()) do
			self:_rec_round_object(d)
		end
	end
end

--------------------------------------------------------------------------------

function BLTNotificationsGui:_get_uid()
	local id = self._uid
	self._uid = self._uid + 1
	return id
end

function BLTNotificationsGui:_get_notification(uid)
	local idx
	for i, data in ipairs(self._notifications) do
		if data.id == uid then
			idx = i
			break
		end
	end
	return self._notifications[idx], idx
end

function BLTNotificationsGui:add_notification(parameters)
	-- Create notification panel
	local new_notif = self._content_panel:panel({}, true)

	local icon_size = math.round(new_notif:h() - padding * 2)
	local icon
	if parameters.icon then
		icon = new_notif:bitmap({
			texture = parameters.icon,
			texture_rect = parameters.icon_texture_rect,
			color = parameters.color or Color.white,
			alpha = parameters.alpha or 1,
			x = padding,
			y = padding,
			w = icon_size,
			h = icon_size
		})
	end

	local _x = math.round((icon and icon:right() or 64) + padding)

	local title = new_notif:text({
		text = parameters.title or "No Title",
		font = small_font,
		font_size = small_font_size,
		x = _x,
		y = padding
	})
	BLT:make_fine_text(title)

	local text = new_notif:text({
		text = parameters.text or "No Text",
		font = small_font,
		font_size = small_font_size,
		x = _x,
		w = new_notif:w() - _x,
		y = math.ceil(title:bottom()),
		h = new_notif:h() - title:bottom(),
		color = tweak_data.gui.colors.raid_white,
		alpha = 0.8,
		wrap = true,
		word_wrap = true
	})

	-- Create notification data
	local data = {
		id = self:_get_uid(),
		priority = parameters.priority or 0,
		callback = parameters.callback,
		parameters = parameters,
		panel = new_notif,
		title = title,
		text = text,
		icon = icon
	}

	-- Update notifications data
	table.insert(self._notifications, data)
	table.sort(self._notifications, function(a, b)
		return a.priority > b.priority
	end)
	self._notifications_count = table.size(self._notifications)

	-- Check notification visibility
	for i, notif in ipairs(self._notifications) do
		notif.panel:set_visible(i == 1)
	end
	self._current = 1

	self:_update_bars()

	return data.id
end

function BLTNotificationsGui:remove_notification(uid)
	local _, idx = self:_get_notification(uid)
	if idx then
		-- the panel of a running swipe may be the one that is removed
		animating = false
		local notif = self._notifications[idx]
		self._content_panel:remove(notif.panel:get_engine_panel())

		table.remove(self._notifications, idx)
		self._notifications_count = table.size(self._notifications)

		-- the shown notification may be gone or the index out of range, show one that exists
		if self._current > self._notifications_count then
			self._current = math.max(self._notifications_count, 1)
		end
		for i, other in ipairs(self._notifications) do
			other.panel:set_visible(i == self._current)
		end

		self:_update_bars()
	end
end

function BLTNotificationsGui:_update_bars()
	-- Remove old buttons
	for i, btn in ipairs(self._buttons) do
		self._buttons_panel:get_engine_panel():remove(btn)
	end
	self._buttons_panel:get_engine_panel():remove(self._bar)

	self._buttons = {}

	-- Add new notifications
	for i = 1, self._notifications_count do
		local page_button = self._buttons_panel:bitmap({
			name = tostring(i),
			w = 32,
			h = 8,
			alpha = 0.25
		})
		page_button:set_x(math.round(((i / (self._notifications_count + 1)) * self._buttons_panel:w() * 0.5 + self._buttons_panel:w() / 4) -
			(page_button:w() * 0.5)))
		page_button:set_y(math.round(((self._buttons_panel:h() - page_button:h()) * 0.5) - (page_button:h() * 0.5)))
		table.insert(self._buttons, page_button)
	end

	-- Add the time bar
	self._bar = self._buttons_panel:bitmap({
		halign = "grow",
		valign = "grow",
		wrap_mode = "wrap",
		x = BAR_X,
		y = BAR_Y,
		w = BAR_W,
		h = BAR_H
	})
	self:set_bar_width(BAR_W, true)
	if #self._buttons > 0 then
		self._bar:set_top(self._buttons[1]:top() + BAR_Y)
		self._bar:set_left(self._buttons[1]:left() + BAR_X)
	else
		self._bar:set_visible(false)
	end
end

--------------------------------------------------------------------------------

function BLTNotificationsGui:set_bar_width(w, random)
	w = w or BAR_W
	self._bar_width = w

	self._bar:set_width(w)

	self._bar_x = not random and self._bar_x or math.random(1, 255)
	self._bar_y = not random and self._bar_y or math.random(0, math.round(self._bar:texture_height() / 2 - 1)) * 2
	local x = self._bar_x
	local y = self._bar_y
	local h = 6
	local mvector_tl = Vector3()
	local mvector_tr = Vector3()
	local mvector_bl = Vector3()
	local mvector_br = Vector3()

	mvector3.set_static(mvector_tl, x, y, 0)
	mvector3.set_static(mvector_tr, x + w, y, 0)
	mvector3.set_static(mvector_bl, x, y + h, 0)
	mvector3.set_static(mvector_br, x + w, y + h, 0)
	self._bar:set_texture_coordinates(mvector_tl, mvector_tr, mvector_bl, mvector_br)
end

-- Animation
function BLTNotificationsGui:_swipe_func(params)
	animating = true
	local speed = params.a:w() / CHANGE_TIME

	params.a:set_visible(true)
	params.b:set_visible(true)

	while params.a and params.b and params.a:right() >= 0 do
		local dt = coroutine.yield()
		params.a:set_x(params.a:x() - dt * speed)
		params.b:set_x(params.a:right())
	end

	params.a:set_x(0)
	params.a:set_visible(false)
	params.b:set_x(0)
	params.b:set_visible(true)

	animating = false
	self._current = params.destination
end

function BLTNotificationsGui:_move_to_notification(destination)
	-- Start swap animation for next notification
	local a = self._notifications[self._current]
	local b = self._notifications[destination]
	if not a or not b or not a.panel or not b.panel then
		return
	end

	-- Stop all animations
	for _, notification in ipairs(self._notifications) do
		if notification.panel then
			notification.panel:stop()
			notification.panel:set_x(0)
			notification.panel:set_visible(false)
		end
	end

	a.panel:animate(callback(self, self, "_swipe_func", {
		a = a.panel,
		b = b.panel,
		destination = destination
	}))

	-- Update bar
	self._bar:set_top(self._buttons[destination]:top() + BAR_Y)
	self._bar:set_left(self._buttons[destination]:left() + BAR_X)
end

function BLTNotificationsGui:_move_notifications(dir)
	if self._notifications_count < 1 then
		self._queued = nil
		return
	end
	self._queued = self._current + dir
	while self._queued > self._notifications_count do
		self._queued = self._queued - self._notifications_count
	end
	while self._queued < 1 do
		self._queued = self._queued + self._notifications_count
	end
end

function BLTNotificationsGui:_next_notification()
	self:_move_notifications(1)
end

function BLTNotificationsGui:update(t, dt)
	-- Update download count
	local pending_downloads_count = table.size(BLT.Downloads:pending_downloads())
	if pending_downloads_count > 0 then
		self._downloads_panel:set_visible(true)
		self._downloads_count:set_text(tostring(pending_downloads_count))
	else
		self._downloads_panel:set_visible(false)
	end

	-- Update notifications
	if self._notifications_count <= 1 then
		return
	end

	self._next_time = self._next_time or t + TIME_PER_PAGE

	if t >= self._next_time then
		self:_next_notification()
		self._next_time = t + TIME_PER_PAGE
	end

	self:set_bar_width(BAR_W * (1 - (self._next_time - t) / TIME_PER_PAGE))

	if not animating and self._queued then
		self:_move_to_notification(self._queued)
		self._queued = nil
	end
end

--------------------------------------------------------------------------------

function BLTNotificationsGui:mouse_moved(o, x, y)
	if not self._enabled then
		return
	end

	if self._downloads_panel and self._downloads_panel:visible() and self._downloads_panel:inside(x, y) then
		return true, "link"
	end

	for i, button in ipairs(self._buttons) do
		if button:inside(x, y) then
			return true, "link"
		end
	end
end

function BLTNotificationsGui:mouse_released(o, btn, x, y)
	if not self._enabled or btn ~= Idstring("0") then
		return
	end

	if self._downloads_panel and self._downloads_panel:visible() and self._downloads_panel:inside(x, y) then
		MenuHelper:OpenMenu("blt_download_manager")
		return true
	end

	if self._content_panel and self._content_panel:inside(x, y) then
		local current = self._notifications[self._current]
		if current and current.callback then
			current.callback(current.id)
		else
			MenuHelper:OpenMenu("blt_mods")
		end
		return true
	end

	for _, button in ipairs(self._buttons) do
		if button:inside(x, y) then
			local i = tonumber(button:name())
			if self._current ~= i then
				self:_move_to_notification(i)
				self._next_time = Application:time() + TIME_PER_PAGE
			end
			return true
		end
	end
end

MenuHelper:AddComponent("blt_notifications", BLTNotificationsGui)

--------------------------------------------------------------------------------
-- Patch main menu to add notifications menu component

Hooks:Add("CoreMenuData.LoadDataMenu", "BLTNotificationsGui.CoreMenuData.LoadDataMenu", function(menu_id, menu)
	if menu_id ~= "start_menu" then
		return
	end

	for _, node in ipairs(menu) do
		if node.name == "main" then
			if node.menu_components then
				node.menu_components = node.menu_components .. " blt_notifications"
			end
		end
	end
end)
