Hooks:RegisterHook("CustomizeControllerOnKeySet")

local function active_node_gui()
	local menu = managers.menu:active_menu()
	return menu and menu.renderer and menu.renderer:active_node_gui()
end

Hooks:PostHook(RaidGuiControlKeyBind, "activate_customize_controller", "BLT.RaidGuiControlKeyBind.activate_customize_controller", function(self)
	self._skip_first_activate_key = true

	-- NOTE: This isn't the prettiest way to do this, but there's no easy way to check
	-- if we're binding a key otherwise...
	local node_gui = active_node_gui()
	if node_gui then
		node_gui._listening_to_input = true
	end
end)

RaidGuiControlKeyBind._blt_orig_key_press = RaidGuiControlKeyBind._key_press

function RaidGuiControlKeyBind:_key_press(text, key, input_id, ...)
	if not self._params.is_blt then -- use normal for non blt keybinds.
		return RaidGuiControlKeyBind._blt_orig_key_press(self, text, key, input_id, ...)
	end
	
	if managers.system_menu:is_active() then
		return
	end

	if self._skip_first_activate_key then
		self._skip_first_activate_key = false
		if input_id == "mouse" then
			if key == Idstring("0") then
				return
			end
		elseif input_id == "keyboard" and key == Idstring("enter") then
			return
		end
	end

	if key == Idstring("esc") then
		self:_end_customize_controller(text, true)
		return
	end

	local key_name = "" .. (input_id == "mouse" and Input:mouse():button_name_str(key) or Input:keyboard():button_name_str(key))
	if input_id == "mouse" then
		key_name = "mouse " .. key_name or key_name
	end

	local forbidden_btns = {
		"esc",
		"tab",
		"num abnt c1",
		"num abnt c2",
		"@",
		"ax",
		"convert",
		"kana",
		"kanji",
		"no convert",
		"oem 102",
		"stop",
		"unlabeled",
		"yen",
		"mouse 8",
		"mouse 9",
		""
	}

	if not key_name:is_nil_or_empty() then
		for _, btn in ipairs(forbidden_btns) do
			if Idstring(btn) == key then
				managers.menu:show_key_binding_forbidden({KEY = key_name})
				self:_end_customize_controller(text, true)
				return
			end
		end
	end

	local button_data = RaidMenuOptionsControlsKeybinds.CONTROLS_INFO[self._keybind_params.button]
	if not button_data then
		button_data = {
			text_id = "",
			category = "normal"
		}
	end

	local button_category = button_data.category
	local connections = managers.controller:get_settings(managers.controller:get_default_wrapper_type()):get_connection_map()
	for _, name in ipairs(RaidMenuOptionsControlsKeybinds.controls_info_by_category(button_category)) do
		local connection = connections[name]
		if connection._btn_connections then
			for _, btn_connection in pairs(connection._btn_connections) do
				if btn_connection.name == key_name and self._keybind_params.binding ~= btn_connection.name then
					managers.menu:show_key_binding_collision({
						KEY = key_name,
						MAPPED = managers.localization:text(RaidMenuOptionsControlsKeybinds.CONTROLS_INFO[name].text_id)
					})
					self:_end_customize_controller(text)
					return
				end
			end
		else
			for _, b_name in ipairs(connection:get_input_name_list()) do
				if tostring(b_name) == key_name and self._keybind_params.binding ~= b_name then
					managers.menu:show_key_binding_collision({
						KEY = key_name,
						MAPPED = managers.localization:text(RaidMenuOptionsControlsKeybinds.CONTROLS_INFO[name].text_id)
					})
					self:_end_customize_controller(text)
					return
				end
			end
		end
	end

	local connection = nil
	if self._keybind_params.axis then
		connections[self._keybind_params.axis]._btn_connections[self._keybind_params.button].name = key_name
		managers.controller:set_user_mod(self._keybind_params.connection_name, {
			axis = self._keybind_params.axis,
			button = self._keybind_params.button,
			connection = key_name
		})
		self._keybind_params.binding = key_name
		connection = connections[self._keybind_params.axis]
	else
		if connections[self._keybind_params.button] == nil then
			for k, v in pairs(connections) do
				connections[self._keybind_params.button] = clone(v)
				break
			end
			connections[self._keybind_params.button]._name = self._keybind_params.connection_name
		end

		connections[self._keybind_params.button]:set_controller_id(input_id)
		connections[self._keybind_params.button]:set_input_name_list({key_name})
		managers.controller:set_user_mod(self._keybind_params.connection_name, {
			button = self._keybind_params.button,
			connection = key_name,
			controller_id = input_id
		})
		self._keybind_params.binding = key_name
		connection = connections[self._keybind_params.button]
	end

	if connection then
		local key_button = self._keybind_params.binding
		if self._keybind_params.callback then
			self._keybind_params.callback(key_button, self)
		else
			Hooks:Call("CustomizeControllerOnKeySet", self._keybind_params.connection_name, key_button)
		end
	end

	managers.controller:rebind_connections()
	self:_end_customize_controller(text)
end

Hooks:PreHook(RaidGuiControlKeyBind, "_end_customize_controller", "BLT.RaidGuiControlKeyBind._end_customize_controller", function()
	local node_gui = active_node_gui()
	if node_gui then
		node_gui._listening_to_input = false
	end
end)