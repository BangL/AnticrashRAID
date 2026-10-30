-- AnticrashRAID: keeps the game from crashing on network messages that are malformed (lag, mods, malicious peers).
-- Port of Anticrash by TdlQ (PAYDAY 2).
--  * every message handler of ConnectionNetworkHandler / UnitNetworkHandler runs protected (failures are logged)
--  * text parameters of the messages are checked for valid UTF-8 (ill-formed text crashes the text rendering)
--  * unit spawns in the callbacks of peers and in projectile messages are skipped if the unit is not loaded
--  * outfit strings are checked before they are applied, stances are checked before they are applied
-- What happens to the peer is up to the player: nothing by default, a chat message, or a kick (host only).

_G.Anticrash = _G.Anticrash or {}
local Anticrash = _G.Anticrash

if Anticrash._loaded then
	return
end
Anticrash._loaded = true

-- the pcall of the game only hands back the status
local ac_pcall = (blt and blt.pcall) or pcall

Anticrash.ModPath = ModPath
Anticrash.settings_path = SavePath .. "AnticrashRAID.json"

-- default/unprotected only make sense per source: 'default' = use the default action, 'unprotected' = no protection
Anticrash.action_types = { "default", "unprotected", "quiet", "chat", "kick" }
Anticrash.default_action_types = { "quiet", "chat", "kick" }
Anticrash.action_ranks = {}
for rank, action in ipairs(Anticrash.action_types) do
	Anticrash.action_ranks[action] = rank
end

-- no kick and no ban without being asked for, a kick needs several failures of the same peer
Anticrash.DEFAULT_ACTION = "chat"
Anticrash.strike_window = 60 -- seconds
Anticrash.strikes_to_act = 3 -- failures within the window before somebody is kicked
Anticrash.chat_interval = 30 -- seconds between two chat messages for the same source and peer

-- RAID has no ban list, message id 0 of kick_peer puts the peer on the kicked list of the session
Anticrash.KICK_MESSAGE_ID = 0

-- sources that do not come from the generic protection of a handler
Anticrash.manual_sources = {
	"anim_cbk_spawn_melee_item",
	"end_action_interact",
	"request_throw_projectile",
	"set_stance (manual)",
	"sync_outfit (manual)",
	"sync_throw_projectile",
	"unpack_blueprint_from_string",
}

Anticrash.objects = {
	ConnectionNetworkHandler = {},
	UnitNetworkHandler = {
		protect_spawn = {
			request_throw_projectile = true,
			sync_throw_projectile = true,
		},
	},
}

Anticrash.settings = {
	default_action = Anticrash.DEFAULT_ACTION,
	actions = {}, -- source -> action, 'default' is not stored
	seen = {}, -- sources that failed once, they are listed in the menu
}
Anticrash.strikes = {}
Anticrash.last_chat = {}

dofile(ModPath .. "lua/text_fields.lua")

---------------------------------------------------------------------------------------------------------------------
-- settings

function Anticrash:load()
	local file = io.open(self.settings_path, "r")
	if not file then
		return
	end

	local ok, data = ac_pcall(json.decode, file:read("*all"))
	file:close()
	if not ok or type(data) ~= "table" then
		return
	end

	if self.action_ranks[data.default_action] and data.default_action ~= "default" and data.default_action ~= "unprotected" then
		self.settings.default_action = data.default_action
	end
	for source, action in pairs(type(data.actions) == "table" and data.actions or {}) do
		if self.action_ranks[action] and action ~= "default" then
			self.settings.actions[source] = action
		end
	end
	for source in pairs(type(data.seen) == "table" and data.seen or {}) do
		self.settings.seen[source] = true
	end
end

function Anticrash:save()
	local file = io.open(self.settings_path, "w+")
	if file then
		file:write(json.encode(self.settings))
		file:close()
	end
end

function Anticrash:get_action(source)
	return self.settings.actions[source] or "default"
end

function Anticrash:set_action(source, action)
	self.settings.actions[source] = action ~= "default" and action or nil
end

function Anticrash:is_unprotected(source)
	return self.settings.actions[source] == "unprotected"
end

-- everything that is listed in the menu: the manual sources and what failed once
function Anticrash:get_all_sources()
	local sources = {}
	for _, source in ipairs(self.manual_sources) do
		sources[source] = true
	end
	for source in pairs(self.settings.seen) do
		sources[source] = true
	end
	for source in pairs(self.settings.actions) do
		sources[source] = true
	end
	return sources
end

---------------------------------------------------------------------------------------------------------------------
-- reaction

local function text(id, macros)
	return managers.localization and managers.localization:text(id, macros) or id
end

function Anticrash:send_to_chat(peer, source)
	if not managers.chat then
		return
	end

	local t = TimerManager:wall():time()
	local key = tostring(source) .. "\t" .. (peer and tostring(peer:id()) or "")
	if self.last_chat[key] and t - self.last_chat[key] < self.chat_interval then
		return
	end
	self.last_chat[key] = t

	local message = text("anticrash_crash_prevented", { SOURCE = source })
	if peer then
		message = message .. text("anticrash_crash_coming_from", { NAME = peer:name() })
	end
	ac_pcall(managers.chat._receive_message, managers.chat, ChatManager.GAME, text("anticrash_title"), nil, message, Color(0.52, 1, 0), nil, true)
end

function Anticrash:take_action_against_peer(peer, source)
	if not source then
		return
	end

	if not self.settings.seen[source] then
		self.settings.seen[source] = true
		self:save()
	end

	local action = self.settings.actions[source] or self.settings.default_action
	if action == "unprotected" then
		action = "quiet"
	end

	local session = managers.network and managers.network:session()

	if action == "kick" then
		if not (peer and session and Network:is_server()) then
			action = "chat"
		elseif peer == session:local_peer() then
			log("[Anticrash] action overridden: peer is local player")
			action = "chat"
		else
			-- a single failure is not enough to throw somebody out: the handler can fail for reasons that are not the
			-- sender's doing (a unit that is not loaded or synced yet, a bug in another mod, a late joiner...)
			local now = TimerManager:wall():time()
			local id = peer:user_id() or peer:id()
			local strikes = self.strikes[id]
			if not strikes or now - strikes.t > self.strike_window then
				strikes = { t = now, n = 0 }
				self.strikes[id] = strikes
			end
			strikes.n = strikes.n + 1
			if strikes.n < self.strikes_to_act then
				log(("[Anticrash] %s: strike %d/%d against %s"):format(tostring(source), strikes.n, self.strikes_to_act, tostring(peer:name())))
				action = "chat"
			end
		end
	end

	if action == "kick" then
		log(("[Anticrash] %s: kick %s (peer %s)"):format(tostring(source), tostring(peer:name()), tostring(peer:id())))
		session:send_to_peers("kick_peer", peer:id(), self.KICK_MESSAGE_ID)
		session:on_peer_kicked(peer, peer:id(), self.KICK_MESSAGE_ID)
		action = "chat"
	end

	if action == "chat" then
		self:send_to_chat(peer, source)
	end
end

function Anticrash:log(object_name, fname, peer, ...)
	local params = { ... }
	if managers.network and not peer then
		local sender = params[#params]
		peer = type(sender) == "userdata" and sender.type_name == "RPCCaller" and BaseNetworkHandler._verify_sender(sender) or nil
	end

	-- the message of the failure, if the pcall in use hands it back, otherwise it is in the log entry just before this
	local from = peer and (" from " .. tostring(peer:name()) .. " (peer " .. tostring(peer:id()) .. ")") or ""
	log("[Anticrash] error in " .. object_name .. "." .. fname .. "()" .. from .. (self.last_error and (": " .. tostring(self.last_error)) or ""))
	for i, v in ipairs(params) do
		log("[Anticrash] - param" .. i .. ": " .. tostring(v))
	end
	if managers.network then
		self:take_action_against_peer(peer, fname)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- text check

local band = bit.band
local string_byte = string.byte
local function utf8_is_ok(str)
	local i = 1
	while true do
		local c = string_byte(str, i, i)
		if not c then
			return true
		elseif c <= 127 then
			i = i + 1
		elseif c <= 193 then
			return false
		elseif c <= 223 then
			local c2 = string_byte(str, i + 1, i + 1)
			i = i + 2
			if not (c2 and band(c2, 192) == 128) then
				return false
			end
		elseif c <= 224 then
			local c2, c3 = string_byte(str, i + 1, i + 2)
			i = i + 3
			if not (c3 and c2 and band(c2, 224) == 160 and band(c3, 192) == 128) then
				return false
			end
		elseif c <= 236 then
			local c2, c3 = string_byte(str, i + 1, i + 2)
			i = i + 3
			if not (c3 and c2 and band(c2, 192) == 128 and band(c3, 192) == 128) then
				return false
			end
		elseif c <= 237 then
			local c2, c3 = string_byte(str, i + 1, i + 2)
			i = i + 3
			if not (c3 and c2 and band(c2, 224) == 128 and band(c3, 192) == 128) then
				return false
			end
		elseif c <= 239 then
			local c2, c3 = string_byte(str, i + 1, i + 2)
			i = i + 3
			if not (c3 and c2 and band(c2, 192) == 128 and band(c3, 192) == 128) then
				return false
			end
		elseif c <= 240 then
			local c2, c3, c4 = string_byte(str, i + 1, i + 3)
			i = i + 4
			if not (c4 and c3 and c2 and c2 >= 144 and c2 <= 191 and band(c3, 192) == 128 and band(c4, 192) == 128) then
				return false
			end
		elseif c <= 243 then
			local c2, c3, c4 = string_byte(str, i + 1, i + 3)
			i = i + 4
			if not (c4 and c3 and c2 and band(c2, 192) == 128 and band(c3, 192) == 128 and band(c4, 192) == 128) then
				return false
			end
		elseif c <= 244 then
			local c2, c3, c4 = string_byte(str, i + 1, i + 3)
			i = i + 4
			if not (c4 and c3 and c2 and band(c2, 240) == 128 and band(c3, 192) == 128 and band(c4, 192) == 128) then
				return false
			end
		else
			return false
		end
	end
end

Anticrash.utf8_is_ok = utf8_is_ok
Anticrash.ILL_FORMED = "*ill-formed text*"

function Anticrash.utf8_clean_string(str)
	if type(str) ~= "string" or utf8_is_ok(str) then
		return str
	end
	return Anticrash.ILL_FORMED
end

-- the parameters at the given positions of a handler call, self is position 1
function Anticrash.utf8_clean(text_fields, ...)
	local params = { ... }
	local n = select("#", ...)
	for _, i in ipairs(text_fields) do
		params[i] = Anticrash.utf8_clean_string(params[i])
	end
	return unpack(params, 1, n)
end

---------------------------------------------------------------------------------------------------------------------
-- outfit and weapons

-- false if the outfit string would break the game
function Anticrash:check_outfit_string(outfit_string)
	-- an ill-formed string was replaced by the text check of the handler
	if type(outfit_string) ~= "string" or outfit_string == self.ILL_FORMED then
		return false
	end

	local ok, outfit = ac_pcall(managers.blackmarket.unpack_outfit_from_string, managers.blackmarket, outfit_string)
	if not ok or type(outfit) ~= "table" then
		return false
	end

	local factory = tweak_data.weapon.factory
	if not (outfit.primary and factory[outfit.primary.factory_id] and outfit.secondary and factory[outfit.secondary.factory_id]) then
		return false
	end

	if not tweak_data.blackmarket.melee_weapons[outfit.melee_weapon] then
		return false
	end

	return true
end

-- the blueprint with only the parts that fit together, built from the default blueprint of the weapon
function Anticrash:sanitize_weapon(factory_id, blueprint)
	local new_blueprint = table.deep_map_copy(managers.weapon_factory:get_default_blueprint_by_factory_id(factory_id))

	local i, changed = 0
	repeat
		i = i + 1
		changed = false
		for _, part_id in ipairs(blueprint) do
			if not table.contains(new_blueprint, part_id) then
				managers.weapon_factory:change_part_blueprint_only(factory_id, part_id, new_blueprint)
				changed = true
			end
		end
	until not changed or i > 5

	return new_blueprint
end

---------------------------------------------------------------------------------------------------------------------
-- unit spawns

local ac_original_world = World
local ids_unit = Idstring("unit")
local fake_world = {
	spawn_unit = function(acw, ids_unit_name, ...)
		if not PackageManager:has(ids_unit, ids_unit_name:id()) then
			log("[Anticrash] ignored call to spawn a unit not loaded: " .. tostring(ids_unit_name))
			return
		end
		return ac_original_world:spawn_unit(ids_unit_name, ...)
	end,
}
Anticrash.original_world = World
Anticrash.fake_world = setmetatable({}, {
	__index = function(t, k)
		if fake_world[k] then
			return fake_world[k]
		end
		local vk = ac_original_world[k]
		if type(vk) == "function" then
			return function(acw, ...)
				return vk(ac_original_world, ...)
			end
		end
		return vk
	end,
})

-- runs object[fname] with a World that skips spawns of units that are not loaded
function Anticrash:protect_spawn(object_name, fname, func_get_peer)
	local func = _G[object_name] and _G[object_name][fname]
	if type(func) ~= "function" then
		log(("[Anticrash] %s.%s() not found!"):format(object_name, fname))
		return
	end
	if self:is_unprotected(fname) then
		return
	end

	_G[object_name][fname] = function(object_self, ...)
		World = self.fake_world
		local status, err = ac_pcall(func, object_self, ...)
		World = self.original_world
		if not status then
			self.last_error = err
			local peer = func_get_peer and func_get_peer(object_self)
			self:log(object_name, fname, peer, object_self, ...)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- install: wraps what is there once all mods are loaded

function Anticrash:install()
	if self._installed then
		return
	end
	self._installed = true

	for object_name, stuff in pairs(self.objects) do
		local object = _G[object_name]
		if object then
			local names = {}
			for fname, func in pairs(object) do
				if type(func) == "function" and fname:sub(1, 1) ~= "_" and fname ~= "new" and fname ~= "init" then
					table.insert(names, fname)
				end
			end

			for _, fname in ipairs(names) do
				local func = object[fname]
				local text_fields = stuff.text_fields and stuff.text_fields[fname]
				if stuff.protect_spawn and stuff.protect_spawn[fname] then
					self:protect_spawn(object_name, fname)
				elseif not self:is_unprotected(fname) then
					if text_fields then
						object[fname] = function(...)
							local status, err = ac_pcall(func, Anticrash.utf8_clean(text_fields, ...))
							if not status then
								Anticrash.last_error = err
								Anticrash:log(object_name, fname, nil, ...)
							end
						end
					else
						object[fname] = function(self, ...)
							local status, err = ac_pcall(func, self, ...)
							if not status then
								Anticrash.last_error = err
								Anticrash:log(object_name, fname, nil, self, ...)
							end
						end
					end
				end
			end
		end
	end

	-- the interaction can fail when the unit is not synced yet (bad network)
	if ObjectInteractionManager and not self:is_unprotected("end_action_interact") then
		local end_action_interact = ObjectInteractionManager.end_action_interact
		function ObjectInteractionManager.end_action_interact(...)
			local status, err = ac_pcall(end_action_interact, ...)
			if not status then
				Anticrash.last_error = err
				log("[Anticrash] error in ObjectInteractionManager.end_action_interact(): " .. tostring(err))
				Anticrash:send_to_chat(nil, "end_action_interact")
			end
		end
	end
end

Anticrash:load()
