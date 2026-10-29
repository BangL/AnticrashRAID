-- options menu

AnticrashMenu = AnticrashMenu or class(BLTMenu)

function AnticrashMenu:Init(root)
	self._something_changed = false

	self:Title({
		text = "anticrash_title",
	})
	self:Label({
		text = nil,
		localize = false,
		h = 8,
	})

	self:EnableScrolling() -- header stays fixed, everything below scrolls

	self:AutoBindNamedControlsBegin()

	self:SubTitle({ text = "anticrash_cat_default", localize = true, y_offset = 16 })
	self:_MakeChoice("default_action", "anticrash_default_action", Anticrash.default_action_types, Anticrash.settings.default_action)

	self:SubTitle({ text = "anticrash_cat_sources", localize = true, y_offset = 16 })

	local sources = {}
	for source in pairs(Anticrash:get_all_sources()) do
		table.insert(sources, source)
	end
	-- what is acted on first, then by name
	table.sort(sources, function(a, b)
		local rank_a, rank_b = Anticrash.action_ranks[Anticrash:get_action(a)], Anticrash.action_ranks[Anticrash:get_action(b)]
		if rank_a ~= rank_b then
			return rank_a > rank_b
		end
		return a < b
	end)

	for _, source in ipairs(sources) do
		self:_MakeChoice(source, source:gsub("_", " "), Anticrash.action_types, Anticrash:get_action(source), true)
	end

	self:AutoBindNamedControlsEnd()
end

function AnticrashMenu:_MakeChoice(source, text_id, action_types, value, plain_text)
	local params = {
		name = "anticrash_" .. source,
		text = text_id,
		localize = not plain_text,
		upper = false,
		value = nil,
		callback = callback(self, self, "OnActionChanged", source),
		items = {},
		auto_select_on_hover = true,
	}
	if not plain_text then
		params.desc = text_id .. "_desc"
	end
	for i, action in ipairs(action_types) do
		table.insert(params.items, {
			text_id = "anticrash_action_" .. action,
			value = i,
		})
		if action == value then
			params.value = i
		end
	end
	self:MultiChoice(params)
end

function AnticrashMenu:OnActionChanged(source, value)
	value = type(value) == "table" and value.value or value
	if source == "default_action" then
		Anticrash.settings.default_action = Anticrash.default_action_types[value] or Anticrash.DEFAULT_ACTION
	else
		Anticrash:set_action(source, Anticrash.action_types[value])
	end
	self._something_changed = true
end

function AnticrashMenu:Close()
	if self._something_changed then
		Anticrash:save()
	end
end

Hooks:Add("MenuComponentManagerInitialize", "Anticrash_MenuComponentManagerInitialize", function(self)
	-- all mods are loaded now, wrap what they changed too
	Anticrash:install()

	RaidMenuHelper:CreateMenu({
		name = "anticrash_options",
		name_id = "anticrash_title",
		inject_list = "blt_options",
		icon = "menu_item_network",
		class = AnticrashMenu,
	})
end)
