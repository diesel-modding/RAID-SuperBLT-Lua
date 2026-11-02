---@class BLTMod
---@field new fun(self, identifier: string, data?: table, path: string):BLTMod, boolean
BLTMod = blt_class()

BLT:Require("req/ModAssetLoader")

BLTMod.enabled = true
BLTMod._enabled = true
BLTMod.safe_mode = true
BLTMod._tags = {
	updates = "init",
	dependencies = "init",
	localization = "init",
	hooks = "setup",
	assets = "setup",
	persist_scripts = "setup",
	keybinds = "setup",
	scripts = "post_init",
	native_module = "setup",
	wren = "",
	tweak = "",
}

function BLTMod:init(identifier, data, path)
	if not identifier or not path then
		return false
	end

	self._errors = {}
	self._legacy_updates = {}
	self._setup_callbacks = {}

	-- Default values
	self.id = identifier
	self.name = "Unnamed BLT Mod"
	self.desc = "No description"
	self.version = "1.0"
	self.author = "Unknown"
	self.contact = "N/A"
	self.priority = 0
	self.dependencies = {}
	self.default_language = "english"
	self.localizations = {}
	self.image_path = nil
	self.disable_safe_mode = false
	self.undisablable = false
	self.library = false
	self.min_sblt_version = nil

	self.path = path
	self.data = data
	self.json_data = data

	self.updates = {}
	self.hooks = {}

	-- Attempt to load JSON or XML
	self:LoadData()
	self:LoadXML()

	self._supermod = self

	return self.data ~= nil or self._xml_data ~= nil
end

--- Let's you add your own custom tags (make sure to add them early on via scripts tag and high enough priority)
--- If string is given, the tag will load on that event on the BLTMod class. Leave empty to only register the tag (Like wren tags)
--- The current events: 
--- init - When the XML is first loaded. You must handle enabled state! 
--- post_init - After init, runs only if enabled.
--- setup - When the mod gets setup. The mod is enabled by then.
--- If you wish to run a callback function instead, define it as a table as shown on the prop doc
--- callback - Runs on both table and XML data, data_callback - Runs on table only, xml_callback - Runs on XML only
--- If not defined, it will try to look up on BLTMod class - LoadTagXML, LoadTagData, LoadTagShared
--- @param options string|{ event: string, callback: function, data_callback: function, xml_callback: function }
function BLTMod.AddTag(name, options)
	BLTMod._tags[name] = options
end

function BLTMod:LoadData()
	if not self.data then -- If no data, try loading the json file
		local mod_path = self:GetPath()
		local json_file = io.open(mod_path .. "mod.txt")

		if json_file then
			local file_contents = json_file:read("*all")
			json_file:close()
			if file_contents then
				local data = json.decode(file_contents)
				if not data then
					BLT:Log(LogLevel.ERROR, "[BLT] An error occured while loading mod.txt from: " .. tostring(mod_path))
					return
				end

				--- Data doesn't have to be JSON so the name doesn't make sense
				---@deprecated
				self.json_data = data
				self.data = data
			end
		end
	end

	if not self.data then
		return
	end

	self:SetParams(self.data)

	for tag, v in pairs(self._tags) do
		local tag_data = self.data[tag]
		if tag_data then
			local clbk = type(v) == "table" and v.callback or self["_load_"..tag.."_data"] or self["_load_"..tag]
			if clbk and (v == "init" or (type(v) == "table" and v.event == "init")) then
				clbk(self, tag_data)
			end
		end
	end
end

function BLTMod:LoadXML()
	local mod_path = self:GetPath()
	local supermod_path = mod_path .. (self.data and self.data.supermod_definition or "supermod.xml")

	-- Attempt to read the mod definition file
	local file = io.open(supermod_path)
	if file then

		-- Read the file contents
		local file_contents = file:read("*all")
		file:close()

		-- Parse it
		local xml = blt.parsexml(file_contents)
		if not xml then
			BLT:Log(LogLevel.ERROR, "[BLT] An error occured while loading supermod.xml from: " .. tostring(mod_path))
			return
		end

		self:SetParams(xml.params)

		xml._doc = { filename = supermod_path }

		if self:IsEnabled() then
			self._assets = BLTMod.AssetLoader:new(self)
		end

		Utils.IO.ReplaceIncludesInXML(xml, self.path)

		local load_tags = {}

		for tag, v in pairs(self._tags) do
			if v == "init" or (type(v) == "table" and v.event == "init") then
				local clbk = type(v) == "table" and v.xml_callback or self["_load_"..tag.."_xml"] or self["_load_"..tag]
				if clbk then
					load_tags[tag] = function(scope, _tag)
						clbk(self, scope, _tag)
					end
				end
			end
		end

		Utils.IO.TraverseXML(xml, {}, load_tags, true)

		self._xml_data = xml
	end
end

--- Called once the mod has been loaded with its data. Used to load tags with enabled check.
function BLTMod:PostInit()
	-- The mod isn't enabled for the current platform
	-- Check dependencies are installed for this mod
	if not self:AreDependenciesInstalled() then
		table.insert(self._errors, "blt_mod_missing_dependencies")
		self:RetrieveDependencies()
		self:SetEnabled(false, true)
	end

	if self.min_sblt_version and BLT:CompareVersions(BLT:GetBaseVersion(), self.min_sblt_version) == 2 then
		table.insert(self._errors, "blt_mod_info_min_sblt_ver_not_met")
		self:SetEnabled(false, true)
	end

	if not self:IsEnabled() then
		return
	end

	local xml = self._xml_data
	local load_tags = {}
	for tag, v in pairs(self._tags) do
		local tag_data = self.data and self.data[tag]

		local xml_clbk = type(v) == "table" and v.xml_callback or self["_load_"..tag.."_xml"] or self["_load_"..tag]
		local data_clbk = type(v) == "table" and v.data_callback or self["_load_"..tag.."_data"] or self["_load_"..tag]

		local event = type(v) == "table" and v.event or v

		if event ~= "post_init" then
			load_tags[tag] = function() end
		end

		if event == "post_init" then
			if xml_clbk then
				load_tags[tag] = function(scope, _tag)
					xml_clbk(self, scope, _tag)
				end
			end
			if data_clbk and tag_data then
				data_clbk(self, tag_data)
			end
		elseif event == "setup" then  -- Load them later in :Setup
			if xml_clbk then
				load_tags[tag] = function(scope, _tag)
					table.insert(self._setup_callbacks, function()
						xml_clbk(self, scope, _tag)
					end)
				end
			end
			if data_clbk and tag_data then
				table.insert(self._setup_callbacks, function()
					data_clbk(self, tag_data)
				end)
			end
		end
	end

	if xml then
		Utils.IO.TraverseXML(xml, {}, load_tags)
	end
end

-- XML attributes are strings, "false" would count as true
local function to_bool(v)
	if type(v) == "string" then
		v = v:lower()
		return not (v == "" or v == "false" or v == "0" or v == "no")
	end
	return v
end

function BLTMod:SetParams(data)
	local merge = {
		name = data.name,
		desc = data.description,
		version = data.version,
		author = data.author,
		contact = data.contact ,
		priority = tonumber(data.priority),
		color = data.color,
		image_path = data.image,
		disable_safe_mode = to_bool(data.disable_safe_mode),
		undisablable = to_bool(data.undisablable),
		library = to_bool(data.is_library),
		min_sblt_version = data.min_sblt_version
	}

	for k, v in pairs(merge) do
		self[k] = Utils:FirstNonNil(v, merge[k])
	end
end

function BLTMod:Setup()
	if self:IsEnabled() then
		BLT:Log(LogLevel.INFO, string.format("[BLT] Setting up mod '%s'", self:GetName()))
		for _, clbk in pairs(self._setup_callbacks) do
			clbk()
		end
	end
end

function BLTMod:AddKeybind(data)
	BLT.Keybinds:register_keybind_json(self, data)
end

function BLTMod:AddUpdate(data)
	local new_update, valid = BLTUpdate:new(self, data)
	if valid and new_update:IsPresent() then
		table.insert(self.updates, new_update)
	end
end

function BLTMod:AddDependency(id, data)
	local new_dependency, valid = BLTModDependency:new(self, id, data)
	if valid then
		if not self.dependencies[id] then
			self.dependencies[id] = new_dependency
		else
			self.dependencies[id]:merge(new_dependency)
		end
	end
end

function BLTMod:AddHooks(data_key, destination, wildcards_destination)
	for _, hook_data in ipairs(self.data[data_key] or {}) do
		local hook_id = hook_data.hook_id and hook_data.hook_id:lower()
		local script = hook_data.script_path
		local game = hook_data.game

		self:AddHook(data_key, hook_id, script, destination, wildcards_destination, game)
	end
end

function BLTMod:AddHook(data_key, hook_id, script, destination, wildcards_destination, game)
	self.hooks[data_key] = self.hooks[data_key] or {}
	hook_id = hook_id and hook_id:lower() -- the require override looks hooks up in lower case

	-- Add hook to info table
	local unique = true
	for i, hook in ipairs(self.hooks[data_key]) do
		if hook == hook_id then
			unique = false
			break
		end
	end
	if unique then
		table.insert(self.hooks[data_key], hook_id)
	end

	-- Add hook to hooks tables
	if hook_id and script and self:IsEnabled() then
		local data = {
			mod = self,
			script = script,
			game = game
		}

		if hook_id ~= "*" then
			destination[hook_id] = destination[hook_id] or {}
			table.insert(destination[hook_id], data)
		else
			table.insert(wildcards_destination, data)
		end
	end
end

function BLTMod:AddPersistScript(global, file)
	self._persists = self._persists or {}
	table.insert(self._persists, {
		global = global,
		file = file
	})
end

function BLTMod:GetHooks()
	return (self.hooks or {}).hooks
end

function BLTMod:GetPreHooks()
	return (self.hooks or {}).pre_hooks
end

function BLTMod:GetPersistScripts()
	return self._persists or {}
end

function BLTMod:Errors()
	if #self._errors > 0 then
		return self._errors
	else
		return false
	end
end

function BLTMod:LastError()
	local n = #self._errors
	if n > 0 then
		return self._errors[n]
	else
		return false
	end
end

function BLTMod:IsOutdated()
	return self._outdated -- FIXME: _outdated is never set! implement min_sblt_version as in RaidBLT?
end

function BLTMod:IsEnabled()
	return self.enabled
end

function BLTMod:WasEnabledAtStart()
	return self._enabled
end

function BLTMod:SetEnabled(enable, force)
	self.enabled = self:IsUndisablable() or enable
	if force then
		self._enabled = self.enabled
	end
end

function BLTMod:GetPath()
	return self.path
end

function BLTMod:GetDir()
	-- Strip mod folder name from path
	local dir = self:GetPath():gsub("[^/\\]+[/\\]$", "")
	return dir
end

--- @deprecated
function BLTMod:GetJsonData()
	return self.json_data
end

function BLTMod:GetId()
	return self.id
end

function BLTMod:GetName()
	return self.name
end

function BLTMod:GetDescription()
	return self.desc
end

function BLTMod:GetVersion()
	return self.version
end

function BLTMod:GetAuthor()
	return self.author
end

function BLTMod:GetContact()
	return self.contact
end

---Returns the first web address in the contact, or `nil`
---The result is safe to hand to a shell (see `Utils.IsSafeUrl`)
---@return string?
function BLTMod:GetContactUrl()
	return self.contact and string.match(self.contact, "https?://[^%s\"<>|^`]+") or nil
end

function BLTMod:IsContactWebsite()
	return self:GetContactUrl() ~= nil
end

function BLTMod:GetPriority()
	return self.priority
end

function BLTMod:GetMinSBLTVer()
	return self.min_sblt_version
end

function BLTMod:GetColor()
	if not self.color then
		return tweak_data.screen_colors.button_stage_3
	end

	-- Delay evaluation of color until first call
	if type(self.color) == "string" then
		local r, g, b = self.color:match("([.0-9]+)%s+([.0-9]+)%s+([.0-9]+)")
		r = tonumber(r) or 0
		g = tonumber(g) or 0
		b = tonumber(b) or 0
		if r > 1 or g > 1 or b > 1 then
			r = r / 255
			g = g / 255
			b = b / 255
		end
		self.color = Color(r, g, b)
	end

	return self.color
end

function BLTMod:HasModImage()
	return self.image_path ~= nil
end

function BLTMod:GetModImagePath()
	return self:GetPath() .. tostring(self.image_path)
end

function BLTMod:GetModImage()
	if self.mod_image_id then
		return self.mod_image_id
	end

	if not self:HasModImage() or not DB or not DB.create_entry then
		return nil
	end

	-- Check if the file exists on disk and generate if it does
	if file.FileExists(Application:nice_path(self:GetModImagePath())) then
		local type_texture_id = Idstring("texture")
		local path = self:GetModImagePath()
		local texture_id = Idstring(path)

		DB:create_entry(type_texture_id, texture_id, path)

		self.mod_image_id = texture_id

		return texture_id
	else
		BLT:Log(LogLevel.WARN, string.format("Mod image '%s' does not exist", tostring(self:GetModImagePath())))
		return nil
	end
end

function BLTMod:HasUpdates()
	return table.size(self:GetUpdates()) > 0
end

function BLTMod:GetUpdates()
	return self.updates or {}
end

function BLTMod:GetUpdate(id)
	for _, update in ipairs(self:GetUpdates()) do
		if update:GetId() == id then
			return update
		end
	end
end

function BLTMod:HasLegacyUpdate(id)
	return self._legacy_updates[id]
end

function BLTMod:AreUpdatesEnabled()
	for _, update in ipairs(self:GetUpdates()) do
		if not update:IsEnabled() then
			return false
		end
	end
	return true
end

function BLTMod:SetUpdatesEnabled(enable)
	for _, update in ipairs(self:GetUpdates()) do
		update:SetEnabled(enable)
	end
end

function BLTMod:CheckForUpdates(clbk)
	self._update_cache = self._update_cache or {}
	self._update_cache.clbk = clbk

	for _, update in ipairs(self:GetUpdates()) do
		update:CheckForUpdates(callback(self, self, "clbk_check_for_updates"))
	end
end

function BLTMod:IsCheckingForUpdates()
	for _, update in ipairs(self.updates) do
		if update:IsCheckingForUpdates() then
			return true
		end
	end
	return false
end

function BLTMod:GetUpdateError()
	for _, update in ipairs(self:GetUpdates()) do
		if update:GetError() then
			return update:GetError(), update
		end
	end
	return false
end

function BLTMod:clbk_check_for_updates(update, required, reason)
	self._update_cache = self._update_cache or {}
	self._update_cache[update:GetId()] = {
		requires_update = required,
		reason = reason,
		update = update,
		mod = update:GetParentMod(),
	}

	if self._update_cache.clbk and not self:IsCheckingForUpdates() then
		local clbk = self._update_cache.clbk
		self._update_cache.clbk = nil
		clbk(self._update_cache)
	end
end

function BLTMod:IsSafeModeEnabled()
	return self.safe_mode
end

function BLTMod:SetSafeModeEnabled(enabled)
	if enabled == nil then
		enabled = true
	end
	if self:DisableSafeMode() then
		enabled = false
	end
	self.safe_mode = enabled
end

function BLTMod:DisableSafeMode()
	if self:IsUndisablable() then
		return true
	end
	return self.disable_safe_mode
end

function BLTMod:IsUndisablable()
	return self.id == "base" or self.undisablable or false
end

function BLTMod:HasDependencies()
	return next(self.dependencies) and true or false
end

function BLTMod:GetDependencies()
	return self.dependencies or {}
end

function BLTMod:GetMissingDependencies()
	return self.missing_dependencies or {}
end

function BLTMod:GetDisabledDependencies()
	return self.disabled_dependencies or {}
end

function BLTMod:AreDependenciesInstalled()
	local installed = true
	self.missing_dependencies = {}
	self.disabled_dependencies = {}

	-- Iterate all mods and updates to find dependencies, store any that are missing
	for id, data in pairs(self:GetDependencies()) do
		local found = false
		for _, mod in ipairs(BLT.Mods:Mods()) do
			if mod:GetName() == id then
				found = true
			elseif mod:HasLegacyUpdate(id) then
				found = true
			else
				for _, update in ipairs(mod:GetUpdates()) do
					if update:GetId() == id then
						found = true
						break
					end
				end
			end

			if found then
				if not mod:IsEnabled() then
					installed = false
					table.insert(self.disabled_dependencies, mod)
					table.insert(self._errors, "blt_mod_dependency_disabled")
				end
				break
			end
		end

		if not found then
			installed = false
			local download_data = type(data) == "table" and data._download_data or { download_url = data }
			local new_dependency, valid = BLTModDependency:new(self, id, download_data)
			if valid then
				table.insert(self.missing_dependencies, new_dependency)
			else
				BLT:Log(LogLevel.ERROR, string.format("Invalid dependency '%s' for mod '%s'", id, self:GetName()))
			end
		end
	end

	return installed
end

function BLTMod:RetrieveDependencies()
	for _, dependency in ipairs(self:GetMissingDependencies()) do
		dependency:Retrieve(function(dep, exists_on_server)
			self:clbk_retrieve_dependency(dep, exists_on_server)
		end)
	end
end

function BLTMod:clbk_retrieve_dependency(dependency, exists_on_server)
	-- Register the dependency as a download
	if exists_on_server then
		BLT.Downloads:add_pending_download(dependency)
	end
end

function BLTMod:GetDeveloperInfo()
	local str = ""
	local append = function(...)
		for i, s in ipairs({...}) do
			str = str .. (i > 1 and " " or "") .. tostring(s)
		end
		str = str .. "\n"
	end

	local hooks = self:GetHooks() or {}
	local prehooks = self:GetPreHooks() or {}
	local persists = self:GetPersistScripts() or {}
	local min_sblt_version = self:GetMinSBLTVer() or nil

	append(managers.localization:text("blt_devinfo_path") .. ":", self:GetPath())
	append(managers.localization:text("blt_devinfo_loadprio") .. ":", self:GetPriority())
	if min_sblt_version then
		append(managers.localization:text("blt_mod_info_min_sblt_version") .. ":", min_sblt_version)
	end
	append(managers.localization:text("blt_devinfo_disablable") .. ":", not self:IsUndisablable())
	append(managers.localization:text("blt_devinfo_allowsafemode") .. ":", not self:DisableSafeMode())

	if table.size(hooks) < 1 then
		append(managers.localization:text("blt_devinfo_nohooks"))
	else
		append(managers.localization:text("blt_devinfo_hooks") .. ":")
		for _, hook in ipairs(hooks) do
			append("   ", tostring(hook))
		end
	end

	if table.size(prehooks) < 1 then
		append(managers.localization:text("blt_devinfo_noprehooks"))
	else
		append(managers.localization:text("blt_devinfo_prehooks") .. ":")
		for _, hook in ipairs(prehooks) do
			append("   ", tostring(hook))
		end
	end

	if table.size(persists) < 1 then
		append(managers.localization:text("blt_devinfo_nopersistentscripts"))
	else
		append(managers.localization:text("blt_devinfo_persistentscripts") .. ":")
		for _, script in ipairs(persists) do
			append("   ", script.global, "->", script.file)
		end
	end

	return str
end

---@deprecated
function BLTMod:GetSuperMod()
	return self
end

function BLTMod:IsLibrary()
	return self.library
end

function BLTMod:__tostring()
	return string.format("[BLTMod %s (%s)]", self:GetName(), self:GetId())
end

function BLTMod:_load_persist_scripts_data()
	for _, persist_data in ipairs(self.data.persist_scripts or {}) do
		if persist_data.global and persist_data.script_path then
			self:AddPersistScript(persist_data.global, persist_data.script_path)
		end
	end
end

function BLTMod:_load_persist_scripts_xml(_scope, tag)
	Utils.IO.TraverseXML(tag, _scope, {
		script = function(scope)
			if scope.global and scope.script_path then
				self:AddPersistScript(scope.global, scope.script_path)
			end
		end
	})
end

function BLTMod:_load_keybinds_data(data)
	for _, _data in ipairs(data or {}) do
		self:AddKeybind(_data)
	end
end

function BLTMod:_load_keybinds_xml(_scope, tag)
	Utils.IO.TraverseXML(tag, _scope, {
		keybind = function(scope)
			scope.run_in_menu = Utils:ToBoolean(scope.run_in_menu)
			scope.run_in_game = Utils:ToBoolean(scope.run_in_game)
			scope.run_in_paused_game = Utils:ToBoolean(scope.run_in_paused_game)
			scope.show_in_menu = (scope.show_in_menu == nil) or Utils:ToBoolean(scope.show_in_menu) -- show_in_menu needs to default to true, if unset
			scope.localized = Utils:ToBoolean(scope.localized)
			scope.localized_desc = Utils:ToBoolean(scope.localized_desc)
			self:AddKeybind(scope)
		end
	})
end

function BLTMod:_load_updates_data(data)
	for _, update_data in ipairs(data) do
		if not (update_data.host or update_data.provider) then
			-- Old PaydayMods update, server is gone so don't update those
			-- Do keep track of what we have installed though, for dependencies
			if update_data.identifier then -- sanity check
				self._legacy_updates[update_data.identifier] = true
			end
		else
			self:AddUpdate(update_data)
		end
	end
end

function BLTMod:_load_updates_xml(scope, tag)
	Utils.IO.TraverseXML(tag, scope, {
		update = function(update, sub)
			Utils.IO.TraverseXML(sub, update, {
				misc_data = function (misc_data)
					update.misc_data = misc_data
				end,
				host = function (host)
					update.host = host
				end
			})
			if update.host or update.provider then
				update.disallow_update = update.disallow_update
				update.critical = Utils:ToBoolean(update.critical)
				self:AddUpdate(update)
			end
		end
	})
end

function BLTMod:_load_dependencies_data(data)
	for id, dependency in pairs(data) do
		self:AddDependency(id, dependency)
	end
end

function BLTMod:_load_dependencies_xml(scope, tag)
	Utils.IO.TraverseXML(tag, scope, {
		dependency = function(dependency)
			self:AddDependency(dependency.name, dependency)
		end
	})
end

function BLTMod:_load_assets_data(data)
	if self._assets then
		self._assets:LoadAssets(data)
	end
end

function BLTMod:_load_assets_xml(scope, tag)
	if self._assets then
		self._assets:FromXML(scope, tag)
	end
end

function BLTMod:_load_hooks_data()
	self:AddHooks("hooks", BLT.hook_tables.post, BLT.hook_tables.wildcards)
	self:AddHooks("pre_hooks", BLT.hook_tables.pre, BLT.hook_tables.wildcards)
end

function BLTMod:_load_hooks_xml(_scope, tag)
	Utils.IO.TraverseXML(tag, _scope, {
		pre = function(scope)
			self:AddHook("hooks", scope.hook_id, scope.script_path, BLT.hook_tables.pre, BLT.hook_tables.wildcards)
		end,
		post = function(scope)
			self:AddHook("hooks", scope.hook_id, scope.script_path, BLT.hook_tables.post, BLT.hook_tables.wildcards)
		end,
		entry = function(scope)
			BLT:RunHookFile(scope.script_path, {
				mod = self,
				script = scope.script_path
			})
		end,
		wildcard = function()
			BLT:Log(LogLevel.ERROR, "Wildcard hooks are not implemented yet!")
		end
	})
end

function BLTMod:_load_native_module(data)
	if data.loading_vector == "preload" then
		return -- Uses Wren
	end

	if not blt.load_native or not blt.blt_info then
		BLT:Log(LogLevel.ERROR, string.format("[BLT] Cannot load native module for '%s' (functionality missing)", self:GetName()))
		return
	end

	if blt.blt_info().platform ~= data.platform then
		BLT:Log(LogLevel.ERROR, string.format("[BLT] Incorrect platform for native module for '%s'", self:GetName()))
		return
	end

	BLT:Log(LogLevel.INFO, string.format("[BLT] Loading native module for '%s'", self:GetName()))
	blt.load_native(self:GetPath() .. data.filename)
end

function BLTMod:_load_scripts_data(data)
	for _, _data in ipairs(data.scripts or data) do
		dofile(self:GetPath() .. _data.script_path)
	end
end

function BLTMod:_load_scripts_xml(_scope, tag)
	Utils.IO.TraverseXML(tag, _scope, {
		script = function(scope)
			if scope.script_path then
				dofile(self:GetPath() .. scope.script_path)
			else
				BLT:Log(LogLevel.ERROR, string.format("[BLT] No script path given for script in the mod '%s'", self:GetName()))
			end
		end
	})
end

function BLTMod:_load_localization_xml(scope, tag)
	self.default_language = scope.default_language or "english"
	self.localization_directory = scope.directory and (self:GetPath() .. scope.directory .. "/") or self:GetPath()
	self.localizations = {}

	local inner_clbk = function(...)
		self:_load_localization_xml_inner(...)
	end
	Utils.IO.TraverseXML(tag, scope, {
		loc = inner_clbk,
		localization = inner_clbk
	})

	if managers and managers.localization then
		self:_apply_localization()
	else
		Hooks:Add("LocalizationManagerPostInit", self:GetPath() .. "_Localization", function(loc)
			self:_apply_localization()
		end)
	end
end

function BLTMod:_load_localization_xml_inner(scope)
	if not self.default_localization then
		self.default_localization = scope.file
	end
	local lang = scope.language
	self.localizations[lang] = self.localizations[lang] or {}
	local path = (self.localization_directory .. scope.file)
	if io.file_is_readable(path) then
		table.insert(self.localizations[lang], path)
	else
		BLT:Log(LogLevel.ERROR, string.format("Localization file with path %s for language %s doesn't exist!", tostring(path), tostring(lang)))
	end
end

function BLTMod:_apply_localization()
	local lang_key = Steam:current_language()
	local default_loc = self.localizations[self.default_language]
	local loc = self.localizations[lang_key] or default_loc
	if loc then
		-- load localization matching game language
		for _, path in pairs(loc) do
			if not LocalizationManager:load_localization_file(path) then
				BLT:Log(LogLevel.ERROR, string.format("Language file has errors and cannot be loaded! Path %s", path))
			end
		end
		-- load default localization as fallback
		if default_loc then
			for _, path in pairs(default_loc) do
				if not LocalizationManager:load_localization_file(path, false) then
					BLT:Log(LogLevel.ERROR, string.format("Language file has errors and cannot be loaded! Path %s", path))
				end
			end
		end
	else -- legacy
		local path = (self.localization_directory .. self.default_localization)
		if not LocalizationManager:load_localization_file(path) then
			BLT:Log(LogLevel.ERROR, string.format("Language file has errors and cannot be loaded! Path %s", path))
		end
	end
end
