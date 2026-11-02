---@class BLTUpdate
---@field new fun(self, parent_mod: BLTMod, data: table):BLTUpdate, boolean
BLTUpdate = blt_class()
BLTUpdate.enabled = true
BLTUpdate.revision = 1

function BLTUpdate:init(parent_mod, data)
	if not parent_mod or not data or not (data.host or data.provider) then
		return false
	end

	self.parent_mod = parent_mod
	self.id = data.identifier or data.id or ""
	self.name = data.display_name or parent_mod:GetName()
	self.dir = data.install_dir or parent_mod:GetDir()
	self.folder = data.install_folder or parent_mod:GetId()
	self.disallow_update = data.disallow_update or false
	self.hash_file = data.hash_file or false
	self.critical = data.critical or false
	self.host = data.host or nil
	self.provider = data.provider or nil
	self.present_func = data.present_func or nil
	self.present_file = data.present_file or nil
	self.version_func = data.version_func or nil
	self.misc_data = data.misc_data or nil

	self._event_handlers = {}

	return true
end

function BLTUpdate:__tostring()
	return string.format("[BLTUpdate %s (%s)]", self:GetName(), self:GetId())
end

function BLTUpdate:IsEnabled()
	return self.enabled
end

function BLTUpdate:SetEnabled(enable)
	self.enabled = enable
end

function BLTUpdate:RequiresUpdate()
	return self._requires_update
end

function BLTUpdate:CheckForUpdates(clbk)
	-- Flag this update as already requesting updates
	self._requesting_updates = true

	-- Perform the request from the server
	if self.provider then
		-- by provider
		if self.provider == "modworkshop" then
			dohttpreq("https://api.modworkshop.net/mods/" .. self:GetId() .. "/version",
				function(version, http_id, request_info)
					-- a failed request must still finish the check (clbk_got_update_data reports it)
					local data = nil
					if not string.is_nil_or_empty(version) then
						data = {
							ident = self:GetId(),
							version = version,
							download_url = "https://api.modworkshop.net/mods/" .. self:GetId() .. "/download",
							patchnotes_url = self.misc_data and self.misc_data.patchnotes_url or ("https://modworkshop.net/mod/" .. self:GetId() .. "?tab=changelog")
						}
					end
					self:clbk_got_update_data(clbk, data, http_id, request_info)
				end)
		else
			BLT:Log(LogLevel.ERROR, "Unknown update provider: " .. tostring(self.provider))
			self._error = "Unknown update provider."
			self._requesting_updates = false
			self:_run_update_callback(clbk, false, self._error)
		end
	else
		-- by superblt meta data
		dohttpreq(self.host.meta, function(json_data, http_id, request_info)
			self:clbk_got_update_data(clbk, json_data, http_id, request_info)
		end)
	end
end

function BLTUpdate:clbk_got_update_data(clbk, json_data, http_id, request_info)
	self._requesting_updates = false

	if not request_info.querySucceeded or (json_data == nil or (type(json_data) == "string" and string.is_nil_or_empty(json_data))) then
		BLT:Log(LogLevel.WARN, string.format("[Updates] Could not retrieve update data for '%s'", self:GetId()))
		self._error = "Could not retrieve update data."
		return self:_run_update_callback(clbk, false, self._error)
	end

	local server_data = type(json_data) == "string" and json.decode(json_data) or {json_data}
	if type(server_data) == "table" then
		for _, data in pairs(server_data) do
			if data.ident == self:GetId() then
				BLT:Log(LogLevel.INFO, string.format("[Updates] Received update data for update id '%s'", self:GetId()))
				self._update_data = data
				if data.hash  ~= nil then -- Use hash to check
					self._server_hash = data.hash
					self._uses_hash = true
				elseif data.version ~= nil then -- Use version
					self._server_version = data.version
					self._uses_hash = false
					local local_version = (not self.version_func) and self.parent_mod.version or BLTUpdateCallbacks[self.version_func]() or nil
					if local_version == nil then
						self._error = "Unable to get local version."
						BLT:Log(LogLevel.ERROR,
							string.format("[Updates] Unable to get local version for '%s'", self:GetId()))
						return self:_run_update_callback(clbk, false, self._error)
					end
					local newer = BLT:CompareVersions(local_version, data.version)
					BLT:Log(LogLevel.INFO, string.format("[Updates] Received version '%s' from the server (local is '%s'). %s",
						tostring(data.version), tostring(local_version),
						newer == 2 and "Update available!" or (newer == 1 and "[local is newer]" or "")
					))
					return self:_run_update_callback(clbk, newer == 2) -- Request an update if the remote version greater than local version.
				end

				local dat = { data, clbk }
				local hash_result = self:GetHash(callback(self, self, "_check_hash", dat))

				-- Nil indicates the file to hash was missing
				-- True indicates our callback will be run at a later date
				-- A string is the hashed value
				if not hash_result then
					-- Errored, file does not exist
					self._error = "File to be version checked is missing."
					BLT:Log(LogLevel.ERROR,
						string.format("[Updates] File to be version checked is missing for '%s'", self:GetId()))
					return self:_run_update_callback(clbk, false, self._error)
				elseif hash_result ~= true then
					-- Manually check the hash, since we're running on an old
					-- version of the DLL that doesn't support the callbacks
					return self:_check_hash(dat, hash_result)
				else
					-- At this point we've started the hash callback
					-- Keep 'Checking for Updates' until the hash is complete
					-- as this is set to false above in the check_hash callback
					self._requesting_updates = true
					return
				end
			end
		end
	end

	self._error = "No valid mod ID was returned by the server."
	BLT:Log(LogLevel.ERROR, string.format("[Updates] Invalid or corrupt update data for '%s'", self:GetId()))
	return self:_run_update_callback(clbk, false, self._error)
end

function BLTUpdate:_check_hash(dat, local_hash)
	local data, clbk = unpack(dat)

	self._requesting_updates = false

	BLT:Log(LogLevel.INFO,
		string.format("[Updates] Comparing hash data for '%s':\nServer: %s\n Local: %s", data.ident, data.hash,
			local_hash))
	if not data.hash then
		BLT:Log(LogLevel.WARN, string.format("[Updates] [WARN] Missing server hash for mod '%s'", data.ident))
		return self:_run_update_callback(clbk, false)
	end

	if data.hash == local_hash then
		return self:_run_update_callback(clbk, false)
	end

	return self:_run_update_callback(clbk, true)
end

function BLTUpdate:_run_update_callback(clbk, requires_update, error_reason)
	self._requires_update = requires_update
	clbk(self, requires_update, error_reason)
	self:call_event_handlers(requires_update, error_reason)
	return requires_update
end

function BLTUpdate:IsCheckingForUpdates()
	return self._requesting_updates or false
end

function BLTUpdate:GetParentMod()
	return self.parent_mod
end

function BLTUpdate:GetId()
	return tostring(self.id)
end

function BLTUpdate:GetName()
	return self.name
end

function BLTUpdate:GetHash(callback)
	if self.hash_file then
		return file.FileExists(self.hash_file) and file.FileHash(self.hash_file, callback) or nil
	else
		local directory = Application:nice_path(self:GetInstallDirectory() .. "/" .. self:GetInstallFolder(), true)
		return file.DirectoryExists(directory) and file.DirectoryHash(directory, callback) or nil
	end
end

function BLTUpdate:GetServerHash()
	return self._server_hash
end

function BLTUpdate:GetServerVersion()
	return self._server_version
end

function BLTUpdate:UsesHash()
	return self._uses_hash
end

function BLTUpdate:GetInstallDirectory()
	return self.dir
end

function BLTUpdate:GetInstallFolder()
	return self.folder
end

function BLTUpdate:DisallowsUpdate()
	return self.disallow_update ~= false
end

function BLTUpdate:GetDisallowCallback()
	return self.disallow_update
end

function BLTUpdate:GetPatchNotes()
	return (self._update_data and self._update_data.patchnotes_url) or (self.host and self.host.patchnotes)
end

function BLTUpdate:IsCritical()
	return self.critical
end

function BLTUpdate:ViewPatchNotes()
	-- Use the URL returned in the update metadata if possible
	-- this allows for easier migration of URLs
	local url = self:GetPatchNotes()
	Utils.OpenUrlSafe(url)
end

function BLTUpdate:GetDownloadURL()
	-- Use the URL returned in the update metadata if possible
	-- this allows for easier migration of URLs
	if self._update_data and self._update_data.download_url then
		return self._update_data.download_url
	end

	return self.host and self.host.download
end

function BLTUpdate:GetUpdateMiscData()
	return self._update_data and self._update_data.misc_data or self.misc_data
end

function BLTUpdate:IsInstall()
	return false
end

function BLTUpdate:IsPresent()
	if self.present_func then
		return BLTUpdateCallbacks[self.present_func](self)
	end

	return true
end

function BLTUpdate:GetError()
	return self._error
end

function BLTUpdate:HasAssets()
	for _, v2 in ipairs(self:GetParentMod()._xml_data or {}) do
		if v2.name ~= nil and v2.name == "assets" then
			return true
		end
	end
	return false
end

function BLTUpdate:register_event_handler(id, callback)
	self._event_handlers[id] = callback
end

function BLTUpdate:remove_event_handler(id)
	self._event_handlers[id] = nil
end

function BLTUpdate:call_event_handlers(requires_update, error_reason)
	for handler, callback in pairs(self._event_handlers) do
		if callback then
			callback(self, requires_update, error_reason)
		end
	end
end
