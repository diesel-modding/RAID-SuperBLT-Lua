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
	for _, peer in pairs(receivers or self:GetPeers()) do
		if peer:ip_verified() then
			self:_SendToPeer(peer, message)
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
	-- chunking is handled here and never shows up as a message of its own
	if splitData[2] == self.ChunkAnnounceId then
		self:_OnChunkAnnounce(sender, splitData[3])
		return
	elseif splitData[2] == self.ChunkFragmentId then
		self:_OnChunkFragment(sender, splitData[3])
		return
	end
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

-- Chunking of messages that exceed the maximum data length
--
-- The chat rpc ("send_chat_message") takes a plain "string" parameter, which is limited to 255 characters.
-- A longer message is split into fragments ("GNAP/NHF/...") for peers that announced ("GNAP/NHC/...")
-- that they can reassemble them, the receiver processes the reassembled message like any other.
-- Peers running an older SuperBLT get the message the way it always was sent (with a warning).

LuaNetworking.ChunkAnnounceId = "NHC"
LuaNetworking.ChunkFragmentId = "NHF"
LuaNetworking._chunk_timeout = 30
LuaNetworking._chunk_retry_time = 10 -- seconds before an unanswered announcement is repeated
LuaNetworking._chunk_wait_time = 3 -- seconds an oversized message waits for the answer to our announcement
LuaNetworking._chunk_max_buffers = 32 -- incomplete messages kept per sender
LuaNetworking._chunk_next_uid = 0
LuaNetworking._chunk_peers = {} -- peers that can reassemble fragments
LuaNetworking._chunk_announced = {} -- peer id -> time our announcement was sent
LuaNetworking._chunk_buffers = {} -- sender -> uid -> incomplete message
LuaNetworking._chunk_pending = {} -- peer id -> messages held back until it is known if the peer can reassemble
LuaNetworking._chunk_settled = {} -- peers that did not answer in time, oversized messages are not held back for them anymore

---Tells a peer that we can reassemble fragments
---@param peer table @Peer to announce to
---@param reply_wanted boolean @If the peer should announce itself in return
function LuaNetworking:AnnounceChunking(peer, reply_wanted)
	local peer_id = peer:id()
	local now = TimerManager:wall_running():time()
	if not peer:ip_verified() or (reply_wanted and self._chunk_announced[peer_id] and now - self._chunk_announced[peer_id] < self._chunk_retry_time) then
		return
	end

	if reply_wanted then
		self._chunk_announced[peer_id] = now
	end
	peer:send("send_chat_message", self.HiddenChannel, self.AllPeersString:format(self.AllPeers, self.ChunkAnnounceId, reply_wanted and "1" or "0"))
end

---Splits a formatted message into messages that fit the limit
---@param message string
---@return string[]? @The fragments, or `nil` if the message can not be split
function LuaNetworking:_FragmentMessage(message)
	self._chunk_next_uid = self._chunk_next_uid % 99999 + 1
	local uid = self._chunk_next_uid

	-- header: uid|part|parts|, sized for up to 999 parts
	local overhead = self.AllPeersString:format(self.AllPeers, self.ChunkFragmentId, ""):len() + string.format("%d|999|999|", uid):len()
	local chunk_len = self._max_message_len - overhead
	if chunk_len < 16 then
		return
	end

	local pieces = {}
	local pos = 1
	while pos <= message:len() do
		local stop = math.min(pos + chunk_len - 1, message:len())
		if stop < message:len() then
			-- do not cut through a multibyte character
			while stop > pos do
				local next_byte = message:byte(stop + 1)
				if next_byte < 0x80 or next_byte >= 0xC0 then
					break
				end
				stop = stop - 1
			end
		end
		table.insert(pieces, message:sub(pos, stop))
		pos = stop + 1
	end

	local parts = #pieces
	if parts > 999 then
		return
	end

	local fragments = {}
	for i, piece in ipairs(pieces) do
		fragments[i] = self.AllPeersString:format(self.AllPeers, self.ChunkFragmentId, string.format("%d|%d|%d|%s", uid, i, parts, piece))
	end
	return fragments
end

function LuaNetworking:_FlushId(peer_id)
	return "LuaNetworking.chunk_flush_" .. tostring(peer_id)
end

---Sends one message to a peer, oversized ones are fragmented if the peer supports it
---If that is not known yet the message is held back, and everything that follows it to keep the order
---@param peer table
---@param message string
function LuaNetworking:_SendToPeer(peer, message)
	local peer_id = peer:id()

	local pending = self._chunk_pending[peer_id]
	if pending then
		table.insert(pending, message)
		return
	end

	if message:len() > self._max_message_len and not self._chunk_peers[peer_id] and not self._chunk_settled[peer_id] then
		self._chunk_pending[peer_id] = { message }
		self:AnnounceChunking(peer, true)
		DelayedCalls:Add(self:_FlushId(peer_id), self._chunk_wait_time, function()
			self:_FlushPending(peer_id, true)
		end)
		return
	end

	self:_DeliverToPeer(peer, message)
end

function LuaNetworking:_DeliverToPeer(peer, message)
	if message:len() > self._max_message_len then
		local fragments = self._chunk_peers[peer:id()] and self:_FragmentMessage(message)
		if fragments then
			for _, fragment in ipairs(fragments) do
				peer:send("send_chat_message", self.HiddenChannel, fragment)
			end
			return
		end

		if self._chunk_last_warned ~= message then
			self._chunk_last_warned = message
			local message_id = string.split(message, self.Split, nil, 3)[2]
			BLT:Log(LogLevel.WARN, string.format("[LuaNetworking] Message with id '%s' exceeds maximum data length of %d (%d)", tostring(message_id), self._max_message_len, message:len()))
		end
	end

	peer:send("send_chat_message", self.HiddenChannel, message)
end

---Sends the messages held back for a peer
---@param peer_id integer
---@param timed_out boolean @The peer did not answer our announcement in time
function LuaNetworking:_FlushPending(peer_id, timed_out)
	local pending = self._chunk_pending[peer_id]
	if not pending then
		return
	end

	self._chunk_pending[peer_id] = nil
	DelayedCalls:Remove(self:_FlushId(peer_id))

	if timed_out and not self._chunk_peers[peer_id] then
		self._chunk_settled[peer_id] = true
	end

	local peer = self:GetPeers()[peer_id]
	if peer and peer:ip_verified() then
		for _, message in ipairs(pending) do
			self:_DeliverToPeer(peer, message)
		end
	end
end

function LuaNetworking:_OnChunkAnnounce(sender, data)
	self._chunk_peers[sender] = true

	if data == "1" then
		local peer = self:GetPeers()[sender]
		if peer then
			self:AnnounceChunking(peer, false)
		end
	end

	self:_FlushPending(sender, false)
end

function LuaNetworking:_OnChunkFragment(sender, data)
	local uid, part, parts, rest = tostring(data):match("^(%d+)|(%d+)|(%d+)|(.*)$")
	uid, part, parts = tonumber(uid), tonumber(part), tonumber(parts)
	if not (uid and part and parts) or part < 1 or part > parts or parts > 999 then
		return
	end

	local now = TimerManager:wall_running():time()
	local buffers = self._chunk_buffers[sender] or {}
	self._chunk_buffers[sender] = buffers
	for key, buffer in pairs(buffers) do
		if now - buffer.time > self._chunk_timeout then
			buffers[key] = nil
		end
	end

	local buffer = buffers[uid]
	if not buffer or buffer.parts ~= parts then
		if table.size(buffers) >= self._chunk_max_buffers then
			return
		end
		buffer = { time = now, parts = parts, count = 0, pieces = {} }
		buffers[uid] = buffer
	end

	if not buffer.pieces[part] then
		buffer.pieces[part] = rest
		buffer.count = buffer.count + 1
	end

	if buffer.count == buffer.parts then
		buffers[uid] = nil
		local message = table.concat(buffer.pieces)

		-- chunking messages are never allowed inside a reassembled message (nesting)
		local split_data = string.split(message, self.Split, nil, 2)
		if split_data[1] == self.AllPeers and (split_data[2] == self.ChunkAnnounceId or split_data[2] == self.ChunkFragmentId) then
			return
		end

		self:ProcessChatString(sender, message)
	end
end

---Forgets everything known about chunking support, of one peer or of all
---Peer ids are reused (the host is always 1), so the state must not outlive the peer or the session
---@param peer_id integer? @Peer to forget, `nil` for all
function LuaNetworking:_ResetChunkState(peer_id)
	if peer_id == nil then
		for pending_id in pairs(self._chunk_pending) do
			DelayedCalls:Remove(self:_FlushId(pending_id))
		end
		self._chunk_peers = {}
		self._chunk_announced = {}
		self._chunk_buffers = {}
		self._chunk_pending = {}
		self._chunk_settled = {}
		return
	end

	if self._chunk_pending[peer_id] then
		DelayedCalls:Remove(self:_FlushId(peer_id))
	end
	self._chunk_peers[peer_id] = nil
	self._chunk_announced[peer_id] = nil
	self._chunk_buffers[peer_id] = nil
	self._chunk_pending[peer_id] = nil
	self._chunk_settled[peer_id] = nil
end

Hooks:Add("BaseNetworkSessionOnPeerRemoved", "BLT.LuaNetworking.chunk_peer_removed", function(peer, peer_id)
	LuaNetworking:_ResetChunkState(peer_id)
end)

Hooks:Add("BaseNetworkSessionOnEnteredLobby", "BLT.LuaNetworking.chunk_session_start", function()
	LuaNetworking:_ResetChunkState()
end)
