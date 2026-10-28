-- A rejected outfit string is not applied; a broken one crashes the game of everybody who loads it.

local sync_outfit = ConnectionNetworkHandler.sync_outfit

function ConnectionNetworkHandler:sync_outfit(outfit_string, outfit_version, outfit_signature, sender)
	if not Anticrash:is_unprotected("sync_outfit (manual)") then
		local peer = self._verify_sender(sender)
		if not peer then
			return
		end

		if not Anticrash:check_outfit_string(outfit_string) then
			Anticrash:take_action_against_peer(peer, "sync_outfit (manual)")
			return
		end
	end

	return sync_outfit(self, outfit_string, outfit_version, outfit_signature, sender)
end
