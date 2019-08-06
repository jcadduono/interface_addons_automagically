if select(2, UnitClass('player')) ~= 'MAGE' then
	DisableAddOn('Automagically')
	return
end

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
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

SLASH_Automagically1, SLASH_Automagically2, SLASH_Automagically3 = '/am', '/amagic', '/auto'
BINDING_HEADER_AUTOMAGICALLY = 'Automagically'

local function InitializeOpts()
	local function SetDefaults(t, ref)
		local k, v
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
		pot = false,
		trinket = true,
		conserve_mana = 60,
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	ARCANE = 1,
	FIRE = 2,
	FROST = 3,
}

local events, glows = {}, {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	mana = 0,
	mana_max = 0,
	mana_regen = 0,
	previous_gcd = {},-- list of previous GCD abilities
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false,
	estimated_range = 30,
}

-- Azerite trait API access
local Azerite = {}

-- base mana for each level
local BaseMana = {
	145,        160,    175,    190,    205,    -- 5
	220,        235,    250,    290,    335,    -- 10
	390,        445,    510,    580,    735,    -- 15
	825,        865,    910,    950,    995,    -- 20
	1060,       1125,   1195,   1405,   1490,   -- 25
	1555,       1620,   1690,   1760,   1830,   -- 30
	2110,       2215,   2320,   2425,   2540,   -- 35
	2615,       2695,   3025,   3110,   3195,   -- 40
	3270,       3345,   3420,   3495,   3870,   -- 45
	3940,       4015,   4090,   4170,   4575,   -- 50
	4660,       4750,   4835,   5280,   5380,   -- 55
	5480,       5585,   5690,   5795,   6300,   -- 60
	6420,       6540,   6660,   6785,   6915,   -- 65
	7045,       7175,   7310,   7915,   8065,   -- 70
	8215,       8370,   8530,   8690,   8855,   -- 75
	9020,       9190,   9360,   10100,  10290,  -- 80
	10485,      10680,  10880,  11085,  11295,  -- 85
	11505,      11725,  12605,  12845,  13085,  -- 90
	13330,      13585,  13840,  14100,  14365,  -- 95
	14635,      15695,  15990,  16290,  16595,  -- 100
	16910,      17230,  17550,  17880,  18220,  -- 105
	18560,      18910,  19265,  19630,  20000,  -- 110
	35985,      42390,  48700,  54545,  59550,  -- 115
	64700,      68505,  72450,  77400,  100000  -- 120
}

local amagicPanel = CreateFrame('Frame', 'amagicPanel', UIParent)
amagicPanel:SetPoint('CENTER', 0, -169)
amagicPanel:SetFrameStrata('BACKGROUND')
amagicPanel:SetSize(64, 64)
amagicPanel:SetMovable(true)
amagicPanel:Hide()
amagicPanel.icon = amagicPanel:CreateTexture(nil, 'BACKGROUND')
amagicPanel.icon:SetAllPoints(amagicPanel)
amagicPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
amagicPanel.border = amagicPanel:CreateTexture(nil, 'ARTWORK')
amagicPanel.border:SetAllPoints(amagicPanel)
amagicPanel.border:SetTexture('Interface\\AddOns\\Automagically\\border.blp')
amagicPanel.border:Hide()
amagicPanel.dimmer = amagicPanel:CreateTexture(nil, 'BORDER')
amagicPanel.dimmer:SetAllPoints(amagicPanel)
amagicPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
amagicPanel.dimmer:Hide()
amagicPanel.swipe = CreateFrame('Cooldown', nil, amagicPanel, 'CooldownFrameTemplate')
amagicPanel.swipe:SetAllPoints(amagicPanel)
amagicPanel.swipe:SetDrawBling(false)
amagicPanel.text = CreateFrame('Frame', nil, amagicPanel)
amagicPanel.text:SetAllPoints(amagicPanel)
amagicPanel.text.br = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.text.br:SetPoint('BOTTOMRIGHT', amagicPanel, 'BOTTOMRIGHT', -1.5, 3)
amagicPanel.text.center = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 10, 'OUTLINE')
amagicPanel.text.center:SetAllPoints(amagicPanel.text)
amagicPanel.text.center:SetJustifyH('CENTER')
amagicPanel.text.center:SetJustifyV('CENTER')
amagicPanel.button = CreateFrame('Button', nil, amagicPanel)
amagicPanel.button:SetAllPoints(amagicPanel)
amagicPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local amagicPreviousPanel = CreateFrame('Frame', 'amagicPreviousPanel', UIParent)
amagicPreviousPanel:SetFrameStrata('BACKGROUND')
amagicPreviousPanel:SetSize(64, 64)
amagicPreviousPanel:Hide()
amagicPreviousPanel:RegisterForDrag('LeftButton')
amagicPreviousPanel:SetScript('OnDragStart', amagicPreviousPanel.StartMoving)
amagicPreviousPanel:SetScript('OnDragStop', amagicPreviousPanel.StopMovingOrSizing)
amagicPreviousPanel:SetMovable(true)
amagicPreviousPanel.icon = amagicPreviousPanel:CreateTexture(nil, 'BACKGROUND')
amagicPreviousPanel.icon:SetAllPoints(amagicPreviousPanel)
amagicPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
amagicPreviousPanel.border = amagicPreviousPanel:CreateTexture(nil, 'ARTWORK')
amagicPreviousPanel.border:SetAllPoints(amagicPreviousPanel)
amagicPreviousPanel.border:SetTexture('Interface\\AddOns\\Automagically\\border.blp')
local amagicCooldownPanel = CreateFrame('Frame', 'amagicCooldownPanel', UIParent)
amagicCooldownPanel:SetSize(64, 64)
amagicCooldownPanel:SetFrameStrata('BACKGROUND')
amagicCooldownPanel:Hide()
amagicCooldownPanel:RegisterForDrag('LeftButton')
amagicCooldownPanel:SetScript('OnDragStart', amagicCooldownPanel.StartMoving)
amagicCooldownPanel:SetScript('OnDragStop', amagicCooldownPanel.StopMovingOrSizing)
amagicCooldownPanel:SetMovable(true)
amagicCooldownPanel.icon = amagicCooldownPanel:CreateTexture(nil, 'BACKGROUND')
amagicCooldownPanel.icon:SetAllPoints(amagicCooldownPanel)
amagicCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
amagicCooldownPanel.border = amagicCooldownPanel:CreateTexture(nil, 'ARTWORK')
amagicCooldownPanel.border:SetAllPoints(amagicCooldownPanel)
amagicCooldownPanel.border:SetTexture('Interface\\AddOns\\Automagically\\border.blp')
amagicCooldownPanel.cd = CreateFrame('Cooldown', nil, amagicCooldownPanel, 'CooldownFrameTemplate')
amagicCooldownPanel.cd:SetAllPoints(amagicCooldownPanel)
local amagicInterruptPanel = CreateFrame('Frame', 'amagicInterruptPanel', UIParent)
amagicInterruptPanel:SetFrameStrata('BACKGROUND')
amagicInterruptPanel:SetSize(64, 64)
amagicInterruptPanel:Hide()
amagicInterruptPanel:RegisterForDrag('LeftButton')
amagicInterruptPanel:SetScript('OnDragStart', amagicInterruptPanel.StartMoving)
amagicInterruptPanel:SetScript('OnDragStop', amagicInterruptPanel.StopMovingOrSizing)
amagicInterruptPanel:SetMovable(true)
amagicInterruptPanel.icon = amagicInterruptPanel:CreateTexture(nil, 'BACKGROUND')
amagicInterruptPanel.icon:SetAllPoints(amagicInterruptPanel)
amagicInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
amagicInterruptPanel.border = amagicInterruptPanel:CreateTexture(nil, 'ARTWORK')
amagicInterruptPanel.border:SetAllPoints(amagicInterruptPanel)
amagicInterruptPanel.border:SetTexture('Interface\\AddOns\\Automagically\\border.blp')
amagicInterruptPanel.cast = CreateFrame('Cooldown', nil, amagicInterruptPanel, 'CooldownFrameTemplate')
amagicInterruptPanel.cast:SetAllPoints(amagicInterruptPanel)
local amagicExtraPanel = CreateFrame('Frame', 'amagicExtraPanel', UIParent)
amagicExtraPanel:SetFrameStrata('BACKGROUND')
amagicExtraPanel:SetSize(64, 64)
amagicExtraPanel:Hide()
amagicExtraPanel:RegisterForDrag('LeftButton')
amagicExtraPanel:SetScript('OnDragStart', amagicExtraPanel.StartMoving)
amagicExtraPanel:SetScript('OnDragStop', amagicExtraPanel.StopMovingOrSizing)
amagicExtraPanel:SetMovable(true)
amagicExtraPanel.icon = amagicExtraPanel:CreateTexture(nil, 'BACKGROUND')
amagicExtraPanel.icon:SetAllPoints(amagicExtraPanel)
amagicExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
amagicExtraPanel.border = amagicExtraPanel:CreateTexture(nil, 'ARTWORK')
amagicExtraPanel.border:SetAllPoints(amagicExtraPanel)
amagicExtraPanel.border:SetTexture('Interface\\AddOns\\Automagically\\border.blp')

-- Start Auto AoE

local targetModes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.ARCANE] = {
		{1, ''},
		{2, '2'},
		{3, '3+'},
		{6, '6+'},
	},
	[SPEC.FIRE] = {
		{1, ''},
		{2, '2'},
		{3, '3+'},
		{5, '5+'},
		{7, '7+'},
	},
	[SPEC.FROST] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	}
}

local function SetTargetMode(mode)
	if mode == targetMode then
		return
	end
	targetMode = min(mode, #targetModes[Player.spec])
	Player.enemies = targetModes[Player.spec][targetMode][1]
	amagicPanel.text.br:SetText(targetModes[Player.spec][targetMode][2])
end
Automagically_SetTargetMode = SetTargetMode

function ToggleTargetMode()
	local mode = targetMode + 1
	SetTargetMode(mode > #targetModes[Player.spec] and 1 or mode)
end
Automagically_ToggleTargetMode = ToggleTargetMode

local function ToggleTargetModeReverse()
	local mode = targetMode - 1
	SetTargetMode(mode < 1 and #targetModes[Player.spec] or mode)
end
Automagically_ToggleTargetModeReverse = ToggleTargetModeReverse

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:add(guid, update)
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
		self:update()
	end
end

function autoAoe:remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #targetModes[Player.spec], 1, -1 do
		if count >= targetModes[Player.spec][i][1] then
			SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:purge()
	local update, guid, t
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
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability.add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_pet = false,
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
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable()
	if not self.known then
		return false
	end
	if self:cost() > Player.mana then
		return false
	end
	if self.requires_pet and not Player.pet_active then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready()
end

function Ability:remains()
	if self:traveling() or self:casting() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:refreshable()
	if self.buff_duration > 0 then
		return self:remains() < self:duration() * 0.3
	end
	return self:down()
end

function Ability:up()
	return self:remains() > 0
end

function Ability:down()
	return not self:up()
end

function Ability:setVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:travelTime()
	return Target.estimated_range / self.velocity
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana_base) or 0
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:chargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return Player.ability_casting == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:castRegen()
	return Player.mana_regen * self:castTime() - self:cost()
end

function Ability:tickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:autoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
	end
end

function Ability:recordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:updateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:removeAura(guid)
			end
		end
	end
end

function trackAuras:remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:removeAura(guid)
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
end

function Ability:applyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:refreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(guid)
		return
	end
	local duration = self:duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:removeAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Mage Abilities
---- Multiple Specializations
local ArcaneIntellect = Ability.add(1459, true, false)
ArcaneIntellect.mana_cost = 4
ArcaneIntellect.buff_duration = 3600
local Blink = Ability.add(1953, true, true)
Blink.mana_cost = 2
Blink.cooldown_duration = 15
local Counterspell = Ability.add(2139, false, true)
Counterspell.mana_cost = 2
Counterspell.cooldown_duration = 24
Counterspell.triggers_gcd = false
local TimeWarp = Ability.add(80353, true, true)
TimeWarp.mana_cost = 4
TimeWarp.buff_duration = 40
TimeWarp.cooldown_duration = 300
TimeWarp.triggers_gcd = false
------ Procs

------ Talents
local IncantersFlow = Ability.add(116267, true, true, 236219)
local MirrorImage = Ability.add(55342, true, true)
MirrorImage.mana_cost = 2
MirrorImage.buff_duration = 40
MirrorImage.cooldown_duration = 120
local RuneOfPower = Ability.add(116011, true, true, 116014)
RuneOfPower.requires_charge = true
RuneOfPower.buff_duration = 10
RuneOfPower.cooldown_duration = 40
local Shimmer = Ability.add(212653, true, true)
Shimmer.mana_cost = 2
Shimmer.cooldown_duration = 20
Shimmer.requires_charge = true
Shimmer.triggers_gcd = false
---- Arcane
local ArcaneBarrage = Ability.add(44425, false, true)
ArcaneBarrage.cooldown_duration = 3
ArcaneBarrage.hasted_cooldown = true
ArcaneBarrage:setVelocity(25)
ArcaneBarrage:autoAoe()
local ArcaneBlast = Ability.add(30451, false, true)
ArcaneBlast.mana_cost = 2.75
local ArcaneExplosion = Ability.add(1449, false, true)
ArcaneExplosion.mana_cost = 10
ArcaneExplosion:autoAoe()
local ArcaneMissiles = Ability.add(5143, false, true, 7268)
ArcaneMissiles.mana_cost = 15
ArcaneMissiles:setVelocity(50)
local ArcanePower = Ability.add(12042, true, true)
ArcanePower.buff_duration = 10
ArcanePower.cooldown_duration = 90
local Evocation = Ability.add(12051, true, true)
Evocation.buff_duration = 6
Evocation.cooldown_duration = 90
local PrismaticBarrier = Ability.add(235450, true, true)
PrismaticBarrier.mana_cost = 3
PrismaticBarrier.buff_duration = 60
PrismaticBarrier.cooldown_duration = 25
local PresenceOfMind = Ability.add(205025, true, true)
PresenceOfMind.cooldown_duration = 60
PresenceOfMind.triggers_gcd = false
------ Talents
local Amplification = Ability.add(236628, false, true)
local ArcaneFamiliar = Ability.add(205022, true, true, 210126)
ArcaneFamiliar.buff_duration = 3600
ArcaneFamiliar.cooldown_duration = 10
local ArcaneOrb = Ability.add(153626, false, true, 153640)
ArcaneOrb.mana_cost = 1
ArcaneOrb.cooldown_duration = 20
ArcaneOrb:autoAoe()
local ChargedUp = Ability.add(205032, true, true)
ChargedUp.cooldown_duration = 40
local NetherTempest = Ability.add(114923, false, true, 114954)
NetherTempest.mana_cost = 1.5
NetherTempest.buff_duration = 12
NetherTempest.tick_interval = 1
NetherTempest.hasted_ticks = true
NetherTempest:autoAoe()
local Overpowered = Ability.add(155147, false, true)
local Resonance = Ability.add(205028, false, true)
local RuleOfThrees = Ability.add(264354, true, true, 264774)
RuleOfThrees.buff_duration = 15
local Slipstream = Ability.add(236457, false, true)
local Supernova = Ability.add(157980, false, true)
Supernova.cooldown_duration = 25
Supernova:autoAoe()
------ Procs
local Clearcasting = Ability.add(79684, true, true, 276743)
Clearcasting.buff_duration = 15
---- Fire
local BlazingBarrier = Ability.add(235313, true, true)
BlazingBarrier.mana_cost = 3
BlazingBarrier.buff_duration = 60
BlazingBarrier.cooldown_duration = 25
local Combustion = Ability.add(190319, true, true)
Combustion.mana_cost = 10
Combustion.buff_duration = 10
Combustion.cooldown_duration = 120
Combustion.triggers_gcd = false
local DragonsBreath = Ability.add(31661, false, true)
DragonsBreath.mana_cost = 4
DragonsBreath.buff_duration = 4
DragonsBreath.cooldown_duration = 20
DragonsBreath:autoAoe()
local Fireball = Ability.add(133, false, true)
Fireball.mana_cost = 2
Fireball:setVelocity(45)
local FireBlast = Ability.add(108853, false, true)
FireBlast.mana_cost = 1
FireBlast.cooldown_duration = 12
FireBlast.hasted_cooldown = true
FireBlast.requires_charge = true
FireBlast.triggers_gcd = false
local Flamestrike = Ability.add(2120, false, true)
Flamestrike.mana_cost = 2.5
Flamestrike.buff_duration = 8
Flamestrike:autoAoe()
local Ignite = Ability.add(12846, false, true, 12654)
Ignite.buff_duration = 9
Ignite.tick_interval = 1
Ignite:autoAoe(false, 'apply')
local Pyroblast = Ability.add(11366, false, true)
Pyroblast.mana_cost = 2
Pyroblast:setVelocity(35)
local Scorch = Ability.add(2948, false, true)
Scorch.mana_cost = 1
------ Talents
local AlexstraszasFury = Ability.add(235870, false, true)
local BlastWave = Ability.add(157981, false, true)
BlastWave.buff_duration = 4
BlastWave.cooldown_duration = 25
local Conflagration = Ability.add(205023, false, true, 226757)
Conflagration.buff_duration = 8
Conflagration.tick_interval = 2
Conflagration.hasted_ticks = true
local Firestarter = Ability.add(205026, false, true)
local FlameOn = Ability.add(205029, false, true)
local FlamePatch = Ability.add(205037, false, true, 205472)
local Kindling = Ability.add(155148, false, true)
local LivingBomb = Ability.add(44457, false, true, 217694)
LivingBomb.buff_duration = 4
LivingBomb.mana_cost = 1.5
LivingBomb.cooldown_duration = 12
LivingBomb.tick_interval = 1
LivingBomb.hasted_duration = true
LivingBomb.hasted_cooldown = true
LivingBomb.hasted_ticks = true
LivingBomb.explosion = Ability.add(44461, false, true)
LivingBomb.explosion:autoAoe()
LivingBomb.spread = Ability.add(44461, false, true)
LivingBomb.spread.buff_duration = 4
LivingBomb.spread.tick_interval = 1
LivingBomb.spread.hasted_duration = true
LivingBomb.spread.hasted_ticks = true
local Meteor = Ability.add(153561, false, true, 153564)
Meteor.mana_cost = 1
Meteor.buff_duration = 8
Meteor.cooldown_duration = 45
Meteor:autoAoe()
local PhoenixFlames = Ability.add(257541, false, true, 257542)
PhoenixFlames.cooldown_duration = 30
PhoenixFlames.requires_charge = true
PhoenixFlames:setVelocity(50)
PhoenixFlames:autoAoe()
local Pyroclasm = Ability.add(269650, false, true, 269651)
Pyroclasm.buff_duration = 15
local SearingTouch = Ability.add(269644, false, true)
------ Procs
local HeatingUp = Ability.add(48107, true, true)
HeatingUp.buff_duration = 10
local HotStreak = Ability.add(195283, true, true, 48108)
HotStreak.buff_duration = 15
---- Frost
local Blizzard = Ability.add(190356, false, true, 190357)
Blizzard.mana_cost = 2.5
Blizzard.cooldown_duration = 8
Blizzard:autoAoe()
local Chilled = Ability.add(205708, false, true)
Chilled.buff_duration = 15
local ConeOfCold = Ability.add(120, false, true)
ConeOfCold.mana_cost = 4
ConeOfCold.buff_duration = 5
ConeOfCold.cooldown_duration = 12
ConeOfCold:autoAoe()
local Flurry = Ability.add(44614, false, true, 228354)
Flurry.mana_cost = 1
Flurry.buff_duration = 1
Flurry:setVelocity(50)
local Freeze = Ability.add(33395, false, true)
Freeze.cooldown_duration = 25
Freeze.buff_duration = 8
Freeze.requires_pet = true
Freeze.triggers_gcd = false
Freeze:autoAoe()
local Frostbolt = Ability.add(116, false, true, 228597)
Frostbolt.mana_cost = 2
Frostbolt:setVelocity(35)
local FrostNova = Ability.add(122, false, true)
FrostNova.mana_cost = 2
FrostNova.buff_duration = 8
FrostNova:autoAoe()
local FrozenOrb = Ability.add(84714, false, true, 84721)
FrozenOrb.mana_cost = 1
FrozenOrb.buff_duration = 15
FrozenOrb.cooldown_duration = 60
FrozenOrb:setVelocity(20)
FrozenOrb:autoAoe()
local IceBarrier = Ability.add(11426, true, true)
IceBarrier.mana_cost = 3
IceBarrier.buff_duration = 60
IceBarrier.cooldown_duration = 25
local IceLance = Ability.add(30455, false, true, 228598)
IceLance.mana_cost = 1
IceLance:setVelocity(47)
local IcyVeins = Ability.add(12472, true, true)
IcyVeins.buff_duration = 20
IcyVeins.cooldown_duration = 180
local SummonWaterElemental = Ability.add(31687, false, true)
SummonWaterElemental.mana_cost = 3
SummonWaterElemental.cooldown_duration = 30
local Waterbolt = Ability.add(31707, false, true)
------ Talents
local BoneChilling = Ability.add(205027, false, true, 205766)
BoneChilling.buff_duration = 8
local ChainReaction = Ability.add(278309, true, true, 278310)
ChainReaction.buff_duration = 10
local CometStorm = Ability.add(153595, false, true, 153596)
CometStorm.mana_cost = 1
CometStorm.cooldown_duration = 30
CometStorm:autoAoe()
local Ebonbolt = Ability.add(257537, false, true, 257538)
Ebonbolt.mana_cost = 2
Ebonbolt.cooldown_duration = 45
Ebonbolt:setVelocity(30)
local FreezingRain = Ability.add(270233, true, true, 270232)
FreezingRain.buff_duration = 12
local FrozenTouch = Ability.add(205030, false, true)
local GlacialSpike = Ability.add(199786, false, true, 228600)
GlacialSpike.mana_cost = 1
GlacialSpike.buff_duration = 4
GlacialSpike:setVelocity(40)
local IceFloes = Ability.add(108839, true, true)
IceFloes.requires_charge = true
IceFloes.buff_duration = 15
IceFloes.cooldown_duration = 20
local IceNova = Ability.add(157997, false, true)
IceNova.buff_duration = 2
IceNova.cooldown_duration = 25
IceNova:autoAoe()
local LonelyWinter = Ability.add(205024, false, true)
local RayOfFrost = Ability.add(205021, false, true)
RayOfFrost.mana_cost = 2
RayOfFrost.buff_duration = 5
RayOfFrost.cooldown_duration = 75
local SplittingIce = Ability.add(56377, false, true)
local ThermalVoid = Ability.add(155149, false, true)
------ Procs
local BrainFreeze = Ability.add(190446, true, true, 190447)
BrainFreeze.buff_duration = 15
local FingersOfFrost = Ability.add(112965, true, true, 44544)
FingersOfFrost.buff_duration = 15
local Icicles = Ability.add(76613, true, true, 205473)
Icicles.buff_duration = 60
local WintersChill = Ability.add(228358, false, true)
WintersChill.buff_duration = 1
-- Azerite Traits
local ArcanePummeling = Ability.add(270669, true, true, 270670)
ArcanePummeling.buff_duration = 3
local BlasterMaster = Ability.add(274596, true, true, 274598)
BlasterMaster.buff_duration = 3
local Preheat = Ability.add(273331, true, true, 273333)
Preheat.buff_duration = 30
local WintersReach = Ability.add(273346, true, true, 273347)
WintersReach.buff_duration = 15
-- Heart of Azeroth
---- Major Essences
local ConcentratedFlame = Ability.add(295373, true, true, 295378)
ConcentratedFlame.buff_duration = 180
ConcentratedFlame.cooldown_duration = 30
ConcentratedFlame.requires_charge = true
ConcentratedFlame.essence_id = 12
ConcentratedFlame.essence_major = true
ConcentratedFlame.dot = Ability.add(295368, false, true)
ConcentratedFlame.dot.buff_duration = 6
ConcentratedFlame.dot.essence_id = 12
ConcentratedFlame.dot.essence_major = true
local GuardianOfAzeroth = Ability.add(295840, false, true)
GuardianOfAzeroth.cooldown_duration = 180
GuardianOfAzeroth.essence_id = 14
GuardianOfAzeroth.essence_major = true
local FocusedAzeriteBeam = Ability.add(295258, false, true)
FocusedAzeriteBeam.cooldown_duration = 90
FocusedAzeriteBeam.essence_id = 5
FocusedAzeriteBeam.essence_major = true
local MemoryOfLucidDreams = Ability.add(298357, true, true)
MemoryOfLucidDreams.buff_duration = 15
MemoryOfLucidDreams.cooldown_duration = 120
MemoryOfLucidDreams.essence_id = 27
MemoryOfLucidDreams.essence_major = true
local PurifyingBlast = Ability.add(295337, false, true, 295338)
PurifyingBlast.cooldown_duration = 60
PurifyingBlast.essence_id = 6
PurifyingBlast.essence_major = true
PurifyingBlast:autoAoe(true)
local RippleInSpace = Ability.add(302731, true, true)
RippleInSpace.buff_duration = 2
RippleInSpace.cooldown_duration = 60
RippleInSpace.essence_id = 15
RippleInSpace.essence_major = true
local TheUnboundForce = Ability.add(298452, false, true)
TheUnboundForce.cooldown_duration = 45
TheUnboundForce.essence_id = 28
TheUnboundForce.essence_major = true
local VisionOfPerfection = Ability.add(299370, true, true, 303345)
VisionOfPerfection.buff_duration = 10
VisionOfPerfection.essence_id = 22
VisionOfPerfection.essence_major = true
local WorldveinResonance = Ability.add(295186, true, true)
WorldveinResonance.cooldown_duration = 60
WorldveinResonance.essence_id = 4
WorldveinResonance.essence_major = true
---- Minor Essences
local AncientFlame = Ability.add(295367, false, true)
AncientFlame.buff_duration = 10
AncientFlame.essence_id = 12
local CondensedLifeForce = Ability.add(295367, false, true)
CondensedLifeForce.essence_id = 14
local FocusedEnergy = Ability.add(295248, true, true)
FocusedEnergy.buff_duration = 4
FocusedEnergy.essence_id = 5
local Lifeblood = Ability.add(295137, true, true)
Lifeblood.essence_id = 4
local LucidDreams = Ability.add(298343, true, true)
LucidDreams.buff_duration = 8
LucidDreams.essence_id = 27
local PurificationProtocol = Ability.add(295305, false, true)
PurificationProtocol.essence_id = 6
PurificationProtocol:autoAoe()
local RealityShift = Ability.add(302952, true, true)
RealityShift.buff_duration = 20
RealityShift.cooldown_duration = 30
RealityShift.essence_id = 15
local RecklessForce = Ability.add(302917, true, true)
RecklessForce.essence_id = 28
local StriveForPerfection = Ability.add(299369, true, true)
StriveForPerfection.essence_id = 22
-- Racials

-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems = {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:equipped()
	return self.equip_slot and true
end

function InventoryItem:usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:equipped() and self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local FlaskOfEndlessFathoms = InventoryItem.add(152693)
FlaskOfEndlessFathoms.buff = Ability.add(251837, true, true)
local BattlePotionOfIntellect = InventoryItem.add(163222)
BattlePotionOfIntellect.buff = Ability.add(279151, true, true)
BattlePotionOfIntellect.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem.add(0)
local Trinket2 = InventoryItem.add(0)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:initialize()
	self.locations = {}
	self.traits = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:update()
	local _, loc, tinfo, tslot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			tinfo = C_AzeriteEmpoweredItem.GetAllTierInfo(loc)
			for _, tslot in next, tinfo do
				if tslot.azeritePowerIDs then
					for _, pid in next, tslot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
end

-- End Azerite Trait API

-- Start Helpful Functions

local function Mana()
	return Player.mana
end

local function ManaPct()
	return Player.mana / Player.mana_max * 100
end

local function ManaRegen()
	return Player.mana_regen
end

local function ManaMax()
	return Player.mana_max
end

local function ManaTimeToMax()
	local deficit = Player.mana_max - Player.mana
	if deficit <= 0 then
		return 0
	end
	return deficit / Player.mana_regen
end

local function ArcaneCharges()
	if ArcaneBlast:casting() then
		return min(4, Player.arcane_charges + 1)
	end
	return Player.arcane_charges
end

local function TimeInCombat()
	if Player.combat_start > 0 then
		return Player.time - Player.combat_start
	end
	return 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

local function InArenaOrBattleground()
	return Player.instance == 'arena' or Player.instance == 'pvp'
end

function Target:frozen()
	return FrostNova:up() or IceNova:up() or Freeze:up() or WintersChill:up() or GlacialSpike:up()
end

-- End Helpful Functions

-- Start Ability Modifications

function Ability:cost()
	if self.mana_cost == 0 then
		return 0
	end
	local cost = self.mana_cost / 100 * Player.mana_base
	if ArcanePower.known and ArcanePower:up() then
		cost = cost - cost * 0.60
	end
	return cost
end

function ArcaneBlast:cost()
	if Ability.up(RuleOfThrees) then
		return 0
	end
	return Ability.cost(self) * (ArcaneCharges() + 1)
end

function ArcaneExplosion:cost()
	if Clearcasting:up() then
		return 0
	end
	return Ability.cost(self)
end

function ArcaneMissiles:cost()
	if RuleOfThrees:up() or Clearcasting:up() then
		return 0
	end
	return Ability.cost(self)
end

function RuleOfThrees:up()
	if ArcaneBlast:casting() then
		return false
	end
	return Ability.up(self)
end

function PresenceOfMind:cooldown()
	if self:up() then
		return self.cooldown_duration
	end
	return Ability.cooldown(self)
end

function Freeze:usable()
	if not Target.stunnable then
		return false
	end
	return Ability.usable(self)
end

function FrostNova:usable()
	if not Target.stunnable then
		return false
	end
	return Ability.usable(self)
end

function FrozenOrb:inFlight()
	if (Player.time - self.last_used) < 10 then
		return true
	end
end

function TimeWarp:usable()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HARMFUL')
		if (
			id == 57724 or -- Sated
			id == 57723 or -- Exhaustion
			id == 80354    -- Temporal Displacement
		) then
			return false
		end
	end
	return Ability.usable(self)
end

function BrainFreeze:up()
	if Ebonbolt:casting() then
		return true
	end
	return Ability.up(self)
end

function GlacialSpike:up()
	if Target.stunnable and self:casting() then
		return true
	end
	return Ability.up(self)
end

function GlacialSpike:usable()
	if Icicles:stack() < 5 or Icicles:remains() < self:castTime() then
		return false
	end
	return Ability.usable(self)
end

function WintersChill:up()
	if Flurry:traveling() then
		return true
	end
	return Ability.up(self)
end

function Icicles:stack()
	if GlacialSpike:casting() then
		return 0
	end
	local count = Ability.stack(self)
	if Frostbolt:casting() or Flurry:casting() then
		count = count + 1
	end
	return min(5, count)
end

function RuneOfPower:remains()
	if self:casting() then
		return self.buff_duration
	end
	return max((self.last_used or 0) + self.buff_duration - Player.time - Player.execute_remains, 0)
end

function Firestarter:remains()
	if not Firestarter.known or Target.healthPercentage <= 90 then
		return 0
	end
	if Target.healthLostPerSec <= 0 then
		return 600
	end
	local health_above_90 = (Target.health - (Target.healthLostPerSec * Player.execute_remains)) - (Target.healthMax * 0.9)
	return health_above_90 / Target.healthLostPerSec
end

function SearingTouch:up()
	return SearingTouch.known and Target.healthPercentage < 30
end

function HeatingUp:remains()
	if Scorch:casting() and SearingTouch:up() then
		if Ability.up(self) then
			return 0
		end
		if Ability.up(HotStreak) then
			return 0
		end
		return self.buff_duration
	end
	return Ability.remains(self)
end

function HotStreak:remains()
	if Scorch:casting() and SearingTouch:up() and Ability.up(HeatingUp) and not Ability.up(HotStreak) then
		return self.buff_duration
	end
	return Ability.remains(self)
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

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.ARCANE] = {},
	[SPEC.FIRE] = {},
	[SPEC.FROST] = {}
}

APL[SPEC.ARCANE].main = function(self)
--[[
# Executed before combat begins. Accepts non-harmful actions only.
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/arcane_intellect
actions.precombat+=/summon_arcane_familiar
# conserve_mana is the mana percentage we want to go down to during conserve. It needs to leave enough room to worst case scenario spam AB only during AP.
actions.precombat+=/variable,name=conserve_mana,op=set,value=60
actions.precombat+=/snapshot_stats
actions.precombat+=/mirror_image
actions.precombat+=/potion
actions.precombat+=/arcane_blast
]]
	if TimeInCombat() == 0 then
		if ArcaneIntellect:usable() and ArcaneIntellect:remains() < 300 then
			return ArcaneIntellect
		end
		if ArcaneFamiliar:usable() and ArcaneFamiliar:remains() < 300 then
			return ArcaneFamiliar
		end
		if MirrorImage:usable() then
			UseCooldown(MirrorImage)
		end
		if not InArenaOrBattleground() then
			if Opt.pot and BattlePotionOfIntellect:usable() then
				UseCooldown(BattlePotionOfIntellect)
			end
		end
		if ArcaneBlast:usable() and not ArcaneBlast:casting() then
			return ArcaneBlast
		end
	else
		if ArcaneIntellect:down() and ArcaneIntellect:usable() then
			UseExtra(ArcaneIntellect)
		elseif ArcaneFamiliar:usable() and ArcaneFamiliar:down() then
			UseExtra(ArcaneFamiliar)
		end
	end
--[[
# Go to Burn Phase when already burning, or when boss will die soon.
actions+=/call_action_list,name=burn,if=burn_phase|target.time_to_die<variable.average_burn_length
# Start Burn Phase when Arcane Power is ready and Evocation will be ready (on average) before the burn phase is over. Also make sure we got 4 Arcane Charges, or can get 4 Arcane Charges with Charged Up.
actions+=/call_action_list,name=burn,if=(cooldown.arcane_power.remains=0&cooldown.evocation.remains<=variable.average_burn_length&(buff.arcane_charge.stack=buff.arcane_charge.max_stack|(talent.charged_up.enabled&cooldown.charged_up.remains=0&buff.arcane_charge.stack<=1)))
actions+=/call_action_list,name=conserve,if=!burn_phase
actions+=/call_action_list,name=movement
]]
	local apl
	if Player.burn_phase or (Target.boss and Target.timeToDie < Player.average_burn_length) then
		apl = self:burn()
		if apl then return apl end
	end
	if ArcanePower:ready() and Evocation:ready(max(Player.average_burn_length, 20)) and (ArcaneCharges() == 4 or (ChargedUp.known and ChargedUp:ready() and ArcaneCharges() <= 1)) then
		apl = self:burn()
		if apl then return apl end
	end
	if not Player.burn_phase then
		if (Evocation:usable() and ManaPct() < 25) or (Evocation:channeling() and ManaPct() < 85) then
			return Evocation
		end
		apl = self:conserve()
		if apl then return apl end
	end
	return self:movement()
end

APL[SPEC.ARCANE].toggle_burn_phase = function(self, on)
	if on and not Player.burn_phase then
		Player.burn_phase = Player.time
		Player.burn_phase_duration = 0
		Player.total_burns = Player.total_burns + 1
	elseif not on and Player.burn_phase then
		Player.burn_phase = false
		Player.average_burn_length = (Player.average_burn_length * (Player.total_burns - 1) + Player.burn_phase_duration) / Player.total_burns
	end
end

APL[SPEC.ARCANE].burn = function(self)
--[[
# Increment our burn phase counter. Whenever we enter the `burn` actions without being in a burn phase, it means that we are about to start one.
actions.burn=variable,name=total_burns,op=add,value=1,if=!burn_phase
actions.burn+=/start_burn_phase,if=!burn_phase
# End the burn phase when we just evocated.
actions.burn+=/stop_burn_phase,if=burn_phase&prev_gcd.1.evocation&target.time_to_die>variable.average_burn_length&burn_phase_duration>0
# Less than 1 instead of equals to 0, because of pre-cast Arcane Blast
actions.burn+=/charged_up,if=buff.arcane_charge.stack<=1
actions.burn+=/mirror_image
actions.burn+=/nether_tempest,if=(refreshable|!ticking)&buff.arcane_charge.stack=buff.arcane_charge.max_stack&buff.rune_of_power.down&buff.arcane_power.down
# When running Overpowered, and we got a Rule of Threes proc (AKA we got our 4th Arcane Charge via Charged Up), use it before using RoP+AP, because the mana reduction is otherwise largely wasted since the AB was free anyway.
actions.burn+=/arcane_blast,if=buff.rule_of_threes.up&talent.overpowered.enabled&active_enemies<3
actions.burn+=/lights_judgment,if=buff.arcane_power.down
actions.burn+=/rune_of_power,if=!buff.arcane_power.up&(mana.pct>=50|cooldown.arcane_power.remains=0)&(buff.arcane_charge.stack=buff.arcane_charge.max_stack)
actions.burn+=/berserking
actions.burn+=/arcane_power,if=buff.rune_of_power.up
actions.burn+=/use_items,if=buff.arcane_power.up|target.time_to_die<cooldown.arcane_power.remains
actions.burn+=/blood_fury
actions.burn+=/fireblood
actions.burn+=/ancestral_call
actions.burn+=/presence_of_mind,if=buff.rune_of_power.remains<=buff.presence_of_mind.max_stack*action.arcane_blast.execute_time|buff.arcane_power.remains<=buff.presence_of_mind.max_stack*action.arcane_blast.execute_time
actions.burn+=/potion,if=buff.arcane_power.up&(buff.berserking.up|buff.blood_fury.up|!(race.troll|race.orc))
actions.burn+=/arcane_orb,if=buff.arcane_charge.stack=0|(active_enemies<3|(active_enemies<2&talent.resonance.enabled))
actions.burn+=/arcane_blast,if=active_enemies>=3&active_enemies<6&buff.rule_of_threes.up&buff.arcane_charge.stack>3
actions.burn+=/arcane_barrage,if=active_enemies>=3&(buff.arcane_charge.stack=buff.arcane_charge.max_stack)
actions.burn+=/arcane_explosion,if=active_enemies>=3
# Ignore Arcane Missiles during Arcane Power, aside from some very specific exceptions, like not having Overpowered talented & running 3x Arcane Pummeling.
actions.burn+=/arcane_missiles,if=buff.clearcasting.react&active_enemies<3&(talent.amplification.enabled|(!talent.overpowered.enabled&azerite.arcane_pummeling.rank>=2)|buff.arcane_power.down),chain=1
actions.burn+=/arcane_blast,if=active_enemies<3
# Now that we're done burning, we can update the average_burn_length with the length of this burn.
actions.burn+=/variable,name=average_burn_length,op=set,value=(variable.average_burn_length*variable.total_burns-variable.average_burn_length+(burn_phase_duration))%variable.total_burns
actions.burn+=/evocation,interrupt_if=mana.pct>=85,interrupt_immediate=1
# For the rare occasion where we go oom before evocation is back up. (Usually because we get very bad rng so the burn is cut very short)
actions.burn+=/arcane_barrage
]]
	if Player.burn_phase then
		Player.burn_phase_duration = Player.time - Player.burn_phase
		if Evocation:previous() and Target.timeToDie > Player.average_burn_length and Player.burn_phase_duration > 0 then
			self:toggle_burn_phase(false)
			return
		end
	else
		self:toggle_burn_phase(true)
	end
	if ChargedUp:usable() and ArcaneCharges() <= 1 then
		UseCooldown(ChargedUp)
	end
	if MirrorImage:usable() then
		UseCooldown(MirrorImage)
	end
	if NetherTempest:usable() and NetherTempest:refreshable() and ArcaneCharges() == 4 and not (RuneOfPower:up() and ArcanePower:up()) then
		return NetherTempest
	end
	if RuleOfThrees.known and Overpowered.known and Player.enemies < 3 and ArcaneBlast:usable() and RuleOfThrees:up() then
		return ArcaneBlast
	end
	if RuneOfPower:usable() and RuneOfPower:down() and ArcanePower:down() and (ManaPct() >= 50 or ArcanePower:ready()) and ArcaneCharges() == 4 then
		UseCooldown(RuneOfPower)
	end
	if ArcanePower:usable() and RuneOfPower:remains() > 6 then
		UseCooldown(ArcanePower)
	end
	if Opt.trinket and (ArcanePower:up() or (Target.boss and Target.timeToDie < 15)) then
		if Trinket1:usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:usable() then
			UseCooldown(Trinket2)
		end
	end
	if PresenceOfMind:usable() and ((RuneOfPower:up() and RuneOfPower:remains() <= (2 * ArcaneBlast:castTime())) or (ArcanePower:up() and ArcanePower:remains() <= (2 * ArcaneBlast:castTime()))) then
		UseCooldown(PresenceOfMind)
	end
	if Opt.pot and BattlePotionOfIntellect:usable() and ArcanePower:up() then
		UseExtra(BattlePotionOfIntellect)
	end
	if ArcaneOrb:usable() and (ArcaneCharges() == 0 or Player.enemies < (Resonance.known and 2 or 3)) then
		UseCooldown(ArcaneOrb)
	end
	if Player.enemies >= 3 then
		if RuleOfThrees.known and Player.enemies < 6 and ArcaneBlast:usable() and ArcaneCharges() > 3 and RuleOfThrees:up() then
			return ArcaneBlast
		end
		if ArcaneBarrage:usable() and ArcaneCharges() == 4 then
			return ArcaneBarrage
		end
		if ArcaneExplosion:usable() then
			return ArcaneExplosion
		end
	else
		if ArcaneMissiles:usable() and Clearcasting:up() and (Amplification.known or (not Overpowered.known and ArcanePummeling:azeriteRank() >= 2) or ArcanePower:down()) then
			return ArcaneMissiles
		end
		if ArcaneBlast:usable() then
			return ArcaneBlast
		end
	end
	self:toggle_burn_phase(false)
	if Evocation:usable() then
		return Evocation
	end
	if ArcaneBarrage:usable() then
		return ArcaneBarrage
	end
end

APL[SPEC.ARCANE].conserve = function(self)
--[[
actions.conserve=mirror_image
actions.conserve+=/charged_up,if=buff.arcane_charge.stack=0
actions.conserve+=/nether_tempest,if=(refreshable|!ticking)&buff.arcane_charge.stack=buff.arcane_charge.max_stack&buff.rune_of_power.down&buff.arcane_power.down
actions.conserve+=/arcane_orb,if=buff.arcane_charge.stack<=2&(cooldown.arcane_power.remains>10|active_enemies<=2)
# Arcane Blast shifts up in priority when running rule of threes.
actions.conserve+=/arcane_blast,if=buff.rule_of_threes.up&buff.arcane_charge.stack>3
actions.conserve+=/rune_of_power,if=buff.arcane_charge.stack=buff.arcane_charge.max_stack&(full_recharge_time<=execute_time|full_recharge_time<=cooldown.arcane_power.remains|target.time_to_die<=cooldown.arcane_power.remains)
actions.conserve+=/arcane_missiles,if=mana.pct<=95&buff.clearcasting.react&active_enemies<3,chain=1
# During conserve, we still just want to continue not dropping charges as long as possible.So keep 'burning' as long as possible (aka conserve_mana threshhold) and then swap to a 4x AB->Abarr conserve rotation. If we do not have 4 AC, we can dip slightly lower to get a 4th AC. We also sustain at a higher mana percentage when we plan to use a Rune of Power during conserve phase, so we can burn during the Rune of Power.
actions.conserve+=/arcane_barrage,if=((buff.rune_of_power.remains<action.arcane_blast.execute_time&buff.arcane_charge.stack=buff.arcane_charge.max_stack)&((mana.pct<=variable.conserve_mana)|(cooldown.arcane_power.remains>cooldown.rune_of_power.full_recharge_time&mana.pct<=variable.conserve_mana+25))|(talent.arcane_orb.enabled&cooldown.arcane_orb.remains<=gcd&cooldown.arcane_power.remains>10))|mana.pct<=(variable.conserve_mana-10)
# Supernova is barely worth casting, which is why it is so far down, only just above AB. 
actions.conserve+=/supernova,if=mana.pct<=95
actions.conserve+=/arcane_barrage,if=active_enemies>=3&buff.arcane_charge.stack=buff.arcane_charge.max_stack
# Keep 'burning' in aoe situations until conserve_mana pct. After that only cast AE with 3 Arcane charges, since it's almost equal mana cost to a 3 stack AB anyway. At that point AoE rotation will be AB x3->AE->Abarr
actions.conserve+=/arcane_explosion,if=active_enemies>=3&(mana.pct>=variable.conserve_mana|buff.arcane_charge.stack=3)
actions.conserve+=/arcane_blast
actions.conserve+=/arcane_barrage
]]
	if MirrorImage:usable() then
		UseCooldown(MirrorImage)
	end
	if ChargedUp:usable() and ArcaneCharges() == 0 then
		UseCooldown(ChargedUp)
	end
	if NetherTempest:usable() and NetherTempest:refreshable() and ArcaneCharges() == 4 and not (RuneOfPower:up() and ArcanePower:up()) then
		return NetherTempest
	end
	if ArcaneOrb:usable() and ArcaneCharges() <= 2 and (ArcanePower:cooldown() > 10 or Player.enemies <= 2) then
		UseCooldown(ArcaneOrb)
	end
	if RuleOfThrees.known and ArcaneBlast:usable() and ArcaneCharges() > 3 and RuleOfThrees:up() then
		return ArcaneBlast
	end
	if RuneOfPower:usable() and RuneOfPower:down() and ArcaneCharges() == 4 and (RuneOfPower:fullRechargeTime() <= RuneOfPower:castTime() or RuneOfPower:fullRechargeTime() <= ArcanePower:cooldown() or Target.timeToDie <= ArcanePower:cooldown()) then
		UseCooldown(RuneOfPower)
	end
	if ArcaneMissiles:usable() and ManaPct() <= 95 and Clearcasting:up() and Player.enemies < 3 then
		return ArcaneMissiles
	end
	if ArcaneBarrage:usable() and (ManaPct() <= (Opt.conserve_mana - 10) or (ArcaneCharges() == 4 and RuneOfPower:remains() < ArcaneBlast:castTime() and (ManaPct() <= Opt.conserve_mana or (ArcanePower:cooldown() > RuneOfPower:fullRechargeTime() and ManaPct() <= Opt.conserve_mana + 25))) or (ArcaneOrb.known and ArcaneOrb:ready(Player.gcd) and not ArcanePower:ready(10))) then
		return ArcaneBarrage
	end
	if Supernova:usable() and ManaPct() <= 95 then
		UseCooldown(Supernova)
	end
	if ArcaneBarrage:usable() and Player.enemies >= 3 and ArcaneCharges() == 4 then
		return ArcaneBarrage
	end
	if ArcaneExplosion:usable() and Player.enemies >= 3 and (ManaPct() >= Opt.conserve_mana or ArcaneCharges() == 3) then
		return ArcaneExplosion
	end
	if ArcaneBlast:usable() then
		return ArcaneBlast
	end
	if ArcaneBarrage:usable() then
		return ArcaneBarrage
	end
end

APL[SPEC.ARCANE].movement = function(self)
--[[
actions.movement=shimmer,if=movement.distance>=10
actions.movement+=/blink,if=movement.distance>=10
actions.movement+=/presence_of_mind
actions.movement+=/arcane_missiles
actions.movement+=/arcane_orb
actions.movement+=/supernova
]]
	if Blink:usable() then
		UseExtra(Blink)
	elseif Shimmer:usable() then
		UseExtra(Shimmer)
	end
	if PresenceOfMind:usable() then
		UseCooldown(PresenceOfMind)
	end
	if Slipstream.known and ArcaneMissiles:usable() and Clearcasting:up() then
		return ArcaneMissiles
	end
	if ArcaneOrb:usable() then
		UseCooldown(ArcaneOrb)
	end
	if Supernova:usable() then
		UseCooldown(Supernova)
	end
end

APL[SPEC.FIRE].main = function(self)
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/arcane_intellect
# This variable sets the time at which Rune of Power should start being saved for the next Combustion phase
actions.precombat+=/variable,name=combustion_rop_cutoff,op=set,value=60
actions.precombat+=/variable,name=combustion_on_use,op=set,value=equipped.notorious_aspirants_badge|equipped.notorious_gladiators_badge|equipped.sinister_gladiators_badge|equipped.sinister_aspirants_badge|equipped.dread_gladiators_badge|equipped.dread_aspirants_badge|equipped.dread_combatants_insignia|equipped.notorious_aspirants_medallion|equipped.notorious_gladiators_medallion|equipped.sinister_gladiators_medallion|equipped.sinister_aspirants_medallion|equipped.dread_gladiators_medallion|equipped.dread_aspirants_medallion|equipped.dread_combatants_medallion|equipped.ignition_mages_fuse|equipped.tzanes_barkspines|equipped.azurethos_singed_plumage|equipped.ancient_knot_of_wisdom|equipped.shockbiters_fang|equipped.neural_synapse_enhancer|equipped.balefire_branch
actions.precombat+=/variable,name=font_double_on_use,op=set,value=equipped.azsharas_font_of_power&variable.combustion_on_use
# Items that are used outside of Combustion are not used after this time if they would put a trinket used with Combustion on a sharded cooldown.
actions.precombat+=/variable,name=on_use_cutoff,op=set,value=20*variable.combustion_on_use&!variable.font_double_on_use+40*variable.font_double_on_use+25*equipped.azsharas_font_of_power&!variable.font_double_on_use
actions.precombat+=/snapshot_stats
actions.precombat+=/use_item,name=azsharas_font_of_power
actions.precombat+=/mirror_image
actions.precombat+=/potion
actions.precombat+=/pyroblast
]]
	if TimeInCombat() == 0 then
		Player.combustion_rop_cutoff = 60
		if ArcaneIntellect:usable() and ArcaneIntellect:remains() < 300 then
			return ArcaneIntellect
		end
		if MirrorImage:usable() then
			UseCooldown(MirrorImage)
		end
		if not InArenaOrBattleground() then
			if Opt.pot and BattlePotionOfIntellect:usable() then
				UseCooldown(BattlePotionOfIntellect)
			end
		end
		if Pyroblast:usable() and not (Pyroblast:casting() or Fireball:casting()) then
			return Pyroblast
		end
	else
		if ArcaneIntellect:down() and ArcaneIntellect:usable() then
			UseExtra(ArcaneIntellect)
		end
	end
--[[
actions=counterspell
actions+=/call_action_list,name=items_high_priority
actions+=/mirror_image,if=buff.combustion.down
actions+=/guardian_of_azeroth,if=cooldown.combustion.remains<10|target.time_to_die<cooldown.combustion.remains
actions+=/concentrated_flame
actions+=/focused_azerite_beam
actions+=/purifying_blast
actions+=/ripple_in_space
actions+=/the_unbound_force
actions+=/worldvein_resonance
actions+=/rune_of_power,if=talent.firestarter.enabled&firestarter.remains>full_recharge_time|cooldown.combustion.remains>variable.combustion_rop_cutoff&buff.combustion.down|target.time_to_die<cooldown.combustion.remains&buff.combustion.down
actions+=/call_action_list,name=combustion_phase,if=(talent.rune_of_power.enabled&cooldown.combustion.remains<=action.rune_of_power.cast_time|cooldown.combustion.ready)&!firestarter.active|buff.combustion.up
actions+=/fire_blast,use_while_casting=1,use_off_gcd=1,if=(essence.memory_of_lucid_dreams.major|essence.memory_of_lucid_dreams.minor&azerite.blaster_master.enabled)&charges=max_charges&!buff.hot_streak.react&!(buff.heating_up.react&(buff.combustion.up&(action.fireball.in_flight|action.pyroblast.in_flight|action.scorch.executing)|target.health.pct<=30&action.scorch.executing))&!(!buff.heating_up.react&!buff.hot_streak.react&buff.combustion.down&(action.fireball.in_flight|action.pyroblast.in_flight))
actions+=/call_action_list,name=rop_phase,if=buff.rune_of_power.up&buff.combustion.down
actions+=/variable,name=fire_blast_pooling,value=talent.rune_of_power.enabled&cooldown.rune_of_power.remains<cooldown.fire_blast.full_recharge_time&(cooldown.combustion.remains>variable.combustion_rop_cutoff|firestarter.active)&(cooldown.rune_of_power.remains<target.time_to_die|action.rune_of_power.charges>0)|cooldown.combustion.remains<action.fire_blast.full_recharge_time+cooldown.fire_blast.duration*azerite.blaster_master.enabled&!firestarter.active&cooldown.combustion.remains<target.time_to_die|talent.firestarter.enabled&firestarter.active&firestarter.remains<cooldown.fire_blast.full_recharge_time+cooldown.fire_blast.duration*azerite.blaster_master.enabled
actions+=/variable,name=phoenix_pooling,value=talent.rune_of_power.enabled&cooldown.rune_of_power.remains<cooldown.phoenix_flames.full_recharge_time&cooldown.combustion.remains>variable.combustion_rop_cutoff&(cooldown.rune_of_power.remains<target.time_to_die|action.rune_of_power.charges>0)|cooldown.combustion.remains<action.phoenix_flames.full_recharge_time&cooldown.combustion.remains<target.time_to_die
actions+=/call_action_list,name=standard_rotation
]]
	if MirrorImage:usable() and Combustion:down() then
		UseCooldown(MirrorImage)
	end
	if GuardianOfAzeroth:usable() and (Combustion:cooldown() < 10 or Target.timeToDie < Combustion:cooldown()) then
		UseCooldown(GuardianOfAzeroth)
	elseif ConcentratedFlame:usable() and ConcentratedFlame.dot:down() and not ConcentratedFlame:previous() then
		UseCooldown(ConcentratedFlame)
	elseif FocusedAzeriteBeam:usable() and not Player.moving then
		UseCooldown(FocusedAzeriteBeam)
	elseif PurifyingBlast:usable() then
		UseCooldown(PurifyingBlast)
	elseif RippleInSpace:usable() then
		UseCooldown(RippleInSpace)
	elseif TheUnboundForce:usable() then
		UseCooldown(TheUnboundForce)
	elseif WorldveinResonance:usable() and Lifeblood:stack() < 3 then
		UseCooldown(WorldveinResonance)
	end
	if RuneOfPower:usable() and ((Firestarter.known and Firestarter:remains() > RuneOfPower:fullRechargeTime()) or (Combustion:down() and (Combustion:cooldown() > Player.combustion_rop_cutoff or Target.timeToDie < Combustion:cooldown()))) then
		UseCooldown(RuneOfPower)
	end
	local apl
	if (RuneOfPower.known and Combustion:cooldown() < RuneOfPower:castTime() or Combustion:ready()) and Firestarter:down() or Combustion:up() then
		apl = self:combustion_phase()
		if apl then return apl end
	end
	if FireBlast:usable() and (MemoryOfLucidDreams.known or LucidDreams.known and BlasterMaster.known) and FireBlast:charges() == FireBlast:maxCharges() and HotStreak:down() and (HeatingUp:up() and (Combustion:up() and (Fireball:traveling() or Pyroblast:traveling() or Scorch:casting()) or Target.healthPct <= 30 and Scorch:casting())) and not (HeatingUp:down() and HotStreak:down() and Combustion:down() and (Fireball:traveling() or Pyroblast:traveling())) then
		UseExtra(FireBlast)
	end
	if RuneOfPower.known and RuneOfPower:up() and Combustion:down() then
		apl = self:rop_phase()
		if apl then return apl end
	end
	return self:standard_rotation()
end

APL[SPEC.FIRE].active_talents = function(self)
--[[
actions.active_talents=living_bomb,if=active_enemies>1&buff.combustion.down&(cooldown.combustion.remains>cooldown.living_bomb.duration|cooldown.combustion.ready)
actions.active_talents+=/meteor,if=buff.rune_of_power.up&(firestarter.remains>cooldown.meteor.duration|!firestarter.active)|cooldown.rune_of_power.remains>target.time_to_die&action.rune_of_power.charges<1|(cooldown.meteor.duration<cooldown.combustion.remains|cooldown.combustion.ready)&!talent.rune_of_power.enabled&(cooldown.meteor.duration<firestarter.remains|!talent.firestarter.enabled|!firestarter.active)
]]
	if LivingBomb:usable() and Player.enemies > 1 and Combustion:down() and (Combustion:cooldown() > LivingBomb:cooldownDuration() or Combustion:ready()) then
		return LivingBomb
	end
	if Meteor:usable() then
		if RuneOfPower.known then
			if (RuneOfPower:up() and (Firestarter:remains() > Meteor:cooldownDuration() or Firestarter:down())) or (RuneOfPower:cooldown() > Target.timeToDie and RuneOfPower:charges() < 1) then
				UseCooldown(Meteor)
			end
		else
			if (Meteor:cooldownDuration() < Combustion:cooldown() or Combustion:ready()) and (Meteor:cooldownDuration() < Firestarter:remains() or not Firestarter.known or not Firestarter:up()) then
				UseCooldown(Meteor)
			end
		end
	end
end

APL[SPEC.FIRE].combustion_phase = function(self)
--[[
# Combustion phase prepares abilities with a delay, then launches into the Combustion sequence
actions.combustion_phase=lights_judgment,if=buff.combustion.down
actions.combustion_phase+=/blood_of_the_enemy
actions.combustion_phase+=/memory_of_lucid_dreams
# During Combustion, Fire Blasts are used to generate Hot Streaks and minimize the amount of time spent executing other spells. For standard Fire, Fire Blasts are only used when Heating Up is active or when a Scorch cast is in progress and Heating Up and Hot Streak are not active. With Blaster Master and Flame On, Fire Blasts can additionally be used while Hot Streak and Heating Up are not active and a Pyroblast is in the air and also while casting Scorch even if Heating Up is already active. The latter allows two Hot Streak Pyroblasts to be cast in succession after the Scorch. Additionally with Blaster Master and Flame On, Fire Blasts should not be used unless Blaster Master is about to expire or there are more than enough Fire Blasts to extend Blaster Master to the end of Combustion.
actions.combustion_phase+=/fire_blast,use_while_casting=1,use_off_gcd=1,if=charges>=1&((action.fire_blast.charges_fractional+(buff.combustion.remains-buff.blaster_master.duration)%cooldown.fire_blast.duration-(buff.combustion.remains)%(buff.blaster_master.duration-0.5))>=0|!azerite.blaster_master.enabled|!talent.flame_on.enabled|buff.combustion.remains<=buff.blaster_master.duration|buff.blaster_master.remains<0.5|equipped.hyperthread_wristwraps&cooldown.hyperthread_wristwraps_300142.remains<5)&buff.combustion.up&(!action.scorch.executing&!action.pyroblast.in_flight&buff.heating_up.up|action.scorch.executing&buff.hot_streak.down&(buff.heating_up.down|azerite.blaster_master.enabled)|azerite.blaster_master.enabled&talent.flame_on.enabled&action.pyroblast.in_flight&buff.heating_up.down&buff.hot_streak.down)
actions.combustion_phase+=/rune_of_power,if=buff.combustion.down
# With Blaster Master, a Fire Blast should be used while casting Rune of Power.
actions.combustion_phase+=/fire_blast,use_while_casting=1,if=azerite.blaster_master.enabled&talent.flame_on.enabled&buff.blaster_master.down&(talent.rune_of_power.enabled&action.rune_of_power.executing&action.rune_of_power.execute_remains<0.6|(cooldown.combustion.ready|buff.combustion.up)&!talent.rune_of_power.enabled&!action.pyroblast.in_flight&!action.fireball.in_flight)
actions.combustion_phase+=/call_action_list,name=active_talents
actions.combustion_phase+=/combustion,use_off_gcd=1,use_while_casting=1,if=((action.meteor.in_flight&action.meteor.in_flight_remains<=0.5)|!talent.meteor.enabled)&(buff.rune_of_power.up|!talent.rune_of_power.enabled)
actions.combustion_phase+=/potion
actions.combustion_phase+=/blood_fury
actions.combustion_phase+=/berserking
actions.combustion_phase+=/fireblood
actions.combustion_phase+=/ancestral_call
actions.combustion_phase+=/flamestrike,if=((talent.flame_patch.enabled&active_enemies>2)|active_enemies>6)&buff.hot_streak.react&!azerite.blaster_master.enabled
actions.combustion_phase+=/pyroblast,if=buff.pyroclasm.react&buff.combustion.remains>cast_time
actions.combustion_phase+=/pyroblast,if=buff.hot_streak.react
actions.combustion_phase+=/pyroblast,if=prev_gcd.1.scorch&buff.heating_up.up
actions.combustion_phase+=/phoenix_flames
actions.combustion_phase+=/scorch,if=buff.combustion.remains>cast_time&buff.combustion.up|buff.combustion.down
actions.combustion_phase+=/living_bomb,if=buff.combustion.remains<gcd.max&active_enemies>1
actions.combustion_phase+=/dragons_breath,if=buff.combustion.remains<gcd.max&buff.combustion.up
actions.combustion_phase+=/scorch,if=target.health.pct<=30&talent.searing_touch.enabled
]]
	if MemoryOfLucidDreams:usable() then
		UseCooldown(MemoryOfLucidDreams)
	end
	if FireBlast:usable() and Combustion:up() and ((FireBlast:chargesFractional() + (Combustion:remains() - BlasterMaster:duration()) / FireBlast:cooldownDuration() - (Combustion:remains() / (BlasterMaster:duration() - 0.5)) >= 0) or not BlasterMaster.known or not FlameOn.known or Combustion:remains() <= BlasterMaster:duration() or BlasterMaster:remains() < 0.5) and ((not Scorch:casting() and not Pyroblast:traveling() and HeatingUp:up()) or (Scorch:casting() and HotStreak:down() and (HeatingUp:down() or BlasterMaster.known and FlameOn.known and Pyroblast:traveling() and HeatingUp:down() and HotStreak:down()))) then
		UseExtra(FireBlast)
	end 
	if RuneOfPower:usable() and Combustion:down() then
		UseCooldown(RuneOfPower)
	end
	if FireBlast:usable() and BlasterMaster.known and FlameOn.known and BlasterMaster:down() then
		if RuneOfPower.known then
			if RuneOfPower:casting() and Player.execute_remains < 0.6 then
				UseExtra(FireBlast)
			end
		elseif (Combustion:ready() or Combustion:up()) and not (Pyroblast:traveling() or Fireball:traveling()) then
			UseExtra(FireBlast)
		end
	end
	local apl = self:active_talents()
	if apl then return apl end
	if Combustion:usable() and (not Meteor.known or Meteor:cooldown() > 43) and (not RuneOfPower.known or RuneOfPower:up()) then
		UseCooldown(Combustion)
	end
	if Opt.pot and Target.boss and BattlePotionOfIntellect:usable() then
		UseCooldown(BattlePotionOfIntellect)
	end
	if Opt.trinket then
		if Trinket1:usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:usable() then
			UseCooldown(Trinket2)
		end
	end
	if Flamestrike:usable() and not BlasterMaster.known and HotStreak:up() and Player.enemies > (FlamePatch.known and 2 or 6) then
		return Flamestrike
	end
	if Pyroblast:usable() then
		if Pyroclasm.known and Pyroclasm:up() and Combustion:remains() > Pyroblast:castTime() then
			return Pyroblast
		end
		if HotStreak:up() then
			return Pyroblast
		end
		if Scorch:casting() and HeatingUp:up() and Combustion:up() then
			return Pyroblast
		end
	end
	if PhoenixFlames:usable() then
		return PhoenixFlames
	end
	if Scorch:usable() and (Combustion:down() or Combustion:remains() > Scorch:castTime()) then
		return Scorch
	end
	if Combustion:remains() < Player.gcd then
		if Player.enemies > 1 and LivingBomb:usable() then
			return LivingBomb
		end
		if DragonsBreath:usable() then
			UseExtra(DragonsBreath)
		end
	end
	if Scorch:usable() and SearingTouch:up() then
		return Scorch
	end
end

APL[SPEC.FIRE].rop_phase = function(self)
--[[
actions.rop_phase=rune_of_power
actions.rop_phase+=/flamestrike,if=((talent.flame_patch.enabled&active_enemies>1)|active_enemies>4)&buff.hot_streak.react
actions.rop_phase+=/pyroblast,if=buff.hot_streak.react
actions.rop_phase+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=(cooldown.combustion.remains>0|firestarter.active&buff.rune_of_power.up)&(!buff.heating_up.react&!buff.hot_streak.react&!prev_off_gcd.fire_blast&(action.fire_blast.charges>=2|(action.phoenix_flames.charges>=1&talent.phoenix_flames.enabled)|(talent.alexstraszas_fury.enabled&cooldown.dragons_breath.ready)|(talent.searing_touch.enabled&target.health.pct<=30)|(talent.firestarter.enabled&firestarter.active)))
actions.rop_phase+=/call_action_list,name=active_talents
actions.rop_phase+=/pyroblast,if=buff.pyroclasm.react&cast_time<buff.pyroclasm.remains&buff.rune_of_power.remains>cast_time
actions.rop_phase+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=(cooldown.combustion.remains>0|firestarter.active&buff.rune_of_power.up)&(buff.heating_up.react&(target.health.pct>=30|!talent.searing_touch.enabled))
actions.rop_phase+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=(cooldown.combustion.remains>0|firestarter.active&buff.rune_of_power.up)&talent.searing_touch.enabled&target.health.pct<=30&(buff.heating_up.react&!action.scorch.executing|!buff.heating_up.react&!buff.hot_streak.react)
actions.rop_phase+=/pyroblast,if=prev_gcd.1.scorch&buff.heating_up.up&talent.searing_touch.enabled&target.health.pct<=30&(!talent.flame_patch.enabled|active_enemies=1)
actions.rop_phase+=/phoenix_flames,if=!prev_gcd.1.phoenix_flames&buff.heating_up.react
actions.rop_phase+=/scorch,if=target.health.pct<=30&talent.searing_touch.enabled
actions.rop_phase+=/dragons_breath,if=active_enemies>2
actions.rop_phase+=/flamestrike,if=(talent.flame_patch.enabled&active_enemies>2)|active_enemies>5
actions.rop_phase+=/fireball
]]
	if RuneOfPower:down() then
		if RuneOfPower:usable() then
			UseCooldown(RuneOfPower)
		end
		return
	end
	if Flamestrike:usable() and HotStreak:up() and Player.enemies > (FlamePatch.known and 1 or 4) then
		return Flamestrike
	end
	if Pyroblast:usable() and HotStreak:up() then
		return Pyroblast
	end
	if FireBlast:usable() and HeatingUp:down() and HotStreak:down() and not FireBlast:previous() and (FireBlast:charges() >= 2 or (PhoenixFlames.known and PhoenixFlames:charges() >= 1) or (AlexstraszasFury.known and DragonsBreath:ready()) or SearingTouch:up() or Firestarter:up()) then
		UseExtra(FireBlast)
	end
	local apl = self:active_talents()
	if apl then return apl end
	if Pyroclasm.known and Pyroblast:usable() and Pyroclasm:up() and min(Pyroclasm:remains(), RuneOfPower:remains()) > Pyroblast:castTime() then
		return Pyroblast
	end
	if HeatingUp:up() then
		if FireBlast:usable() and not FireBlast:previous() then
			UseExtra(FireBlast)
		elseif PhoenixFlames:usable() and not PhoenixFlames:previous() then
			return PhoenixFlames
		end
	end
	if Scorch:usable() and SearingTouch:up() then
		return Scorch
	end
	if Player.enemies > 2 and DragonsBreath:usable() then
		UseExtra(DragonsBreath)
	end
	if Flamestrike:usable() and HotStreak:up() and Player.enemies > (FlamePatch.known and 2 or 5) then
		return Flamestrike
	end
	if Fireball:usable() then
		return Fireball
	end
end

APL[SPEC.FIRE].standard_rotation = function(self)
--[[
actions.standard_rotation=flamestrike,if=((talent.flame_patch.enabled&active_enemies>1&!firestarter.active)|active_enemies>4)&buff.hot_streak.react
actions.standard_rotation+=/pyroblast,if=buff.hot_streak.react&buff.hot_streak.remains<action.fireball.execute_time
actions.standard_rotation+=/pyroblast,if=buff.hot_streak.react&(prev_gcd.1.fireball|firestarter.active|action.pyroblast.in_flight)
actions.standard_rotation+=/phoenix_flames,if=charges>=3&active_enemies>2&!variable.phoenix_pooling
actions.standard_rotation+=/pyroblast,if=buff.hot_streak.react&target.health.pct<=30&talent.searing_touch.enabled
actions.standard_rotation+=/pyroblast,if=buff.pyroclasm.react&cast_time<buff.pyroclasm.remains
actions.standard_rotation+=/fire_blast,use_off_gcd=1,use_while_casting=1,if=(cooldown.combustion.remains>0&buff.rune_of_power.down|firestarter.active)&!talent.kindling.enabled&!variable.fire_blast_pooling&(((action.fireball.executing|action.pyroblast.executing)&(buff.heating_up.react|firestarter.active&!buff.hot_streak.react&!buff.heating_up.react))|(talent.searing_touch.enabled&target.health.pct<=30&(buff.heating_up.react&!action.scorch.executing|!buff.hot_streak.react&!buff.heating_up.react&action.scorch.executing&!action.pyroblast.in_flight&!action.fireball.in_flight))|(firestarter.active&(action.pyroblast.in_flight|action.fireball.in_flight)&!buff.heating_up.react&!buff.hot_streak.react))
actions.standard_rotation+=/fire_blast,if=talent.kindling.enabled&buff.heating_up.react&(cooldown.combustion.remains>full_recharge_time+2+talent.kindling.enabled|firestarter.remains>full_recharge_time|(!talent.rune_of_power.enabled|cooldown.rune_of_power.remains>target.time_to_die&action.rune_of_power.charges<1)&cooldown.combustion.remains>target.time_to_die)
actions.standard_rotation+=/pyroblast,if=prev_gcd.1.scorch&buff.heating_up.up&talent.searing_touch.enabled&target.health.pct<=30&((talent.flame_patch.enabled&active_enemies=1&!firestarter.active)|(active_enemies<4&!talent.flame_patch.enabled))
actions.standard_rotation+=/phoenix_flames,if=(buff.heating_up.react|(!buff.hot_streak.react&(action.fire_blast.charges>0|talent.searing_touch.enabled&target.health.pct<=30)))&!variable.phoenix_pooling
actions.standard_rotation+=/call_action_list,name=active_talents
actions.standard_rotation+=/dragons_breath,if=active_enemies>1
actions.standard_rotation+=/call_action_list,name=items_low_priority
actions.standard_rotation+=/scorch,if=target.health.pct<=30&talent.searing_touch.enabled
actions.standard_rotation+=/fireball
actions.standard_rotation+=/scorch
]]
	if Flamestrike:usable() and HotStreak:up() and Player.enemies > (FlamePatch.known and Firestarter:down() and 1 or 4) then
		return Flamestrike
	end
	if Pyroblast:usable() and HotStreak:up() then
		if HotStreak:remains() < Fireball:castTime() then
			return Pyroblast
		end
		if Fireball:previous() or Firestarter:up() or Pyroblast:traveling() then
			return Pyroblast
		end
	end
	if PhoenixFlames:usable() then
		Player.phoenix_pooling = PhoenixFlames.known and ((RuneOfPower.known and RuneOfPower:cooldown() < PhoenixFlames:fullRechargeTime() and Combustion:cooldown() > Player.combustion_rop_cutoff and (RuneOfPower:cooldown() < Target.timeToDie or RuneOfPower:charges() > 0)) or
			(Combustion:cooldown() < PhoenixFlames:fullRechargeTime() and Combustion:cooldown() < Target.timeToDie))
		if not Player.phoenix_pooling and Player.enemies > 2 and PhoenixFlames:charges() >= 3 then
			return PhoenixFlames
		end
	end
	if Pyroblast:usable() then
		if HotStreak:up() and SearingTouch:up() then
			return Pyroblast
		end
		if Pyroclasm:up() and Pyroblast:castTime() < Pyroclasm:remains() then
			return Pyroblast
		end
	end
	if FireBlast:usable() then
		Player.fire_blast_pooling = (RuneOfPower.known and RuneOfPower:cooldown() < FireBlast:fullRechargeTime() and (Combustion:cooldown() > Player.combustion_rop_cutoff or Firestarter:up()) and (RuneOfPower:cooldown() < Target.timeToDie or RuneOfPower:charges() > 0)) or
			(Combustion:cooldown() < (FireBlast:fullRechargeTime() + (BlasterMaster.known and FireBlast:cooldownDuration() or 0)) and Firestarter:down() and Combustion:cooldown() < Target.timeToDie) or
			(Firestarter.known and Firestarter:up() and Firestarter:remains() < (FireBlast:fullRechargeTime() + (BlasterMaster.known and FireBlast:cooldownDuration() or 0)))
		if Target.timeToDie < 4 then
			UseExtra(FireBlast)
		elseif Kindling.known then
			if HeatingUp:up() and (Combustion:cooldown() > (FireBlast:fullRechargeTime() + 3) or Firestarter:remains() > FireBlast:fullRechargeTime() or (not RuneOfPower.known or (RuneOfPower:cooldown() > Target.timeToDie and RuneOfPower:charges() < 1)) and Combustion:cooldown() > Target.timeToDie) then
				UseExtra(FireBlast)
			end
		elseif not Player.fire_blast_pooling and HeatingUp:up() then
			UseExtra(FireBlast)
		end
	end
	if PhoenixFlames:usable() and not Player.phoenix_pooling and (HeatingUp:up() or (not HotStreak:up() and (FireBlast:charges() > 0 or SearingTouch:up()))) then
		return PhoenixFlames
	end
	local apl = self:active_talents()
	if apl then return apl end
	if Player.enemies > 1 and DragonsBreath:usable() then
		UseExtra(DragonsBreath)
	end
	if Player.moving and Pyroblast:usable() and HotStreak:up() then
		return Pyroblast
	end
	if Scorch:usable() and (Player.moving or SearingTouch:up() or (Preheat.known and Preheat:down())) then
		return Scorch
	end
	if Fireball:usable() then
		return Fireball
	end
end

APL[SPEC.FROST].main = function(self)
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/arcane_intellect
actions.precombat+=/water_elemental
actions.precombat+=/snapshot_stats
actions.precombat+=/mirror_image
actions.precombat+=/potion
actions.precombat+=/frostbolt
]]
	if TimeInCombat() == 0 then
		if ArcaneIntellect:usable() and ArcaneIntellect:remains() < 300 then
			return ArcaneIntellect
		end
		if SummonWaterElemental:usable() and not Player.pet_active then
			return SummonWaterElemental
		end
		if MirrorImage:usable() then
			UseCooldown(MirrorImage)
		end
		if not InArenaOrBattleground() then
			if Opt.pot and BattlePotionOfIntellect:usable() then
				UseCooldown(BattlePotionOfIntellect)
			end
		end
		if Frostbolt:usable() and not Frostbolt:casting() then
			return Frostbolt
		end
	else
		if ArcaneIntellect:down() and ArcaneIntellect:usable() then
			UseExtra(ArcaneIntellect)
		elseif SummonWaterElemental:usable() and not Player.pet_active then
			UseExtra(SummonWaterElemental)
		end
	end
--[[
# If the mage has FoF after casting instant Flurry, we can delay the Ice Lance and use other high priority action, if available.
actions+=/ice_lance,if=prev_gcd.1.flurry&brain_freeze_active&!buff.fingers_of_frost.react
actions+=/call_action_list,name=cooldowns
# The target threshold isn't exact. Between 3-5 targets, the differences between the ST and AoE action lists are rather small. However, Freezing Rain prefers using AoE action list sooner as it benefits greatly from the high priority Blizzard action.
actions+=/call_action_list,name=aoe,if=active_enemies>3&talent.freezing_rain.enabled|active_enemies>4
actions+=/call_action_list,name=single
]]
	if IceLance:usable() and Flurry:previous() and not FingersOfFrost:up() then
		return IceLance
	end
	self:cooldowns()
	if Player.enemies > (FreezingRain.known and 3 or 4) then
		local apl = self:aoe()
		if apl then return apl end
	end
	return self:single()
end

APL[SPEC.FROST].cooldowns = function(self)
	-- Let's not waste a shatter with a cooldown's GCD
	if Ebonbolt:previous() or (GlacialSpike:previous() and BrainFreeze:up()) then
		return
	end
--[[
actions.cooldowns=icy_veins
actions.cooldowns+=/mirror_image
# Rune of Power is always used with Frozen Orb. Any leftover charges at the end of the fight should be used, ideally if the boss doesn't die in the middle of the Rune buff.
actions.cooldowns+=/rune_of_power,if=prev_gcd.1.frozen_orb|time_to_die>10+cast_time&time_to_die<20
# On single target fights, the cooldown of Rune of Power is lower than the cooldown of Frozen Orb, this gives extra Rune of Power charges that should be used with active talents, if possible.
actions.cooldowns+=/call_action_list,name=talent_rop,if=talent.rune_of_power.enabled&active_enemies=1&cooldown.rune_of_power.full_recharge_time<cooldown.frozen_orb.remains
actions.cooldowns+=/potion,if=prev_gcd.1.icy_veins|target.time_to_die<70
actions.cooldowns+=/use_items
actions.cooldowns+=/blood_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/lights_judgment
actions.cooldowns+=/fireblood
actions.cooldowns+=/ancestral_call
]]
	if IcyVeins:usable() then
		return UseCooldown(IcyVeins)
	end
	if MirrorImage:usable() then
		return UseCooldown(MirrorImage)
	end
	if RuneOfPower:usable() then
		if FrozenOrb:previous() or (Target.timeToDie > (10 + RuneOfPower:castTime()) and Target.timeToDie < 20) then
			return UseCooldown(RuneOfPower)
		end
		if Player.enemies == 1 and RuneOfPower:fullRechargeTime() < FrozenOrb:cooldown() then
--[[
# With Glacial Spike, Rune of Power should be used right before the Glacial Spike combo (i.e. with 5 Icicles and a Brain Freeze). When Ebonbolt is off cooldown, Rune of Power can also be used just with 5 Icicles.
actions.talent_rop=rune_of_power,if=talent.glacial_spike.enabled&buff.icicles.stack=5&(buff.brain_freeze.remains>cast_time+action.glacial_spike.cast_time|talent.ebonbolt.enabled&cooldown.ebonbolt.remains<cast_time)
# Without Glacial Spike, Rune of Power should be used before any bigger cooldown (Ebonbolt, Comet Storm, Ray of Frost) or when Rune of Power is about to reach 2 charges.
actions.talent_rop+=/rune_of_power,if=!talent.glacial_spike.enabled&(talent.ebonbolt.enabled&cooldown.ebonbolt.remains<cast_time|talent.comet_storm.enabled&cooldown.comet_storm.remains<cast_time|talent.ray_of_frost.enabled&cooldown.ray_of_frost.remains<cast_time|charges_fractional>1.9)
]]
			local rop_cast = RuneOfPower:castTime()
			if GlacialSpike.known then
				if Icicles:stack() == 5 and (BrainFreeze:remains() > (rop_cast + GlacialSpike:castTime()) or (Ebonbolt.known and Ebonbolt:cooldown() < rop_cast)) then
					return UseCooldown(RuneOfPower)
				end
			elseif RuneOfPower:chargesFractional() > 1.9 or (Ebonbolt.known and Ebonbolt:cooldown() < rop_cast) or (CometStorm.known and CometStorm:cooldown() < rop_cast) or (RayOfFrost.known and RayOfFrost:cooldown() < rop_cast) then
				return UseCooldown(RuneOfPower)
			end
		end
	end
	if Opt.pot and BattlePotionOfIntellect:usable() and (IcyVeins:previous() or Target.timeToDie < 70) then
		return UseCooldown(BattlePotionOfIntellect)
	end
	if Opt.trinket then
		if Trinket1:usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:usable() then
			UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.FROST].movement = function(self)
--[[
actions.movement=blink,if=movement.distance>10
actions.movement+=/ice_floes,if=buff.ice_floes.down
]]
	if Blink:usable() then
		UseExtra(Blink)
	elseif Shimmer:usable() then
		UseExtra(Shimmer)
	elseif IceFloes:usable() then
		UseExtra(IceFloes)
	end
end

APL[SPEC.FROST].single = function(self)
	if Freeze:usable() and not Target:frozen() and (CometStorm:previous() or (Player.enemies < 3 and BrainFreeze:down() and (Ebonbolt:casting() or GlacialSpike:casting()))) then
		UseExtra(Freeze)
	end
--[[
# In some situations, you can shatter Ice Nova even after already casting Flurry and Ice Lance. Otherwise this action is used when the mage has FoF after casting Flurry, see above.
actions.single=ice_nova,if=cooldown.ice_nova.ready&debuff.winters_chill.up
# Without GS, Ebonbolt is always shattered. With GS, Ebonbolt is shattered if it would waste Brain Freeze charge (i.e. when the mage starts casting Ebonbolt with Brain Freeze active) or when below 4 Icicles (if Ebonbolt is cast when the mage has 4-5 Icicles, it's better to use the Brain Freeze from it on Glacial Spike).
actions.single+=/flurry,if=talent.ebonbolt.enabled&prev_gcd.1.ebonbolt&(!talent.glacial_spike.enabled|buff.icicles.stack<4|buff.brain_freeze.react)
# Glacial Spike is always shattered.
actions.single+=/flurry,if=talent.glacial_spike.enabled&prev_gcd.1.glacial_spike&buff.brain_freeze.react
# Without GS, the mage just tries to shatter as many Frostbolts as possible. With GS, the mage only shatters Frostbolt that would put them at 1-3 Icicle stacks. Difference between shattering Frostbolt with 1-3 Icicles and 1-4 Icicles is small, but 1-3 tends to be better in more situations (the higher GS damage is, the more it leans towards 1-3). Forcing shatter on Frostbolt is still a small gain, so is not caring about FoF. Ice Lance is too weak to warrant delaying Brain Freeze Flurry.
actions.single+=/flurry,if=prev_gcd.1.frostbolt&buff.brain_freeze.react&(!talent.glacial_spike.enabled|buff.icicles.stack<4)
actions.single+=/frozen_orb
# With Freezing Rain and at least 2 targets, Blizzard needs to be used with higher priority to make sure you can fit both instant Blizzards into a single Freezing Rain. Starting with three targets, Blizzard leaves the low priority filler role and is used on cooldown (and just making sure not to waste Brain Freeze charges) with or without Freezing Rain.
actions.single+=/blizzard,if=active_enemies>2|active_enemies>1&cast_time=0&buff.fingers_of_frost.react<2
# Trying to pool charges of FoF for anything isn't worth it. Use them as they come.
actions.single+=/ice_lance,if=buff.fingers_of_frost.react
actions.single+=/comet_storm
actions.single+=/ebonbolt
# Ray of Frost is used after all Fingers of Frost charges have been used and there isn't active Frozen Orb that could generate more. This is only a small gain against multiple targets, as Ray of Frost isn't too impactful.
actions.single+=/ray_of_frost,if=!action.frozen_orb.in_flight&ground_aoe.frozen_orb.remains=0
# Blizzard is used as low priority filler against 2 targets. When using Freezing Rain, it's a medium gain to use the instant Blizzard even against a single target, especially with low mastery.
actions.single+=/blizzard,if=cast_time=0|active_enemies>1
# Glacial Spike is used when there's a Brain Freeze proc active (i.e. only when it can be shattered). This is a small to medium gain in most situations. Low mastery leans towards using it when available. When using Splitting Ice and having another target nearby, it's slightly better to use GS when available, as the second target doesn't benefit from shattering the main target.
actions.single+=/glacial_spike,if=buff.brain_freeze.remains>cast_time|prev_gcd.1.ebonbolt|active_enemies>1&talent.splitting_ice.enabled
actions.single+=/ice_nova
actions.single+=/flurry,if=buff.brain_freeze.react&active_enemies=1&target.time_to_die<2
actions.single+=/flurry,if=azerite.winters_reach.enabled&!buff.brain_freeze.react&buff.winters_reach.react
actions.single+=/frostbolt
actions.single+=/call_action_list,name=movement
actions.single+=/ice_lance
]]
	if IceNova:usable() and WintersChill:up() then
		return IceNova
	end
	if Flurry:usable() then
		if Ebonbolt.known and Ebonbolt:previous() and (not GlacialSpike.known or Icicles:stack() < 4 or BrainFreeze:up()) then
			return Flurry
		end
		if GlacialSpike.known and GlacialSpike:previous() and BrainFreeze:up() then
			return Flurry
		end
		if Frostbolt:previous() and BrainFreeze:up() and (not GlacialSpike.known or Icicles:stack() < 4) then
			return Flurry
		end
	end
	if FrozenOrb:usable() then
		UseCooldown(FrozenOrb)
	end
	if Blizzard:usable() and (Player.enemies > 2 or (Player.enemies > 1 and FreezingRain:up() and FingersOfFrost:stack() < 2)) then
		return Blizzard
	end
	if IceLance:usable() and FingersOfFrost:up() then
		return IceLance
	end
	if CometStorm:usable() and not Player.cd then
		if Freeze:usable() and not Target:frozen() then
			UseExtra(Freeze)
		end
		UseCooldown(CometStorm)
	end
	if Ebonbolt:usable() and (Ebonbolt:castTime() + Player.gcd) < Target.timeToDie then
		return Ebonbolt
	end
	if RayOfFrost:usable() and not FrozenOrb:inFlight() then
		return RayOfFrost
	end
	if Blizzard:usable() and (FreezingRain:up() or Player.enemies > 1) then
		return Blizzard
	end
	if GlacialSpike:usable() and (GlacialSpike:castTime() + Player.gcd) < Target.timeToDie and (BrainFreeze:remains() > GlacialSpike:castTime() or Ebonbolt:previous() or (Player.enemies > 1 and SplittingIce.known)) then
		return GlacialSpike
	end
	if IceNova:usable() then
		return IceNova
	end
	if IceLance:usable() and Target:frozen() and GetNumGroupMembers() <= 3 and not IceLance:previous() then
		return IceLance
	end
	if Flurry:usable() then
		if Player.enemies == 1 and Target.timeToDie < 2 and BrainFreeze:up() then
			return Flurry
		end
		if WintersReach.known and BrainFreeze:down() and WintersReach:up() then
			return Flurry
		end
	end
	if Frostbolt:usable() then
		return Frostbolt
	end
	if Player.moving then
		self:movement()
	end
	if IceLance:usable() then
		return IceLance
	end
end

APL[SPEC.FROST].aoe = function(self)
	if Freeze:usable() and not Target:frozen() then
		if CometStorm.known and CometStorm:cooldown() > 28 then 
			UseExtra(Freeze)
		elseif GlacialSpike.known and SplittingIce.known and GlacialSpike:casting() and BrainFreeze:down() then
			UseExtra(Freeze)
		end
	end
--[[
# With Freezing Rain, it's better to prioritize using Frozen Orb when both FO and Blizzard are off cooldown. Without Freezing Rain, the converse is true although the difference is miniscule until very high target counts.
actions.aoe=frozen_orb
actions.aoe+=/blizzard
actions.aoe+=/comet_storm
actions.aoe+=/ice_nova
# Simplified Flurry conditions from the ST action list. Since the mage is generating far less Brain Freeze charges, the exact condition here isn't all that important.
actions.aoe+=/flurry,if=prev_gcd.1.ebonbolt|buff.brain_freeze.react&(prev_gcd.1.frostbolt&(buff.icicles.stack<4|!talent.glacial_spike.enabled)|prev_gcd.1.glacial_spike)
actions.aoe+=/ice_lance,if=buff.fingers_of_frost.react
# The mage will generally be generating a lot of FoF charges when using the AoE action list. Trying to delay Ray of Frost until there are no FoF charges and no active Frozen Orbs would lead to it not being used at all.
actions.aoe+=/ray_of_frost
actions.aoe+=/ebonbolt
actions.aoe+=/glacial_spike,if=cast_time<cooldown.blizzard.remains
# Using Cone of Cold is mostly DPS neutral with the AoE target thresholds. It only becomes decent gain with roughly 7 or more targets.
actions.aoe+=/cone_of_cold
actions.aoe+=/frostbolt
actions.aoe+=/call_action_list,name=movement
actions.aoe+=/ice_lance
]]
	if FrozenOrb:usable() then
		return FrozenOrb
	end
	if Blizzard:usable() then
		return Blizzard
	end
	if CometStorm:usable() then
		if Freeze:usable() and not Target:frozen() then
			UseExtra(Freeze)
		end
		return CometStorm
	end
	if IceNova:usable() then
		if Freeze:usable() and not Target:frozen() and (not CometStorm.known or CometStorm:cooldown() > 25) then
			UseExtra(Freeze)
		end
		return IceNova
	end
	if Flurry:usable() and (Ebonbolt:previous() or (BrainFreeze:up() and ((Frostbolt:previous() and (Icicles:stack() < 4 or not GlacialSpike.known)) or GlacialSpike:previous()))) then
		return Flurry
	end
	if IceLance:usable() and FingersOfFrost:up() then
		return IceLance
	end
	if RayOfFrost:usable() then
		return RayOfFrost
	end
	if Ebonbolt:usable() and (Ebonbolt:castTime() + Player.gcd) < Target.timeToDie then
		return Ebonbolt
	end
	if GlacialSpike:usable() and GlacialSpike:castTime() < Blizzard:cooldown() and (GlacialSpike:castTime() + Player.gcd) < Target.timeToDie then
		return GlacialSpike
	end
--[[
	if ConeOfCold:usable() and Player.enemies >= 5 then
		UseExtra(ConeOfCold)
	end
]]
	if IceLance:usable() and Target:frozen() and not IceLance:previous() then
		return IceLance
	end
	if Frostbolt:usable() then
		return Frostbolt
	end
	if Player.moving then
		self:movement()
	end
	if IceLance:usable() then
		return IceLance
	end
end

APL.Interrupt = function(self)
	if Counterspell:usable() then
		return Counterspell
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start then
		_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
	end
	if not start or notInterruptible then
		Player.interrupt = nil
		amagicInterruptPanel:Hide()
		return
	end
	Player.interrupt = APL.Interrupt()
	if Player.interrupt then
		amagicInterruptPanel.icon:SetTexture(Player.interrupt.icon)
	end
	amagicInterruptPanel.icon:SetShown(Player.interrupt)
	amagicInterruptPanel.border:SetShown(Player.interrupt)
	amagicInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
	amagicInterruptPanel:Show()
end

local function DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

local function CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			glows[#glows + 1] = glow
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
	UpdateGlowColorAndScale()
end

local function UpdateGlows()
	local glow, icon, i
	for i = 1, #glows do
		glow = glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function events:ACTIONBAR_SLOT_CHANGED()
	UpdateGlows()
end

local function ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.ARCANE and Opt.hide.arcane) or
		   (Player.spec == SPEC.FIRE and Opt.hide.fire) or
		   (Player.spec == SPEC.FROST and Opt.hide.frost))
end

local function Disappear()
	amagicPanel:Hide()
	amagicPanel.icon:Hide()
	amagicPanel.border:Hide()
	amagicCooldownPanel:Hide()
	amagicInterruptPanel:Hide()
	amagicExtraPanel:Hide()
	Player.main, Player.last_main = nil
	Player.cd, Player.last_cd = nil
	Player.interrupt = nil
	Player.extra, Player.last_extra = nil
	UpdateGlows()
end

function Equipped(name, slot)
	local function SlotMatches(name, slot)
		local ilink = GetInventoryItemLink('player', slot)
		if ilink then
			local iname = ilink:match('%[(.*)%]')
			return (iname and iname:find(name))
		end
		return false
	end
	if slot then
		return SlotMatches(name, slot)
	end
	local i
	for i = 1, 19 do
		if SlotMatches(name, i) then
			return true
		end
	end
	return false
end

local function Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

local function UpdateDraggable()
	amagicPanel:EnableMouse(Opt.aoe or not Opt.locked)
	amagicPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		amagicPanel:SetScript('OnDragStart', nil)
		amagicPanel:SetScript('OnDragStop', nil)
		amagicPanel:RegisterForDrag(nil)
		amagicPreviousPanel:EnableMouse(false)
		amagicCooldownPanel:EnableMouse(false)
		amagicInterruptPanel:EnableMouse(false)
		amagicExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			amagicPanel:SetScript('OnDragStart', amagicPanel.StartMoving)
			amagicPanel:SetScript('OnDragStop', amagicPanel.StopMovingOrSizing)
			amagicPanel:RegisterForDrag('LeftButton')
		end
		amagicPreviousPanel:EnableMouse(true)
		amagicCooldownPanel:EnableMouse(true)
		amagicInterruptPanel:EnableMouse(true)
		amagicExtraPanel:EnableMouse(true)
	end
end

local function SnapAllPanels()
	amagicPreviousPanel:ClearAllPoints()
	amagicPreviousPanel:SetPoint('BOTTOMRIGHT', amagicPanel, 'BOTTOMLEFT', -10, -5)
	amagicCooldownPanel:ClearAllPoints()
	amagicCooldownPanel:SetPoint('BOTTOMLEFT', amagicPanel, 'BOTTOMRIGHT', 10, -5)
	amagicInterruptPanel:ClearAllPoints()
	amagicInterruptPanel:SetPoint('TOPLEFT', amagicPanel, 'TOPRIGHT', 16, 25)
	amagicExtraPanel:ClearAllPoints()
	amagicExtraPanel:SetPoint('TOPRIGHT', amagicPanel, 'TOPLEFT', -16, 25)
end

local resourceAnchor = {}

local ResourceFramePoints = {
	['blizzard'] = {
		[SPEC.ARCANE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -28 }
		},
		[SPEC.FIRE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		}
	},
	['kui'] = {
		[SPEC.ARCANE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.FIRE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		}
	},
}

local function OnResourceFrameHide()
	if Opt.snap then
		amagicPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if Opt.snap then
		amagicPanel:ClearAllPoints()
		local p = ResourceFramePoints[resourceAnchor.name][Player.spec][Opt.snap]
		amagicPanel:SetPoint(p[1], resourceAnchor.frame, p[2], p[3], p[4])
		SnapAllPanels()
	end
end

local function HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		resourceAnchor.name = 'kui'
		resourceAnchor.frame = KuiNameplatesPlayerAnchor
	else
		resourceAnchor.name = 'blizzard'
		resourceAnchor.frame = ClassNameplateManaBarFrame
	end
	resourceAnchor.frame:HookScript("OnHide", OnResourceFrameHide)
	resourceAnchor.frame:HookScript("OnShow", OnResourceFrameShow)
end

local function UpdateAlpha()
	amagicPanel:SetAlpha(Opt.alpha)
	amagicPreviousPanel:SetAlpha(Opt.alpha)
	amagicCooldownPanel:SetAlpha(Opt.alpha)
	amagicInterruptPanel:SetAlpha(Opt.alpha)
	amagicExtraPanel:SetAlpha(Opt.alpha)
end

local function UpdateTargetHealth()
	timer.health = 0
	Target.health = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[15] = Target.health
	Target.timeToDieMax = Target.health / UnitHealthMax('player') * 15
	Target.healthPercentage = Target.healthMax > 0 and (Target.health / Target.healthMax * 100) or 100
	Target.healthLostPerSec = (Target.healthArray[1] - Target.health) / 3
	Target.timeToDie = Target.healthLostPerSec > 0 and min(Target.timeToDieMax, Target.health / Target.healthLostPerSec) or Target.timeToDieMax
end

local function UpdateDisplay()
	timer.display = 0
	local dim, text_center
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Player.spec == SPEC.ARCANE then
		text_center = Player.burn_phase and 'BURN' or 'CONSERVE'
	end
	amagicPanel.dimmer:SetShown(dim)
	amagicPanel.text.center:SetText(text_center)
end

local function UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.last_main = Player.main
	Player.last_cd = Player.cd
	Player.last_extra = Player.extra
	Player.main =  nil
	Player.cd = nil
	Player.extra = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.gcd = 1.5 * Player.haste_factor
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	Player.mana_regen = GetPowerRegen()
	Player.mana = UnitPower('player', 0) + (Player.mana_regen * Player.execute_remains)
	Player.mana_max = UnitPowerMax('player', 0)
	if Player.ability_casting then
		Player.mana = Player.mana - Player.ability_casting:cost()
	end
	Player.mana = min(max(Player.mana, 0), Player.mana_max)
	if Player.spec == SPEC.ARCANE then
		Player.arcane_charges = UnitPower('player', 16)
	end
	Player.moving = GetUnitSpeed('player') ~= 0
	Player.pet = UnitGUID('pet')
	Player.pet_alive = (Player.pet and not UnitIsDead('pet') or SummonWaterElemental:previous()) and true
	Player.pet_active = (Player.pet_alive and not Player.pet_stuck or IsFlying()) and true

	trackAuras:purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:updateTargetsHit()
		end
		autoAoe:purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main ~= Player.last_main then
		if Player.main then
			amagicPanel.icon:SetTexture(Player.main.icon)
		end
		amagicPanel.icon:SetShown(Player.main)
		amagicPanel.border:SetShown(Player.main)
	end
	if Player.cd ~= Player.last_cd then
		if Player.cd then
			amagicCooldownPanel.icon:SetTexture(Player.cd.icon)
		end
		amagicCooldownPanel:SetShown(Player.cd)
	end
	if Player.extra ~= Player.last_extra then
		if Player.extra then
			amagicExtraPanel.icon:SetTexture(Player.extra.icon)
		end
		amagicExtraPanel:SetShown(Player.extra)
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
	UpdateDisplay()
end

local function UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local start, duration
		local _, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		amagicPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'ARCANE_CHARGES' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:ADDON_LOADED(name)
	if name == 'Automagically' then
		Opt = Automagically
		if not Opt.frequency then
			print('It looks like this is your first time running Automagically, why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Automagically1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] Automagically is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitializeOpts()
		Azerite:initialize()
		UpdateDraggable()
		UpdateAlpha()
		SnapAllPanels()
		amagicPanel:SetScale(Opt.scale.main)
		amagicPreviousPanel:SetScale(Opt.scale.previous)
		amagicCooldownPanel:SetScale(Opt.scale.cooldown)
		amagicInterruptPanel:SetScale(Opt.scale.interrupt)
		amagicExtraPanel:SetScale(Opt.scale.extra)
	end
end

function events:UI_ERROR_MESSAGE(errorId)
	if (
	    errorId == 394 or -- pet is rooted
	    errorId == 396 or -- target out of pet range
	    errorId == 400    -- no pet path to target
	) then
		Player.pet_stuck = true
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:remove(dstGUID)
		end
	end
	if Opt.auto_aoe and (eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED') then
		if dstGUID == Player.guid or dstGUID == Player.pet then
			autoAoe:add(srcGUID, true)
		elseif (srcGUID == Player.guid or srcGUID == Player.pet) and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:add(dstGUID, true)
		end
	end

	if (srcGUID ~= Player.guid and srcGUID ~= Player.pet) then
		return
	end

	if srcGUID == Player.pet then
		if Player.pet_stuck and (eventType == 'SPELL_CAST_SUCCESS' or eventType == 'SPELL_DAMAGE' or eventType == 'SWING_DAMAGE') then
			Player.pet_stuck = false
		elseif not Player.pet_stuck and eventType == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Player.pet_stuck = true
		end
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
			ability.last_used = Player.time
			if ability.triggers_gcd then
				Player.previous_gcd[10] = nil
				table.insert(Player.previous_gcd, 1, ability)
			end
			if ability.travel_start then
				ability.travel_start[dstGUID] = Player.time
			end
			if Opt.previous and amagicPanel:IsVisible() then
				amagicPreviousPanel.ability = ability
				amagicPreviousPanel.border:SetTexture('Interface\\AddOns\\Automagically\\border.blp')
				amagicPreviousPanel.icon:SetTexture(ability.icon)
				amagicPreviousPanel:Show()
			end
			if Player.spec == SPEC.ARCANE then
				if ability == ArcanePower then
					APL[SPEC.ARCANE]:toggle_burn_phase(true)
				elseif ability == Evocation then
					APL[SPEC.ARCANE]:toggle_burn_phase(false)
				end
			end
		end
		if Player.pet_stuck and ability.requires_pet then
			Player.pet_stuck = false
		end
		return
	end
	if eventType == 'SPELL_CAST_FAILED' then
		if ability.requires_pet and missType == 'No path available' then
			Player.pet_stuck = true
		end
		return
	end
	if dstGUID == Player.guid or dstGUID == Player.pet then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:applyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:refreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:removeAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:remove(dstGUID)
		elseif ability.auto_aoe and eventType == ability.auto_aoe.trigger then
			ability:recordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and amagicPanel:IsVisible() and ability == amagicPreviousPanel.ability then
			amagicPreviousPanel.border:SetTexture('Interface\\AddOns\\Automagically\\misseffect.blp')
		end
		if Player.spec == SPEC.FROST and dstGUID == Target.guid then
			if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
				if ability == Chilled or ability == FrostNova or ability == IceNova or ability == Freeze or ability == ConeOfCold or ability == GlacialSpike then
					Target.stunnable = true
				end
			elseif eventType == 'SPELL_MISSED' and extraType == 'IMMUNE' then
				if ability == Freeze then
					Target.stunnable = false
				end
			end
		end
	end
end

local function UpdateTargetInfo()
	Disappear()
	if ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		Target.guid = nil
		Target.boss = false
		Target.stunnable = true
		Target.classification = 'normal'
		Target.player = false
		Target.level = UnitLevel('player')
		Target.healthMax = 0
		Target.hostile = true
		local i
		for i = 1, 15 do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateTargetHealth()
			UpdateCombat()
			amagicPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			amagicPreviousPanel:Hide()
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		local i
		for i = 1, 15 do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.boss = false
	Target.stunnable = true
	Target.classification = UnitClassification('target')
	Target.player = UnitIsPlayer('target')
	Target.level = UnitLevel('target')
	Target.healthMax = UnitHealthMax('target')
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not Target.player and Target.classification ~= 'minus' and Target.classification ~= 'normal' then
		if Target.level == -1 or (Player.instance == 'party' and Target.level >= UnitLevel('player') + 2) then
			Target.boss = true
			Target.stunnable = false
		elseif Player.instance == 'raid' or (Target.healthMax > Player.health_max * 10) then
			Target.stunnable = false
		end
	end
	if Target.hostile or Opt.always_on then
		UpdateTargetHealth()
		UpdateCombat()
		amagicPanel:Show()
		return true
	end
end

function events:PLAYER_TARGET_CHANGED()
	UpdateTargetInfo()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.pet_stuck = false
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		amagicPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:clear()
		autoAoe:update()
	end
	if Player.spec == SPEC.ARCANE then
		Player.burn_phase = false
		Player.burn_phase_duration = 0
		Player.total_burns = 0
		Player.average_burn_length = 0
	elseif Player.spec == SPEC.FIRE then
		Player.combustion_rop_cutoff = 60
	end
end

local function UpdateAbilityData()
	Player.mana_base = BaseMana[UnitLevel('player')]
	local _, ability
	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = (IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) or Azerite.traits[ability.spellId]) and true or false
	end
	Freeze.known = SummonWaterElemental.known
	Waterbolt.known = SummonWaterElemental.known
	WintersChill.known = BrainFreeze.known
	HeatingUp.known = HotStreak.known
	if FlameOn.known then
		FireBlast.cooldown_duration = 10
	end

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	Azerite:update()
	UpdateAbilityData()
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	local _, i, equipType, hasCooldown
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
	end
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	amagicPreviousPanel.ability = nil
	SetTargetMode(1)
	UpdateTargetInfo()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
end

function events:PLAYER_PVP_TALENT_UPDATE()
	UpdateAbilityData()
end

function events:PLAYER_ENTERING_WORLD()
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

amagicPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			ToggleTargetMode()
		elseif button == 'RightButton' then
			ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			SetTargetMode(1)
		end
	end
end)

amagicPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UpdateCombat()
	end
	if timer.display >= 0.05 then
		UpdateDisplay()
	end
	if timer.health >= 0.2 then
		UpdateTargetHealth()
	end
end)

amagicPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	amagicPanel:RegisterEvent(event)
end

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
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
	print('Automagically -', desc .. ':', opt_view, ...)
end

function SlashCmdList.Automagically(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				amagicPanel:ClearAllPoints()
			end
			OnResourceFrameShow()
		end
		return Status('Snap to Blizzard combat resources frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				amagicPreviousPanel:SetScale(Opt.scale.previous)
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				amagicPanel:SetScale(Opt.scale.main)
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				amagicCooldownPanel:SetScale(Opt.scale.cooldown)
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				amagicInterruptPanel:SetScale(Opt.scale.interrupt)
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				amagicExtraPanel:SetScale(Opt.scale.extra)
			end
			return Status('Extra/Pet cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
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
				UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (extra/pet cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return Status('Show the Automagically UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use Automagically for cooldown management', Opt.cooldown)
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
		return Status('Dim main ability icon when you don\'t have enough mana to use it', Opt.dimmer)
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
			Automagically_SetTargetMode(1)
			UpdateDraggable()
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
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Arcane specialization', not Opt.hide.arcane)
			end
			if startsWith(msg[2], 'fi') then
				Opt.hide.fire = not Opt.hide.fire
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Fire specialization', not Opt.hide.fire)
			end
			if startsWith(msg[2], 'fr') then
				Opt.hide.frost = not Opt.hide.frost
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Frost specialization', not Opt.hide.frost)
			end
		end
		return Status('Possible hidespec options',  '|cFFFFD000arcane|r, |cFFFFD000fire|r, and |cFFFFD000frost')
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
	if startsWith(msg[1], 'con') then
		if msg[2] then
			Opt.conserve_mana = max(min(tonumber(msg[2]) or 60, 80), 20)
		end
		return Status('Mana conservation threshold (Arcane)', Opt.conserve_mana .. '%')
	end
	if msg[1] == 'reset' then
		amagicPanel:ClearAllPoints()
		amagicPanel:SetPoint('CENTER', 0, -169)
		SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Automagically (version: |cFFFFD000' .. GetAddOnMetadata('Automagically', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Automagically UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Automagically UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000glow|r - adjust the scale of the Automagically UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Automagically UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Automagically UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Automagically for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough mana to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000arcane|r/|cFFFFD000fire|r/|cFFFFD000frost|r - toggle disabling Automagically for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'conserve |cFFFFD000[20-80]|r  - mana conservation threshold (arcane, default is 60%)',
		'|cFFFFD000reset|r - reset the location of the Automagically UI to default',
	} do
		print('  ' .. SLASH_Automagically1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end
