Utils.IO = Utils.IO or {}

local c = Utils.IO

--- Traverses through a SBLT XML, if it matches a tag defined in callbacks,
--- it will run a callback that receives the scope and tag to keep traversing if needed.
---@param xml table The XML table that was read by blt.parsexml
---@param parent_scope table If applicable, the scope of the parent for the child to access.
---@param callbacks table a table of key-value pairs for each tag of the XML. The funcs will receive scope (params) and the XML tag itself.
---@param allow_unknown boolean Whether to report about unknown tags (not defined in callbacks).
function c.TraverseXML(xml, parent_scope, callbacks, allow_unknown)
	for _, tag in ipairs(xml) do
		local scope = {}
		setmetatable(scope, {__index = parent_scope})

		for name, val in pairs(tag.params) do
			while true do
				local first, last = val:find("#{%a[%w_]-}")
				if not first then break end

				local _name = val:sub(first + 2, last - first)
				local target_var = scope[_name]

				assert(target_var, "Trying to use missing parameter '"
					.. _name .. "' as a #{value} in " .. tag._doc.filename)

				val = val:sub(1, first - 1) .. target_var .. val:sub(last + 1)
			end

			if name:sub(1,1) == ":" then
				name = name:sub(2)
				if not scope[name] then
					BLT:Log(LogLevel.WARN, "Trying to append to missing parameter '" .. name
							.. "' in " .. tag._doc.filename)
				end
				scope[name] = scope[name] .. val
			else
				scope[name] = val
			end
		end

		if tag.name == "group" then
			c.TraverseXML(tag, scope, callbacks, allow_unknown)
		elseif callbacks[tag.name] then
			callbacks[tag.name](scope, tag, callbacks)
		elseif not allow_unknown then
			BLT:Log(LogLevel.WARN, "Unknown tag name '" .. tag.name .. "' in: " .. tag._doc.filename)
		end
	end
end

--- Replaces :include in SBLT XML. :include basically let's you have multiple XML files that are mixed into one.
---@param xml table The XML table to traverse through
---@param path string The path to load the XML files from; usually being a mod path.
function c.ReplaceIncludesInXML(xml, path)
	for i, tag in ipairs(xml) do
		tag._doc = xml._doc

		if tag.name == ":include" then
			local file_path = path .. tag.params.src

			-- Attempt to read the mod definition file
			local file = io.open(file_path)
			assert(file, "Could not open " .. file_path)

			-- Read the file contents
			local file_contents = file:read("*all")
			file:close()

			-- Parse it
			local included = blt.parsexml(file_contents)
			if included then
				included._doc = {
					filename = file_path
				}

				-- Substitute it in
				tag = included
				xml[i] = included
			end
		end

		c.ReplaceIncludesInXML(tag, path)
	end
end

---Checks if a file can be opened to read from
---@param fname string @The path (relative to payday2_win32_release.exe) and file name to check
---@return boolean @`true` if the file can be opened for reading, `false` otherwise
function io.file_is_readable(fname)
	local file = io.open(fname, "r")
	if file ~= nil then
		io.close(file)
		return true
	end

	return false
end

---Recursively deletes all files and folders from the directory specified
---@param path string @The path (relative to payday2_win32_release.exe) of the directory to delete
---@param verbose boolean? @Wether to print verbose output to the log
---@return boolean @`true` if the operation was successful, `false` otherwise
function io.remove_directory_and_files(path, verbose)
	local vlog = function(str)
		if verbose then
			BLT:Log(LogLevel.INFO, str)
		end
	end

	if not path then
		BLT:Log(LogLevel.ERROR, "Parameter #1 to io.remove_directory_and_files, string expected, received " .. tostring(path))
		return false
	end

	if path == "" then
		BLT:Log(LogLevel.ERROR, "Cannot delete the root directory!")
		return false
	end

	if not file.DirectoryExists(path) then
		BLT:Log(LogLevel.ERROR, string.format("Directory '%s' does not exist", path))
		return false
	end

	-- Ensure final path separator
	local path_end = path:sub(-1)
	if path_end ~= "/" and path_end ~= "\\" then
		path = path .. "/"
	end

	local files = file.GetFiles(path)
	if files then
		for _, v in pairs(files) do
			local file_path = path .. v
			vlog(string.format("Removing file '%s'", file_path))
			local r, error_str = os.remove(file_path)
			if not r then
				BLT:Log(LogLevel.ERROR, string.format("Could not remove '%s': %s", file_path, error_str))
				return false
			end
		end
	end

	local dirs = file.GetDirectories(path)
	if dirs then
		for _, v in pairs(dirs) do
			local child_path = path .. v .. "/"
			vlog(string.format("Removing directory '%s'", child_path))
			local r = io.remove_directory_and_files(child_path, verbose)
			if not r then
				BLT:Log(LogLevel.ERROR, string.format("Could not remove directory '%s'", child_path))
				return false
			end
		end
	end

	vlog(string.format("Removing directory '%s'", path))
	local r = file.RemoveDirectory(path)
	if not r then
		BLT:Log(LogLevel.ERROR, string.format("Could not remove directory '%s'", path))
		return false
	end

	return true
end

---Converts a Lua table to a JSON string and saves it to a file
---@param data table @The data to save as JSON file
---@param path string @The path (relative to payday2_win32_release.exe) and file name to save the data to
---@return boolean @`true` if the operation was successful, `false` otherwise
function io.save_as_json(data, path)
	local count = 0
	for k, v in pairs(type(data) == "table" and data or {}) do
		count = count + 1
	end

	if count > 0 then
		-- write to a temp file first, a crash while writing must not leave a truncated file
		local temp_path = path .. ".tmp"
		local file = io.open(temp_path, "w+")
		if not file then
			BLT:Log(LogLevel.ERROR, string.format("Could not save to file '%s', data may be lost", path))
			return false
		end

		local written = file:write(json.encode(data))
		file:close()
		if not written then
			os.remove(temp_path)
			BLT:Log(LogLevel.ERROR, string.format("Could not write to file '%s', data may be lost", path))
			return false
		end

		-- renaming over an existing file fails on windows
		if not os.rename(temp_path, path) then
			os.remove(path)
			if not os.rename(temp_path, path) then
				BLT:Log(LogLevel.ERROR, string.format("Could not replace file '%s', data may be lost", path))
				return false
			end
		end
		return true
	else
		BLT:Log(LogLevel.WARN, string.format("Skipped saving empty data table to '%s'", path))
		return true
	end
end

---Loads a file containing JSON data and converts it into a Lua table
---@param path string @The path (relative to payday2_win32_release.exe) and file name to load the data from
---@return table? @The table containing the data, or `nil` if loading wasn't successful
function io.load_as_json(path)
	local file = io.open(path, "r")
	if file then
		local file_contents = file:read("*all")
		file:close()
		return json.decode(file_contents)
	else
		BLT:Log(LogLevel.ERROR, string.format("Could not load file '%s', no data loaded", path))
	end
end
