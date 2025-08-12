local ADDON = 'Automagically'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_AUTOMAGICALLY = ADDON
BINDING_NAME_AUTOMAGICALLY_TARGETMORE = "Toggle Targets +"
BINDING_NAME_AUTOMAGICALLY_TARGETLESS = "Toggle Targets -"
BINDING_NAME_AUTOMAGICALLY_TARGET1 = "Set Targets to 1"
BINDING_NAME_AUTOMAGICALLY_TARGET2 = "Set Targets to 2"
BINDING_NAME_AUTOMAGICALLY_TARGET3 = "Set Targets to 3"
BINDING_NAME_AUTOMAGICALLY_TARGET4 = "Set Targets to 4"
BINDING_NAME_AUTOMAGICALLY_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'MAGE' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetActionInfo = _G.GetActionInfo
local GetBindingKey = _G.GetBindingKey
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = C_Spell.GetSpellCharges
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellInfo = C_Spell.GetSpellInfo
local GetItemCount = C_Item.GetItemCount
local GetItemCooldown = C_Item.GetItemCooldown
local GetInventoryItemCooldown = _G.GetInventoryItemCooldown
local GetItemInfo = C_Item.GetItemInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local IsSpellUsable = C_Spell.IsSpellUsable
local IsItemUsable = C_Item.IsUsableItem
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = C_UnitAuras.GetAuraDataByIndex
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

local function ToUID(guid)
	local uid = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	return uid and tonumber(uid)
end
-- end useful functions

Automagically = {}
local Opt -- use this as a local table reference to Automagically

SLASH_Automagically1, SLASH_Automagically2, SLASH_Automagically3 = '/am', '/amagic', '/automagically'

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
		keybinds = true,
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
	tracked = {},
}

-- summoned pet template
local SummonedPet = {}
SummonedPet.__index = SummonedPet

-- classified summoned pets
local SummonedPets = {
	all = {},
	known = {},
	byUnitId = {},
}

-- inventory item template
local InventoryItem, Trinket = {}, {}
InventoryItem.__index = InventoryItem

-- classified inventory items
local InventoryItems = {
	all = {},
	byItemId = {},
}

-- action button template
local Button = {}
Button.__index = Button

-- classified action buttons
local Buttons = {
	all = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- methods for tracking ticking debuffs on targets
local TrackedAuras = {}

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
	initialized = false,
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
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	mana = {
		base = 0,
		current = 0,
		max = 100,
		pct = 100,
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
		t33 = 0, -- Sparks of Violet Rebirth
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

-- base mana pool max for each level
Player.BaseMana = {
	260,     270,     285,     300,     310,     -- 5
	330,     345,     360,     380,     400,     -- 10
	430,     465,     505,     550,     595,     -- 15
	645,     700,     760,     825,     890,     -- 20
	965,     1050,    1135,    1230,    1335,    -- 25
	1445,    1570,    1700,    1845,    2000,    -- 30
	2165,    2345,    2545,    2755,    2990,    -- 35
	3240,    3510,    3805,    4125,    4470,    -- 40
	4845,    5250,    5690,    6170,    6685,    -- 45
	7245,    7855,    8510,    9225,    10000,   -- 50
	11745,   13795,   16205,   19035,   22360,   -- 55
	26265,   30850,   36235,   42565,   50000,   -- 60
	58730,   68985,   81030,   95180,   111800,  -- 65
	131325,  154255,  181190,  212830,  250000,  -- 70
	293650,  344930,  405160,  475910,  559015,  -- 75
	656630,  771290,  905970,  1064170, 2500000, -- 80
}

-- current pet information
local Pet = {
	active = false,
	alive = false,
	stuck = false,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	mana = {
		current = 0,
		max = 100,
	},
}

-- current target information
local Target = {
	boss = false,
	dummy = false,
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

-- target dummy unit IDs (count these units as bosses)
Target.Dummies = {
	[189617] = true,
	[189632] = true,
	[194643] = true,
	[194644] = true,
	[194648] = true,
	[194649] = true,
	[197833] = true,
	[198594] = true,
	[219250] = true,
	[225983] = true,
	[225984] = true,
	[225985] = true,
	[225976] = true,
	[225977] = true,
	[225978] = true,
	[225982] = true,
}

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
	local uid = ToUID(guid)
	if uid and self.ignored_units[uid] then
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
		requires_pet = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		mana_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		summon_count = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
		keybinds = {},
		pet_spell = player == 'pet',
	}
	if ability.pet_spell then
		ability.aura_target = buff and 'pet' or 'target'
	end
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

function Ability:Usable(seconds)
	if not self.known then
		return false
	end
	if (self.requires_pet or self.pet_spell) and not Pet.active then
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

function Ability:Remains(offGCD)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			if aura.expirationTime == 0 then
				return 600 -- infinite duration
			end
			return max(0, aura.expirationTime - Player.ctime - (offGCD and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:React()
	return self:Remains()
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
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

function Ability:HighestRemains()
	local highest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				highest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not highest or remains > highest) then
				highest = remains
			end
		end
	end
	return highest or 0
end

function Ability:LowestRemains()
	local lowest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				lowest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not lowest or remains < lowest) then
				lowest = remains
			end
		end
	end
	return lowest or 0
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
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	return max(0, cooldown.duration - (Player.ctime - cooldown.startTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	local remains = cooldown.duration - (Player.ctime - cooldown.startTime)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			return (aura.expirationTime == 0 or aura.expirationTime - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and aura.applications or 0
		end
	end
	return 0
end

function Ability:MaxStack()
	return self.max_stack
end

function Ability:Capped(deficit)
	return self:Stack() >= (self:MaxStack() - (deficit or 0))
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.base) or 0
end

function Ability:ACCost()
	return self.arcane_charge_cost
end

function Ability:ACGain()
	return self.arcane_charge_gain
end

function Ability:Free()
	return (
		(self.mana_cost > 0 and self:ManaCost() == 0) or
		(Player.spec == SPEC.ARCANE and self.arcane_charge_cost > 0 and self:ACCost() == 0)
	)
end

function Ability:ChargesFractional()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return charges
	end
	return charges + ((max(0, Player.ctime - info.cooldownStartTime + (self.off_gcd and 0 or Player.execute_remains))) / info.cooldownDuration)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local info = GetSpellCharges(self.spellId)
	return info and info.maxCharges or 0
end

function Ability:FullRechargeTime()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return info.cooldownDuration
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return 0
	end
	return (info.maxCharges - charges - 1) * info.cooldownDuration + (info.cooldownDuration - (Player.ctime - info.cooldownStartTime) - (self.off_gcd and 0 or Player.execute_remains))
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
	local info = GetSpellInfo(self.spellId)
	return info and info.castTime / 1000 or 0
end

function Ability:CastRegen()
	return Player.mana.regen * self:CastTime() - self:ManaCost()
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

function Ability:CastFailed(dstGUID, missType)
	if self.requires_pet and missType == 'No path available' then
		Pet.stuck = true
	end
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.ignore_cast then
		return
	end
	if self.requires_pet then
		Pet.stuck = false
	end
	if self.pet_spell then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
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
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and amagicPreviousPanel.ability == self then
		amagicPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

function TrackedAuras:Purge()
	for _, ability in next, Abilities.tracked do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function TrackedAuras:Remove(guid)
	for _, ability in next, Abilities.tracked do
		ability:RemoveAura(guid)
	end
end

function Ability:Track()
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

function Ability:RefreshAura(guid, extend)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	return aura
end

function Ability:RefreshAuraAll(extend)
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
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
/dump GetMouseFoci()[1]:GetNodeID()
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
Frostbolt.triggers_combat = true
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
ArcaneBlast.triggers_combat = true
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
local CallOfTheSunKing = Ability:Add(343222, false, true)
local Combustion = Ability:Add(190319, true, true)
Combustion.mana_cost = 10
Combustion.buff_duration = 10
Combustion.cooldown_duration = 120
Combustion.triggers_gcd = false
Combustion.off_gcd = true
local DeepImpact = Ability:Add(416719, false, true)
local DragonsBreath = Ability:Add(31661, false, true)
DragonsBreath.mana_cost = 4
DragonsBreath.buff_duration = 4
DragonsBreath.cooldown_duration = 45
DragonsBreath:AutoAoe()
local FeelTheBurn = Ability:Add(383391, true, true, 383395)
FeelTheBurn.buff_duration = 5
FeelTheBurn.max_stack = 3
local Fireball = Ability:Add(133, false, true)
Fireball.mana_cost = 2
Fireball.triggers_combat = true
Fireball:SetVelocity(45)
local Firestarter = Ability:Add(205026, false, true)
local FlameAccelerant = Ability:Add(203275, true, true, 203277)
local FlameOn = Ability:Add(205029, false, true)
local FlamePatch = Ability:Add(205037, false, true, 205472)
local Flamestrike = Ability:Add(2120, false, true)
Flamestrike.mana_cost = 2.5
Flamestrike.buff_duration = 8
Flamestrike.triggers_combat = true
Flamestrike:AutoAoe()
local FuelTheFire = Ability:Add(416094, false, true)
local FuryOfTheSunKing = Ability:Add(383883, true, true)
FuryOfTheSunKing.buff_duration = 30
local HeatShimmer = Ability:Add(457735, true, true, 458964)
HeatShimmer.buff_duration = 10
local Hyperthermia = Ability:Add(383860, true, true, 383874)
Hyperthermia.buff_duration = 6
local Ignite = Ability:Add(12846, false, true, 12654)
Ignite.buff_duration = 9
Ignite.tick_interval = 1
Ignite:AutoAoe(false, 'apply')
local ImprovedCombustion = Ability:Add(383967, true, true)
local ImprovedScorch = Ability:Add(383604, false, true, 383608)
ImprovedScorch.buff_duration = 12
ImprovedScorch.max_stack = 2
local Kindling = Ability:Add(155148, false, true)
local LitFuse = Ability:Add(450716, true, true, 453207)
LitFuse.buff_duration = 10
local LivingBomb = Ability:Add(217694, false, true)
LivingBomb.buff_duration = 2
LivingBomb.tick_interval = 1
LivingBomb.hasted_duration = true
LivingBomb.hasted_ticks = true
LivingBomb.explosion = Ability:Add(44461, false, true)
LivingBomb.explosion:AutoAoe()
LivingBomb.spread = Ability:Add(244813, false, true)
LivingBomb.spread.buff_duration = 2
LivingBomb.spread.tick_interval = 1
LivingBomb.spread.hasted_duration = true
LivingBomb.spread.hasted_ticks = true
local MajestyOfThePhoenix = Ability:Add(451440, true, true, 453329)
MajestyOfThePhoenix.buff_duration = 20
MajestyOfThePhoenix.max_stack = 3
local Meteor = Ability:Add(153561, false, true, 351140)
Meteor.mana_cost = 1
Meteor.buff_duration = 3
Meteor.cooldown_duration = 45
Meteor.hasted_duration = true
Meteor.travel_delay = 1
Meteor:AutoAoe()
local PhoenixFlames = Ability:Add(257541, false, true, 257542)
PhoenixFlames.cooldown_duration = 25
PhoenixFlames.requires_charge = true
PhoenixFlames.travel_delay = 0.1
PhoenixFlames:SetVelocity(50)
PhoenixFlames:AutoAoe()
local PhoenixReborn = Ability:Add(453123, false, true)
local Pyroblast = Ability:Add(11366, false, true)
Pyroblast.mana_cost = 2
Pyroblast.triggers_combat = true
Pyroblast:SetVelocity(35)
local Scald = Ability:Add(450746, false, true)
local Scorch = Ability:Add(2948, false, true)
Scorch.mana_cost = 1
Scorch.triggers_combat = true
local SpontaneousCombustion = Ability:Add(451875, true, true)
local SunKingsBlessing = Ability:Add(383886, true, true, 383882)
SunKingsBlessing.buff_duration = 30
SunKingsBlessing.max_stack = 10
local Quickflame = Ability:Add(450807, false, true)
local UnleashedInferno = Ability:Add(416506, false, true)
------ Procs
local Calefaction = Ability:Add(408673, true, true)
Calefaction.max_stack = 25
Calefaction.buff_duration = 60
local FlamesFury = Ability:Add(409964, true, true)
FlamesFury.buff_duration = 30
FlamesFury.max_stack = 2
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
Blizzard.triggers_combat = true
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
Ebonbolt.triggers_combat = true
Ebonbolt:SetVelocity(30)
local FreezingRain = Ability:Add(270233, true, true, 270232)
FreezingRain.buff_duration = 12
local FrozenTouch = Ability:Add(205030, false, true)
local GlacialSpike = Ability:Add(199786, false, true, 228600)
GlacialSpike.mana_cost = 1
GlacialSpike.buff_duration = 4
GlacialSpike.triggers_combat = true
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
-- Hero talents
---- Frostfire
local ExcessFrost = Ability:Add(438600, true, true, 438611)
ExcessFrost.buff_duration = 30
local FrostfireBolt = Ability:Add(431044, false, true, 468655)
FrostfireBolt.buff_duration = 8
FrostfireBolt.mana_cost = 2
FrostfireBolt.triggers_combat = true
FrostfireBolt:SetVelocity(40)
local FrostfireEmpowerment = Ability:Add(431176, true, true, 431177)
local IsothermicCore = Ability:Add(431095, false, true)
---- Spellslinger

---- Sunfury
local InvocationArcanePhoenix = Ability:Add(448658, true, true)
local MemoryOfAlar = Ability:Add(449619, true, true)
local Rondurmancy = Ability:Add(449596, true, true)
local SavorTheMoment = Ability:Add(449412, true, true)
local SpellfireSpheres = Ability:Add(448601, true, true, 448604)
SpellfireSpheres.max_stack = 3
-- Tier set bonuses

-- Racials

-- PvP talents
local BurstOfCold = Ability:Add(206431, true, true, 206432)
BurstOfCold.buff_duration = 6
local Frostbite = Ability:Add(198120, false, true, 198121)
Frostbite.buff_duration = 4
-- Trinket effects
local SpymastersReport = Ability:Add(451199, true, true) -- Spymaster's Web
SpymastersReport.max_stack = 40
-- Class cooldowns
local PowerInfusion = Ability:Add(10060, true)
PowerInfusion.buff_duration = 20
-- Aliases
local Bolt = Frostbolt
-- End Abilities

-- Start Summoned Pets

function SummonedPets:Purge()
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires <= Player.time then
				pet.active_units[guid] = nil
			end
		end
	end
end

function SummonedPets:Update()
	wipe(self.known)
	wipe(self.byUnitId)
	for _, pet in next, self.all do
		pet.known = pet.summon_spell and pet.summon_spell.known
		if pet.known then
			self.known[#SummonedPets.known + 1] = pet
			self.byUnitId[pet.unitId] = pet
		end
	end
end

function SummonedPets:Count()
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:Count()
	end
	return count
end

function SummonedPets:Clear()
	for _, pet in next, self.known do
		pet:Clear()
	end
end

function SummonedPet:Add(unitId, duration, summonSpell)
	local pet = {
		unitId = unitId,
		duration = duration,
		active_units = {},
		summon_spell = summonSpell,
		known = false,
	}
	setmetatable(pet, self)
	SummonedPets.all[#SummonedPets.all + 1] = pet
	return pet
end

function SummonedPet:Remains(initial, offGCD)
	if self.summon_spell and self.summon_spell.summon_count > 0 and self.summon_spell:Casting() then
		return self:Duration()
	end
	local expires_max = 0
	for guid, unit in next, self.active_units do
		if (not initial or unit.initial) and unit.expires > expires_max then
			expires_max = unit.expires
		end
	end
	return max(0, expires_max - Player.time - (offGCD and 0 or Player.execute_remains))
end

function SummonedPet:Up(...)
	return self:Remains(...) > 0
end

function SummonedPet:Down(...)
	return self:Remains(...) <= 0
end

function SummonedPet:Count()
	local count = 0
	if self.summon_spell and self.summon_spell:Casting() then
		count = count + self.summon_spell.summon_count
	end
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time > Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:Duration()
	return self.duration
end

function SummonedPet:Expiring(seconds)
	local count = 0
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time <= (seconds or Player.execute_remains) then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:AddUnit(guid)
	local unit = {
		guid = guid,
		spawn = Player.time,
		expires = Player.time + self:Duration(),
	}
	self.active_units[guid] = unit
	--log(format('%.3f SUMMONED PET ADDED %s EXPIRES %.3f', unit.spawn, guid, unit.expires))
	return unit
end

function SummonedPet:RemoveUnit(guid)
	if self.active_units[guid] then
		--log(format('%.3f SUMMONED PET REMOVED %s AFTER %.3fs EXPECTED %.3fs', Player.time, guid, Player.time - self.active_units[guid], self.active_units[guid].expires))
		self.active_units[guid] = nil
	end
end

function SummonedPet:ExtendAll(seconds)
	for guid, unit in next, self.active_units do
		if unit.expires > Player.time then
			unit.expires = unit.expires + seconds
		end
	end
end

function SummonedPet:Clear()
	for guid in next, self.active_units do
		self.active_units[guid] = nil
	end
end

-- Summoned Pets
Pet.ArcanePhoenix = SummonedPet:Add(223453, 10, InvocationArcanePhoenix)

-- End Summoned Pets

-- Start Inventory Items

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
		off_gcd = true,
		keybinds = {},
	}
	setmetatable(item, self)
	InventoryItems.all[#InventoryItems.all + 1] = item
	InventoryItems.byItemId[itemId] = item
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
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
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
local Healthstone = InventoryItem:Add(5512)
Healthstone.max_charges = 3
local HyperthreadWristwraps = InventoryItem:Add(168989)
HyperthreadWristwraps.cooldown_duration = 120
HyperthreadWristwraps.casts = {}
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.SpymastersWeb = InventoryItem:Add(220202)
Trinket.SpymastersWeb.cooldown_duration = 20
-- End Inventory Items

-- Start Buttons

Buttons.KeybindPatterns = {
	['ALT%-'] = 'a-',
	['CTRL%-'] = 'c-',
	['SHIFT%-'] = 's-',
	['META%-'] = 'm-',
	['NUMPAD'] = 'NP',
	['PLUS'] = '%+',
	['MINUS'] = '%-',
	['MULTIPLY'] = '%*',
	['DIVIDE'] = '%/',
	['BACKSPACE'] = 'BS',
	['BUTTON'] = 'MB',
	['CLEAR'] = 'Clr',
	['DELETE'] = 'Del',
	['END'] = 'End',
	['HOME'] = 'Home',
	['INSERT'] = 'Ins',
	['MOUSEWHEELDOWN'] = 'MwD',
	['MOUSEWHEELUP'] = 'MwU',
	['PAGEDOWN'] = 'PgDn',
	['PAGEUP'] = 'PgUp',
	['CAPSLOCK'] = 'Caps',
	['NUMLOCK'] = 'NumL',
	['SCROLLLOCK'] = 'ScrL',
	['SPACEBAR'] = 'Space',
	['SPACE'] = 'Space',
	['TAB'] = 'Tab',
	['DOWNARROW'] = 'Down',
	['LEFTARROW'] = 'Left',
	['RIGHTARROW'] = 'Right',
	['UPARROW'] = 'Up',
}

function Buttons:Scan()
	if Bartender4 then
		for i = 1, 120 do
			Button:Add(_G['BT4Button' .. i])
		end
		for i = 1, 10 do
			Button:Add(_G['BT4PetButton' .. i])
		end
		return
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				Button:Add(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
		return
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				Button:Add(_G['LUIBarBottom' .. b .. 'Button' .. i])
				Button:Add(_G['LUIBarLeft' .. b .. 'Button' .. i])
				Button:Add(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
		return
	end
	if Dominos then
		for i = 1, 60 do
			Button:Add(_G['DominosActionButton' .. i])
		end
		-- fallthrough because Dominos re-uses Blizzard action buttons
	end
	for i = 1, 12 do
		Button:Add(_G['ActionButton' .. i])
		Button:Add(_G['MultiBarLeftButton' .. i])
		Button:Add(_G['MultiBarRightButton' .. i])
		Button:Add(_G['MultiBarBottomLeftButton' .. i])
		Button:Add(_G['MultiBarBottomRightButton' .. i])
		Button:Add(_G['MultiBar5Button' .. i])
		Button:Add(_G['MultiBar6Button' .. i])
		Button:Add(_G['MultiBar7Button' .. i])
	end
	for i = 1, 10 do
		Button:Add(_G['PetActionButton' .. i])
	end
end

function Button:UpdateGlowDisplay()
	local w, h = self.frame:GetSize()
	self.glow:SetSize(w * 1.4, h * 1.4)
	self.glow:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
	self.glow:SetPoint('BOTTOMRIGHT', self.frame, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
	self.glow.ProcStartFlipbook:SetVertexColor(Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b)
	self.glow.ProcLoopFlipbook:SetVertexColor(Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b)
	self.glow.ProcStartAnim:Play()
	self.glow:Hide()
end

function Button:UpdateActionID()
	self.action_id = (
		(self.frame._state_type == 'action' and self.frame._state_action) or
		(self.frame.CalculateAction and self.frame:CalculateAction()) or
		(self.frame:GetAttribute('action'))
	) or 0
end

function Button:UpdateAction()
	self.action = nil
	if self.action_id <= 0 then
		return
	end
	local actionType, id, subType = GetActionInfo(self.action_id)
	if id and type(id) == 'number' and id > 0 then
		if (actionType == 'item' or (actionType == 'macro' and subType == 'item')) then
			self.action = InventoryItems.byItemId[id]
		elseif (actionType == 'spell' or (actionType == 'macro' and subType == 'spell')) then
			self.action = Abilities.bySpellId[id]
		end
	end
end

function Button:UpdateKeybind()
	self.keybind = nil
	local bind = self.frame.bindingAction or (self.frame.config and self.frame.config.keyBoundTarget)
	if bind then
		local key = GetBindingKey(bind)
		if key then
			key = key:gsub(' ', ''):upper()
			for pattern, short in next, Buttons.KeybindPatterns do
				key = key:gsub(pattern, short)
			end
			self.keybind = key
			return
		end
	end
end

function Button:Add(actionButton)
	if not actionButton then
		return
	end
	local button = {
		frame = actionButton,
		name = actionButton:GetName(),
		action_id = 0,
		glow = CreateFrame('Frame', nil, actionButton, 'ActionButtonSpellAlertTemplate')
	}
	setmetatable(button, self)
	Buttons.all[#Buttons.all + 1] = button
	button:UpdateActionID()
	button:UpdateAction()
	button:UpdateKeybind()
	button:UpdateGlowDisplay()
	return button
end

-- End Buttons

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.tracked)
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
				self.tracked[#self.tracked + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:ManaTimeToMax()
	local deficit = self.mana.max - self.mana.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.mana.regen
end

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
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 2825 or   -- Bloodlust (Horde Shaman)
			aura.spellId == 32182 or  -- Heroism (Alliance Shaman)
			aura.spellId == 80353 or  -- Time Warp (Mage)
			aura.spellId == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			aura.spellId == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			aura.spellId == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			aura.spellId == 381301 or -- Feral Hide Drums (Leatherworking)
			aura.spellId == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Exhausted()
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HARMFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 57724 or -- Sated (Alliance Shaman)
			aura.spellId == 57723 or -- Exhaustion (Horde Shaman)
			aura.spellId == 80354 or -- Temporal Displacement (Mage)
			aura.spellId == 264689 or-- Fatigued (Hunter)
			aura.spellId == 390435   -- Exhaustion (Evoker)
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
	local info, node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		if not ability.pet_spell then
			ability.known = false
			ability.rank = 0
			for _, spellId in next, ability.spellIds do
				info = GetSpellInfo(spellId)
				if info then
					ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
				end
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
			if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsSpellUsable(ability.spellId)) then
				ability.known = false -- spell is locked, do not mark as known
			end
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
	if LitFuse.known then
		LivingBomb.known = true
		LivingBomb.explosion.known = true
		LivingBomb.spread.known = true
	end
	Calefaction.known = PhoenixReborn.known
	FlamesFury.known = PhoenixReborn.known
	if Player.spec == SPEC.FIRE then
		Bolt = Fireball
	else
		Bolt = Frostbolt
	end
	if FrostfireBolt.known then
		Frostbolt.known = false
		Fireball.known = false
		Bolt = FrostfireBolt
	end
	if MemoryOfAlar.known then
		Hyperthermia.known = true
	end

	Abilities:Update()
	SummonedPets:Update()

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
	if ability then
		if ability == channel.ability then
			channel.chained = true
		end
		channel.interrupt_if = ability.interrupt_if
	else
		channel.interrupt_if = nil
	end
	channel.ability = ability
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
	local _, cooldown, start, ends, spellId, speed, max_speed
	self.main = nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	cooldown = GetSpellCooldown(61304)
	self.gcd_remains = cooldown.startTime > 0 and cooldown.duration - (self.ctime - cooldown.startTime) or 0
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
	if self.cast.ability and self.cast.ability.mana_cost > 0 then
		self.mana.current = self.mana.current - self.cast.ability:ManaCost()
	end
	self.mana.current = clamp(self.mana.current, 0, self.mana.max)
	self.mana.pct = self.mana.current / self.mana.max * 100
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
	if FireBlast.known then
		Player.fb_charges = FireBlast:ChargesFractional()
	end
	if Pet.ArcanePhoenix.known then
		Player.phoenix_remains = Pet.ArcanePhoenix:Remains()
	end
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

	Pet:Update()

	SummonedPets:Purge()
	TrackedAuras:Purge()
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
	if not self.initialized then
		Buttons:Scan()
		UI:DisableOverlayGlows()
		UI:HookResourceFrame()
		self.guid = UnitGUID('player')
		self.name = UnitName('player')
		self.initialized = true
	end
	amagicPreviousPanel.ability = nil
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Pet Functions

function Pet:UpdateKnown()
	local info
	for _, ability in next, Abilities.all do
		if ability.pet_spell then
			ability.known = false
			ability.rank = 0
			for _, spellId in next, ability.spellIds do
				info = GetSpellInfo(spellId)
				ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
				if IsSpellKnown(spellId, true) then
					ability.known = true
					break
				end
			end
		end
	end

	Abilities:Update()
end

function Pet:Update()
	self.guid = UnitGUID('pet')
	self.alive = self.guid and not UnitIsDead('pet')
	self.active = (self.alive and not self.stuck or IsFlying()) and true
	self.mana.max = self.active and UnitPowerMax('pet', 0) or 100
	self.mana.current = UnitPower('pet', 0)
end

-- End Pet Functions

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
	self.timeToDieMax = self.health.current / Player.health.max * 15
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.dummy and 600) or
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
		self.boss = false
		self.dummy = false
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
		self.uid = ToUID(guid) or 0
		self:UpdateHealth(true)
	end
	self.boss = false
	self.dummy = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.Dummies[self.uid] then
		self.boss = true
		self.dummy = true
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		amagicPanel:Show()
		return true
	end
	UI:Disappear()
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

function Freeze:Usable(...)
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self, ...)
end

function FrostNova:Usable(...)
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self, ...)
end

function TimeWarp:Usable(...)
	return not Player:Exhausted() and Ability.Usable(self, ...)
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

function GlacialSpike:Usable(...)
	if Icicles:Stack() < 5 or Icicles:Remains() < self:CastTime() then
		return false
	end
	return Ability.Usable(self, ...)
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
		stack = stack - Bolt:Traveling() - IceLance:Traveling()
	end
	return max(0, stack)
end

function Icicles:Stack()
	if GlacialSpike:Casting() then
		return 0
	end
	local count = Ability.Stack(self)
	if Bolt:Casting() or Flurry:Casting() then
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

function Scorch:Execute()
	return Target.health.pct < 30
end

function Scorch:Free()
	return HeatShimmer.known and HeatShimmer:Up()
end

function HeatingUp:Remains()
	if (
		(Scorch:Casting() and Scorch:Execute()) or
		(Combustion.known and (Scorch:Casting() or (FuelTheFire.known and Flamestrike:Casting())) and Combustion:Up())
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
		(Scorch:Casting() and Scorch:Execute()) or
		(Combustion.known and (Scorch:Casting() or (FuelTheFire.known and Flamestrike:Casting())) and Combustion:Up())
	) then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function FrostfireBolt:Free()
	return FrostfireEmpowerment.known and FrostfireEmpowerment:Up()
end

function Pyroblast:Free()
	return HotStreak:Up() or Hyperthermia:Up()
end

function Flamestrike:Free()
	return HotStreak:Up() or Hyperthermia:Up()
end

function PhoenixFlames:Free()
	return PhoenixReborn.known and FlamesFury:Up()
end

function Combustion:Duration()
	local duration = Ability.Duration(self)
	if ImprovedCombustion.known then
		duration = duration + 2
	end
	if SavorTheMoment.known then
		duration = duration + min(2.5, SpellfireSpheres:Stack() * 0.5)
	end
	return duration
end

function Combustion:Remains(offGCD)
	local remains = Ability.Remains(self, offGCD)
	if not offGCD and SunKingsBlessing.known and Ability.Remains(FuryOfTheSunKing) > 0 and (Pyroblast:Casting() or Flamestrike:Casting()) then
		remains = remains + 6
	end
	return remains
end

function FuryOfTheSunKing:Remains(offGCD)
	if not offGCD and (Pyroblast:Casting() or Flamestrike:Casting()) then
		return 0
	end
	return Ability.Remains(self, offGCD)
end

function Hyperthermia:Remains(offGCD)
	if not offGCD and MemoryOfAlar.known and InvocationArcanePhoenix.known and Pet.ArcanePhoenix:Expiring() > 0 then
		return self:Duration()
	end
	return Ability.Remains(self, offGCD)
end

function Meteor:LandingIn(seconds)
	if not self.landing_time or self.landing_time < Player.time then
		return false
	end
	return (self.landing_time - Player.time) < seconds
end

function Meteor:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	self.landing_time = Player.time + self:Duration()
end

function ImprovedScorch:Active()
	return self.known and Scorch:Execute()
end

function ImprovedScorch:Remains()
	if self:Active() and Scorch:Casting() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function ImprovedScorch:Stack()
	local stack = Ability.Stack(self)
	if self:Active() and Scorch:Casting() then
		stack = stack + 1
	end
	return clamp(stack, 0, self:MaxStack())
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

function SpellfireSpheres:MaxStack()
	if Rondurmancy.known then
		return 5
	end
	return Ability.MaxStack(self)
end

function Meteor:CooldownDuration()
	local duration = Ability.CooldownDuration(self)
	if DeepImpact.known then
		duration = duration - 10
	end
	return duration
end

function HyperthreadWristwraps:Cast(ability)
	if ability.ignore_cast or ability.pet_spell or not ability.spellId then
		return
	end
	self.casts[3] = nil
	table.insert(self.casts, 1, ability)
end

function HyperthreadWristwraps:Casts(ability)
	local count = 0
	for i = 1, #self.casts do
		if self.casts[i] == ability then
			count = count + 1
		end
	end
	return count
end

-- End Ability Modifications

-- Start Summoned Pet Modifications

function Pet.ArcanePhoenix:AddUnit(...)
	local unit = SummonedPet.AddUnit(self, ...)
	unit.expires = unit.spawn + Combustion:Duration()
	return unit
end

-- End Summoned Pet Modifications

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
	self.in_combust_off_gcd = Combustion:Up(true)
	self.in_combust = Combustion:Up()
	self:spells_in_flight()
	self:combustion_timing()
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/arcane_intellect
actions.precombat+=/snapshot_stats
actions.precombat+=/mirror_image
actions.precombat+=/flamestrike,if=active_enemies>=variable.hot_streak_flamestrike
actions.precombat+=/pyroblast
]]
		if Opt.barrier and BlazingBarrier:Usable() and BlazingBarrier:Remains() < 15 then
			UseCooldown(BlazingBarrier)
		end
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 300 then
			return ArcaneIntellect
		end
		if Target.boss then
			if MirrorImage:Usable() then
				UseCooldown(MirrorImage)
			end
			if Flamestrike:Usable() and Player.enemies >= self.hot_streak_flamestrike then
				return Flamestrike
			end
			if Pyroblast:Usable() then
				return Pyroblast
			end
		end
	else
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 10 then
			UseExtra(ArcaneIntellect)
		elseif Opt.barrier and BlazingBarrier:Usable() and BlazingBarrier:Remains() < 5 and self.time_to_combustion > 0 and not self.in_combust then
			UseExtra(BlazingBarrier)
		elseif MirrorImage:Usable() and Player:UnderAttack() then
			UseExtra(MirrorImage)
		end
	end
--[[
actions=counterspell
actions+=/phoenix_flames,if=time=0
actions+=/call_action_list,name=combustion_timing
actions+=/potion,if=buff.potion.duration>variable.time_to_combustion+buff.combustion.duration
actions+=/variable,name=shifting_power_before_combustion,value=variable.time_to_combustion>cooldown.shifting_power.remains
actions+=/variable,name=item_cutoff_active,value=(variable.time_to_combustion<variable.on_use_cutoff|buff.combustion.remains>variable.skb_duration&!cooldown.item_cd_1141.remains)&((trinket.1.has_cooldown&trinket.1.cooldown.remains<variable.on_use_cutoff)+(trinket.2.has_cooldown&trinket.2.cooldown.remains<variable.on_use_cutoff)>1)
actions+=/use_item,effect_name=spymasters_web,if=(trinket.1.has_use&trinket.2.has_use&buff.combustion.remains>10&fight_remains<80)|((buff.combustion.remains>10&buff.spymasters_report.stack>35&fight_remains<60)|fight_remains<25)
actions+=/use_item,name=treacherous_transmitter,if=variable.time_to_combustion<10|fight_remains<25
actions+=/do_treacherous_transmitter_task,use_off_gcd=1,if=buff.combustion.up|fight_remains<20
actions+=/use_item,name=imperfect_ascendancy_serum,if=variable.time_to_combustion<3
actions+=/use_item,effect_name=gladiators_badge,if=variable.time_to_combustion>cooldown-5
actions+=/use_items,if=!variable.item_cutoff_active
actions+=/variable,use_off_gcd=1,use_while_casting=1,name=fire_blast_pooling,value=buff.combustion.down&action.fire_blast.charges_fractional+(variable.time_to_combustion+action.shifting_power.full_reduction*variable.shifting_power_before_combustion)%cooldown.fire_blast.duration-1<cooldown.fire_blast.max_charges+variable.overpool_fire_blasts%cooldown.fire_blast.duration-(buff.combustion.duration%cooldown.fire_blast.duration)%%1&variable.time_to_combustion<fight_remains
actions+=/call_action_list,name=combustion_phase,if=variable.time_to_combustion<=0|buff.combustion.up|variable.time_to_combustion<variable.combustion_precast_time&cooldown.combustion.remains<variable.combustion_precast_time
actions+=/variable,use_off_gcd=1,use_while_casting=1,name=fire_blast_pooling,value=scorch_execute.active&action.fire_blast.full_recharge_time>3*gcd.max,if=!variable.fire_blast_pooling&talent.sun_kings_blessing
actions+=/shifting_power,if=buff.combustion.down&(!improved_scorch.active|debuff.improved_scorch.remains>cast_time+action.scorch.cast_time&!buff.fury_of_the_sun_king.up)&!buff.hot_streak.react&buff.hyperthermia.down&(cooldown.phoenix_flames.charges<=1|cooldown.combustion.remains<20)
actions+=/variable,name=phoenix_pooling,if=!talent.sun_kings_blessing,value=(variable.time_to_combustion+buff.combustion.duration-5<action.phoenix_flames.full_recharge_time+cooldown.phoenix_flames.duration-action.shifting_power.full_reduction*variable.shifting_power_before_combustion&variable.time_to_combustion<fight_remains|talent.sun_kings_blessing)&!talent.alexstraszas_fury
actions+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=!variable.fire_blast_pooling&variable.time_to_combustion>0&active_enemies>=variable.hard_cast_flamestrike&!firestarter.active&!buff.hot_streak.react&(buff.heating_up.react&action.flamestrike.execute_remains<0.5|charges_fractional>=2)
actions+=/call_action_list,name=firestarter_fire_blasts,if=buff.combustion.down&firestarter.active&variable.time_to_combustion>0
actions+=/fire_blast,use_while_casting=1,if=action.shifting_power.executing&(full_recharge_time<action.shifting_power.tick_reduction|talent.sun_kings_blessing&buff.heating_up.react)
actions+=/call_action_list,name=standard_rotation,if=variable.time_to_combustion>0&buff.combustion.down
actions+=/ice_nova,if=!scorch_execute.active
actions+=/scorch,if=buff.combustion.down
]]
	self.shifting_power_before_combustion = self.time_to_combustion > ShiftingPower:Cooldown()
	if Opt.trinket and self.use_cds and Trinket.SpymastersWeb:Usable() and (
		(SpymastersReport:Stack() > 35 and (Combustion:Remains() > 9 or (Meteor.known and self.time_to_combustion <= 0 and Meteor:LandingIn(3)))) or
		(Target.boss and Target.timeToDie < 25 and (Combustion:Up() or not Combustion:Ready(10)))
	) then
		UseCooldown(Trinket.SpymastersWeb)
	end
	if self.use_cds and self.in_combust and HyperthreadWristwraps:Usable() and FireBlast:Charges() == 0 and HyperthreadWristwraps:Casts(FireBlast) >= 2 then
		UseCooldown(HyperthreadWristwraps)
	end
	self.fire_blast_pooling = not self.in_combust_off_gcd and (Player.fb_charges + ((self.time_to_combustion + (self.shifting_power_before_combustion and 12 or 0)) / FireBlast:CooldownDuration()) - 1) < (FireBlast:MaxCharges() + (self.overpool_fire_blasts / FireBlast:CooldownDuration()) - (Combustion:Duration() / FireBlast:CooldownDuration()) % 1) and (not Target.boss or self.time_to_combustion < Target.timeToDie)
	if Combustion.known and (self.time_to_combustion <= 0 or self.in_combust or (self.time_to_combustion < self.combustion_precast_time and Combustion:Ready(self.combustion_precast_time))) then
		local apl = self:combustion_phase()
		if apl then return apl end
	end
	if not self.fire_blast_pooling and SunKingsBlessing.known then
		self.fire_blast_pooling = Scorch:Execute() and FireBlast:FullRechargeTime() > (3 * Player.gcd)
	end
	if self.use_cds and ShiftingPower:Usable() and not self.in_combust and HotStreak:Down() and (not Hyperthermia.known or Hyperthermia:Down()) and (not ImprovedScorch:Active() or ImprovedScorch:Remains() > ((4 * Player.haste_factor) + Scorch:CastTime()) and FuryOfTheSunKing:Down()) and (PhoenixFlames:Charges() <= 1 or between(Combustion:Cooldown(), 10, 25)) then
		UseCooldown(ShiftingPower)
	end
	self.phoenix_pooling = not CallOfTheSunKing.known and (SunKingsBlessing.known or ((self.time_to_combustion + Combustion:Duration() - 5) < (PhoenixFlames:FullRechargeTime() + PhoenixFlames:CooldownDuration() - (self.shifting_power_before_combustion and 12 or 0))) and (Target.boss and self.time_to_combustion < Target.timeToDie))
	if FireBlast:Usable() and not self.fire_blast_pooling and self.time_to_combustion > 0 and Player.enemies >= self.hard_cast_flamestrike and Firestarter:Down() and HotStreak:Down() and (
		Player.fb_charges >= 2 or
		(HeatingUp:Up() and Flamestrike:Casting() and Player.execute_remains < 0.5)
	) then
		UseExtra(FireBlast, true)
	end
	if Firestarter.known and self.time_to_combustion > 0 and not self.in_combust and Firestarter:Up() then
		self:firestarter_fire_blasts()
	end
	if FireBlast:Usable() and ShiftingPower:Channeling() and (FireBlast:FullRechargeTime() < 3 or (SunKingsBlessing.known and HeatingUp:Up())) then
		UseExtra(FireBlast, true)
	end
	if self.time_to_combustion > 0 and not self.in_combust then
		local apl = self:standard_rotation()
		if apl then return apl end
	end
	if IceNova:Usable() and not Scorch:Execute() then
		UseCooldown(IceNova)
	end
	if Scorch:Usable() and not self.in_combust then
		return Scorch
	end
end

APL[SPEC.FIRE].precombat_variables = function(self)
--[[
actions.precombat+=/variable,name=firestarter_combustion,default=-1,value=talent.sun_kings_blessing,if=variable.firestarter_combustion<0
actions.precombat+=/variable,name=hot_streak_flamestrike,if=variable.hot_streak_flamestrike=0,value=4*(talent.quickflame|talent.flame_patch)+999*(!talent.flame_patch&!talent.quickflame)
actions.precombat+=/variable,name=hard_cast_flamestrike,if=variable.hard_cast_flamestrike=0,value=999
actions.precombat+=/variable,name=combustion_flamestrike,if=variable.combustion_flamestrike=0,value=4*(talent.quickflame|talent.flame_patch)+999*(!talent.flame_patch&!talent.quickflame)
actions.precombat+=/variable,name=skb_flamestrike,if=variable.skb_flamestrike=0,value=3*(talent.quickflame|talent.flame_patch)+999*(!talent.flame_patch&!talent.quickflame)
actions.precombat+=/variable,name=arcane_explosion,if=variable.arcane_explosion=0,value=999
actions.precombat+=/variable,name=arcane_explosion_mana,default=40,op=reset
actions.precombat+=/variable,name=combustion_cast_remains,default=0.3,op=reset
actions.precombat+=/variable,name=overpool_fire_blasts,default=0,op=reset
actions.precombat+=/variable,name=skb_duration,value=dbc.effect.1016075.base_value
actions.precombat+=/variable,name=treacherous_transmitter_precombat_cast,value=12
actions.precombat+=/variable,name=combustion_on_use,value=equipped.gladiators_badge|equipped.treacherous_transmitter|equipped.moonlit_prism|equipped.irideus_fragment|equipped.spoils_of_neltharus|equipped.timebreaching_talon|equipped.horn_of_valor
actions.precombat+=/variable,name=on_use_cutoff,value=20,if=variable.combustion_on_use
]]
	self.firestarter_combustion = SunKingsBlessing.known
	self.hot_streak_flamestrike = (Quickflame.known or FlamePatch.known) and 4 or 999
	self.hard_cast_flamestrike = 999
	self.combustion_flamestrike = (Quickflame.known or FlamePatch.known) and 4 or 999
	self.skb_flamestrike = (Quickflame.known or FlamePatch.known) and 3 or 999
	self.arcane_explosion = 999
	self.arcane_explosion_mana = 40
	self.combustion_cast_remains = 0.7
	self.overpool_fire_blasts = 0
	self.time_to_combustion = 0
	self.skb_duration = 6
end

APL[SPEC.FIRE].spells_in_flight = function(self)
	self.hot_streak_spells_in_flight_off_gcd = 0
	self.hot_streak_spells_in_flight = 0
	self.fb_traveling = Bolt:Traveling(true)
	self.pb_traveling = Pyroblast:Traveling(true)
	self.pf_traveling = PhoenixFlames:Traveling()
	if self.pf_traveling > 0 and (CallOfTheSunKing.known or self.in_combust_off_gcd) then
		self.hot_streak_spells_in_flight_off_gcd = self.hot_streak_spells_in_flight_off_gcd + self.pf_traveling
	end
	if self.in_combust and self.fb_traveling > 0 then
		self.hot_streak_spells_in_flight_off_gcd = self.hot_streak_spells_in_flight_off_gcd + self.fb_traveling
	end
	if self.pb_traveling > 0 and (self.in_combust_off_gcd or (Hyperthermia.known and Hyperthermia:Up())) then
		self.hot_streak_spells_in_flight_off_gcd = self.hot_streak_spells_in_flight_off_gcd + self.pb_traveling
	end
	if (Bolt:Casting() or Pyroblast:Casting()) and (Combustion:Remains() > Player.cast.ability:TravelTime() or (Firestarter.known and Firestarter:Up())) then
		self.hot_streak_spells_in_flight = self.hot_streak_spells_in_flight + 1
	end
	self.hot_streak_spells_in_flight = self.hot_streak_spells_in_flight + self.hot_streak_spells_in_flight_off_gcd
end

APL[SPEC.FIRE].firestarter_fire_blasts = function(self)
--[[
actions.firestarter_fire_blasts=fire_blast,use_while_casting=1,if=!variable.fire_blast_pooling&!buff.hot_streak.react&(action.fireball.execute_remains>gcd.remains|action.pyroblast.executing)&buff.heating_up.react+hot_streak_spells_in_flight=1&(cooldown.shifting_power.ready|charges>1|buff.feel_the_burn.remains<2*gcd.max)
actions.firestarter_fire_blasts+=/fire_blast,use_off_gcd=1,if=!variable.fire_blast_pooling&buff.heating_up.react+hot_streak_spells_in_flight=1&(talent.feel_the_burn&buff.feel_the_burn.remains<gcd.remains|cooldown.shifting_power.ready)&time>0
]]
	if FireBlast:Usable() and not self.fire_blast_pooling and HotStreak:Down() and ((HeatingUp:Up() and 1 or 0) + self.hot_streak_spells_in_flight_off_gcd) == 1 and (
		((Bolt:Casting() or Pyroblast:Casting()) and (ShiftingPower:Ready() or FireBlast:Charges() > 1 or FeelTheBurn:Remains() < (2 * Player.gcd))) or
		(FeelTheBurn.known and FeelTheBurn:Remains() < Player.execute_remains) or
		ShiftingPower:Ready()
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
	self.combustion_precast_time = (Player.enemies < self.combustion_flamestrike and Bolt:CastTime() or 0) + (Player.enemies >= self.combustion_flamestrike and Flamestrike:CastTime() or 0) - self.combustion_cast_remains
	self.time_to_combustion = max(self.combustion_ready_time, Combustion:Remains())
	self.combustion_in_cast = self.time_to_combustion <= 0 and (
		(self.hot_streak_spells_in_flight_off_gcd == 0 and not self.in_combust and ((Scorch:Casting() or Bolt:Casting() or Pyroblast:Casting() or Flamestrike:Casting()) or Meteor:LandingIn(3))) or
		(SunKingsBlessing.known and FuryOfTheSunKing:Up(true) and Combustion:Down(true) and (Pyroblast:Casting() or Flamestrike:Casting()))
	)
end

APL[SPEC.FIRE].active_talents = function(self)
--[[
actions.active_talents=meteor,if=(buff.combustion.up&buff.combustion.remains<cast_time)|(variable.time_to_combustion<=0|buff.combustion.remains>travel_time)
actions.active_talents+=/dragons_breath,if=talent.alexstraszas_fury&(buff.combustion.down&!buff.hot_streak.react)&(buff.feel_the_burn.up|time>15)&(!improved_scorch.active)
]]
	if self.use_cds and Meteor:Usable() and (
		(self.time_to_combustion <= 0 and (not SunKingsBlessing.known or FuryOfTheSunKing:Down())) or
		(self.in_combust and (
			Combustion:Remains() > 3 or
			(Combustion:Remains() < Player.gcd and (not SunKingsBlessing.known or (FuryOfTheSunKing:Down() and SunKingsBlessing:Stack() < 7)))
		))
	) then
		return UseCooldown(Meteor)
	end
	if AlexstraszasFury.known and DragonsBreath:Usable() and Target.estimated_range < 15 and not self.in_combust and HotStreak:Down() and (FeelTheBurn:Up() or Player:TimeInCombat() > 15) and not ImprovedScorch:Active() and Firestarter:Down() then
		return UseCooldown(DragonsBreath)
	end
end

APL[SPEC.FIRE].skb = function(self)
	if FuryOfTheSunKing:Down() then
		return
	end
	if ImprovedScorch.known and Scorch:Usable() and ImprovedScorch:Active() and ImprovedScorch:Remains() < (3 * Player.gcd) and Target.timeToDie > (2 + ImprovedScorch:Remains()) then
		return Scorch
	end
	if Flamestrike:Usable() and FuryOfTheSunKing:Remains() > Flamestrike:CastTime() and Player.enemies >= self.skb_flamestrike then
		return Flamestrike
	end
	if Pyroblast:Usable() and FuryOfTheSunKing:Remains() > Pyroblast:CastTime() then
		return Pyroblast
	end
end

APL[SPEC.FIRE].combustion_phase = function(self)
--[[
actions.combustion_phase=call_action_list,name=combustion_cooldowns,if=buff.combustion.remains>variable.skb_duration|fight_remains<20
actions.combustion_phase+=/call_action_list,name=active_talents
actions.combustion_phase+=/flamestrike,if=buff.combustion.down&buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.remains>cast_time&buff.fury_of_the_sun_king.expiration_delay_remains=0&cooldown.combustion.remains<cast_time&active_enemies>=variable.skb_flamestrike
actions.combustion_phase+=/pyroblast,if=buff.combustion.down&buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.remains>cast_time&(buff.fury_of_the_sun_king.expiration_delay_remains=0|buff.flame_accelerant.up)
actions.combustion_phase+=/meteor,if=talent.isothermic_core&buff.combustion.down&cooldown.combustion.remains<cast_time
actions.combustion_phase+=/fireball,if=buff.combustion.down&cooldown.combustion.remains<cast_time&active_enemies<2&!improved_scorch.active&!(talent.sun_kings_blessing&talent.flame_accelerant)
actions.combustion_phase+=/scorch,if=buff.combustion.down&cooldown.combustion.remains<cast_time
actions.combustion_phase+=/fireball,if=buff.combustion.down&buff.frostfire_empowerment.up
actions.combustion_phase+=/combustion,use_off_gcd=1,use_while_casting=1,if=hot_streak_spells_in_flight=0&buff.combustion.down&variable.time_to_combustion<=0&(action.scorch.executing&action.scorch.execute_remains<variable.combustion_cast_remains|action.fireball.executing&action.fireball.execute_remains<variable.combustion_cast_remains|action.pyroblast.executing&action.pyroblast.execute_remains<variable.combustion_cast_remains|action.flamestrike.executing&action.flamestrike.execute_remains<variable.combustion_cast_remains|!talent.isothermic_core&action.meteor.in_flight&action.meteor.in_flight_remains<variable.combustion_cast_remains|talent.isothermic_core&action.meteor.in_flight)
actions.combustion_phase+=/variable,name=TA_combust,value=cooldown.combustion.remains<10&buff.combustion.up
actions.combustion_phase+=/phoenix_flames,if=talent.spellfire_spheres&talent.phoenix_reborn&buff.heating_up.react&!buff.hot_streak.react&buff.flames_fury.up
actions.combustion_phase+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=(!variable.TA_combust|talent.sun_kings_blessing)&!variable.fire_blast_pooling&(!improved_scorch.active|action.scorch.executing|debuff.improved_scorch.remains>4*gcd.max)&(buff.fury_of_the_sun_king.down|action.pyroblast.executing)&buff.combustion.up&!buff.hot_streak.react&hot_streak_spells_in_flight+buff.heating_up.react*(gcd.remains>0)<2
actions.combustion_phase+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=variable.TA_combust&!variable.fire_blast_pooling&charges_fractional>2.5&(!improved_scorch.active|action.scorch.executing|debuff.improved_scorch.remains>4*gcd.max)&(buff.fury_of_the_sun_king.down|action.pyroblast.executing)&buff.combustion.up&!buff.hot_streak.react&hot_streak_spells_in_flight+buff.heating_up.react*(gcd.remains>0)<2
actions.combustion_phase+=/cancel_buff,name=hyperthermia,if=buff.fury_of_the_sun_king.react
actions.combustion_phase+=/flamestrike,if=(buff.hot_streak.react&active_enemies>=variable.combustion_flamestrike)|(buff.hyperthermia.react&active_enemies>=variable.combustion_flamestrike-talent.hyperthermia)
actions.combustion_phase+=/pyroblast,if=buff.hyperthermia.react
actions.combustion_phase+=/pyroblast,if=buff.hot_streak.react&buff.combustion.up
actions.combustion_phase+=/pyroblast,if=prev_gcd.1.scorch&buff.heating_up.react&active_enemies<variable.combustion_flamestrike&buff.combustion.up
actions.combustion_phase+=/scorch,if=talent.sun_kings_blessing&improved_scorch.active&debuff.improved_scorch.remains<3*gcd.max
actions.combustion_phase+=/flamestrike,if=buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.remains>cast_time&active_enemies>=variable.skb_flamestrike&buff.fury_of_the_sun_king.expiration_delay_remains=0&(buff.combustion.remains>cast_time+3|buff.combustion.remains<cast_time)
actions.combustion_phase+=/pyroblast,if=buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.remains>cast_time&buff.fury_of_the_sun_king.expiration_delay_remains=0&(buff.combustion.remains>cast_time+3|buff.combustion.remains<cast_time)
actions.combustion_phase+=/fireball,if=buff.frostfire_empowerment.up&!buff.hot_streak.react&!buff.excess_frost.up
actions.combustion_phase+=/phoenix_flames,if=talent.phoenix_reborn&buff.heating_up.react+hot_streak_spells_in_flight<2&buff.flames_fury.up
actions.combustion_phase+=/scorch,if=improved_scorch.active&(debuff.improved_scorch.remains<4*gcd.max)&active_enemies<variable.combustion_flamestrike
actions.combustion_phase+=/scorch,if=buff.heat_shimmer.react&(talent.scald|talent.improved_scorch)&active_enemies<variable.combustion_flamestrike
actions.combustion_phase+=/phoenix_flames,if=(!talent.call_of_the_sun_king&travel_time<buff.combustion.remains|(talent.call_of_the_sun_king&buff.combustion.remains<4|buff.sun_kings_blessing.stack<8))&buff.heating_up.react+hot_streak_spells_in_flight<2
actions.combustion_phase+=/fireball,if=buff.frostfire_empowerment.up&!buff.hot_streak.react
actions.combustion_phase+=/scorch,if=buff.combustion.remains>cast_time&cast_time>=gcd.max
actions.combustion_phase+=/fireball
]]
	if Combustion:Usable() and self.combustion_in_cast and ((Player.cast.remains < self.combustion_cast_remains and (Scorch:Casting() or Bolt:Casting() or Pyroblast:Casting() or Flamestrike:Casting())) or Meteor:LandingIn(self.combustion_cast_remains)) then
		UseCooldown(Combustion)
	end
	if (Target.boss and Target.timeToDie < 20) or (Combustion:Remains() > self.skb_duration) then
		self:combustion_cooldowns()
	end
	if not self.combustion_in_cast then
		local apl = self:active_talents()
		if apl then return apl end
	end
	if self.use_cds and not self.in_combust then
		if SunKingsBlessing.known then
			local apl = self:skb()
			if apl then return apl end
		end
		if Meteor:Usable() and IsothermicCore.known and Combustion:Ready(0.5) then
			UseCooldown(Meteor)
		end
		if Hyperthermia.known and Combustion:Usable() and Hyperthermia:Up() then
			UseCooldown(Combustion)
		end
		if Bolt:Usable() and Combustion:Ready(Bolt:CastTime()) and Player.enemies < 2 and not ImprovedScorch:Active() and Hyperthermia:Down() then
			return Bolt
		end
		if Scorch:Usable() and Combustion:Ready(Scorch:CastTime()) and Hyperthermia:Down() then
			return Scorch
		end
		if FrostfireEmpowerment.known and Bolt:Usable() and FrostfireEmpowerment:Up() then
			return Bolt
		end
	end
	self.TA_combust = Combustion:Ready(10) and self.in_combust
	if SpellfireSpheres.known and PhoenixReborn.known and PhoenixFlames:Usable() and FlamesFury:Up() and HotStreak:Down() and HeatingUp:Up() then
		return PhoenixFlames
	end
	if FireBlast:Usable() and not self.fire_blast_pooling and (not ImprovedScorch:Active() or Scorch:Casting() or ImprovedScorch:Remains() > (4 * Player.gcd)) and (FuryOfTheSunKing:Down() or Pyroblast:Casting()) and self.in_combust_off_gcd and HotStreak:Down() and ((HeatingUp:Up() and 1 or 0) + self.hot_streak_spells_in_flight_off_gcd) < 2 and (not self.TA_combust or SunKingsBlessing.known or Player.fb_charges > 2.5) then
		UseExtra(FireBlast, true)
	end
	if Flamestrike:Usable() and (Player.enemies >= self.hot_streak_flamestrike or (MajestyOfThePhoenix.known and Player.enemies >= 2 and MajestyOfThePhoenix:Stack() >= MajestyOfThePhoenix:MaxStack())) and (HotStreak:Up() or Hyperthermia:Up()) then
		return Flamestrike
	end
	if Pyroblast:Usable() and (
		Hyperthermia:Up() or
		(HotStreak:Up() and Player.enemies < self.combustion_flamestrike)
	) then
		return Pyroblast
	end
	if SunKingsBlessing.known then
		local apl = self:skb()
		if apl then return apl end
	end
	if FrostfireEmpowerment.known and Bolt:Usable() and FrostfireEmpowerment:Up() and HotStreak:Down() and ExcessFrost:Down() then
		return Bolt
	end
	if PhoenixReborn.known and PhoenixFlames:Usable() and FlamesFury:Up() and HotStreak:Down() and ((HeatingUp:Up() and 1 or 0) + self.hot_streak_spells_in_flight) < 2 then
		return PhoenixFlames
	end
	if Scorch:Usable() and Player.enemies < self.combustion_flamestrike and (
		(ImprovedScorch.known and ImprovedScorch:Active() and ImprovedScorch:Remains() < (4 * Player.gcd) and Target.timeToDie > (4 + ImprovedScorch:Remains())) or
		(HeatShimmer.known and (Scald.known or ImprovedScorch.known) and HeatShimmer:Up())
	) then
		return Scorch
	end
	if PhoenixFlames:Usable() and HotStreak:Down() and ((HeatingUp:Up() and 1 or 0) + self.hot_streak_spells_in_flight) < 2 and (
		(not CallOfTheSunKing.known and PhoenixFlames:TravelTime() < Combustion:Remains()) or
		(CallOfTheSunKing.known and (Combustion:Remains() < 4 or SunKingsBlessing:Stack() < 8))
	) then
		return PhoenixFlames
	end
	if FrostfireEmpowerment.known and Bolt:Usable() and FrostfireEmpowerment:Up() and HotStreak:Down() then
		return Bolt
	end
	if Scorch:Usable() and Combustion:Remains() > Scorch:CastTime() and Scorch:CastTime() >= Player.gcd then
		return Scorch
	end
	if Bolt:Usable() then
		return Bolt
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
actions.combustion_cooldowns+=/use_item,effect_name=gladiators_badge
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
actions.standard_rotation+=/fireball,if=buff.hot_streak.up&!buff.frostfire_empowerment.up&buff.hyperthermia.down&!cooldown.shifting_power.ready&cooldown.phoenix_flames.charges<1&!scorch_execute.active&!prev_gcd.1.fireball,line_cd=2*gcd.max
actions.standard_rotation+=/pyroblast,if=(buff.hyperthermia.react|buff.hot_streak.react&(buff.hot_streak.remains<action.fireball.execute_time)|buff.hot_streak.react&(hot_streak_spells_in_flight|firestarter.active|talent.call_of_the_sun_king&action.phoenix_flames.charges)|buff.hot_streak.react&scorch_execute.active)
actions.standard_rotation+=/flamestrike,if=active_enemies>=variable.skb_flamestrike&buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.expiration_delay_remains=0
actions.standard_rotation+=/scorch,if=improved_scorch.active&((talent.unleashed_inferno&debuff.improved_scorch.remains<action.pyroblast.cast_time+5*gcd.max)|(talent.sun_kings_blessing&debuff.improved_scorch.remains<4*gcd.max))&buff.fury_of_the_sun_king.up&!action.scorch.in_flight
actions.standard_rotation+=/pyroblast,if=buff.fury_of_the_sun_king.up&buff.fury_of_the_sun_king.expiration_delay_remains=0
actions.standard_rotation+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=!firestarter.active&(!variable.fire_blast_pooling|talent.spontaneous_combustion)&buff.fury_of_the_sun_king.down&(((action.fireball.executing&(action.fireball.execute_remains<0.5|!talent.hyperthermia)|action.pyroblast.executing&(action.pyroblast.execute_remains<0.5))&buff.heating_up.react)|(scorch_execute.active&(!improved_scorch.active|debuff.improved_scorch.stack=debuff.improved_scorch.max_stack|full_recharge_time<3)&(buff.heating_up.react&!action.scorch.executing|!buff.hot_streak.react&!buff.heating_up.react&action.scorch.executing&!hot_streak_spells_in_flight)))
actions.standard_rotation+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=!firestarter.active&((!variable.fire_blast_pooling&talent.unleashed_inferno)|talent.spontaneous_combustion)&buff.fury_of_the_sun_king.down&(buff.heating_up.up&hot_streak_spells_in_flight<1&(prev_gcd.1.phoenix_flames|prev_gcd.1.scorch))|(((buff.bloodlust.up&charges_fractional>1.5)|charges_fractional>2.5|buff.feel_the_burn.remains<0.5|full_recharge_time*1-(0.5*cooldown.shifting_power.ready)<buff.hyperthermia.duration)&buff.heating_up.react)
actions.standard_rotation+=/pyroblast,if=prev_gcd.1.scorch&buff.heating_up.react&scorch_execute.active&active_enemies<variable.hot_streak_flamestrike
actions.standard_rotation+=/scorch,if=improved_scorch.active&debuff.improved_scorch.remains<4*gcd.max
actions.standard_rotation+=/fireball,if=buff.frostfire_empowerment.up&!buff.hot_streak.react&!buff.excess_frost.up
actions.standard_rotation+=/scorch,if=buff.heat_shimmer.react&(talent.scald|talent.improved_scorch)&active_enemies<variable.combustion_flamestrike
actions.standard_rotation+=/phoenix_flames,if=!buff.hot_streak.up&(hot_streak_spells_in_flight<1&(!prev_gcd.1.fireball|(buff.heating_up.down&buff.hot_streak.down)))|(hot_streak_spells_in_flight<2&buff.flames_fury.react)
actions.standard_rotation+=/call_action_list,name=active_talents
actions.standard_rotation+=/dragons_breath,if=active_enemies>1&talent.alexstraszas_fury
actions.standard_rotation+=/scorch,if=(scorch_execute.active|buff.heat_shimmer.react)
actions.standard_rotation+=/arcane_explosion,if=active_enemies>=variable.arcane_explosion&mana.pct>=variable.arcane_explosion_mana
actions.standard_rotation+=/flamestrike,if=active_enemies>=variable.hard_cast_flamestrike
actions.standard_rotation+=/fireball
]]
	if Flamestrike:Usable() and (Player.enemies >= self.hot_streak_flamestrike or (MajestyOfThePhoenix.known and Player.enemies >= (Quickflame.known and 2 or 3) and MajestyOfThePhoenix:Stack() >= MajestyOfThePhoenix:MaxStack())) and (HotStreak:Up() or Hyperthermia:Up()) then
		return Flamestrike
	end
	if Bolt:Usable() and HotStreak:Up() and FrostfireEmpowerment:Down() and Hyperthermia:Down() and not ShiftingPower:Ready() and PhoenixFlames:Charges() < 1 and not Scorch:Execute() and not Bolt:Previous() and Bolt:Traveling() == 0 then
		return Bolt
	end
	if Pyroblast:Usable() and (
		Hyperthermia:Up() or
		HotStreak:Up() and (
			Scorch:Execute() or
			HotStreak:Remains() < Bolt:CastTime() or
			self.hot_streak_spells_in_flight > 0 or
			Firestarter:Up() or
			(CallOfTheSunKing.known and PhoenixFlames:Charges() > 0) or
			true
		)
	) then
		return Pyroblast
	end
	if SunKingsBlessing.known then
		local apl = self:skb()
		if apl then return apl end
	end
	if FireBlast:Usable() and Firestarter:Down() and (not FuryOfTheSunKing.known or FuryOfTheSunKing:Down()) and (
		((not self.fire_blast_pooling or SpontaneousCombustion.known) and (
			(HeatingUp:Up() and ((Bolt:Casting() and (Player.execute_remains < 0.5 or not Hyperthermia.known)) or (Pyroblast:Casting() and Player.execute_remains < 0.5))) or
			(Scorch:Execute() and (not ImprovedScorch.known or ImprovedScorch:Capped() or FireBlast:FullRechargeTime() < 3) and ((HeatingUp:Up() and not Scorch:Casting()) or (HotStreak:Down() and HeatingUp:Down() and Scorch:Casting() and self.hot_streak_spells_in_flight_off_gcd < 1)))
		)) or
		(((not self.fire_blast_pooling and UnleashedInferno.known) or SpontaneousCombustion.known) and HeatingUp:Up() and (
			(self.hot_streak_spells_in_flight_off_gcd < 1 and (PhoenixFlames:Previous() or Scorch:Previous())) or
			Player.fb_charges > (Player:BloodlustActive() and 1.5 or 2.5) or
			(FeelTheBurn.known and FeelTheBurn:Up() and FeelTheBurn:Remains() < 0.5) or
			(FireBlast:FullRechargeTime() * (ShiftingPower:Ready() and 0.5 or 1)) < Hyperthermia:Duration()
		))
	) then
		UseExtra(FireBlast, true)
	end
	if Pyroblast:Usable() and HotStreak:Up() and Scorch:Execute() and Player.enemies < self.hot_streak_flamestrike then
		return Pyroblast
	end
	if ImprovedScorch.known and Scorch:Usable() and ImprovedScorch:Active() and ImprovedScorch:Remains() < (4 * Player.gcd) and Target.timeToDie > (4 + ImprovedScorch:Remains()) then
		return Scorch
	end
	if CallOfTheSunKing.known and PhoenixFlames:Usable() and (not FeelTheBurn.known or FeelTheBurn:Remains() < (2 * Player.gcd)) then
		return PhoenixFlames
	end
	if ImprovedScorch.known and Scorch:Usable() and ImprovedScorch:Active() and ImprovedScorch:Stack() < ImprovedScorch:MaxStack() and Target.timeToDie > (4 + ImprovedScorch:Remains()) then
		return Scorch
	end
	if FrostfireEmpowerment.known and Bolt:Usable() and FrostfireEmpowerment:Up() and HotStreak:Down() and ExcessFrost:Down() then
		return Bolt
	end
	if HeatShimmer.known and Scorch:Usable() and HeatShimmer:Up() and (Scald.known or ImprovedScorch.known) and Player.enemies < self.combustion_flamestrike then
		return Scorch
	end
	if PhoenixFlames:Usable() and (
		(PhoenixReborn.known and not CallOfTheSunKing.known and not self.phoenix_pooling and HotStreak:Down() and FlamesFury:Up()) or
		(CallOfTheSunKing.known and HotStreak:Down() and self.hot_streak_spells_in_flight == 0 and (
			(PhoenixReborn.known and not self.phoenix_pooling and FlamesFury:Up()) or
			PhoenixFlames:ChargesFractional() > 2.5 or
			(PhoenixFlames:ChargesFractional() > 1.5 and (not FeelTheBurn.known or FeelTheBurn:Remains() < (3 * Player.gcd)))
		))
	) then
		return PhoenixFlames
	end
	local apl = self:active_talents()
	if apl then return apl end
	if AlexstraszasFury.known and DragonsBreath:Usable() and Player.enemies > 1 and Target.estimated_range < 15 then
		UseCooldown(DragonsBreath)
	end
	if Scorch:Usable() and (Scorch:Execute() or HeatShimmer:Up()) then
		return Scorch
	end
	if Flamestrike:Usable() and Player.enemies >= self.hard_cast_flamestrike then
		return Flamestrike
	end
	if Bolt:Usable() then
		return Bolt
	end
end

APL[SPEC.FROST].Main = function(self)
--[[

]]
	if Player:TimeInCombat() == 0 then
		if Opt.barrier and IceBarrier:Usable() and IceBarrier:Down() then
			UseExtra(IceBarrier)
		end
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 300 then
			return ArcaneIntellect
		end
		if SummonWaterElemental:Usable() and not Pet.active then
			return SummonWaterElemental
		end
		if Player.enemies >= 2 then
			if Blizzard:Usable() then
				return Blizzard
			end
		elseif Bolt:Usable() and not Bolt:Casting() then
			return Bolt
		end
	else
		if ArcaneIntellect:Down() and ArcaneIntellect:Usable() then
			UseExtra(ArcaneIntellect)
		elseif SummonWaterElemental:Usable() and not Pet.active then
			UseExtra(SummonWaterElemental)
		elseif MirrorImage:Usable() and Player:UnderAttack() then
			UseExtra(MirrorImage)
		elseif Opt.barrier and IceBarrier:Usable() and IceBarrier:Down() then
			UseExtra(IceBarrier)
		end
	end
--[[

]]
	self.use_cds = Target.boss or Target.timeToDie > Opt.cd_ttd or IcyVeins:Up()
	if self.use_cds then
		self:cooldowns()
	end
	local apl
	if Player.enemies >= 3 then
		apl = self:aoe()
	else
		apl = self:st()
	end
	if apl then return apl end
	if Player.moving then
		return self:movement()
	end
end

APL[SPEC.FROST].cooldowns = function(self)
	-- Let's not waste a shatter with a cooldown's GCD
	if Ebonbolt:Previous() or (GlacialSpike:Previous() and BrainFreeze:Up()) then
		return
	end
--[[

]]
	if IcyVeins:Usable() and IcyVeins:Down() and (Player.enemies >= 2 or (not SlickIce.known or SlickIce:Down())) then
		return UseCooldown(IcyVeins)
	end
	if Opt.trinket then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.FROST].movement = function(self)
--[[

]]
	if Blink:Usable() then
		UseExtra(Blink)
	elseif Shimmer:Usable() then
		UseExtra(Shimmer)
	elseif IceFloes:Usable() and IceFloes:Down() then
		UseExtra(IceFloes)
	end
	if ArcaneExplosion:Usable() and Player:ManaPct() > 30 and Player.enemies >= 2 then
		return ArcaneExplosion
	end
	if FireBlast:Usable() then
		return FireBlast
	end
	if IceLance:Usable() then
		return IceLance
	end
end

APL[SPEC.FROST].st = function(self)
	if Freeze:Usable() and not Target:Frozen() and (CometStorm:Previous() or (BrainFreeze:Down() and (Ebonbolt:Casting() or GlacialSpike:Casting()))) then
		UseExtra(Freeze)
	end
--[[

]]
	if Flurry:Usable() and WintersChill:Down() and (Ebonbolt:Previous() or (BrainFreeze:Up() and (GlacialSpike:Previous() or Bolt:Previous() or (FingersOfFrost:Down() and ((FreezingWinds.known and FreezingWinds:Up())))))) then
		return Flurry
	end
	if FrozenOrb:Usable() and (not FreezingWinds.known or IcyVeins:Up() or IcyVeins:Cooldown() > 12) then
		UseCooldown(FrozenOrb)
	end
	if Blizzard:Usable() and (Player.enemies >= 2 or (FreezingRain.known and FreezingRain:Up())) then
		return Blizzard
	end
	if RayOfFrost:Usable() and WintersChill:Stack() == 1 and Target.timeToDie > (5 * Player.haste_factor) then
		return RayOfFrost
	end
	if GlacialSpike:Usable() and WintersChill:Remains() > (GlacialSpike:CastTime() + GlacialSpike:TravelTime()) and Target.timeToDie > (GlacialSpike:CastTime() + GlacialSpike:TravelTime()) then
		return GlacialSpike
	end
	if IceLance:Usable() and WintersChill:Stack() > FingersOfFrost:Stack() and WintersChill:Remains() > IceLance:TravelTime() then
		return IceLance
	end
	if CometStorm:Usable() and not Player.cd then
		if Freeze:Usable() and not Target:Frozen() then
			UseExtra(Freeze)
		end
		UseCooldown(CometStorm)
	end
	if IceNova:Usable() then
		return IceNova
	end
	if IceLance:Usable() and (FingersOfFrost:Up() or (Target:Frozen() and not IceLance:Previous())) then
		return IceLance
	end
	if Ebonbolt:Usable() and Target.timeToDie > (Ebonbolt:CastTime() + Ebonbolt:TravelTime()) then
		return Ebonbolt
	end
	if ShiftingPower:Usable() and (not FreezingWinds.known or FreezingWinds:Down()) and (GroveInvigoration.known or FieldOfBlossoms.known or FreezingWinds.known or Player.enemies >= 2) then
		UseCooldown(ShiftingPower)
	end
	if GlacialSpike:Usable() and BrainFreeze:Up() and Target.timeToDie > (GlacialSpike:CastTime() + GlacialSpike:TravelTime()) then
		return GlacialSpike
	end
	if FreezingWinds.known and Blizzard:Usable() and (not Target.boss or Target.timeToDie > 4) and (FrozenOrb:Cooldown() > (IcyVeins:Cooldown() + 4)) then
		UseCooldown(Blizzard)
	end
	if Bolt:Usable() then
		return Bolt
	end
end

APL[SPEC.FROST].aoe = function(self)
	if Freeze:Usable() and not Target:Frozen() then
		if CometStorm.known and CometStorm:Cooldown() > 28 then
			UseExtra(Freeze)
		elseif GlacialSpike.known and SplittingIce.known and GlacialSpike:Casting() and BrainFreeze:Down() then
			UseExtra(Freeze)
		end
	end
--[[

]]
	if FrozenOrb:Usable() then
		return FrozenOrb
	end
	if Blizzard:Usable() then
		return Blizzard
	end
	if Flurry:Usable() and WintersChill:Down() and (Ebonbolt:Previous() or (BrainFreeze:Up() and FingersOfFrost:Down())) then
		return Flurry
	end
	if IceNova:Usable() then
		if Freeze:Usable() and not Target:Frozen() and (not CometStorm.known or CometStorm:Cooldown() > 25) then
			UseExtra(Freeze)
		end
		return IceNova
	end
	if CometStorm:Usable() then
		if Freeze:Usable() and not Target:Frozen() then
			UseExtra(Freeze)
		end
		return CometStorm
	end
	if IceLance:Usable() and (FingersOfFrost:Up() or (Target:Frozen() and not IceLance:Previous()) or WintersChill:Remains() > IceLance:TravelTime()) then
		return IceLance
	end
	if BurstOfCold.known and ConeOfCold:Usable() and BurstOfCold:Up() and (Target:Frozen() or BurstOfCold:Remains() < Player.gcd) then
		UseCooldown(BurstOfCold)
	end
	if ShiftingPower:Usable() and not FrozenOrb:Ready(8) and (not FreezingWinds.known or FreezingWinds:Down()) then
		UseCooldown(ShiftingPower)
	end
	if Ebonbolt:Usable() and Target.timeToDie > (Ebonbolt:CastTime() + Ebonbolt:TravelTime()) then
		return Ebonbolt
	end
	if Bolt:Usable() then
		return Bolt
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

function UI:DisableOverlayGlows()
	if not Opt.glow.blizzard then
		SetCVar('assistedCombatHighlight', 0)
	end
	if Opt.glow.blizzard or not LibStub then
		return
	end
	local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
	if lib then
		lib.ShowOverlayGlow = function(...)
			return lib.HideOverlayGlow(...)
		end
	end
end

function UI:UpdateGlows()
	for _, button in next, Buttons.all do
		if button.action and button.frame:IsVisible() and (
			(Opt.glow.main and button.action == Player.main) or
			(Opt.glow.cooldown and button.action == Player.cd) or
			(Opt.glow.interrupt and button.action == Player.interrupt) or
			(Opt.glow.extra and button.action == Player.extra)
		) then
			if not button.glow:IsVisible() then
				button.glow:Show()
				if Opt.glow.animation then
					button.glow.ProcStartAnim:Play()
				else
					button.glow.ProcLoop:Play()
				end
			end
		elseif button.glow:IsVisible() then
			if button.glow.ProcStartAnim:IsPlaying() then
				button.glow.ProcStartAnim:Stop()
			end
			if button.glow.ProcLoop:IsPlaying() then
				button.glow.ProcLoop:Stop()
			end
			button.glow:Hide()
		end
	end
end

function UI:UpdateBindings()
	for _, item in next, InventoryItems.all do
		wipe(item.keybinds)
	end
	for _, ability in next, Abilities.all do
		wipe(ability.keybinds)
	end
	for _, button in next, Buttons.all do
		if button.action and button.keybind then
			button.action.keybinds[#button.action.keybinds + 1] = button.keybind
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	amagicPanel:SetMovable(not Opt.snap)
	amagicPreviousPanel:SetMovable(not Opt.snap)
	amagicCooldownPanel:SetMovable(not Opt.snap)
	amagicInterruptPanel:SetMovable(not Opt.snap)
	amagicExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		amagicPanel:SetUserPlaced(true)
		amagicPreviousPanel:SetUserPlaced(true)
		amagicCooldownPanel:SetUserPlaced(true)
		amagicInterruptPanel:SetUserPlaced(true)
		amagicExtraPanel:SetUserPlaced(true)
	end
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
	amagicPanel.text:SetScale(Opt.scale.main)
	amagicPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	amagicCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	amagicCooldownPanel.text:SetScale(Opt.scale.cooldown)
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
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.FIRE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.ARCANE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.FIRE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
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
	self:UpdateGlows()
end

function UI:Reset()
	amagicPanel:ClearAllPoints()
	amagicPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_center, text_tl, text_tr, text_bl, text_cd_center, text_cd_tr
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsSpellUsable(Player.main.spellId)) or
		           (Player.main.itemId and IsItemUsable(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsSpellUsable(Player.cd.spellId)) or
		           (Player.cd.itemId and IsItemUsable(Player.cd.itemId)))
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
		if Opt.keybinds then
			for _, bind in next, Player.main.keybinds do
				text_tr = bind
				break
			end
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd_center = format('%.1f', react)
			end
		end
		if Opt.keybinds then
			for _, bind in next, Player.cd.keybinds do
				text_cd_tr = bind
				break
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
	if channel.ability and not channel.ability.ignore_channel and channel.tick_count > 0 then
		dim = Opt.dimmer
		if channel.tick_count > 1 then
			local ctime = GetTime()
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = '|cFF00FF00CHAIN'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if Player.major_cd_remains > 0 then
		text_center = format('%.1fs', Player.major_cd_remains)
	end
	if border ~= amagicPanel.border.overlay then
		amagicPanel.border.overlay = border
		amagicPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end
	if Combustion.known and APL[SPEC.FIRE].combustion_in_cast then
		text_center = 'COMBUST\nCAST'
	end
	if FireBlast.known then
		text_tl = format('|cFF%s%.1f', (Player.fb_charges < 1 and 'FF0000') or (Player.fb_charges < 2.5 and 'FFFD00') or '00FF00', Player.fb_charges)
	end
	if Pet.ArcanePhoenix.known and Player.phoenix_remains > 0 then
		text_bl = format('%.1fs', Player.phoenix_remains)
	end

	amagicPanel.dimmer:SetShown(dim)
	amagicPanel.text.center:SetText(text_center)
	amagicPanel.text.tl:SetText(text_tl)
	amagicPanel.text.tr:SetText(text_tr)
	amagicPanel.text.bl:SetText(text_bl)
	amagicCooldownPanel.dimmer:SetShown(dim_cd)
	amagicCooldownPanel.text.center:SetText(text_cd_center)
	amagicCooldownPanel.text.tr:SetText(text_cd_tr)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		amagicPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = Player.main:Free()
	end
	if Player.cd then
		amagicCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local cooldown = GetSpellCooldown(Player.cd.spellId)
			amagicCooldownPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
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
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_Automagically1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			log('[|cFFFFD000Warning|r]', ADDON, 'is not designed for players under level 10, and almost certainly will not operate properly!')
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
	   e == 'SPELL_ABSORBED' or
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
	local uid = ToUID(dstGUID)
	if not uid or Target.Dummies[uid] then
		return
	end
	TrackedAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
	local pet = SummonedPets.byUnitId[uid]
	if pet then
		pet:RemoveUnit(dstGUID)
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
	elseif srcGUID == Pet.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Pet.guid then
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
	elseif srcGUID == Pet.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Pet.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL_SUMMON = function(event, srcGUID, dstGUID)
	if srcGUID ~= Player.guid then
		return
	end
	local uid = ToUID(dstGUID)
	if not uid then
		return
	end
	local pet = SummonedPets.byUnitId[uid]
	if pet then
		pet:AddUnit(dstGUID)
	end
end

--local UnknownSpell = {}

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID == Pet.guid then
		if Pet.stuck and (event == 'SPELL_CAST_SUCCESS' or event == 'SPELL_DAMAGE' or event == 'SWING_DAMAGE') then
			Pet.stuck = false
		elseif not Pet.stuck and event == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Pet.stuck = true
		end
	elseif srcGUID ~= Player.guid then
		local uid = ToUID(srcGUID)
		if uid then
			local pet = SummonedPets.byUnitId[uid]
			if pet then
				local unit = pet.active_units[srcGUID]
				if unit then
					if event == 'SPELL_CAST_SUCCESS' and pet.CastSuccess then
						pet:CastSuccess(unit, spellId, dstGUID)
					elseif event == 'SPELL_CAST_START' and pet.CastStart then
						pet:CastStart(unit, spellId, dstGUID)
					elseif event == 'SPELL_CAST_FAILED' and pet.CastFailed then
						pet:CastFailed(unit, spellId, dstGUID, missType)
					elseif (event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH') and pet.CastLanded then
						pet:CastLanded(unit, spellId, dstGUID, event, missType)
					end
					--log(format('%.3f PET %d EVENT %s SPELL %s ID %d', Player.time, pet.unitId, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
				end
			end
		end
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
--[[
		if not UnknownSpell[event] then
			UnknownSpell[event] = {}
		end
		if not UnknownSpell[event][spellId] then
			UnknownSpell[event][spellId] = true
			log(format('%.3f EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d FROM %s ON %s', Player.time, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0, srcGUID, dstGUID))
		end
]]
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		if HyperthreadWristwraps:Equipped() then
			HyperthreadWristwraps:Cast(ability)
		end
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
	if dstGUID == Player.guid or dstGUID == Pet.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
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
		Player.health.current = UnitHealth(unitId)
		Player.health.max = UnitHealthMax(unitId)
		Player.health.pct = Player.health.current / Player.health.max * 100
	elseif unitId == 'pet' then
		Pet.health.current = UnitHealth(unitId)
		Pet.health.max = UnitHealthMax(unitId)
		Pet.health.pct = Pet.health.current / Pet.health.max * 100
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitEffectiveLevel(unitId)
		Player.mana.base = Player.BaseMana[Player.level]
		Player.mana.max = UnitPowerMax(unitId, 0)
		Player.arcane_charges.max = UnitPowerMax(unitId, 16)
	elseif unitId == 'pet' then
		Pet.mana.max = UnitPowerMax(unitId, 0)
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

function Events:UNIT_PET(unitId)
	if unitId ~= 'player' then
		return
	end
	Pet:UpdateKnown()
	Pet:Update()
end

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Pet.stuck = false
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
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
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
	for _, i in next, InventoryItems.all do
		i.name, _, _, _, _, _, _, _, equipType, i.icon = GetItemInfo(i.itemId or 0)
		i.can_use = i.name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, i.equip_slot = Player:Equipped(i.itemId)
			if i.equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', i.equip_slot)
			end
			i.can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[i.itemId] then
			i.can_use = false
		end
	end

	Player.set_bonus.t33 = (Player:Equipped(212090) and 1 or 0) + (Player:Equipped(212091) and 1 or 0) + (Player:Equipped(212092) and 1 or 0) + (Player:Equipped(212093) and 1 or 0) + (Player:Equipped(212095) and 1 or 0)

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
	Events:UNIT_MAXPOWER('player')
	Events:UPDATE_BINDINGS()
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, cooldown, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			cooldown = {
				startTime = castStart / 1000,
				duration = (castEnd - castStart) / 1000
			}
		else
			cooldown = GetSpellCooldown(61304)
		end
		amagicPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED(slot)
	for _, button in next, Buttons.all do
		if not slot or button.action_id == slot then
			button:UpdateAction()
		end
	end
	UI:UpdateBindings()
	UI:UpdateGlows()
end

function Events:ACTIONBAR_PAGE_CHANGED()
	C_Timer.After(0, function()
		Events:ACTIONBAR_SLOT_CHANGED(0)
	end)
end
Events.UPDATE_BONUS_ACTIONBAR = Events.ACTIONBAR_PAGE_CHANGED

function Events:UPDATE_BINDINGS()
	UI:UpdateBindings()
end
Events.GAME_PAD_ACTIVE_CHANGED = Events.UPDATE_BINDINGS

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
end

function Events:UI_ERROR_MESSAGE(errorId)
	if (
	    errorId == 394 or -- pet is rooted
	    errorId == 396 or -- target out of pet range
	    errorId == 400    -- no pet path to target
	) then
		Pet.stuck = true
	end
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
	log(desc .. ':', opt_view, ...)
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
				UI:Reset()
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
				for _, button in next, Buttons.all do
					button:UpdateGlowDisplay()
				end
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
				for _, button in next, Buttons.all do
					button:UpdateGlowDisplay()
				end
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
	if startsWith(msg[1], 'key') or startsWith(msg[1], 'bind') then
		if msg[2] then
			Opt.keybinds = msg[2] == 'on'
		end
		return Status('Show keybinding text on main ability icon (topright)', Opt.keybinds)
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
	if startsWith(msg[1], 'hide') or startsWith(msg[1], 'spec') then
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
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. C_AddOns.GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
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
		'keybind |cFF00C000on|r/|cFFC00000off|r - show keybinding text on main ability icon (topright)',
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
