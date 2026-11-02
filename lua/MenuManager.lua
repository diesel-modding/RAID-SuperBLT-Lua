Hooks:RegisterHook("MenuManagerInitialize")
Hooks:RegisterHook("MenuManagerPostInitialize")
Hooks:PostHook(MenuManager, "init", "BLT.MenuManager.init", function(self)
	Hooks:Call("MenuManagerInitialize", self)
	Hooks:Call("MenuManagerPostInitialize", self)
end)

Hooks:RegisterHook("MenuManagerOnOpenMenu")
Hooks:PostHook(MenuManager, "open_menu", "BLT.MenuManager.open_menu", function(self, menu_name, position)
	Hooks:Call("MenuManagerOnOpenMenu", self, menu_name, position)
end)

function MenuManager:show_download_progress(mod_name)
	local dialog_data = {}
	dialog_data.title = managers.localization:text("base_mod_download_downloading_mod", { ["mod_name"] = mod_name })
	dialog_data.mod_name = mod_name or "No Mod Name"

	local ok_button = {}
	ok_button.cancel_button = true
	ok_button.text = managers.localization:text("dialog_ok")

	dialog_data.focus_button = 1
	dialog_data.button_list = {
		ok_button
	}

	managers.system_menu:show_download_progress(dialog_data)
end

-- Create this function if it doesn't exist
function MenuCallbackHandler:can_toggle_chat()
	if managers and managers.menu then
		local input = managers.menu:active_menu() and managers.menu:active_menu().input
		return not input or input.can_toggle_chat and input:can_toggle_chat()
	else
		return true
	end
end

---@deprecated Use RaidMenuHelper:RegisterMenu(menu)
function MenuManager:register_menu_new(menu)
	RaidMenuHelper:RegisterMenu(menu)
end

--------------------------------------------------------------------------------
-- Add BLT save function

Hooks:Register("BLTOnSaveData")
function MenuCallbackHandler:perform_blt_save()
	BLT:Log(LogLevel.INFO, "[BLT] Performing save...")

	Hooks:Call("BLTOnSaveData", BLT.save_data)

	local success = io.save_as_json(BLT.save_data, BLTModManager.Constants:ModManagerSaveFile())
	if not success then
		BLT:Log(LogLevel.ERROR, "[BLT] Could not save file " .. BLTModManager.Constants:ModManagerSaveFile())
	end
end

function MenuCallbackHandler:close_blt_mods()
	managers.menu_component:close_blt_mods_gui()
end

function MenuCallbackHandler:close_blt_download_manager()
	managers.menu_component:close_blt_download_manager_gui()
end

--------------------------------------------------------------------------------
-- Add BLT dll update notification

function MenuCallbackHandler:blt_update_dll_dialog(update)
	QuickMenu:new(
		managers.localization:text("blt_update_dll_title"),
		managers.localization:text("blt_update_dll_text"),
		{
			{
				text = managers.localization:text("blt_update_dll_goto_website"),
				callback = callback(self, self, "clbk_goto_paydaymods_download", update:GetUpdateMiscData().update_url)
			},
			{
				text = managers.localization:text("blt_update_later"),
				is_cancel_button = true
			}
		}
		,
		true
	)
end

function MenuCallbackHandler:clbk_goto_paydaymods_download(update_url)
	Utils.OpenUrl(update_url)
end

--------------------------------------------------------------------------------
-- Add visibility callback for showing keybinds

function MenuCallbackHandler:blt_show_keybinds_item()
	return BLT.Keybinds and BLT.Keybinds:has_menu_keybinds()
end

--------------------------------------------------------------------------------
-- Add settings callbacks

function MenuCallbackHandler:blt_choose_log_level(item)
	BLTLogs.log_level = math.clamp(item:value(), _G.LogLevel.NONE, _G.LogLevel.ALL)
end

function MenuCallbackHandler:blt_choose_log_lifetime(item)
	BLTLogs.lifetime = item:value()
end
