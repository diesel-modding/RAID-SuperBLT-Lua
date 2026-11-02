-- Peers can only be written to once their ip is verified, which is later than NetworkManagerOnPeerAdded
Hooks:PostHook(NetworkPeer, "set_ip_verified", "BLT.NetworkPeer.set_ip_verified", function(self, state)
	if state and managers.network and managers.network:session() and self ~= managers.network:session():local_peer() then
		LuaNetworking:AnnounceChunking(self, true)
	end
end)
