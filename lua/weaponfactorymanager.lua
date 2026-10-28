-- unpack_blueprint_from_string errors on a factory id that does not exist and takes every part index of the string.
-- The blueprint is rebuilt from the default blueprint, so only parts that fit together stay.

local ac_pcall = (blt and blt.pcall) or pcall
local unpack_blueprint_from_string = WeaponFactoryManager.unpack_blueprint_from_string

function WeaponFactoryManager:unpack_blueprint_from_string(factory_id, blueprint_string)
	local factory = tweak_data.weapon.factory[factory_id]
	if not (factory and factory.uses_parts and type(blueprint_string) == "string") then
		return {}
	end

	local blueprint = unpack_blueprint_from_string(self, factory_id, blueprint_string)
	if Anticrash:is_unprotected("unpack_blueprint_from_string") then
		return blueprint
	end

	local ok, sanitized = ac_pcall(Anticrash.sanitize_weapon, Anticrash, factory_id, blueprint)
	return ok and sanitized or blueprint
end
