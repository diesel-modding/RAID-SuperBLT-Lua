-- Only run if we have the global table
if not _G then
	return
end

-- Localise globals
---@class _G
local _G = _G
local io = io
local file = file

-- Log levels
LogLevel = {
	NONE = 0,
	ERROR = 1,
	WARN = 2,
	INFO = 3,
	ALL = 4
}

LogLevelPrefix = {
	[LogLevel.ERROR] = "[ERROR]",
	[LogLevel.WARN] = "[WARN]",
	[LogLevel.INFO] = "[INFO]"
}

-- BLT Global table
BLT = { 
	version = 2.0,
	base_version = nil
}
BLT.Base = {}

-- BLT fonts table
BLT.fonts = {
	small = { font = "ui/fonts/pf_din_text_comp_pro_medium_20_mf", font_size = 20 },
	medium = { font = "ui/fonts/pf_din_text_comp_pro_medium_26_mf", font_size = 26 },
	large = { font = "ui/fonts/pf_din_text_comp_pro_medium_32_mf", font_size = 32 },
	massive = { font = "ui/fonts/pf_din_text_comp_pro_medium_66_mf", font_size = 66 } -- raid has no massive in tweak_data.gui, used title which is 66
}

-- Load modules
BLT._PATH = "mods/base/"
function BLT:Require(path)
	dofile(string.format("%s%s", BLT._PATH, path .. ".lua"))
end

BLT:Require("req/utils/UtilsClass")
BLT:Require("req/utils/UtilsCore")
BLT:Require("req/utils/UtilsIO")
BLT:Require("req/utils/json-1.0")
BLT:Require("req/utils/json-0.9")
BLT:Require("req/utils/json")
BLT:Require("req/core/Hooks")
BLT:Require("req/BLTMod")
BLT:Require("req/BLTUpdate")
BLT:Require("req/BLTUpdateCallbacks")
BLT:Require("req/BLTModDependency")
BLT:Require("req/BLTModule")
BLT:Require("req/BLTLogs")
BLT:Require("req/BLTModManager")
BLT:Require("req/BLTDownloadManager")
BLT:Require("req/BLTNotificationsManager")
BLT:Require("req/BLTPersistScripts")
BLT:Require("req/BLTKeybindsManager")
BLT:Require("req/BLTAssetManager")

---Writes a message to the log file
---Multiple arguments can be passed to the function and will be concatenated
---@param level integer @The log level of the message
---@param ... any @The message to log
function BLT:Log(level, ...)
	if level > BLTLogs.log_level then
		return
	end

	local out = {LogLevelPrefix[level] or "", ...}
	local n = select("#", ...) -- allow nil holes
	-- skip prefix, allow for n=0
	for i = 2, n+1, 1 do
		out[i] = tostring(out[i])
	end
	log(table.concat(out, " "))
end

-- BLT base functions
function BLT:Initialize()
	-- Create hook tables
	self.hook_tables = {
		pre = {},
		post = {},
		wildcards = {}
	}

	-- Override require and setup self
	self:OverrideRequire()

	self:Setup()
end

function BLT:Setup()
	-- Load saved data
	if not self.save_data then
		local save_file = BLTModManager.Constants:ModManagerSaveFile()
		self.save_data = io.file_is_readable(save_file) and io.load_as_json(save_file) or {}
	end

	-- Setup modules
	self.Logs = BLTLogs:new()
	self.Mods = BLTModManager:new()
	self.Downloads = BLTDownloadManager:new()
	self.Keybinds = BLTKeybindsManager:new()
	self.PersistScripts = BLTPersistScripts:new()
	self.Notifications = BLTNotificationsManager:new()
	self.AssetManager = BLTAssetManager:new()

	-- Create the required base directories, if necessary
	self:CheckDirectory(BLTModManager.Constants:DownloadsDirectory())
	self:CheckDirectory(BLTModManager.Constants:LogsDirectory())
	self:CheckDirectory(BLTModManager.Constants:SavesDirectory())

	-- save blt base version
	local xml_file = io.open(BLT._PATH .. "supermod.xml")
	if xml_file then
		local content = xml_file:read("*all")
		xml_file:close()
		local xml = blt.parsexml(content)
		self.base_version = xml.params.version
	end

	-- Initialization functions
	self.Logs:CleanLogs()
	self.Mods:SetModsList(self:ProcessModsList(self:FindMods()))

	-- Some backwards compatibility for v1 mods
	local C = self.Mods.Constants
	LuaModManager = {}
	LuaModManager.Constants = C
	LuaModManager.Mods = {} -- No mods are available via old api
	rawset(_G, C.logs_path_global, C.mods_directory .. C.logs_directory)
	rawset(_G, C.save_path_global, C.mods_directory .. C.saves_directory)
end

---Returns the version of BLT
---@return string @The version of BLT
function BLT:GetVersion()
	return tostring(self.version)
end

function BLT:GetBaseVersion()
	return tostring(self.base_version)
end

---Returns the operating system that the game is running on
---@return '"windows"'|'"linux"' @The operating system
function BLT:GetOS()
	local info = blt.blt_info()
	if not info then
		return "windows"
	end
	return info.platform == "mswindows" and "windows" or "linux"
end

---Returns the current running game
---@return '"raid"' @The game
function BLT:GetGame()
	return blt.blt_info().game
end

function BLT:RunHookTable(hooks_table, path)
	if not hooks_table or not hooks_table[path] then
		return false
	end
	for i, hook_data in pairs(hooks_table[path]) do
		self:RunHookFile(path, hook_data)
	end
end

function BLT:SetModGlobals(mod)
	rawset(_G, BLTModManager.Constants.mod_path_global, mod and mod:GetPath() or false)
	rawset(_G, BLTModManager.Constants.mod_instance_global, mod or false)
end

function BLT:RunHookFile(path, hook_data)
	if not hook_data.game or hook_data.game == self:GetGame() then
		rawset(_G, BLTModManager.Constants.required_script_global, path or false)
		self:SetModGlobals(hook_data.mod)
		dofile(hook_data.mod:GetPath() .. hook_data.script)
	end
end

function BLT:OverrideRequire()
	if self.require then
		return false
	end

	-- Cache original require function
	self.require = _G.require

	-- Override require function to run hooks
	_G.require = function(...)
		local args = { ... }
		local path = args[1]
		local path_lower = path:lower()
		local require_result = nil

		rawset(_G, BLTModManager.Constants.required_script_type_global, "PreHook")
		self:RunHookTable(self.hook_tables.pre, path_lower)
		require_result = self.require(...)
		rawset(_G, BLTModManager.Constants.required_script_type_global, "PostHook")
		self:RunHookTable(self.hook_tables.post, path_lower)

		for k, v in ipairs(self.hook_tables.wildcards) do
			self:RunHookFile(path, v)
		end

		return require_result
	end
end

function BLT:FindMods()
	-- Get all folders in mods directory
	local mods_list = {}
	local mods_directory = BLTModManager.Constants.mods_directory
	local folders = file.GetDirectories(mods_directory)

	-- If we didn't get any folders then return an empty mods list
	if not folders then
		return {}
	end

	for _, directory in pairs(folders) do
		-- Check if this directory is excluded from being checked for mods (logs, saves, etc.)
		if not self.Mods:IsExcludedDirectory(directory) then
			local mod_path = mods_directory .. directory .. "/"
			-- If either mod.txt or supermod.xml exists, attempt to load
			if file.FileExists(mod_path .. "mod.txt") or file.FileExists(mod_path .. "supermod.xml") then
				local new_mod, valid = BLTMod:new(directory, nil, mod_path)
				if valid then
					table.insert(mods_list, new_mod)
				else
					self:Log(LogLevel.ERROR, "[BLT] Attempted to load mod.txt or supermod.xml, mod is invalid." .. tostring(mod_path))
				end
			end
		end
	end

	return mods_list
end

function BLT:ProcessModsList(mods_list)
	-- Prioritize mod load order
	table.sort(mods_list, function(a, b)
		return a:GetPriority() > b:GetPriority()
	end)

	return mods_list
end

function BLT:CheckDirectory(path)
	path = path:sub(1, #path - 1)
	if not file.DirectoryExists(path) then
		self:Log(LogLevel.INFO, "[BLT] Creating missing directory " .. path)
		file.CreateDirectory(path)
	end
end

function BLT:ToVersionTable(version)
	local vt = {}
	for num in version:gmatch("%d+") do
		table.insert(vt, tonumber(num))
	end
	return vt
end

-- returns 1 if version 1 is newer, 2 if version 2 is newer, or 0 if versions are equal.
function BLT:CompareVersions(version1, version2)
	local v1 = self:ToVersionTable(tostring(version1))
	local v2 = self:ToVersionTable(tostring(version2))
	for i = 1, math.max(#v1, #v2) do
		local num1 = v1[i] or 0
		local num2 = v2[i] or 0
		if num1 > num2 then
			return 1
		elseif num1 < num2 then
			return 2
		end
	end
	return 0
end

function BLT:CheckUpdatesReluaPossible(downloads)
	for _, update in ipairs(downloads) do
		if update.update.HasAssets ~= nil and update.update:HasAssets() == true then -- check if asset module is used
			return false
		end

	end
	return true
end

function BLT:make_fine_text(text)
	if not alive(text) then
		return
	end
	local _, _, w, h = text:text_rect()
	text:set_size(w, h)
	text:set_position(math.round(text:x()), math.round(text:y()))
	return text:x(), text:y(), w, h
end

function BLT:make_fine_text_aligning(text)
	-- Make fine text, but use the text rect X and Y in set_position
	if not alive(text) then
		return
	end
	local x, y, w, h = text:text_rect()
	text:set_size(w, h)
	text:set_position(math.round(x), math.round(y))
	return x, y, w, h
end

-- Perform startup
BLT:Initialize()
