local ADDON = 'Automagically'
if select(2, UnitClass('player')) ~= 'MAGE' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Automagically = {}
local Opt -- use this as a local table reference to Automagically

SLASH_Automagically1, SLASH_Automagically2, SLASH_Automagically3 = '/am', '/amagic', '/automagically'
BINDING_HEADER_AUTOMAGICALLY = ADDON

local function InitOpts()
	local function SetDefaults(t, ref)
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Automagically, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			animation = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			arcane = false,
			fire = false,
			frost = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		cd_ttd = 10,
		pot = false,
		trinket = true,
		barrier = true,
		conserve_mana = 60,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	ARCANE = 1,
	FIRE = 2,
	FROST = 3,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.ARCANE] = {},
	[SPEC.FIRE] = {},
	[SPEC.FROST] = {},
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	mana = {
		current = 0,
		deficit = 0,
		max = 100,
		regen = 0,
	},
	arcane_charges = {
		current = 0,
		max = 4,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		last_taken = 0,
	},
	set_bonus = {
		t29 = 0, -- Bindings of the Crystal Scholar
		t30 = 0, -- Underlight Conjurer's Brilliance
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	major_cd_remains = 0,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

local amagicPanel = CreateFrame('Frame', 'amagicPanel', UIParent)
amagicPanel:SetPoint('CENTER', 0, -169)
amagicPanel:SetFrameStrata('BACKGROUND')
amagicPanel:SetSize(64, 64)
amagicPanel:SetMovable(true)
amagicPanel:SetUserPlaced(true)
amagicPanel:RegisterForDrag('LeftButton')
amagicPanel:SetScript('OnDragStart', amagicPanel.StartMoving)
amagicPanel:SetScript('OnDragStop', amagicPanel.StopMovingOrSizing)
amagicPanel:Hide()
amagicPanel.icon = amagicPanel:CreateTexture(nil, 'BACKGROUND')
amagicPanel.icon:SetAllPoints(amagicPanel)
amagicPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
amagicPanel.border = amagicPanel:CreateTexture(nil, 'ARTWORK')
amagicPanel.border:SetAllPoints(amagicPanel)
amagicPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
amagicPanel.border:Hide()
amagicPanel.dimmer = amagicPanel:CreateTexture(nil, 'BORDER')
amagicPanel.dimmer:SetAllPoints(amagicPanel)
amagicPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
amagicPanel.dimmer:Hide()
amagicPanel.swipe = CreateFrame('Cooldown', nil, amagicPanel, 'CooldownFrameTemplate')
amagicPanel.swipe:SetAllPoints(amagicPanel)
amagicPanel.swipe:SetDrawBling(false)
amagicPanel.swipe:SetDrawEdge(false)
amagicPanel.text = CreateFrame('Frame', nil, amagicPanel)
amagicPanel.text:SetAllPoints(amagicPanel)
amagicPanel.text.tl = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.text.tl:SetPoint('TOPLEFT', amagicPanel, 'TOPLEFT', 2.5, -3)
amagicPanel.text.tl:SetJustifyH('LEFT')
amagicPanel.text.tr = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.text.tr:SetPoint('TOPRIGHT', amagicPanel, 'TOPRIGHT', -2.5, -3)
amagicPanel.text.tr:SetJustifyH('RIGHT')
amagicPanel.text.bl = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.text.bl:SetPoint('BOTTOMLEFT', amagicPanel, 'BOTTOMLEFT', 2.5, 3)
amagicPanel.text.bl:SetJustifyH('LEFT')
amagicPanel.text.br = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.text.br:SetPoint('BOTTOMRIGHT', amagicPanel, 'BOTTOMRIGHT', -2.5, 3)
amagicPanel.text.br:SetJustifyH('RIGHT')
amagicPanel.text.center = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.text.center:SetAllPoints(amagicPanel.text)
amagicPanel.text.center:SetJustifyH('CENTER')
amagicPanel.text.center:SetJustifyV('CENTER')
amagicPanel.button = CreateFrame('Button', nil, amagicPanel)
amagicPanel.button:SetAllPoints(amagicPanel)
amagicPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local amagicPreviousPanel = CreateFrame('Frame', 'amagicPreviousPanel', UIParent)
amagicPreviousPanel:SetFrameStrata('BACKGROUND')
amagicPreviousPanel:SetSize(64, 64)
amagicPreviousPanel:SetMovable(true)
amagicPreviousPanel:SetUserPlaced(true)
amagicPreviousPanel:RegisterForDrag('LeftButton')
amagicPreviousPanel:SetScript('OnDragStart', amagicPreviousPanel.StartMoving)
amagicPreviousPanel:SetScript('OnDragStop', amagicPreviousPanel.StopMovingOrSizing)
amagicPreviousPanel:Hide()
amagicPreviousPanel.icon = amagicPreviousPanel:CreateTexture(nil, 'BACKGROUND')
amagicPreviousPanel.icon:SetAllPoints(amagicPreviousPanel)
amagicPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
amagicPreviousPanel.border = amagicPreviousPanel:CreateTexture(nil, 'ARTWORK')
amagicPreviousPanel.border:SetAllPoints(amagicPreviousPanel)
amagicPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
local amagicCooldownPanel = CreateFrame('Frame', 'amagicCooldownPanel', UIParent)
amagicCooldownPanel:SetFrameStrata('BACKGROUND')
amagicCooldownPanel:SetSize(64, 64)
amagicCooldownPanel:SetMovable(true)
amagicCooldownPanel:SetUserPlaced(true)
amagicCooldownPanel:RegisterForDrag('LeftButton')
amagicCooldownPanel:SetScript('OnDragStart', amagicCooldownPanel.StartMoving)
amagicCooldownPanel:SetScript('OnDragStop', amagicCooldownPanel.StopMovingOrSizing)
amagicCooldownPanel:Hide()
amagicCooldownPanel.icon = amagicCooldownPanel:CreateTexture(nil, 'BACKGROUND')
amagicCooldownPanel.icon:SetAllPoints(amagicCooldownPanel)
amagicCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
amagicCooldownPanel.border = amagicCooldownPanel:CreateTexture(nil, 'ARTWORK')
amagicCooldownPanel.border:SetAllPoints(amagicCooldownPanel)
amagicCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
amagicCooldownPanel.dimmer = amagicCooldownPanel:CreateTexture(nil, 'BORDER')
amagicCooldownPanel.dimmer:SetAllPoints(amagicCooldownPanel)
amagicCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
amagicCooldownPanel.dimmer:Hide()
amagicCooldownPanel.swipe = CreateFrame('Cooldown', nil, amagicCooldownPanel, 'CooldownFrameTemplate')
amagicCooldownPanel.swipe:SetAllPoints(amagicCooldownPanel)
amagicCooldownPanel.swipe:SetDrawBling(false)
amagicCooldownPanel.swipe:SetDrawEdge(false)
amagicCooldownPanel.text = amagicCooldownPanel:CreateFontString(nil, 'OVERLAY')
amagicCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicCooldownPanel.text:SetAllPoints(amagicCooldownPanel)
amagicCooldownPanel.text:SetJustifyH('CENTER')
amagicCooldownPanel.text:SetJustifyV('CENTER')
local amagicInterruptPanel = CreateFrame('Frame', 'amagicInterruptPanel', UIParent)
amagicInterruptPanel:SetFrameStrata('BACKGROUND')
amagicInterruptPanel:SetSize(64, 64)
amagicInterruptPanel:SetMovable(true)
amagicInterruptPanel:SetUserPlaced(true)
amagicInterruptPanel:RegisterForDrag('LeftButton')
amagicInterruptPanel:SetScript('OnDragStart', amagicInterruptPanel.StartMoving)
amagicInterruptPanel:SetScript('OnDragStop', amagicInterruptPanel.StopMovingOrSizing)
amagicInterruptPanel:Hide()
amagicInterruptPanel.icon = amagicInterruptPanel:CreateTexture(nil, 'BACKGROUND')
amagicInterruptPanel.icon:SetAllPoints(amagicInterruptPanel)
amagicInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
amagicInterruptPanel.border = amagicInterruptPanel:CreateTexture(nil, 'ARTWORK')
amagicInterruptPanel.border:SetAllPoints(amagicInterruptPanel)
amagicInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
amagicInterruptPanel.swipe = CreateFrame('Cooldown', nil, amagicInterruptPanel, 'CooldownFrameTemplate')
amagicInterruptPanel.swipe:SetAllPoints(amagicInterruptPanel)
amagicInterruptPanel.swipe:SetDrawBling(false)
amagicInterruptPanel.swipe:SetDrawEdge(false)
local amagicExtraPanel = CreateFrame('Frame', 'amagicExtraPanel', UIParent)
amagicExtraPanel:SetFrameStrata('BACKGROUND')
amagicExtraPanel:SetSize(64, 64)
amagicExtraPanel:SetMovable(true)
amagicExtraPanel:SetUserPlaced(true)
amagicExtraPanel:RegisterForDrag('LeftButton')
amagicExtraPanel:SetScript('OnDragStart', amagicExtraPanel.StartMoving)
amagicExtraPanel:SetScript('OnDragStop', amagicExtraPanel.StopMovingOrSizing)
amagicExtraPanel:Hide()
amagicExtraPanel.icon = amagicExtraPanel:CreateTexture(nil, 'BACKGROUND')
amagicExtraPanel.icon:SetAllPoints(amagicExtraPanel)
amagicExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
amagicExtraPanel.border = amagicExtraPanel:CreateTexture(nil, 'ARTWORK')
amagicExtraPanel.border:SetAllPoints(amagicExtraPanel)
amagicExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.ARCANE] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5'},
		{6, '6'},
		{7, '7+'},
	},
	[SPEC.FIRE] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.FROST] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	amagicPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function Automagically_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Automagically_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Automagically_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
	local count = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function AutoAoe:Purge()
	local update
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		mana_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if self:ManaCost() > Player.mana.current then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	local remains = duration - (Player.ctime - start)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - Player.execute_remains)
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and count or 0
		end
	end
	return 0
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.max) or 0
end

function Ability:ACCost()
	return self.arcane_charge_cost
end

function Ability:ACGain()
	return self.arcane_charge_gain
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + (self.off_gcd and 0 or Player.execute_remains))) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return 0
	end
	return castTime / 1000
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		amagicPreviousPanel.ability = self
		amagicPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		amagicPreviousPanel.icon:SetTexture(self.icon)
		amagicPreviousPanel:SetShown(amagicPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and amagicPreviousPanel.ability == self then
		amagicPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, Abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, Abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	return aura
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFocus():GetNodeID()
]]

-- Mage Abilities
---- Class
------ Baseline
local ArcaneExplosion = Ability:Add(1449, false, true)
ArcaneExplosion.mana_cost = 10
ArcaneExplosion:AutoAoe()
local ArcaneIntellect = Ability:Add(1459, true, false)
ArcaneIntellect.mana_cost = 4
ArcaneIntellect.buff_duration = 3600
local Blink = Ability:Add(1953, true, true)
Blink.mana_cost = 2
Blink.cooldown_duration = 15
local ConeOfCold = Ability:Add(120, false, true, 212792)
ConeOfCold.mana_cost = 4
ConeOfCold.buff_duration = 5
ConeOfCold.cooldown_duration = 12
ConeOfCold.ignore_immune = true
ConeOfCold:AutoAoe()
local Counterspell = Ability:Add(2139, false, true)
Counterspell.mana_cost = 2
Counterspell.cooldown_duration = 24
Counterspell.triggers_gcd = false
local FireBlast = Ability:Add(108853, false, true)
FireBlast.mana_cost = 1
FireBlast.cooldown_duration = 12
FireBlast.hasted_cooldown = true
FireBlast.requires_charge = true
FireBlast.triggers_gcd = false
FireBlast.off_gcd = true
local Frostbolt = Ability:Add(116, false, true, 228597)
Frostbolt.mana_cost = 2
Frostbolt:SetVelocity(35)
local FrostNova = Ability:Add(122, false, true)
FrostNova.mana_cost = 2
FrostNova.buff_duration = 6
FrostNova:AutoAoe()
local ShiftingPower = Ability:Add(382440, false, true, 382445)
ShiftingPower.mana_cost = 5
ShiftingPower.cooldown_duration = 60
ShiftingPower.buff_duration = 4
ShiftingPower.tick_interval = 1
ShiftingPower.hasted_duration = true
ShiftingPower.hasted_ticks = true
ShiftingPower:AutoAoe()
local TimeWarp = Ability:Add(80353, true, true)
TimeWarp.mana_cost = 4
TimeWarp.buff_duration = 40
TimeWarp.cooldown_duration = 300
TimeWarp.triggers_gcd = false
------ Talents
local AlterTime = Ability:Add(342245, true, true, 342246)
AlterTime.mana_cost = 1
AlterTime.cooldown_duration = 60
AlterTime.buff_duration = 10
AlterTime.revert = Ability:Add(342247, true, true)
local BlastWave = Ability:Add(157981, false, true, 220362)
BlastWave.buff_duration = 6
BlastWave.cooldown_duration = 30
local IceBlock = Ability:Add(45438, true, true)
IceBlock.cooldown_duration = 240
IceBlock.buff_duration = 10
local IceNova = Ability:Add(157997, false, true)
IceNova.buff_duration = 2
IceNova.cooldown_duration = 25
IceNova:AutoAoe()
local IncantersFlow = Ability:Add(1463, true, true, 116267)
local MirrorImage = Ability:Add(55342, true, true)
MirrorImage.mana_cost = 2
MirrorImage.buff_duration = 40
MirrorImage.cooldown_duration = 120
local RemoveCurse = Ability:Add(475, false, true)
RemoveCurse.mana_cost = 1.3
RemoveCurse.cooldown_duration = 8
local Shimmer = Ability:Add(212653, true, true)
Shimmer.mana_cost = 2
Shimmer.cooldown_duration = 25
Shimmer.requires_charge = true
Shimmer.triggers_gcd = false
Shimmer.off_gcd = true
local Spellsteal = Ability:Add(30449, false, true)
Spellsteal.mana_cost = 21
------ Procs

---- Arcane
------ Talents
local Amplification = Ability:Add(236628, false, true)
local ArcaneBarrage = Ability:Add(44425, false, true)
ArcaneBarrage.cooldown_duration = 3
ArcaneBarrage.hasted_cooldown = true
ArcaneBarrage:SetVelocity(25)
ArcaneBarrage:AutoAoe()
local ArcaneBlast = Ability:Add(30451, false, true)
ArcaneBlast.mana_cost = 2.75
ArcaneBlast.arcane_charge_gain = 1
local ArcaneFamiliar = Ability:Add(205022, true, true, 210126)
ArcaneFamiliar.buff_duration = 3600
ArcaneFamiliar.cooldown_duration = 10
local ArcaneMissiles = Ability:Add(5143, false, true, 7268)
ArcaneMissiles.mana_cost = 15
ArcaneMissiles:SetVelocity(50)
local ArcaneOrb = Ability:Add(153626, false, true, 153640)
ArcaneOrb.mana_cost = 1
ArcaneOrb.cooldown_duration = 20
ArcaneOrb:AutoAoe()
local ArcanePower = Ability:Add(12042, true, true)
ArcanePower.buff_duration = 10
ArcanePower.cooldown_duration = 90
local Evocation = Ability:Add(12051, true, true)
Evocation.buff_duration = 6
Evocation.cooldown_duration = 90
local NetherTempest = Ability:Add(114923, false, true, 114954)
NetherTempest.mana_cost = 1.5
NetherTempest.buff_duration = 12
NetherTempest.tick_interval = 1
NetherTempest.hasted_ticks = true
NetherTempest:AutoAoe()
local PrismaticBarrier = Ability:Add(235450, true, true)
PrismaticBarrier.mana_cost = 3
PrismaticBarrier.buff_duration = 60
PrismaticBarrier.cooldown_duration = 25
local PresenceOfMind = Ability:Add(205025, true, true)
PresenceOfMind.cooldown_duration = 45
PresenceOfMind.triggers_gcd = false
local Resonance = Ability:Add(205028, false, true)
local RuleOfThrees = Ability:Add(264354, true, true, 264774)
RuleOfThrees.buff_duration = 15
local Slipstream = Ability:Add(236457, false, true)
local Supernova = Ability:Add(157980, false, true)
Supernova.cooldown_duration = 25
Supernova:AutoAoe()
------ Procs
local Clearcasting = Ability:Add(79684, true, true, 263725)
Clearcasting.buff_duration = 15
---- Fire
------ Talents
local AlexstraszasFury = Ability:Add(235870, false, true)
local BlazingBarrier = Ability:Add(235313, true, true)
BlazingBarrier.mana_cost = 3
BlazingBarrier.buff_duration = 60
BlazingBarrier.cooldown_duration = 25
local CharringEmbers = Ability:Add(408665, false, true) -- T30 2pc
CharringEmbers.buff_duration = 12
local Combustion = Ability:Add(190319, true, true)
Combustion.mana_cost = 10
Combustion.buff_duration = 10
Combustion.cooldown_duration = 120
Combustion.triggers_gcd = false
local Conflagration = Ability:Add(205023, false, true, 226757)
Conflagration.buff_duration = 8
Conflagration.tick_interval = 2
Conflagration.hasted_ticks = true
local DragonsBreath = Ability:Add(31661, false, true)
DragonsBreath.mana_cost = 4
DragonsBreath.buff_duration = 4
DragonsBreath.cooldown_duration = 45
DragonsBreath:AutoAoe()
local FeelTheBurn = Ability:Add(383391, true, true, 383395)
FeelTheBurn.buff_duration = 5
local Fireball = Ability:Add(133, false, true)
Fireball.mana_cost = 2
Fireball:SetVelocity(45)
local Firestarter = Ability:Add(205026, false, true)
local FlameAccelerant = Ability:Add(203275, true, true, 203277)
local FlameOn = Ability:Add(205029, false, true)
local FlamePatch = Ability:Add(205037, false, true, 205472)
local FlamesFury = Ability:Add(409964, true, true) -- T30 4pc
FlamesFury.buff_duration = 30
local Flamestrike = Ability:Add(2120, false, true)
Flamestrike.mana_cost = 2.5
Flamestrike.buff_duration = 8
Flamestrike:AutoAoe()
local FuryOfTheSunKing = Ability:Add(383883, true, true)
FuryOfTheSunKing.buff_duration = 30
local Hyperthermia = Ability:Add(383860, true, true, 383874)
Hyperthermia.buff_duration = 6
local Ignite = Ability:Add(12846, false, true, 12654)
Ignite.buff_duration = 9
Ignite.tick_interval = 1
Ignite:AutoAoe(false, 'apply')
local ImprovedScorch = Ability:Add(383604, true, true, 383608)
ImprovedScorch.buff_duration = 12
local IncendiaryEruptions = Ability:Add(383665, false, true)
local Kindling = Ability:Add(155148, false, true)
local LivingBomb = Ability:Add(44457, false, true, 217694)
LivingBomb.mana_cost = 1.5
LivingBomb.buff_duration = 4
LivingBomb.cooldown_duration = 30
LivingBomb.tick_interval = 1
LivingBomb.hasted_duration = true
LivingBomb.hasted_cooldown = true
LivingBomb.hasted_ticks = true
LivingBomb.explosion = Ability:Add(44461, false, true)
LivingBomb.explosion:AutoAoe()
LivingBomb.spread = Ability:Add(244813, false, true)
LivingBomb.spread.buff_duration = 4
LivingBomb.spread.tick_interval = 1
LivingBomb.spread.hasted_duration = true
LivingBomb.spread.hasted_ticks = true
local Meteor = Ability:Add(153561, false, true, 153564)
Meteor.mana_cost = 1
Meteor.buff_duration = 8
Meteor.cooldown_duration = 45
Meteor:AutoAoe()
local PhoenixFlames = Ability:Add(257541, false, true, 257542)
PhoenixFlames.cooldown_duration = 25
PhoenixFlames.requires_charge = true
PhoenixFlames.travel_delay = 0.1
PhoenixFlames:SetVelocity(50)
PhoenixFlames:AutoAoe()
local Pyroblast = Ability:Add(11366, false, true)
Pyroblast.mana_cost = 2
Pyroblast:SetVelocity(35)
local Scorch = Ability:Add(2948, false, true)
Scorch.mana_cost = 1
local SearingTouch = Ability:Add(269644, false, true)
local SunKingsBlessing = Ability:Add(383886, true, true, 383882)
SunKingsBlessing.buff_duration = 30
local TemperedFlames = Ability:Add(383659, false, true)
local TemporalWarp = Ability:Add(386539, true, true, 386540)
TemporalWarp.buff_duration = 40
------ Procs
local HeatingUp = Ability:Add(48107, true, true)
HeatingUp.buff_duration = 10
local HotStreak = Ability:Add(195283, true, true, 48108)
HotStreak.buff_duration = 15
---- Frost
------ Talents
local Blizzard = Ability:Add(190356, false, true, 190357)
Blizzard.mana_cost = 2.5
Blizzard.buff_duration = 8
Blizzard.cooldown_duration = 8
Blizzard.tick_interval = 1
Blizzard.hasted_cooldown = true
Blizzard.hasted_duration = true
Blizzard.hasted_ticks = true
Blizzard:AutoAoe()
local Chilled = Ability:Add(205708, false, true)
Chilled.buff_duration = 15
local Flurry = Ability:Add(44614, false, true, 228354)
Flurry.mana_cost = 1
Flurry.buff_duration = 1
Flurry:SetVelocity(50)
local Freeze = Ability:Add(33395, false, true)
Freeze.cooldown_duration = 25
Freeze.buff_duration = 8
Freeze.requires_pet = true
Freeze.triggers_gcd = false
Freeze:AutoAoe()
local FreezingWinds = Ability:Add(382103, true, true, 382106)
FreezingWinds.buff_duration = 10
local FrozenOrb = Ability:Add(84714, false, true, 84721)
FrozenOrb.mana_cost = 1
FrozenOrb.buff_duration = 15
FrozenOrb.cooldown_duration = 60
FrozenOrb:SetVelocity(20)
FrozenOrb:AutoAoe()
local IceBarrier = Ability:Add(11426, true, true)
IceBarrier.mana_cost = 3
IceBarrier.buff_duration = 60
IceBarrier.cooldown_duration = 25
local IceLance = Ability:Add(30455, false, true, 228598)
IceLance.mana_cost = 1
IceLance:SetVelocity(47)
local IcyVeins = Ability:Add(12472, true, true)
IcyVeins.buff_duration = 20
IcyVeins.cooldown_duration = 180
local SummonWaterElemental = Ability:Add(31687, false, true)
SummonWaterElemental.mana_cost = 3
SummonWaterElemental.cooldown_duration = 30
local Waterbolt = Ability:Add(31707, false, true)
local BoneChilling = Ability:Add(205027, false, true, 205766)
BoneChilling.buff_duration = 8
local ChainReaction = Ability:Add(278309, true, true, 278310)
ChainReaction.buff_duration = 10
local CometStorm = Ability:Add(153595, false, true, 153596)
CometStorm.mana_cost = 1
CometStorm.cooldown_duration = 30
CometStorm:AutoAoe()
local Ebonbolt = Ability:Add(257537, false, true, 257538)
Ebonbolt.mana_cost = 2
Ebonbolt.cooldown_duration = 45
Ebonbolt:SetVelocity(30)
local FreezingRain = Ability:Add(270233, true, true, 270232)
FreezingRain.buff_duration = 12
local FrozenTouch = Ability:Add(205030, false, true)
local GlacialSpike = Ability:Add(199786, false, true, 228600)
GlacialSpike.mana_cost = 1
GlacialSpike.buff_duration = 4
GlacialSpike:SetVelocity(40)
local IceFloes = Ability:Add(108839, true, true)
IceFloes.requires_charge = true
IceFloes.buff_duration = 15
IceFloes.cooldown_duration = 20
local LonelyWinter = Ability:Add(205024, false, true)
local RayOfFrost = Ability:Add(205021, false, true)
RayOfFrost.mana_cost = 2
RayOfFrost.buff_duration = 5
RayOfFrost.cooldown_duration = 75
local SlickIce = Ability:Add(382144, true, true, 382148)
SlickIce.buff_duration = 60
local SplittingIce = Ability:Add(56377, false, true)
local ThermalVoid = Ability:Add(155149, false, true)
------ Procs
local BrainFreeze = Ability:Add(190447, true, true, 190446)
BrainFreeze.buff_duration = 15
local FingersOfFrost = Ability:Add(112965, true, true, 44544)
FingersOfFrost.buff_duration = 15
local Icicles = Ability:Add(76613, true, true, 205473)
Icicles.buff_duration = 60
local WintersChill = Ability:Add(228358, false, true)
WintersChill.buff_duration = 6
-- Tier set bonuses

-- Racials

-- PvP talents
local BurstOfCold = Ability:Add(206431, true, true, 206432)
BurstOfCold.buff_duration = 6
local Frostbite = Ability:Add(198120, false, true, 198121)
Frostbite.buff_duration = 4
-- Trinket Effects

-- Class cooldowns
local PowerInfusion = Ability:Add(10060, true)
PowerInfusion.buff_duration = 20
-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items

-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.trackAuras)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.trackAuras[#self.trackAuras + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 381301 or -- Feral Hide Drums (Leatherworking)
			id == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Exhausted()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HARMFUL')
		if (
			id == 57724 or -- Sated
			id == 57723 or -- Exhaustion
			id == 80354    -- Temporal Displacement
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateKnown()
	self.mana.max = UnitPowerMax('player', 0)
	self.arcane_charges.max = UnitPowerMax('player', 16)

	local node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsUsableSpell(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	AlterTime.revert.known = AlterTime.known
	if LonelyWinter.known then
		SummonWaterElemental.known = false
	end
	if IceLance.known then
		if SplittingIce.known then
			IceLance:AutoAoe()
		else
			IceLance.auto_aoe = nil
		end
	end
	Freeze.known = SummonWaterElemental.known
	Waterbolt.known = SummonWaterElemental.known
	WintersChill.known = BrainFreeze.known
	HeatingUp.known = HotStreak.known
	if LivingBomb.known or IncendiaryEruptions.known then
		LivingBomb.explosion.known = true
		LivingBomb.spread.known = true
	end
	if self.spec == SPEC.FIRE then
		CharringEmbers.known = self.set_bonus.t30 >= 2
		FlamesFury.known = self.set_bonus.t30 >= 4
	end

	Abilities:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability and ability == channel.ability then
		channel.chained = true
	else
		channel.ability = ability
	end
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, start, ends, duration, spellId
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.current = UnitPower('player', 0) + (self.mana.regen * self.execute_remains)
	if self.cast.ability then
		self.mana.current = self.mana.current - self.cast.ability:ManaCost()
	end
	self.mana.current = clamp(self.mana.current, 0, self.mana.max)
	if self.spec == SPEC.ARCANE then
		self.arcane_charges.current = UnitPower('player', 16)
		if self.cast.ability then
			if self.cast.ability.arcane_charge_cost then
				self.arcane_charges.current = self.arcane_charges.current - self.cast.ability:ACCost()
			end
			if self.cast.ability.arcane_charge_gain then
				self.arcane_charges.current = self.arcane_charges.current + self.cast.ability:ACGain()
			end
		end
		self.arcane_charges.current = clamp(self.arcane_charges.current, 0, self.arcane_charges.max)
	end
	self.moving = GetUnitSpeed('player') ~= 0
	self:UpdateThreat()

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	if Blizzard.known then
		self.blizzard_remains = Blizzard:Remains()
	end
	self.major_cd_remains = (Combustion.known and Combustion:Remains()) or (IcyVeins.known and IcyVeins:Remains()) or (ArcanePower.known and ArcanePower:Remains()) or 0

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	amagicPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			amagicPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			amagicPreviousPanel:Hide()
		end
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health.max > Player.health.max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		amagicPanel:Show()
		return true
	end
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

function Target:Frozen()
	return FrostNova:Up() or WintersChill:Up() or (IceNova.known and IceNova:Up()) or (Freeze.known and Freeze:Up()) or (GlacialSpike.known and GlacialSpike:Up()) or (Frostbite.known and Frostbite:Up())
end

-- End Target Functions

-- Start Ability Modifications

function Ability:ManaCost()
	if self.mana_cost == 0 then
		return 0
	end
	local cost = self.mana_cost / 100 * Player.mana.max
	if ArcanePower.known and ArcanePower:Up() then
		cost = cost - cost * 0.60
	end
	return max(0, cost)
end

function ArcaneBlast:ManaCost()
	if Ability.Up(RuleOfThrees) then
		return 0
	end
	return Ability.ManaCost(self) * (Player.arcane_charges.current + 1)
end

function ArcaneExplosion:ManaCost()
	if Clearcasting:Up() then
		return 0
	end
	return Ability.ManaCost(self)
end

function ArcaneMissiles:ManaCost()
	if RuleOfThrees:Up() or Clearcasting:Up() then
		return 0
	end
	return Ability.ManaCost(self)
end

function RuleOfThrees:Remains()
	if ArcaneBlast:Casting() then
		return 0
	end
	return Ability.Remains(self)
end

function PresenceOfMind:Cooldown()
	if self:Up() then
		return self:CooldownDuration()
	end
	return Ability.Cooldown(self)
end

function Freeze:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end

function FrostNova:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end

function TimeWarp:Usable()
	if not TemporalWarp.known and Player:Exhausted() then
		return false
	end
	return Ability.Usable(self)
end

function Blizzard:Remains()
	if self:Casting() then
		return self:Duration()
	end
	return max(0, self.last_used + (self.ground_duration or self.buff_duration) - Player.time - Player.execute_remains)
end

function BrainFreeze:Remains()
	if Ebonbolt:Casting() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function FrozenOrb:Remains()
	return max(0, self.last_used + self.buff_duration - Player.time - Player.execute_remains)
end

function FreezingWinds:Remains()
	local remains = Ability.Remains(self)
	if remains > 0 then
		return FrozenOrb:Remains()
	end
	return 0
end

function GlacialSpike:Remains()
	if Target.stunnable and self:Casting() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function GlacialSpike:Usable()
	if Icicles:Stack() < 5 or Icicles:Remains() < self:CastTime() then
		return false
	end
	return Ability.Usable(self)
end

function WintersChill:Remains()
	if Flurry:Traveling() > 0 then
		return self:Duration()
	end
	if self:Stack() == 0 then
		return 0
	end
	return Ability.Remains(self)
end

function WintersChill:Stack()
	local stack
	if Flurry:Traveling() > 0 then
		stack = 2
	else
		stack = Ability.Stack(self)
	end
	if stack > 0 then
		stack = stack - Frostbolt:Traveling() - IceLance:Traveling()
	end
	return max(0, stack)
end

function Icicles:Stack()
	if GlacialSpike:Casting() then
		return 0
	end
	local count = Ability.Stack(self)
	if Frostbolt:Casting() or Flurry:Casting() then
		count = count + 1
	end
	return min(5, count)
end

function Firestarter:Remains()
	if not self.known or Target.health.pct <= 90 then
		return 0
	end
	if Target.health.loss_per_sec <= 0 then
		return 600
	end
	local health_above_90 = (Target.health.current - (Target.health.loss_per_sec * Player.execute_remains)) - (Target.health.max * 0.90)
	return health_above_90 / Target.health.loss_per_sec
end

function SearingTouch:Remains()
	return self.known and Target.health.pct < 30 and 600 or 0
end

function HeatingUp:Remains()
	if (
		(Scorch:Casting() and ((SearingTouch.known and SearingTouch:Up()) or (Combustion.known and Combustion:Up())))
	) then
		if Ability.Remains(self) > 0 or Ability.Remains(HotStreak) > 0 then
			return 0
		end
		return self:Duration()
	end
	return Ability.Remains(self)
end

function HotStreak:Remains()
	if Ability.Remains(HeatingUp) > 0 and (
		(Scorch:Casting() and ((SearingTouch.known and SearingTouch:Up()) or (Combustion.known and Combustion:Up())))
	) then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function Pyroblast:Free()
	return HotStreak:Up()
end

function Flamestrike:Free()
	return HotStreak:Up()
end

function Combustion:Remains()
	local remains = Ability.Remains(self)
	if SunKingsBlessing.known and Ability.Remains(FuryOfTheSunKing) > 0 and (Pyroblast:Casting() or Flamestrike:Casting()) then
		remains = remains + 6
	end
	return remains
end

function FuryOfTheSunKing:Remains()
	if Pyroblast:Casting() or Flamestrike:Casting() then
		return 0
	end
	return Ability.Remains(self)
end

function Meteor:LandingIn(seconds)
	if (Player.time - Meteor.last_used) > 3 then
		return false
	end
	return (3 - (Player.time - Meteor.last_used)) < seconds
end

function CharringEmbers:Remains()
	if self.known and PhoenixFlames:Traveling() > 0 then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function Blizzard:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	self.ground_duration = self:Duration()
end

function ArcanePower:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	APL[SPEC.ARCANE]:toggle_burn_phase(true)
end

function Evocation:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	APL[SPEC.ARCANE]:toggle_burn_phase(false)
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

local function WaitFor(ability, wait_time)
	Player.wait_time = wait_time and (Player.ctime + wait_time) or (Player.ctime + ability:Cooldown())
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.ARCANE].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 300 then
			return ArcaneIntellect
		end
	else
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 10 then
			UseExtra(ArcaneIntellect)
		end
	end
end

APL[SPEC.FIRE].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if Opt.barrier and BlazingBarrier:Usable() and BlazingBarrier:Remains() < 15 then
			UseCooldown(BlazingBarrier)
		end
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 300 then
			return ArcaneIntellect
		end
	else
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 10 then
			UseExtra(ArcaneIntellect)
		elseif Opt.barrier and BlazingBarrier:Usable() and BlazingBarrier:Remains() < 5 then
			UseExtra(BlazingBarrier)
		elseif MirrorImage:Usable() and Player:UnderAttack() then
			UseExtra(MirrorImage)
		end
	end
--[[
actions=counterspell
actions+=/call_action_list,name=combustion_timing,if=!variable.disable_combustion
actions+=/time_warp,if=talent.temporal_warp&(buff.exhaustion.up|interpolated_fight_remains<buff.bloodlust.duration)
actions+=/potion,if=buff.potion.duration>variable.time_to_combustion+buff.combustion.duration
actions+=/variable,name=shifting_power_before_combustion,value=variable.time_to_combustion>cooldown.shifting_power.remains
actions+=/variable,name=item_cutoff_active,value=(variable.time_to_combustion<variable.on_use_cutoff|buff.combustion.remains>variable.skb_duration&!cooldown.item_cd_1141.remains)&((trinket.1.has_cooldown&trinket.1.cooldown.remains<variable.on_use_cutoff)+(trinket.2.has_cooldown&trinket.2.cooldown.remains<variable.on_use_cutoff)>1)
actions+=/use_item,effect_name=gladiators_badge,if=variable.time_to_combustion>cooldown-5
actions+=/use_item,name=moonlit_prism,if=variable.time_to_combustion<=5|fight_remains<variable.time_to_combustion
actions+=/use_items,if=!variable.item_cutoff_active
actions+=/variable,use_off_gcd=1,use_while_casting=1,name=fire_blast_pooling,value=buff.combustion.down&action.fire_blast.charges_fractional+(variable.time_to_combustion+action.shifting_power.full_reduction*variable.shifting_power_before_combustion)%cooldown.fire_blast.duration-1<cooldown.fire_blast.max_charges+variable.overpool_fire_blasts%cooldown.fire_blast.duration-(buff.combustion.duration%cooldown.fire_blast.duration)%%1&variable.time_to_combustion<fight_remains
actions+=/call_action_list,name=combustion_phase,if=variable.time_to_combustion<=0|buff.combustion.up|variable.time_to_combustion<variable.combustion_precast_time&cooldown.combustion.remains<variable.combustion_precast_time
actions+=/variable,use_off_gcd=1,use_while_casting=1,name=fire_blast_pooling,value=searing_touch.active&action.fire_blast.full_recharge_time>3*gcd.max,if=!variable.fire_blast_pooling&talent.sun_kings_blessing
actions+=/shifting_power,if=buff.combustion.down&(action.fire_blast.charges=0|variable.fire_blast_pooling)&!buff.hot_streak.react&variable.shifting_power_before_combustion
actions+=/variable,name=phoenix_pooling,if=active_enemies<variable.combustion_flamestrike,value=(variable.time_to_combustion+buff.combustion.duration-5<action.phoenix_flames.full_recharge_time+cooldown.phoenix_flames.duration-action.shifting_power.full_reduction*variable.shifting_power_before_combustion&variable.time_to_combustion<fight_remains|talent.sun_kings_blessing)&!talent.alexstraszas_fury
actions+=/variable,name=phoenix_pooling,if=active_enemies>=variable.combustion_flamestrike,value=(variable.time_to_combustion<action.phoenix_flames.full_recharge_time-action.shifting_power.full_reduction*variable.shifting_power_before_combustion&variable.time_to_combustion<fight_remains|talent.sun_kings_blessing)&!talent.alexstraszas_fury
actions+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=!variable.fire_blast_pooling&variable.time_to_combustion>0&active_enemies>=variable.hard_cast_flamestrike&!firestarter.active&!buff.hot_streak.react&(buff.heating_up.react&action.flamestrike.execute_remains<0.5|charges_fractional>=2)
actions+=/call_action_list,name=firestarter_fire_blasts,if=buff.combustion.down&firestarter.active&variable.time_to_combustion>0
actions+=/fire_blast,use_while_casting=1,if=action.shifting_power.executing&full_recharge_time<action.shifting_power.tick_reduction
actions+=/call_action_list,name=standard_rotation,if=variable.time_to_combustion>0&buff.combustion.down
actions+=/ice_nova,if=!searing_touch.active
actions+=/scorch
]]
	self:combustion_timing()
	if self.use_cds and TemporalWarp.known and TimeWarp:Usable() and Player:Exhausted() then
		UseCooldown(TimeWarp)
	end
	self.hot_streak_spells_in_flight = HeatingUp:Up() and (
		(PhoenixFlames.known and AlexstraszasFury.known and PhoenixFlames:Traveling() or 0) +
		(Combustion:Up() and HeatingUp:Up() and (Fireball:Traveling(true) + Pyroblast:Traveling(true)) or 0) +
		(Firestarter.known and Firestarter:Up() and (Fireball:Traveling() + Pyroblast:Traveling()) or 0) +
		(Hyperthermia.known and Hyperthermia:Up() and Pyroblast:Traveling(true) or 0)
	) or 0
	self.shifting_power_before_combustion = self.time_to_combustion > ShiftingPower:Cooldown()
	self.fire_blast_pooling = (
		(Combustion:Cooldown() < FireBlast:FullRechargeTime() and Firestarter:Down() and Combustion:Cooldown() < Target.timeToDie) or
		(Firestarter.known and Firestarter:Up() and Firestarter:Remains() < FireBlast:FullRechargeTime())
	)
	local apl
	if Combustion.known and (self.time_to_combustion <= 0 or Combustion:Up() or (self.time_to_combustion < self.combustion_precast_time and Combustion:Ready(self.combustion_precast_time))) then
		apl = self:combustion_phase()
		if apl then return apl end
	end
	if self.use_cds and ShiftingPower:Usable() and self.shifting_power_before_combustion and Combustion:Down() and (FireBlast:Charges() == 0 or self.fire_blast_pooling) and HotStreak:Down() then
		UseCooldown(ShiftingPower)
	end
	if Player.enemies < self.combustion_flamestrike then
		self.phoenix_pooling = (SunKingsBlessing.known or ((self.time_to_combustion + Combustion:Duration() - 5) < (PhoenixFlames:FullRechargeTime() + PhoenixFlames:CooldownDuration() - (self.shifting_power_before_combustion and 12 or 0))) and (Target.boss and self.time_to_combustion < Target.timeToDie)) and not AlexstraszasFury.known
	else
		self.phoenix_pooling = (SunKingsBlessing.known or (self.time_to_combustion < (PhoenixFlames:FullRechargeTime() - (self.shifting_power_before_combustion and 12 or 0)) and (Target.boss and self.time_to_combustion < Target.timeToDie))) and not AlexstraszasFury.known
	end
	if FireBlast:Usable() and not self.fire_blast_pooling and self.time_to_combustion > 0 and Player.enemies >= self.hard_cast_flamestrike and Firestarter:Down() and HotStreak:Down() and (FireBlast:ChargesFractional() >= 2 or (HeatingUp:Up() and Flamestrike:Casting() and Player.cast.remains < 0.5)) then
		UseExtra(FireBlast, true)
	end
	if Firestarter.known and self.time_to_combustion > 0 and Combustion:Down() and Firestarter:Up() then
		self:firestarter_fire_blasts()
	end
	if FireBlast:Usable() and ShiftingPower:Channeling() and FireBlast:FullRechargeTime() < 3 then
		UseExtra(FireBlast, true)
	end
	if self.time_to_combustion > 0 and Combustion:Down() then
		apl = self:standard_rotation()
		if apl then return apl end
	end
	if IceNova:Usable() and SearingTouch:Down() then
		UseCooldown(IceNova)
	end
	if Scorch:Usable() then
		return Scorch
	end
end

APL[SPEC.FIRE].precombat_variables = function(self)
--[[
actions.precombat+=/variable,name=disable_combustion,op=reset
actions.precombat+=/variable,name=firestarter_combustion,default=-1,value=talent.sun_kings_blessing,if=variable.firestarter_combustion<0
actions.precombat+=/variable,name=hot_streak_flamestrike,if=variable.hot_streak_flamestrike=0,value=3*talent.flame_patch+999*!talent.flame_patch
actions.precombat+=/variable,name=hard_cast_flamestrike,if=variable.hard_cast_flamestrike=0,value=999
actions.precombat+=/variable,name=combustion_flamestrike,if=variable.combustion_flamestrike=0,value=3*talent.flame_patch+999*!talent.flame_patch
actions.precombat+=/variable,name=skb_flamestrike,if=variable.skb_flamestrike=0,value=3
actions.precombat+=/variable,name=arcane_explosion,if=variable.arcane_explosion=0,value=999
actions.precombat+=/variable,name=arcane_explosion_mana,default=40,op=reset
actions.precombat+=/variable,name=combustion_shifting_power,if=variable.combustion_shifting_power=0,value=999
actions.precombat+=/variable,name=combustion_cast_remains,default=0.3,op=reset
actions.precombat+=/variable,name=overpool_fire_blasts,default=0,op=reset
actions.precombat+=/variable,name=time_to_combustion,value=fight_remains+100,if=variable.disable_combustion
actions.precombat+=/variable,name=skb_duration,value=dbc.effect.1016075.base_value
actions.precombat+=/variable,name=combustion_on_use,value=equipped.gladiators_badge|equipped.moonlit_prism|equipped.irideus_fragment|equipped.spoils_of_neltharus|equipped.tome_of_unstable_power|equipped.timebreaching_talon|equipped.horn_of_valor
actions.precombat+=/variable,name=on_use_cutoff,value=20,if=variable.combustion_on_use
]]
	self.disable_combustion = false
	self.firestarter_combustion = SunKingsBlessing.known
	self.hot_streak_flamestrike = FlamePatch.known and 3 or 999
	self.hard_cast_flamestrike = 999
	self.combustion_flamestrike = FlamePatch.known and 3 or 999
	self.skb_flamestrike = 3
	self.arcane_explosion = 999
	self.arcane_explosion_mana = 40
	self.combustion_shifting_power = 999
	self.combustion_cast_remains = 1
	self.overpool_fire_blasts = false
	self.time_to_combustion = 0
	self.skb_duration = 6
end

APL[SPEC.FIRE].firestarter_fire_blasts = function(self)
--[[
actions.firestarter_fire_blasts=fire_blast,use_while_casting=1,if=!variable.fire_blast_pooling&!buff.hot_streak.react&(action.fireball.execute_remains>gcd.remains|action.pyroblast.executing)&buff.heating_up.react+hot_streak_spells_in_flight=1&(cooldown.shifting_power.ready|charges>1|buff.feel_the_burn.remains<2*gcd.max)
actions.firestarter_fire_blasts+=/fire_blast,use_off_gcd=1,if=!variable.fire_blast_pooling&buff.heating_up.react+hot_streak_spells_in_flight=1&(talent.feel_the_burn&buff.feel_the_burn.remains<gcd.remains|cooldown.shifting_power.ready&(!set_bonus.tier30_2pc|debuff.charring_embers.remains>2*gcd.max))
]]
	if FireBlast:Usable() and not self.fire_blast_pooling and HotStreak:Down() and HeatingUp:Up() and self.hot_streak_spells_in_flight == 0 and (
		((Fireball:Casting() or Pyroblast:Casting()) and (ShiftingPower:Ready() or FireBlast:Charges() > 1 or FeelTheBurn:Remains() < (2 * Player.gcd))) or
		(FeelTheBurn.known and FeelTheBurn:Remains() < Player.execute_remains) or
		(ShiftingPower:Ready() and (not CharringEmbers.known or CharringEmbers:Remains() > (2 * Player.gcd)))
	) then
		UseExtra(FireBlast, true)
	end
end

APL[SPEC.FIRE].combustion_timing = function(self)
--[[
actions.combustion_timing=variable,use_off_gcd=1,use_while_casting=1,name=combustion_ready_time,value=cooldown.combustion.remains*expected_kindling_reduction
actions.combustion_timing+=/variable,use_off_gcd=1,use_while_casting=1,name=combustion_precast_time,value=action.fireball.cast_time*(active_enemies<variable.combustion_flamestrike)+action.flamestrike.cast_time*(active_enemies>=variable.combustion_flamestrike)-variable.combustion_cast_remains
actions.combustion_timing+=/variable,use_off_gcd=1,use_while_casting=1,name=time_to_combustion,value=variable.combustion_ready_time
actions.combustion_timing+=/variable,use_off_gcd=1,use_while_casting=1,name=time_to_combustion,op=max,value=firestarter.remains,if=talent.firestarter&!variable.firestarter_combustion
actions.combustion_timing+=/variable,use_off_gcd=1,use_while_casting=1,name=time_to_combustion,op=max,value=(buff.sun_kings_blessing.max_stack-buff.sun_kings_blessing.stack)*(3*gcd.max),if=talent.sun_kings_blessing&firestarter.active&buff.fury_of_the_sun_king.down
actions.combustion_timing+=/variable,use_off_gcd=1,use_while_casting=1,name=time_to_combustion,op=max,value=cooldown.gladiators_badge_345228.remains,if=equipped.gladiators_badge&cooldown.gladiators_badge_345228.remains-20<variable.time_to_combustion
actions.combustion_timing+=/variable,use_off_gcd=1,use_while_casting=1,name=time_to_combustion,op=max,value=buff.combustion.remains
actions.combustion_timing+=/variable,use_off_gcd=1,use_while_casting=1,name=time_to_combustion,op=max,value=raid_event.adds.in,if=raid_event.adds.exists&raid_event.adds.count>=3&raid_event.adds.duration>15
actions.combustion_timing+=/variable,use_off_gcd=1,use_while_casting=1,name=time_to_combustion,value=raid_event.vulnerable.in*!raid_event.vulnerable.up,if=raid_event.vulnerable.exists&variable.combustion_ready_time<raid_event.vulnerable.in
actions.combustion_timing+=/variable,use_off_gcd=1,use_while_casting=1,name=time_to_combustion,value=variable.combustion_ready_time,if=variable.combustion_ready_time+cooldown.combustion.duration*(1-(0.4+0.2*talent.firestarter)*talent.kindling)<=variable.time_to_combustion|variable.time_to_combustion>fight_remains-20
]]
	self.use_cds = (Target.boss and Player.group_size >= 10) or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or Combustion:Remains() > self.skb_duration
	self.combustion_ready_time = not self.use_cds and 999 or Combustion:CooldownExpected()
	self.combustion_precast_time = (Player.enemies < self.combustion_flamestrike and Fireball:CastTime() or 0) + (Player.enemies >= self.combustion_flamestrike and Flamestrike:CastTime() or 0) - self.combustion_cast_remains
	self.time_to_combustion = self.combustion_ready_time
end

APL[SPEC.FIRE].active_talents = function(self)
--[[
actions.active_talents=living_bomb,if=active_enemies>1&buff.combustion.down&(variable.time_to_combustion>cooldown.living_bomb.duration|variable.time_to_combustion<=0)
actions.active_talents+=/meteor,if=variable.time_to_combustion<=0|buff.combustion.remains>travel_time|!talent.sun_kings_blessing&(cooldown.meteor.duration<variable.time_to_combustion|fight_remains<variable.time_to_combustion)
actions.active_talents+=/dragons_breath,if=talent.alexstraszas_fury&(buff.combustion.down&!buff.hot_streak.react)&(buff.feel_the_burn.up|time>15)&!firestarter.remains&!talent.tempered_flames
actions.active_talents+=/dragons_breath,if=talent.alexstraszas_fury&(buff.combustion.down&!buff.hot_streak.react)&(buff.feel_the_burn.up|time>15)&talent.tempered_flames
]]
	if LivingBomb:Usable() and Player.enemies > 1 and Combustion:Down() and (self.time_to_combustion <= 0 or self.time_to_combustion > LivingBomb:CooldownDuration()) then
		return UseCooldown(LivingBomb)
	end
	if self.use_cds and Meteor:Usable() and (
		((self.time_to_combustion <= 0 and FuryOfTheSunKing:Down()) or Combustion:Remains() > 3) or
		(not SunKingsBlessing.known and (Meteor:CooldownDuration() < self.time_to_combustion or (Target.boss and Target.timeToDie < self.time_to_combustion)))
	) then
		return UseCooldown(Meteor)
	end
	if AlexstraszasFury.known and DragonsBreath:Usable() and Target.estimated_range < 15 and Combustion:Down() and HotStreak:Down() and (FeelTheBurn:Up() or Player:TimeInCombat() > 15) and (TemperedFlames.known or (not TemperedFlames.known and Firestarter:Down())) then
		return UseCooldown(DragonsBreath)
	end
end

APL[SPEC.FIRE].combustion_phase = function(self)
--[[
actions.combustion_phase=lights_judgment,if=buff.combustion.down
actions.combustion_phase+=/bag_of_tricks,if=buff.combustion.down
actions.combustion_phase+=/living_bomb,if=active_enemies>1&buff.combustion.down
actions.combustion_phase+=/call_action_list,name=combustion_cooldowns,if=buff.combustion.remains>variable.skb_duration|fight_remains<20
actions.combustion_phase+=/use_item,name=hyperthread_wristwraps,if=hyperthread_wristwraps.fire_blast>=2&action.fire_blast.charges=0
actions.combustion_phase+=/use_item,name=neural_synapse_enhancer,if=variable.time_to_combustion>60
actions.combustion_phase+=/phoenix_flames,if=set_bonus.tier30_2pc&!action.phoenix_flames.in_flight&debuff.charring_embers.remains<2*gcd.max
actions.combustion_phase+=/call_action_list,name=active_talents
actions.combustion_phase+=/flamestrike,if=buff.combustion.down&buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.remains>cast_time&buff.fury_of_the_sun_king.expiration_delay_remains=0&cooldown.combustion.remains<cast_time&active_enemies>=variable.skb_flamestrike
actions.combustion_phase+=/pyroblast,if=buff.combustion.down&buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.remains>cast_time&buff.fury_of_the_sun_king.expiration_delay_remains=0
actions.combustion_phase+=/fireball,if=buff.combustion.down&cooldown.combustion.remains<cast_time&active_enemies<2
actions.combustion_phase+=/scorch,if=buff.combustion.down&cooldown.combustion.remains<cast_time
actions.combustion_phase+=/combustion,use_off_gcd=1,use_while_casting=1,if=hot_streak_spells_in_flight=0&buff.combustion.down&variable.time_to_combustion<=0&(action.scorch.executing&action.scorch.execute_remains<variable.combustion_cast_remains|action.fireball.executing&action.fireball.execute_remains<variable.combustion_cast_remains|action.pyroblast.executing&action.pyroblast.execute_remains<variable.combustion_cast_remains|action.flamestrike.executing&action.flamestrike.execute_remains<variable.combustion_cast_remains|action.meteor.in_flight&action.meteor.in_flight_remains<variable.combustion_cast_remains)
actions.combustion_phase+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=!variable.fire_blast_pooling&(!improved_scorch.active|action.scorch.executing|debuff.improved_scorch.remains>3)&(buff.fury_of_the_sun_king.down|action.pyroblast.executing)&buff.combustion.up&!buff.hyperthermia.react&!buff.hot_streak.react&hot_streak_spells_in_flight+buff.heating_up.react*(gcd.remains>0)<2
actions.combustion_phase+=/flamestrike,if=(buff.hot_streak.react&active_enemies>=variable.combustion_flamestrike)|(buff.hyperthermia.react&active_enemies>=variable.combustion_flamestrike-talent.hyperthermia)
actions.combustion_phase+=/pyroblast,if=buff.hyperthermia.react
actions.combustion_phase+=/pyroblast,if=buff.hot_streak.react
actions.combustion_phase+=/pyroblast,if=prev_gcd.1.scorch&buff.heating_up.react&active_enemies<variable.combustion_flamestrike&buff.combustion.up
actions.combustion_phase+=/shifting_power,if=buff.combustion.up&!action.fire_blast.charges&(action.phoenix_flames.charges<action.phoenix_flames.max_charges|talent.alexstraszas_fury)&active_enemies>=variable.combustion_shifting_power
actions.combustion_phase+=/flamestrike,if=buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.remains>cast_time&active_enemies>=variable.skb_flamestrike&buff.fury_of_the_sun_king.expiration_delay_remains=0
actions.combustion_phase+=/pyroblast,if=buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.remains>cast_time&buff.fury_of_the_sun_king.expiration_delay_remains=0
actions.combustion_phase+=/scorch,if=improved_scorch.active&debuff.improved_scorch.remains<3
actions.combustion_phase+=/phoenix_flames,if=set_bonus.tier30_2pc&travel_time<buff.combustion.remains&buff.heating_up.react+hot_streak_spells_in_flight<2&(debuff.charring_embers.remains<2*gcd.max|buff.flames_fury.up)
actions.combustion_phase+=/fireball,if=buff.combustion.remains>cast_time&buff.flame_accelerant.react
actions.combustion_phase+=/phoenix_flames,if=!set_bonus.tier30_2pc&!talent.alexstraszas_fury&travel_time<buff.combustion.remains&buff.heating_up.react+hot_streak_spells_in_flight<2
actions.combustion_phase+=/scorch,if=buff.combustion.remains>cast_time&cast_time>=gcd.max
actions.combustion_phase+=/fireball,if=buff.combustion.remains>cast_time
actions.combustion_phase+=/living_bomb,if=buff.combustion.remains<gcd.max&active_enemies>1
actions.combustion_phase+=/ice_nova,if=buff.combustion.remains<gcd.max
]]
	if LivingBomb:Usable() and Player.enemies > 1 and Combustion:Down() and not Meteor:LandingIn(3) then
		UseCooldown(LivingBomb)
	end
	if (Target.boss and Target.timeToDie < 20) or (Combustion:Remains() > self.skb_duration) then
		self:combustion_cooldowns()
	end
	if CharringEmbers.known and PhoenixFlames:Usable() and PhoenixFlames:Traveling() == 0 and CharringEmbers:Remains() < (2 * Player.gcd) then
		return PhoenixFlames
	end
	if self.use_cds and Combustion:Down() then
		if Combustion:Usable() and self.hot_streak_spells_in_flight == 0 and self.time_to_combustion <= 0 and ((Player.cast.remains < self.combustion_cast_remains and (Scorch:Casting() or Fireball:Casting() or Pyroblast:Casting() or Flamestrike:Casting())) or Meteor:LandingIn(self.combustion_cast_remains)) then
			UseCooldown(Combustion)
		end
		if SunKingsBlessing.known and FuryOfTheSunKing:Up() then
			if Flamestrike:Usable() and FuryOfTheSunKing:Remains() > Flamestrike:CastTime() and Combustion:Ready(Flamestrike:CastTime()) and Player.enemies >= self.skb_flamestrike then
				return Flamestrike
			end
			if Pyroblast:Usable() and FuryOfTheSunKing:Remains() > Pyroblast:CastTime() then
				return Pyroblast
			end
		end
		if Fireball:Usable() and Combustion:Ready(Fireball:CastTime()) and Player.enemies < 2 then
			return Fireball
		end
		if Scorch:Usable() and Combustion:Ready(Scorch:CastTime()) then
			return Scorch
		end
	end
	if not Meteor:LandingIn(3) then
		local apl = self:active_talents()
		if apl then return apl end
	end
	if FireBlast:Usable() and not self.fire_blast_pooling and (SearingTouch:Down() or Scorch:Casting() or ImprovedScorch:Remains() > 3) and (FuryOfTheSunKing:Down() or Pyroblast:Casting()) and Combustion:Up() and Hyperthermia:Down() and HotStreak:Down() and self.hot_streak_spells_in_flight == 0 then
		UseExtra(FireBlast, true)
	end
	if Flamestrike:Usable() and Player.enemies >= self.combustion_flamestrike and (HotStreak:Up() or Hyperthermia:Up()) then
		return Flamestrike
	end
	if Pyroblast:Usable() and (
		Hyperthermia:Up() or
		(HotStreak:Up() and Player.enemies < self.combustion_flamestrike)
	) then
		return Pyroblast
	end
	if self.use_cds and ShiftingPower:Usable() and Combustion:Up() and Player.enemies >= self.combustion_shifting_power and FireBlast:Charges() == 0 and (AlexstraszasFury.known or PhoenixFlames:Charges() < 3) then
		UseCooldown(ShiftingPower)
	end
	if SunKingsBlessing.known and FuryOfTheSunKing:Up() then
		if Flamestrike:Usable() and FuryOfTheSunKing:Remains() > Flamestrike:CastTime() and Player.enemies >= self.skb_flamestrike then
			return Flamestrike
		end
		if Pyroblast:Usable() and FuryOfTheSunKing:Remains() > Pyroblast:CastTime() then
			return Pyroblast
		end
	end
	if ImprovedScorch.known and Scorch:Usable() and SearingTouch:Up() and ImprovedScorch:Stack() < 3 then
		return Scorch
	end
	if CharringEmbers.known and PhoenixFlames:Usable() and PhoenixFlames:TravelTime() < Combustion:Remains() and HeatingUp:Up() and self.hot_streak_spells_in_flight == 0 and (CharringEmbers:Remains() < (2 * Player.gcd) or FlamesFury:Up()) then
		return PhoenixFlames
	end
	if FlameAccelerant.known and Fireball:Usable() and Combustion:Remains() > Fireball:CastTime() and FlameAccelerant:Up() then
		return Fireball
	end
	if not CharringEmbers.known and not AlexstraszasFury.known and PhoenixFlames:Usable() and PhoenixFlames:TravelTime() < Combustion:Remains() and HeatingUp:Up() and self.hot_streak_spells_in_flight == 0 then
		return PhoenixFlames
	end
	if Scorch:Usable() and Combustion:Remains() > Scorch:CastTime() and Scorch:CastTime() >= Player.gcd then
		return Scorch
	end
	if Fireball:Usable() and Combustion:Remains() > Fireball:CastTime() then
		return Fireball
	end
	if LivingBomb:Usable() and Combustion:Remains() < Player.gcd and Player.enemies > 1 then
		UseCooldown(LivingBomb)
	end
	if IceNova:Usable() and Combustion:Remains() < Player.gcd then
		return IceNova
	end
end

APL[SPEC.FIRE].combustion_cooldowns = function(self)
--[[
actions.combustion_cooldowns=potion
actions.combustion_cooldowns+=/blood_fury
actions.combustion_cooldowns+=/berserking,if=buff.combustion.up
actions.combustion_cooldowns+=/fireblood
actions.combustion_cooldowns+=/ancestral_call
actions.combustion_cooldowns+=/invoke_external_buff,name=power_infusion,if=buff.power_infusion.down
actions.combustion_cooldowns+=/invoke_external_buff,name=blessing_of_summer,if=buff.blessing_of_summer.down
actions.combustion_cooldowns+=/time_warp,if=talent.temporal_warp&buff.exhaustion.up
actions.combustion_cooldowns+=/use_item,effect_name=gladiators_badge
actions.combustion_cooldowns+=/use_item,name=irideus_fragment
actions.combustion_cooldowns+=/use_item,name=spoils_of_neltharus
actions.combustion_cooldowns+=/use_item,name=tome_of_unstable_power
actions.combustion_cooldowns+=/use_item,name=timebreaching_talon
actions.combustion_cooldowns+=/use_item,name=voidmenders_shadowgem
actions.combustion_cooldowns+=/use_item,name=horn_of_valor
]]
	if Opt.trinket then
		if Trinket1:Usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.FIRE].standard_rotation = function(self)
--[[
actions.standard_rotation=flamestrike,if=active_enemies>=variable.hot_streak_flamestrike&(buff.hot_streak.react|buff.hyperthermia.react)
actions.standard_rotation+=/pyroblast,if=buff.hot_streak.react|buff.hyperthermia.react
actions.standard_rotation+=/flamestrike,if=active_enemies>=variable.skb_flamestrike&buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.expiration_delay_remains=0
actions.standard_rotation+=/pyroblast,if=buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.expiration_delay_remains=0
actions.standard_rotation+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=!firestarter.active&!variable.fire_blast_pooling&buff.fury_of_the_sun_king.down&(((action.fireball.executing&(action.fireball.execute_remains<0.5|!talent.hyperthermia)|action.pyroblast.executing&(action.pyroblast.execute_remains<0.5|!talent.hyperthermia))&buff.heating_up.react)|(searing_touch.active&(!improved_scorch.active|debuff.improved_scorch.stack=debuff.improved_scorch.max_stack|full_recharge_time<3)&(buff.heating_up.react&!action.scorch.executing|!buff.hot_streak.react&!buff.heating_up.react&action.scorch.executing&!hot_streak_spells_in_flight)))
actions.standard_rotation+=/pyroblast,if=prev_gcd.1.scorch&buff.heating_up.react&searing_touch.active&active_enemies<variable.hot_streak_flamestrike
actions.standard_rotation+=/phoenix_flames,if=set_bonus.tier30_2pc&debuff.charring_embers.remains<2*gcd.max
actions.standard_rotation+=/scorch,if=improved_scorch.active&debuff.improved_scorch.stack<debuff.improved_scorch.max_stack
actions.standard_rotation+=/phoenix_flames,if=!talent.alexstraszas_fury&!buff.hot_streak.react&!variable.phoenix_pooling&buff.flames_fury.up
actions.standard_rotation+=/phoenix_flames,if=talent.alexstraszas_fury&!buff.hot_streak.react&hot_streak_spells_in_flight=0&(!variable.phoenix_pooling&buff.flames_fury.up|charges_fractional>2.5|charges_fractional>1.5&buff.feel_the_burn.remains<2*gcd.max)
actions.standard_rotation+=/call_action_list,name=active_talents
actions.standard_rotation+=/dragons_breath,if=active_enemies>1
actions.standard_rotation+=/scorch,if=searing_touch.active
actions.standard_rotation+=/arcane_explosion,if=active_enemies>=variable.arcane_explosion&mana.pct>=variable.arcane_explosion_mana
actions.standard_rotation+=/flamestrike,if=active_enemies>=variable.hard_cast_flamestrike
actions.standard_rotation+=/pyroblast,if=talent.tempered_flames&!buff.flame_accelerant.react
actions.standard_rotation+=/fireball
]]
	if Flamestrike:Usable() and Player.enemies >= self.hot_streak_flamestrike and (HotStreak:Up() or Hyperthermia:Up()) then
		return Flamestrike
	end
	if Pyroblast:Usable() and (Hyperthermia:Up() or HotStreak:Up()) then
		return Pyroblast
	end
	if SunKingsBlessing.known and FuryOfTheSunKing:Up() then
		if Flamestrike:Usable() and Player.enemies >= self.skb_flamestrike then
			return Flamestrike
		end
		if Pyroblast:Usable()  then
			return Pyroblast
		end
	end
	if FireBlast:Usable() and Firestarter:Down() and not self.fire_blast_pooling and (not FuryOfTheSunKing.known or FuryOfTheSunKing:Down()) and (
		(HeatingUp:Up() and (Fireball:Casting() or Pyroblast:Casting()) and (Player.cast.remains < 0.5 or not Hyperthermia.known)) or
		(SearingTouch:Up() and (not ImprovedScorch.known or ImprovedScorch:Stack() >= 3 or FireBlast:FullRechargeTime() < 3) and ((HeatingUp:Up() and not Scorch:Casting()) or (HotStreak:Down() and HeatingUp:Down() and Scorch:Casting() and self.hot_streak_spells_in_flight == 0)))
	) then
		UseExtra(FireBlast, true)
	end
	if Pyroblast:Usable() and HotStreak:Up() and SearingTouch:Up() and Player.enemies < self.hot_streak_flamestrike then
		return Pyroblast
	end
	if PhoenixFlames:Usable() and Player.set_bonus.t30 >= 2 and CharringEmbers:Remains() < (2 * Player.gcd) then
		return PhoenixFlames
	end
	if ImprovedScorch.known and Scorch:Usable() and SearingTouch:Up() and ImprovedScorch:Stack() < 3 then
		return Scorch
	end
	if PhoenixFlames:Usable() and HotStreak:Down() and (
		(not AlexstraszasFury.known and not self.phoenix_pooling and FlamesFury:Up()) or
		(AlexstraszasFury.known and self.hot_streak_spells_in_flight == 0 and PhoenixFlames:Traveling() == 0 and (
			(not self.phoenix_pooling and FlamesFury:Up()) or
			PhoenixFlames:ChargesFractional() > 2.5 or
			PhoenixFlames:ChargesFractional() > 1.5 and FeelTheBurn:Remains() < (2 * Player.gcd)
		))
	) then
		return PhoenixFlames
	end
	local apl = self:active_talents()
	if apl then return apl end
	if DragonsBreath:Usable() and Player.enemies > 1 and Target.estimated_range < 15 then
		UseCooldown(DragonsBreath)
	end
	if Scorch:Usable() and SearingTouch:Up() then
		return Scorch
	end
	if Flamestrike:Usable() and Player.enemies >= self.hard_cast_flamestrike then
		return Flamestrike
	end
	if TemperedFlames.known and Pyroblast:Usable() and FlameAccelerant:Down() then
		return Pyroblast
	end
	if Fireball:Usable() then
		return Fireball
	end
end

APL[SPEC.FROST].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 300 then
			return ArcaneIntellect
		end
	else
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 10 then
			UseExtra(ArcaneIntellect)
		end
	end
end

APL.Interrupt = function(self)
	if Counterspell:Usable() then
		return Counterspell
	end
	if Target.stunnable then
		if DragonsBreath:Usable() then
			return DragonsBreath
		end
		if BlastWave:Usable() then
			return BlastWave
		end
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow:Show()
				if Opt.glow.animation then
					glow.ProcStartAnim:Play()
				else
					glow.ProcLoop:Play()
				end
			end
		elseif glow:IsVisible() then
			if glow.ProcStartAnim:IsPlaying() then
				glow.ProcStartAnim:Stop()
			end
			if glow.ProcLoop:IsPlaying() then
				glow.ProcLoop:Stop()
			end
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	amagicPanel:EnableMouse(draggable or Opt.aoe)
	amagicPanel.button:SetShown(Opt.aoe)
	amagicPreviousPanel:EnableMouse(draggable)
	amagicCooldownPanel:EnableMouse(draggable)
	amagicInterruptPanel:EnableMouse(draggable)
	amagicExtraPanel:EnableMouse(draggable)
end

function UI:UpdateAlpha()
	amagicPanel:SetAlpha(Opt.alpha)
	amagicPreviousPanel:SetAlpha(Opt.alpha)
	amagicCooldownPanel:SetAlpha(Opt.alpha)
	amagicInterruptPanel:SetAlpha(Opt.alpha)
	amagicExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	amagicPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	amagicPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	amagicCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	amagicInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	amagicExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	amagicPreviousPanel:ClearAllPoints()
	amagicPreviousPanel:SetPoint('TOPRIGHT', amagicPanel, 'BOTTOMLEFT', -3, 40)
	amagicCooldownPanel:ClearAllPoints()
	amagicCooldownPanel:SetPoint('TOPLEFT', amagicPanel, 'BOTTOMRIGHT', 3, 40)
	amagicInterruptPanel:ClearAllPoints()
	amagicInterruptPanel:SetPoint('BOTTOMLEFT', amagicPanel, 'TOPRIGHT', 3, -21)
	amagicExtraPanel:ClearAllPoints()
	amagicExtraPanel:SetPoint('BOTTOMRIGHT', amagicPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.ARCANE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.FIRE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.ARCANE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 }
		},
		[SPEC.FIRE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 }
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		amagicPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		amagicPanel:ClearAllPoints()
		amagicPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateManaBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		(Player.spec == SPEC.ARCANE and Opt.hide.arcane) or
		(Player.spec == SPEC.FIRE and Opt.hide.fire) or
		(Player.spec == SPEC.FROST and Opt.hide.frost))
end

function UI:Disappear()
	amagicPanel:Hide()
	amagicPanel.icon:Hide()
	amagicPanel.border:Hide()
	amagicCooldownPanel:Hide()
	amagicInterruptPanel:Hide()
	amagicExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, border, text_center, text_tr, text_cd, color_center

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd = format('%.1f', react)
			end
		end
	end
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT\n%.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.channel.tick_count > 0 then
		dim = Opt.dimmer
		if Player.channel.tick_count > 1 then
			local ctime = GetTime()
			local channel = Player.channel
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = 'CHAIN'
					color_center = 'green'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if Player.major_cd_remains > 0 then
		text_tr = format('%.1fs', Player.major_cd_remains)
	end
	if color_center ~= amagicPanel.text.center.color then
		amagicPanel.text.center.color = color_center
		if color_center == 'green' then
			amagicPanel.text.center:SetTextColor(0, 1, 0, 1)
		elseif color_center == 'red' then
			amagicPanel.text.center:SetTextColor(1, 0, 0, 1)
		else
			amagicPanel.text.center:SetTextColor(1, 1, 1, 1)
		end
	end
	if border ~= amagicPanel.border.overlay then
		amagicPanel.border.overlay = border
		amagicPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	amagicPanel.dimmer:SetShown(dim)
	amagicPanel.text.center:SetText(text_center)
	amagicPanel.text.tr:SetText(text_tr)
	--amagicPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	amagicCooldownPanel.text:SetText(text_cd)
	amagicCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		amagicPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.mana_cost > 0 and Player.main:ManaCost() == 0) or (Player.main.Free and Player.main:Free())
	end
	if Player.cd then
		amagicCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			amagicCooldownPanel.swipe:SetCooldown(start, duration)
		end
	end
	if Player.extra then
		amagicExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			amagicInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			amagicInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		amagicInterruptPanel.icon:SetShown(Player.interrupt)
		amagicInterruptPanel.border:SetShown(Player.interrupt)
		amagicInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and amagicPreviousPanel.ability then
		if (Player.time - amagicPreviousPanel.ability.last_used) > 10 then
			amagicPreviousPanel.ability = nil
			amagicPreviousPanel:Hide()
		end
	end

	amagicPanel.icon:SetShown(Player.main)
	amagicPanel.border:SetShown(Player.main)
	amagicCooldownPanel:SetShown(Player.cd)
	amagicExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Automagically
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Automagically1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end
	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not ability.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth('player')
		Player.health.max = UnitHealthMax('player')
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		amagicPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end

	Player.set_bonus.t29 = (Player:Equipped(200315) and 1 or 0) + (Player:Equipped(200317) and 1 or 0) + (Player:Equipped(200318) and 1 or 0) + (Player:Equipped(200319) and 1 or 0) + (Player:Equipped(200320) and 1 or 0)
	Player.set_bonus.t30 = (Player:Equipped(202549) and 1 or 0) + (Player:Equipped(202550) and 1 or 0) + (Player:Equipped(202551) and 1 or 0) + (Player:Equipped(202552) and 1 or 0) + (Player:Equipped(202554) and 1 or 0)

	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	amagicPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		amagicPanel.swipe:SetCooldown(start, duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
end

amagicPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

amagicPanel:SetScript('OnUpdate', function(self, elapsed)
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

amagicPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	amagicPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				amagicPanel:ClearAllPoints()
			end
			UI:UpdateDraggable()
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'a') then
				Opt.hide.arcane = not Opt.hide.arcane
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Arcane specialization', not Opt.hide.arcane)
			end
			if startsWith(msg[2], 'fi') then
				Opt.hide.fire = not Opt.hide.fire
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Fire specialization', not Opt.hide.fire)
			end
			if startsWith(msg[2], 'fr') then
				Opt.hide.frost = not Opt.hide.frost
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Frost specialization', not Opt.hide.frost)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000arcane|r/|cFFFFD000fire|r/|cFFFFD000frost|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 10
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if startsWith(msg[1], 'ba') then
		if msg[2] then
			Opt.barrier = msg[2] == 'on'
		end
		return Status('Show barrier refresh reminder in extra UI', Opt.barrier)
	end
	if startsWith(msg[1], 'con') then
		if msg[2] then
			Opt.conserve_mana = clamp(tonumber(msg[2]) or 60, 20, 80)
		end
		return Status('Mana conservation threshold (Arcane)', Opt.conserve_mana .. '%')
	end
	if msg[1] == 'reset' then
		amagicPanel:ClearAllPoints()
		amagicPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000arcane|r/|cFFFFD000fire|r/|cFFFFD000frost|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'barrier |cFF00C000on|r/|cFFC00000off|r - show barrier refresh reminder in extra UI',
		'conserve |cFFFFD000[20-80]|r  - mana conservation threshold (arcane, default is 60%)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Automagically1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
