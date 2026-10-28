-- An unknown stance code breaks the movement of the husk. Only husks of players are checked (they have an
-- owner_stance_code), the stance data of other units looks different.

local set_stance = UnitNetworkHandler.set_stance

function UnitNetworkHandler:set_stance(unit, stance_code, instant, execute_queued, sender)
	if not Anticrash:is_unprotected("set_stance (manual)") and alive(unit) then
		local movement = unit:movement()
		local stance = movement and movement._stance
		if stance and stance.owner_stance_code ~= nil and stance.values and not stance.values[stance_code] then
			Anticrash:take_action_against_peer(self._verify_sender(sender), "set_stance (manual)")
			return
		end
	end

	return set_stance(self, unit, stance_code, instant, execute_queued, sender)
end
