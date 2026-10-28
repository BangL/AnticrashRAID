Anticrash:protect_spawn("HuskPlayerMovement", "anim_cbk_spawn_melee_item", function(object)
	return type(object) == "table" and managers.network:session():peer_by_unit(object._unit)
end)
