_G.LuaNetworking = _G.LuaNetworking or {}
LuaNetworking.HiddenChannel = 4
LuaNetworking.AllPeers = "GNAP"
LuaNetworking.AllPeersString = "%s/%s/%s"
LuaNetworking.SinglePeer = "GNSP"
LuaNetworking.SinglePeerString = "%s/%s/%s/%s"
LuaNetworking.ExceptPeer = "GNEP"
LuaNetworking.ExceptPeerString = "%s/%s/%s/%s"
LuaNetworking.Split = "[/]"
LuaNetworking._max_message_len = 255

-- Technically we don't need the message identifiers anymore cause we're only sending to the peers we want to send to anyways
-- For backwards compatibility, we'll keep them for now and they can be phased out at a later date

---Checks if the game is in a multiplayer state, and has an active multiplayer session
---@return boolean @The active multiplayer session, or `false`
function LuaNetworking:IsMultiplayer()
	if not managers.network then
		return false
	end
	return managers.network:session() ~= nil
end

---Checks if the local player is the host of the multiplayer game session  
---Functionally identical to `Network:is_server()`
---@return boolean @`true` if a multiplayer session is running and the local player is the host of it, or `false`
function LuaNetworking:IsHost()
	if not Network then
		return false
	end
	return not Network:is_client()
end

---Checks if the local player is a client of the multiplayer game session  
---Functionally identical to `Network:is_client()`
---@return boolean @`true` if a multiplayer session is running and the local player is not the host of it, or `false`
function LuaNetworking:IsClient()
	if not Network then
		return false
	end
	return Network:is_client()
end

---Returns the peer ID of the local player
---@return integer @Peer ID of the local player or `0` if no multiplayer session is active
function LuaNetworking:LocalPeerID()
	if managers.network == nil or managers.network:session() == nil or managers.network:session():local_peer() == nil then
		return 0
	end
	return managers.network:session():local_peer():id() or 0
end

---Returns the name of the player associated with the specified peer ID
---@param id integer @Peer ID of the player to get the name from
---@return string @Name of the player with peer ID `id`, or `"No Name"` if the player could not be found
function LuaNetworking:GetNameFromPeerID(id)
	for k, v in pairs(self:GetPeers()) do
		if k == id then
			return v:name()
		end
	end

	return "No Name"
end

---Returns an accessor for the session peers table
---@return table @Table of all players in the current multiplayer session
function LuaNetworking:GetPeers()
	return managers.network and managers.network:session() and managers.network:session():peers() or {}
end

---Returns the number of players in the multiplayer session
---@return integer @Number of players in the current session
function LuaNetworking:GetNumberOfPeers()
	return table.size(self:GetPeers())
end

---Sends networked data with a message id to all connected players
---@param id string @Unique name of the data to send
---@param data string @Data to send
function LuaNetworking:SendToPeers(id, data)
	local message = LuaNetworking.AllPeersString:format(LuaNetworking.AllPeers, id, data)
	self:SendStringThroughChat(message, self:GetPeers())
end

---Sends networked data with a message id to a specific player
---@param peer_id integer @Peer ID of the player to send the data to
---@param id string @Unique name of the data to send
---@param data string @Data to send
function LuaNetworking:SendToPeer(peer_id, id, data)
	local message = LuaNetworking.SinglePeerString:format(LuaNetworking.SinglePeer, peer_id, id, data)
	self:SendStringThroughChat(message, { self:GetPeers()[peer_id] })
end

---Sends networked data with a message id to all connected players except specific ones
---@param peer_id integer|integer[] @Peer ID or table of peer IDs of the player(s) to exclude
---@param id string @Unique name of the data to send
---@param data string @Data to send
function LuaNetworking:SendToPeersExcept(peer_id, id, data)
	local except = type(peer_id) == "table" and table.list_to_set(peer_id) or { [peer_id] = true }
	local peerStr = type(peer_id) == "table" and table.concat(peer_id, ",") or peer_id
	local message = LuaNetworking.ExceptPeerString:format(LuaNetworking.ExceptPeer, peerStr, id, data)
	-- FIXME: table.filter ??
	self:SendStringThroughChat(message, table.filter(self:GetPeers(), function (peer) return except[peer:id()] == nil end))
end

---@param message string
---@param receivers? table
function LuaNetworking:SendStringThroughChat(message, receivers)
	local message_len = message:len()
	if message_len > LuaNetworking._max_message_len then
		local message_id = string.split(message, LuaNetworking.Split, nil, 3)[2]
		BLT:Log(LogLevel.WARN, string.format("[LuaNetworking] Message with id '%s' exceeds maximum data length of %d (%d)", tostring(message_id), LuaNetworking._max_message_len, message_len))
	end

	for _, peer in pairs(receivers or self:GetPeers()) do
		if peer:ip_verified() then
			peer:send("send_chat_message", LuaNetworking.HiddenChannel, message)
		end
	end

	local local_peer = managers.network and managers.network:session() and managers.network:session():local_peer()
	BLT:Log(LogLevel.INFO, string.format("[LuaNetworking] %s: %s", local_peer and local_peer:name() or "", message))
end

Hooks:Add("ChatManagerOnReceiveMessage","ChatManagerOnReceiveMessage_Network", function(channel_id, name, message, color, icon)
	if tonumber(channel_id) ~= LuaNetworking.HiddenChannel then
		return
	end

	BLT:Log(LogLevel.INFO, string.format("[LuaNetworking] %s: %s", name, message))

	local senderID
	for k, v in pairs(LuaNetworking:GetPeers()) do
		if v:name() == name then
			senderID = k
		end
	end

	LuaNetworking:ProcessChatString(senderID or name, message, color, icon)
end)

Hooks:RegisterHook("NetworkReceivedData")
function LuaNetworking:ProcessChatString(sender, message, color, icon)
	local splitData = string.split(message, LuaNetworking.Split)
	local msgType = splitData[1]
	if msgType == LuaNetworking.AllPeers then
		self:ProcessAllPeers(sender, message, color, icon)
	elseif msgType == LuaNetworking.SinglePeer then
		self:ProcessSinglePeer(sender, message, color, icon)
	elseif msgType == LuaNetworking.ExceptPeer then
		self:ProcessExceptPeer(sender, message, color, icon)
	end
end

function LuaNetworking:ProcessAllPeers(sender, message, color, icon)
	local splitData = string.split(message, LuaNetworking.Split, nil, 2)
	Hooks:Call("NetworkReceivedData", sender, splitData[2], splitData[3])
end

function LuaNetworking:ProcessSinglePeer(sender, message, color, icon)
	local splitData = string.split(message, LuaNetworking.Split, nil, 3)
	local toPeer = tonumber(splitData[2])

	if toPeer == LuaNetworking:LocalPeerID() then
		Hooks:Call("NetworkReceivedData", sender, splitData[3], splitData[4])
	end
end

function LuaNetworking:ProcessExceptPeer(sender, message, color, icon)
	local splitData = string.split(message, LuaNetworking.Split, nil, 3)
	local exceptedPeers = string.split(splitData[2], "[,]")

	local excepted = false
	for k, v in pairs(exceptedPeers) do
		if tonumber(v) == LuaNetworking:LocalPeerID() then
			excepted = true
		end
	end

	if not excepted then
		Hooks:Call("NetworkReceivedData", sender, splitData[3], splitData[4])
	end
end

-- Utility functions to convert types into strings

---Converts a table to a string representation
---@param tbl table @Table to convert into a string
---@return string @String representation of `tbl`
function LuaNetworking:TableToString(tbl)
	local str = ""
	for k, v in pairs(tbl) do
		if str ~= "" then
			str = str .. ","
		end
		str = str .. string.format("%s|%s", tostring(k), tostring(v))
	end
	return str
end

---Converts the string representation of a table to a table
---@param str string @String representation of a table
---@return table @Table created from `str`
function LuaNetworking:StringToTable(str)
	local tbl = {}
	local tblPairs = string.split(str, "[,]")
	for k, v in pairs(tblPairs) do
		local pairData = string.split(v, "[|]")
		tbl[pairData[1]] = pairData[2]
	end
	return tbl
end

---Creates a string representation of a color
---@param col any
---@return string
function LuaNetworking:ColourToString(col)
	return string.format("r:%.4f|g:%.4f|b:%.4f|a:%.4f", col.r, col.g, col.b, col.a)
end

---Converts a string representation of a color to a color
---@param str string
---@return any
function LuaNetworking:StringToColour(str)
	local r, g, b, a = str:match("r:([0-9.]+)|g:([0-9.]+)|b:([0-9.]+)|a:([0-9.]+)")
	r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
	if r and g and b and a then
		return Color(a, r, g, b)
	end
end

---Creates a string representation of a Vector3
---@param v Vector3 @The Vector3 to convert to a formatted string
---@return string @A formatted string containing the data of the Vector3
function LuaNetworking:Vector3ToString(v)
	return string.format("%08f,%08f,%08f", v.x, v.y, v.z)
end

---Converts a string representation of a Vector3 to a Vector3
---@param string string @The string to convert to a Vector3
---@return Vector3? @A Vector3 of the converted string or `nil` if no conversion could be made
function LuaNetworking:StringToVector3(string)
	local x, y, z = string:match("([-0-9.]+),([-0-9.]+),([-0-9.]+)")
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if x and y and z then
		return Vector3(x, y, z)
	end
end



-- DEPRECATED FUNCTIONALITY --

---@deprecated @Use `LuaNetworking:VectorToString` instead
function Vector3.ToString(v)
	BLT:Log(LogLevel.WARN, "Vector3.ToString is deprecated and will be removed in a future version\n" .. debug.traceback())
	return LuaNetworking:Vector3ToString(v)
end

---@deprecated @Use `LuaNetworking:StringToVector` instead
function string.ToVector3(string)
	BLT:Log(LogLevel.WARN, "string.ToVector3 is deprecated and will be removed in a future version\n" .. debug.traceback())
	return LuaNetworking:StringToVector3(string)
end
