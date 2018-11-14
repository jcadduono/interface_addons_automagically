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

local function InitializeVariables()
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
			color = { r = 1, g = 1, b = 1 }
		},
		hide = {
			arcane = false,
			fire = false,
			frost = false
		},
		alpha = 1,
		frequency = 0.05,
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
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	ARCANE = 1,
	FIRE = 2,
	FROST = 3
}

local events, glows = {}, {}

local abilityTimer, currentSpec, targetMode, combatStartTime = 0, 0, 0, 0

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

-- list of previous GCD abilities
local PreviousGCD = {}

-- items equipped with special effects
local ItemEquipped = {

}

-- Azerite trait API access
local Azerite = {}

local var = {
	gcd = 1.5
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
amagicPanel.text = amagicPanel:CreateFontString(nil, 'OVERLAY')
amagicPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
amagicPanel.text:SetTextColor(1, 1, 1, 1)
amagicPanel.text:SetAllPoints(amagicPanel)
amagicPanel.text:SetJustifyH('CENTER')
amagicPanel.text:SetJustifyV('CENTER')
amagicPanel.swipe = CreateFrame('Cooldown', nil, amagicPanel, 'CooldownFrameTemplate')
amagicPanel.swipe:SetAllPoints(amagicPanel)
amagicPanel.dimmer = amagicPanel:CreateTexture(nil, 'BORDER')
amagicPanel.dimmer:SetAllPoints(amagicPanel)
amagicPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
amagicPanel.dimmer:Hide()
amagicPanel.targets = amagicPanel:CreateFontString(nil, 'OVERLAY')
amagicPanel.targets:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.targets:SetPoint('BOTTOMRIGHT', amagicPanel, 'BOTTOMRIGHT', -1.5, 3)
amagicPanel.button = CreateFrame('Button', 'amagicPanelButton', amagicPanel)
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
		{3, '3'},
		{4, '4'},
		{5, '5+'}
	},
	[SPEC.FIRE] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'}
	},
	[SPEC.FROST] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'}
	}
}

local function SetTargetMode(mode)
	targetMode = min(mode, #targetModes[currentSpec])
	amagicPanel.targets:SetText(targetModes[currentSpec][targetMode][2])
end
Automagically_SetTargetMode = SetTargetMode

function ToggleTargetMode()
	local mode = targetMode + 1
	SetTargetMode(mode > #targetModes[currentSpec] and 1 or mode)
end
Automagically_ToggleTargetMode = ToggleTargetMode

local function ToggleTargetModeReverse()
	local mode = targetMode - 1
	SetTargetMode(mode < 1 and #targetModes[currentSpec] or mode)
end
Automagically_ToggleTargetModeReverse = ToggleTargetModeReverse

local autoAoe = {
	abilities = {},
	targets = {}
}

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		SetTargetMode(1)
		return
	end
	for i = #targetModes[currentSpec], 1, -1 do
		if count >= targetModes[currentSpec][i][1] then
			SetTargetMode(i)
			return
		end
	end
end

function autoAoe:add(guid)
	local new = not self.targets[guid]
	self.targets[guid] = GetTime()
	if new then
		self:update()
	end
end

function autoAoe:remove(guid)
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:purge()
	local update, guid, t
	local now = GetTime()
	for guid, t in next, self.targets do
		if now - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	if update then
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability, abilities, abilityBySpellId = {}, {}, {}
Ability.__index = Ability

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
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities[#abilities + 1] = ability
	abilityBySpellId[spellId] = ability
	if spellId2 then
		abilityBySpellId[spellId2] = ability
	end
	return ability
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable(seconds)
	if not self.known then
		return false
	end
	if self:cost() > var.mana then
		return false
	end
	if self.requires_pet and not var.pet_exists then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

function Ability:remains()
	if self:traveling() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - var.time - var.execute_remains, 0)
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
	if self:traveling() then
		return true
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if id == self.spellId or id == self.spellId2 then
			return expires == 0 or expires - var.time > var.execute_remains
		end
	end
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
		if var.time - self.travel_start[Target.guid] < 40 / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, expires = 0
		for guid, expires in next, self.aura_targets do
			if expires - var.time > var.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (var.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (var.time - start) - var.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			return (expires == 0 or expires - var.time > var.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * var.mana_max) or 0
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:chargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, var.time - recharge_start + var.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (var.time - recharge_start) - var.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return UnitCastingInfo('player') == self.name
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and var.gcd or 0
	end
	return castTime / 1000
end

function Ability:castRegen()
	return var.mana_regen * self:castTime() - self:cost()
end

function Ability:wontCapMana(reduction)
	return (var.mana + self:castRegen()) < (var.mana_max - (reduction or 5))
end

function Ability:tickTime()
	return self.hasted_ticks and (var.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:previous()
	if self:casting() or self:channeling() then
		return true
	end
	return PreviousGCD[1] == self or var.last_ability == self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:setAutoAoe(enabled)
	if enabled and not self.auto_aoe then
		self.auto_aoe = true
		self.first_hit_time = nil
		self.targets_hit = {}
		autoAoe.abilities[#autoAoe.abilities + 1] = self
	end
	if not enabled and self.auto_aoe then
		self.auto_aoe = nil
		self.first_hit_time = nil
		self.targets_hit = nil
		local i
		for i = 1, #autoAoe.abilities do
			if autoAoe.abilities[i] == self then
				autoAoe.abilities[i] = nil
				break
			end
		end
	end
end

function Ability:recordTargetHit(guid)
	local t = GetTime()
	self.targets_hit[guid] = t
	if not self.first_hit_time then
		self.first_hit_time = t
	end
end

function Ability:updateTargetsHit()
	if self.first_hit_time and GetTime() - self.first_hit_time >= 0.3 then
		self.first_hit_time = nil
		local guid, t
		for guid in next, autoAoe.targets do
			if not self.targets_hit[guid] then
				autoAoe.targets[guid] = nil
			end
		end
		for guid, t in next, self.targets_hit do
			autoAoe.targets[guid] = t
			self.targets_hit[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {
	abilities = {}
}

function trackAuras:purge()
	local now = GetTime()
	local _, ability, guid, expires
	for _, ability in next, self.abilities do
		for guid, expires in next, ability.aura_targets do
			if expires <= now then
				ability:removeAura(guid)
			end
		end
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
	trackAuras.abilities[self.spellId] = self
	if self.spellId2 then
		trackAuras.abilities[self.spellId2] = self
	end
end

function Ability:applyAura(guid)
	if self.aura_targets and UnitGUID(self.auraTarget) == guid then -- for now, we can only track if the enemy is targeted
		local _, i, id, expires
		for i = 1, 40 do
			_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
			if not id then
				return
			end
			if id == self.spellId or id == self.spellId2 then
				self.aura_targets[guid] = expires
				return
			end
		end
	end
end

function Ability:removeAura(guid)
	if self.aura_targets then
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

------ Talents

------ Procs

---- Fire

------ Talents

------ Procs

---- Frost
local Blizzard = Ability.add(190356, false, true, 190357)
Blizzard.mana_cost = 2.5
Blizzard.cooldown_duration = 8
Blizzard:setAutoAoe(true)
local Chilled = Ability.add(205708, false, true)
Chilled.buff_duration = 15
local ConeOfCold = Ability.add(120, false, true)
ConeOfCold.mana_cost = 4
ConeOfCold.buff_duration = 5
ConeOfCold.cooldown_duration = 12
ConeOfCold:setAutoAoe(true)
local Flurry = Ability.add(44614, false, true, 228354)
Flurry.mana_cost = 1
Flurry.buff_duration = 1
Flurry:setVelocity(50)
local Freeze = Ability.add(33395, false, true)
Freeze.cooldown_duration = 25
Freeze.buff_duration = 8
Freeze.requires_pet = true
Freeze.triggers_gcd = false
Freeze:setAutoAoe(true)
local Frostbolt = Ability.add(116, false, true, 228597)
Frostbolt.mana_cost = 2
Frostbolt:setVelocity(35)
local FrostNova = Ability.add(122, false, true)
FrostNova.mana_cost = 2
FrostNova.buff_duration = 8
FrostNova:setAutoAoe(true)
local FrozenOrb = Ability.add(84714, false, true, 84721)
FrozenOrb.mana_cost = 1
FrozenOrb.buff_duration = 15
FrozenOrb.cooldown_duration = 60
FrozenOrb:setVelocity(20)
FrozenOrb:setAutoAoe(true)
local IceBarrier = Ability.add(11426, true, true)
IceBarrier.mana_cost = 3
IceBarrier.buff_duration = 60
IceBarrier.cooldown_duration = 25
local IceLance = Ability.add(30455, false, true)
IceLance.mana_cost = 1
IceLance:setVelocity(47)
local IcyVeins = Ability.add(12472, true, true)
IcyVeins.buff_duration = 20
IcyVeins.cooldown_duration = 180
local SummonWaterElemental = Ability.add(31687, false, true)
SummonWaterElemental.mana_cost = 3
SummonWaterElemental.cooldown_duration = 30
------ Talents
local BoneChilling = Ability.add(205027, false, true, 205766)
BoneChilling.buff_duration = 8
local ChainReaction = Ability.add(278309, true, true, 278310)
ChainReaction.buff_duration = 10
local CometStorm = Ability.add(153595, false, true, 153596)
CometStorm.mana_cost = 1
CometStorm.cooldown_duration = 30
CometStorm:setAutoAoe(true)
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
IceNova:setAutoAoe(true)
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
local FingersOfFrost = Ability.add(44544, true, true)
FingersOfFrost.buff_duration = 15
local Icicles = Ability.add(205473, true, true)
Icicles.buff_duration = 60
local WintersChill = Ability.add(228358, false, true)
WintersChill.buff_duration = 1
-- Azerite Traits
local WintersReach = Ability.add(273346, true, true, 273347)
WintersReach.buff_duration = 15
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
		icon = icon
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration = GetItemCooldown(self.itemId)
	return startTime == 0 and 0 or duration - (var.time - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:usable(seconds)
	if self:charges() == 0 then
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
	return var.mana
end

local function ManaDeficit()
	return var.mana_max - var.mana
end

local function ManaRegen()
	return var.mana_regen
end

local function ManaMax()
	return var.mana_max
end

local function ManaTimeToMax()
	local deficit = var.mana_max - var.mana
	if deficit <= 0 then
		return 0
	end
	return deficit / var.mana_regen
end

local function GCD()
	return var.gcd
end

local function Enemies()
	return targetModes[currentSpec][targetMode][1]
end

local function TimeInCombat()
	return combatStartTime > 0 and var.time - combatStartTime or 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or	-- Bloodlust (Horde Shaman)
			id == 32182 or	-- Heroism (Alliance Shaman)
			id == 80353 or	-- Time Warp (Mage)
			id == 90355 or	-- Ancient Hysteria (Mage Pet - Core Hound)
			id == 160452 or -- Netherwinds (Mage Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Mage Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

local function PlayerIsMoving()
	return GetUnitSpeed('player') ~= 0
end

local function TargetIsFreezable()
	if Target.freezable ~= '?' then
		return Target.freezable
	end
	if UnitIsPlayer('target') then
		return true
	end
	if Target.boss then
		return false
	end
	if var.instance == 'raid' then
		return false
	end
	if UnitHealthMax('target') > UnitHealthMax('player') * 10 then
		return false
	end
	return true
end

local function TargetIsFrozen()
	return FrostNova:up() or IceNova:up() or Freeze:up() or WintersChill:up() or GlacialSpike:up()
end

local function InArenaOrBattleground()
	return var.instance == 'arena' or var.instance == 'pvp'
end

-- End Helpful Functions

-- Start Ability Modifications

function SummonWaterElemental:usable()
	if (UnitExists('pet') and not UnitIsDead('pet')) or IsFlying() then
		return false
	end
	return Ability.usable(self)
end

function Freeze:usable()
	if not TargetIsFreezable() then
		return false
	end
	return Ability.usable(self)
end

function FrostNova:usable()
	if not TargetIsFreezable() then
		return false
	end
	return Ability.usable(self)
end

function FrozenOrb:inFlight()
	if (var.time - self.last_used) < 10 then
		return true
	end
end

function TimeWarp:usable()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HARMFUL')
		if (
			id == 57724 or	-- Sated
			id == 57723 or	-- Exhaustion
			id == 80354	-- Temporal Displacement
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
	if TargetIsFreezable() and self:casting() then
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

-- End Ability Modifications

local function UpdateVars()
	local _, start, duration, remains, hp, hp_lost, spellId
	var.last_main = var.main
	var.last_cd = var.cd
	var.last_extra = var.extra
	var.main =  nil
	var.cd = nil
	var.extra = nil
	var.time = GetTime()
	start, duration = GetSpellCooldown(61304)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	var.execute_remains = max(remains and (remains / 1000 - var.time) or 0, var.gcd_remains)
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	var.gcd = 1.5 * var.haste_factor
	var.mana_regen = GetPowerRegen()
	var.mana_max = UnitPowerMax('player', 0)
	var.mana = min(var.mana_max, floor(UnitPower('player', 0) + (var.mana_regen * var.execute_remains)))
	var.pet = UnitGUID('pet')
	var.pet_exists = UnitExists('pet') and not UnitIsDead('pet')
	hp = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[#Target.healthArray + 1] = hp
	Target.timeToDieMax = hp / UnitHealthMax('player') * 5
	Target.healthPercentage = Target.guid == 0 and 100 or (hp / UnitHealthMax('target') * 100)
	hp_lost = Target.healthArray[1] - hp
	Target.timeToDie = hp_lost > 0 and min(Target.timeToDieMax, hp / (hp_lost / 3)) or Target.timeToDieMax
end

local function UseCooldown(ability, overwrite, always)
	if always or (Opt.cooldown and (not Opt.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not var.extra or overwrite then
		var.extra = ability
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
	if TimeInCombat() == 0 then
		if not InArenaOrBattleground() then
			if Opt.pot and BattlePotionOfIntellect:usable() then
				UseCooldown(BattlePotionOfIntellect)
			end
		end
	end
end

APL[SPEC.FIRE].main = function(self)
	if TimeInCombat() == 0 then
		if not InArenaOrBattleground() then
			if Opt.pot and BattlePotionOfIntellect:usable() then
				UseCooldown(BattlePotionOfIntellect)
			end
		end
	end
end

APL[SPEC.FROST].main = function(self)
	if ArcaneIntellect:down() and ArcaneIntellect:usable() then
		UseExtra(ArcaneIntellect)
	elseif SummonWaterElemental:usable() then
		UseExtra(SummonWaterElemental)
	end
--[[
# Executed before combat begins. Accepts non-harmful actions only.
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/arcane_intellect
actions.precombat+=/water_elemental
actions.precombat+=/snapshot_stats
actions.precombat+=/mirror_image
actions.precombat+=/potion
actions.precombat+=/frostbolt

# Executed every time the actor is available.

]]
	if TimeInCombat() == 0 then
		if not InArenaOrBattleground() then
			if Opt.pot and BattlePotionOfIntellect:usable() then
				UseCooldown(BattlePotionOfIntellect)
			end
		end
		if MirrorImage:usable() then
			UseCooldown(MirrorImage)
		end
		if Frostbolt:usable() then
			return Frostbolt
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
	if Enemies() > (FreezingRain.known and 3 or 4) then
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
		if Enemies() == 1 and RuneOfPower:fullRechargeTime() < FrozenOrb:cooldown() then
--[[
# With Glacial Spike, Rune of Power should be used right before the Glacial Spike combo (i.e. with 5 Icicles and a Brain Freeze). When Ebonbolt is off cooldown, Rune of Power can also be used just with 5 Icicles.
actions.talent_rop=rune_of_power,if=talent.glacial_spike.enabled&buff.icicles.stack=5&(buff.brain_freeze.react|talent.ebonbolt.enabled&cooldown.ebonbolt.remains<cast_time)
# Without Glacial Spike, Rune of Power should be used before any bigger cooldown (Ebonbolt, Comet Storm, Ray of Frost) or when Rune of Power is about to reach 2 charges.
actions.talent_rop+=/rune_of_power,if=!talent.glacial_spike.enabled&(talent.ebonbolt.enabled&cooldown.ebonbolt.remains<cast_time|talent.comet_storm.enabled&cooldown.comet_storm.remains<cast_time|talent.ray_of_frost.enabled&cooldown.ray_of_frost.remains<cast_time|charges_fractional>1.9)
]]
			local rop_cast = RuneOfPower:castTime()
			if GlacialSpike.known then
				if Icicles:stack() == 5 and (BrainFreeze:up() or (Ebonbolt.known and Ebonbolt:cooldown() < rop_cast)) then
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
	if Freeze:usable() and not TargetIsFrozen() and (CometStorm:previous() or (Enemies() < 3 and BrainFreeze:down() and (Ebonbolt:casting() or GlacialSpike:casting()))) then
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
actions.single+=/glacial_spike,if=buff.brain_freeze.react|prev_gcd.1.ebonbolt|active_enemies>1&talent.splitting_ice.enabled
actions.single+=/ice_nova
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
	if Blizzard:usable() and (Enemies() > 2 or (Enemies() > 1 and FreezingRain:up() and FingersOfFrost:stack() < 2)) then
		return Blizzard
	end
	if IceLance:usable() and FingersOfFrost:up() then
		return IceLance
	end
	if CometStorm:usable() then
		if Freeze:usable() and not TargetIsFrozen() then
			UseExtra(Freeze)
		end
		UseCooldown(CometStorm)
	end
	if Ebonbolt:usable() and (Ebonbolt:castTime() + GCD()) < Target.timeToDie then
		return Ebonbolt
	end
	if RayOfFrost:usable() and not FrozenOrb:inFlight() then
		return RayOfFrost
	end
	if Blizzard:usable() and (FreezingRain:up() or Enemies() > 1) then
		return Blizzard
	end
	if GlacialSpike:usable() and (GlacialSpike:castTime() + GCD()) < Target.timeToDie and (BrainFreeze:up() or Ebonbolt:previous() or (Enemies() > 1 and SplittingIce.known)) then
		return GlacialSpike
	end
	if IceNova:usable() then
		return IceNova
	end
	if IceLance:usable() and TargetIsFrozen() and GetNumGroupMembers() <= 3 and not IceLance:previous() then
		return IceLance
	end
	if Flurry:usable() and WintersReach.known and BrainFreeze:down() and WintersReach:up() then
		return Flurry
	end
	if Frostbolt:usable() then
		return Frostbolt
	end
	if PlayerIsMoving() then
		self:movement()
	end
	if IceLance:usable() then
		return IceLance
	end
end

APL[SPEC.FROST].aoe = function(self)
	if Freeze:usable() and not TargetIsFrozen() then
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
actions.aoe+=/glacial_spike
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
		if Freeze:usable() and not TargetIsFrozen() then
			UseExtra(Freeze)
		end
		return CometStorm
	end
	if IceNova:usable() then
		if Freeze:usable() and not TargetIsFrozen() and (not CometStorm.known or CometStorm:cooldown() > 25) then
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
	if Ebonbolt:usable() and (Ebonbolt:castTime() + GCD()) < Target.timeToDie then
		return Ebonbolt
	end
	if GlacialSpike:usable() and (GlacialSpike:castTime() + GCD()) < Target.timeToDie then
		return GlacialSpike
	end
--[[
	if ConeOfCold:usable() and Enemies() >= 5 then
		UseExtra(ConeOfCold)
	end
]]
	if IceLance:usable() and TargetIsFrozen() and not IceLance:previous() then
		return IceLance
	end
	if Frostbolt:usable() then
		return Frostbolt
	end
	if PlayerIsMoving() then
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
		var.interrupt = nil
		amagicInterruptPanel:Hide()
		return
	end
	var.interrupt = APL.Interrupt()
	if var.interrupt then
		amagicInterruptPanel.icon:SetTexture(var.interrupt.icon)
		amagicInterruptPanel.icon:Show()
		amagicInterruptPanel.border:Show()
	else
		amagicInterruptPanel.icon:Hide()
		amagicInterruptPanel.border:Hide()
	end
	amagicInterruptPanel:Show()
	amagicInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
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
			(Opt.glow.main and var.main and icon == var.main.icon) or
			(Opt.glow.cooldown and var.cd and icon == var.cd.icon) or
			(Opt.glow.interrupt and var.interrupt and icon == var.interrupt.icon) or
			(Opt.glow.extra and var.extra and icon == var.extra.icon)
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
	return (currentSpec == SPEC.NONE or
		   (currentSpec == SPEC.ARCANE and Opt.hide.arcane) or
		   (currentSpec == SPEC.FIRE and Opt.hide.fire) or
		   (currentSpec == SPEC.FROST and Opt.hide.frost))

end

local function Disappear()
	amagicPanel:Hide()
	amagicPanel.icon:Hide()
	amagicPanel.border:Hide()
	amagicCooldownPanel:Hide()
	amagicInterruptPanel:Hide()
	amagicExtraPanel:Hide()
	var.main, var.last_main = nil
	var.cd, var.last_cd = nil
	var.interrupt = nil
	var.extra, var.last_extra = nil
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

local function UpdateDraggable()
	amagicPanel:EnableMouse(Opt.aoe or not Opt.locked)
	if Opt.aoe then
		amagicPanel.button:Show()
	else
		amagicPanel.button:Hide()
	end
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
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.FIRE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		}
	},
	['kui'] = {
		[SPEC.ARCANE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.FIRE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
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
		local p = ResourceFramePoints[resourceAnchor.name][currentSpec][Opt.snap]
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
		resourceAnchor.frame = NamePlatePlayerResourceFrame
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

local function UpdateHealthArray()
	Target.healthArray = {}
	local i
	for i = 1, floor(3 / Opt.frequency) do
		Target.healthArray[i] = 0
	end
end

local function UpdateCombat()
	abilityTimer = 0
	UpdateVars()
	var.main = APL[currentSpec]:main()
	if var.main ~= var.last_main then
		if var.main then
			amagicPanel.icon:SetTexture(var.main.icon)
			amagicPanel.icon:Show()
			amagicPanel.border:Show()
		else
			amagicPanel.icon:Hide()
			amagicPanel.border:Hide()
		end
	end
	if var.cd ~= var.last_cd then
		if var.cd then
			amagicCooldownPanel.icon:SetTexture(var.cd.icon)
			amagicCooldownPanel:Show()
		else
			amagicCooldownPanel:Hide()
		end
	end
	if var.extra ~= var.last_extra then
		if var.extra then
			amagicExtraPanel.icon:SetTexture(var.extra.icon)
			amagicExtraPanel:Show()
		else
			amagicExtraPanel:Hide()
		end
	end
	if Opt.dimmer then
		if not var.main then
			amagicPanel.dimmer:Hide()
		elseif var.main.spellId and IsUsableSpell(var.main.spellId) then
			amagicPanel.dimmer:Hide()
		elseif var.main.itemId and IsUsableItem(var.main.itemId) then
			amagicPanel.dimmer:Hide()
		else
			amagicPanel.dimmer:Show()
		end
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
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
			if start <= 0 then
				return amagicPanel.swipe:Hide()
			end
		end
		amagicPanel.swipe:SetCooldown(start, duration)
		amagicPanel.swipe:Show()
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
		InitializeVariables()
		Azerite:initialize()
		UpdateHealthArray()
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

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName, spellSchool, extraType = CombatLogGetCurrentEventInfo()
	if Opt.auto_aoe then
		if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
			if dstGUID == var.player then
				autoAoe:add(srcGUID)
			elseif srcGUID == var.player then
				autoAoe:add(dstGUID)
			end
		elseif eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
			autoAoe:remove(dstGUID)
		end
	end
	if srcGUID ~= var.player and srcGUID ~= var.pet then
		return
	end
	local castedAbility = abilityBySpellId[spellId]
	if not castedAbility then
		return
	end
--[[ DEBUG ]
	print(format('EVENT %s TRACK CHECK FOR %s ID %d', eventType, spellName, spellId))
	if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' or eventType == 'SPELL_PERIODIC_DAMAGE' or eventType == 'SPELL_DAMAGE' then
		print(format('%s: %s - time: %.2f - time since last: %.2f', eventType, spellName, timeStamp, timeStamp - (castedAbility.last_trigger or timeStamp)))
		castedAbility.last_trigger = timeStamp
	end
--[ DEBUG ]]
	if eventType == 'SPELL_CAST_SUCCESS' then
		var.last_ability = castedAbility
		castedAbility.last_used = GetTime()
		if castedAbility.triggers_gcd then
			PreviousGCD[10] = nil
			table.insert(PreviousGCD, 1, castedAbility)
		end
		if castedAbility.travel_start then
			castedAbility.travel_start[dstGUID] = castedAbility.last_used
		end
		if Opt.previous and amagicPanel:IsVisible() then
			amagicPreviousPanel.ability = castedAbility
			amagicPreviousPanel.border:SetTexture('Interface\\AddOns\\Automagically\\border.blp')
			amagicPreviousPanel.icon:SetTexture(castedAbility.icon)
			amagicPreviousPanel:Show()
		end
		return
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if castedAbility.travel_start and castedAbility.travel_start[dstGUID] then
			castedAbility.travel_start[dstGUID] = nil
		end
		if Opt.auto_aoe and castedAbility.auto_aoe then
			castedAbility:recordTargetHit(dstGUID)
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and amagicPanel:IsVisible() and castedAbility == amagicPreviousPanel.ability then
			amagicPreviousPanel.border:SetTexture('Interface\\AddOns\\Automagically\\misseffect.blp')
		end
		if currentSpec == SPEC.FROST and dstGUID == Target.guid and Target.freezable == '?' then
			if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
				if castedAbility == Chilled or castedAbility == FrostNova or castedAbility == IceNova or castedAbility == Freeze or castedAbility == ConeOfCold or castedAbility == GlacialSpike then
					Target.freezable = true
				end
			elseif eventType == 'SPELL_MISSED' and extraType == 'IMMUNE' then
				if castedAbility == Freeze then
					Target.freezable = false
				end
			end
		end
	end
	if castedAbility.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
			castedAbility:applyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' or eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
			castedAbility:removeAura(dstGUID)
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
		Target.hostile = true
		Target.freezable = '?'
		local i
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateCombat()
			amagicPanel:Show()
			return true
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		Target.freezable = '?'
		local i
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.level = UnitLevel('target')
	if UnitIsPlayer('target') then
		Target.boss = false
	elseif Target.level == -1 then
		Target.boss = true
	elseif var.instance == 'party' and Target.level >= UnitLevel('player') + 2 then
		Target.boss = true
	else
		Target.boss = false
	end
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or Opt.always_on then
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
	combatStartTime = GetTime()
end

function events:PLAYER_REGEN_ENABLED()
	combatStartTime = 0
	local _, ability, guid
	for _, ability in next, abilities do
		if ability.travel_start then
			for guid in next, ability.travel_start do
				ability.travel_start[guid] = nil
			end
		end
		if ability.aura_targets then
			for guid in next, ability.aura_targets do
				ability.aura_targets[guid] = nil
			end
		end
	end
	if Opt.auto_aoe then
		for guid in next, autoAoe.targets do
			autoAoe.targets[guid] = nil
		end
		SetTargetMode(1)
	end
	if var.last_ability then
		var.last_ability = nil
		amagicPreviousPanel:Hide()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()

end

local function UpdateAbilityData()
	local _, ability
	for _, ability in next, abilities do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = (IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) or Azerite.traits[ability.spellId]) and true or false
	end
	if SummonWaterElemental.known then
		Freeze.known = true
	end
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		Azerite:update()
		UpdateAbilityData()
		local _, i
		for i = 1, #inventoryItems do
			inventoryItems[i].name, _, _, _, _, _, _, _, _, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId)
		end
		amagicPreviousPanel.ability = nil
		PreviousGCD = {}
		currentSpec = GetSpecialization() or 0
		SetTargetMode(1)
		UpdateTargetInfo()
	end
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, var.instance = IsInInstance()
	var.player = UnitGUID('player')
	UpdateVars()
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
	abilityTimer = abilityTimer + elapsed
	if abilityTimer >= Opt.frequency then
		trackAuras:purge()
		if Opt.auto_aoe then
			local _, ability
			for _, ability in next, autoAoe.abilities do
				ability:updateTargetsHit()
			end
			autoAoe:purge()
		end
		UpdateCombat()
	end
end)

amagicPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	amagicPanel:RegisterEvent(event)
end

function SlashCmdList.Automagically(msg, editbox)
	msg = { strsplit(' ', strlower(msg)) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return print('Automagically - Locked: ' .. (Opt.locked and '|cFF00C000On' or '|cFFC00000Off'))
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
		return print('Automagically - Snap to Blizzard combat resources frame: ' .. (Opt.snap and ('|cFF00C000' .. Opt.snap) or '|cFFC00000Off'))
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				amagicPreviousPanel:SetScale(Opt.scale.previous)
			end
			return print('Automagically - Previous ability icon scale set to: |cFFFFD000' .. Opt.scale.previous .. '|r times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				amagicPanel:SetScale(Opt.scale.main)
			end
			return print('Automagically - Main ability icon scale set to: |cFFFFD000' .. Opt.scale.main .. '|r times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				amagicCooldownPanel:SetScale(Opt.scale.cooldown)
			end
			return print('Automagically - Cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.cooldown .. '|r times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				amagicInterruptPanel:SetScale(Opt.scale.interrupt)
			end
			return print('Automagically - Interrupt ability icon scale set to: |cFFFFD000' .. Opt.scale.interrupt .. '|r times')
		end
		if startsWith(msg[2], 'to') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				amagicExtraPanel:SetScale(Opt.scale.extra)
			end
			return print('Automagically - Extra cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.extra .. '|r times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('Automagically - Action button glow scale set to: |cFFFFD000' .. Opt.scale.glow .. '|r times')
		end
		return print('Automagically - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
		end
		return print('Automagically - Icon transparency set to: |cFFFFD000' .. Opt.alpha * 100 .. '%|r')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.05
			UpdateHealthArray()
		end
		return print('Automagically - Calculation frequency: Every |cFFFFD000' .. Opt.frequency .. '|r seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Automagically - Glowing ability buttons (main icon): ' .. (Opt.glow.main and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Automagically - Glowing ability buttons (cooldown icon): ' .. (Opt.glow.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Automagically - Glowing ability buttons (interrupt icon): ' .. (Opt.glow.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Automagically - Glowing ability buttons (extra icon): ' .. (Opt.glow.extra and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Automagically - Blizzard default proc glow: ' .. (Opt.glow.blizzard and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return print('Automagically - Glow color:', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return print('Automagically - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Automagically - Previous ability icon: ' .. (Opt.previous and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Automagically - Show the Automagically UI without a target: ' .. (Opt.always_on and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return print('Automagically - Use Automagically for cooldown management: ' .. (Opt.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
			if not Opt.spell_swipe then
				amagicPanel.swipe:Hide()
			end
		end
		return print('Automagically - Spell casting swipe animation: ' .. (Opt.spell_swipe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
			if not Opt.dimmer then
				amagicPanel.dimmer:Hide()
			end
		end
		return print('Automagically - Dim main ability icon when you don\'t have enough mana to use it: ' .. (Opt.dimmer and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return print('Automagically - Red border around previous ability when it fails to hit: ' .. (Opt.miss_effect and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			SetTargetMode(1)
			UpdateDraggable()
		end
		return print('Automagically - Allow clicking main ability icon to toggle amount of targets (disables moving): ' .. (Opt.aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return print('Automagically - Only use cooldowns on bosses: ' .. (Opt.boss_only and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.arcane = not Opt.hide.arcane
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Automagically - BeastMastery specialization: |cFFFFD000' .. (Opt.hide.arcane and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'm') then
				Opt.hide.fire = not Opt.hide.fire
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Automagically - Marksmanship specialization: |cFFFFD000' .. (Opt.hide.fire and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 's') then
				Opt.hide.frost = not Opt.hide.frost
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Automagically - Survival specialization: |cFFFFD000' .. (Opt.hide.frost and '|cFFC00000Off' or '|cFF00C000On'))
			end
		end
		return print('Automagically - Possible hidespec options: |cFFFFD000arcane|r/|cFFFFD000fire|r/|cFFFFD000frost|r - toggle disabling Automagically for specializations')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return print('Automagically - Show an icon for interruptable spells: ' .. (Opt.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return print('Automagically - Automatically change target mode on AoE spells: ' .. (Opt.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return print('Automagically - Length of time target exists in auto AoE after being hit: |cFFFFD000' .. Opt.auto_aoe_ttl .. '|r seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return print('Automagically - Show Battle potions in cooldown UI: ' .. (Opt.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'reset' then
		amagicPanel:ClearAllPoints()
		amagicPanel:SetPoint('CENTER', 0, -169)
		SnapAllPanels()
		return print('Automagically - Position has been reset to default')
	end
	print('Automagically (version: |cFFFFD000' .. GetAddOnMetadata('Automagically', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Automagically UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Automagically UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Automagically UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Automagically UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
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
		'pot |cFF00C000on|r/|cFFC00000off|r - show Battle potions in cooldown UI',
		'|cFFFFD000reset|r - reset the location of the Automagically UI to default',
	} do
		print('  ' .. SLASH_Automagically1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Contact |cFF40C7EBIcicles|cFFFFD000-Dalaran|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end
