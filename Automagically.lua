local ADDON = 'Automagically'
if select(2, UnitClass('player')) ~= 'MAGE' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

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
local Opt

SLASH_Automagically1, SLASH_Automagically2, SLASH_Automagically3 = '/am', '/amagic', '/auto'
BINDING_HEADER_AUTOMAGICALLY = ADDON

local function InitOpts()
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
		cd_ttd = 8,
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

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- specialization constants
local SPEC = {
	NONE = 0,
	ARCANE = 1,
	FIRE = 2,
	FROST = 3,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	target_mode = 0,
	execute_remains = 0,
	haste_factor = 1,
	gcd = 1.5,
	gcd_remains = 0,
	health = 0,
	health_max = 0,
	mana = 0,
	mana_base = 0,
	mana_max = 0,
	mana_regen = 0,
	arcane_charges = 0,
	arcane_charges_max = 0,
	moving = false,
	movement_speed = 100,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health_array = {},
	hostile = false,
	estimated_range = 30,
}

-- base mana by player level
local BaseMana = {
	52,   54,   57,   60,   62,   66,   69,   72,   76,   80,
	86,   93,   101,  110,  119,  129,  140,  152,  165,  178,
	193,  210,  227,  246,  267,  289,  314,  340,  369,  400,
	433,  469,  509,  551,  598,  648,  702,  761,  825,  894,
	969,  1050, 1138, 1234, 1337, 1449, 1571, 1702, 1845, 2000,
	2349, 2759, 3241, 3807, 4472, 5253, 6170, 7247, 8513, 10000
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
amagicPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
amagicPanel.text.tl = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.text.tl:SetPoint('TOPLEFT', amagicPanel, 'TOPLEFT', 2.5, -3)
amagicPanel.text.tl:SetJustifyH('LEFT')
amagicPanel.text.tl:SetJustifyV('TOP')
amagicPanel.text.tr = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.text.tr:SetPoint('TOPRIGHT', amagicPanel, 'TOPRIGHT', -2.5, -3)
amagicPanel.text.tr:SetJustifyH('RIGHT')
amagicPanel.text.tr:SetJustifyV('TOP')
amagicPanel.text.bl = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.text.bl:SetPoint('BOTTOMLEFT', amagicPanel, 'BOTTOMLEFT', 2.5, 3)
amagicPanel.text.bl:SetJustifyH('LEFT')
amagicPanel.text.bl:SetJustifyV('BOTTOM')
amagicPanel.text.br = amagicPanel.text:CreateFontString(nil, 'OVERLAY')
amagicPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
amagicPanel.text.br:SetPoint('BOTTOMRIGHT', amagicPanel, 'BOTTOMRIGHT', -2.5, 3)
amagicPanel.text.br:SetJustifyH('RIGHT')
amagicPanel.text.br:SetJustifyV('BOTTOM')
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
amagicPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
amagicCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
amagicInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
amagicInterruptPanel.cast = CreateFrame('Cooldown', nil, amagicInterruptPanel, 'CooldownFrameTemplate')
amagicInterruptPanel.cast:SetAllPoints(amagicInterruptPanel)
amagicInterruptPanel.cast:SetDrawBling(false)
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
		{4, '4+'},
	},
	[SPEC.FIRE] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.FROST] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	}
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

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
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

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
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

function autoAoe:Purge()
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
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
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
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
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
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable(seconds)
	if not self.known then
		return false
	end
	if self:Cost() > Player.mana then
		return false
	end
	if self.requires_pet and not Player.pet_active then
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
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
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

function Ability:Up(condition)
	return self:Remains(condition) > 0
end

function Ability:Down(condition)
	return self:Remains(condition) <= 0
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
	local count, cast, _ = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:Cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana_base) or 0
end

function Ability:Charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:CastRegen()
	return Player.mana_regen * self:CastTime() - self:Cost()
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
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
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		self.auto_aoe.target_count = 0
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID, timeStamp)
	self.last_used = timeStamp
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
end

function Ability:CastLanded(dstGUID, timeStamp, eventType)
	if not self.traveling then
		return
	end
	local guid, cast, oldest
	for guid, cast in next, self.traveling do
		if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
			self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
		elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
			oldest = cast
		end
	end
	if oldest then
		Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, timeStamp - oldest.start)))
		self.traveling[oldest.guid] = nil
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Mage Abilities
---- Multiple Specializations
local ArcaneIntellect = Ability:Add(1459, true, false)
ArcaneIntellect.mana_cost = 4
ArcaneIntellect.buff_duration = 3600
local Blink = Ability:Add(1953, true, true)
Blink.mana_cost = 2
Blink.cooldown_duration = 15
local Counterspell = Ability:Add(2139, false, true)
Counterspell.mana_cost = 2
Counterspell.cooldown_duration = 24
Counterspell.triggers_gcd = false
local TimeWarp = Ability:Add(80353, true, true)
TimeWarp.mana_cost = 4
TimeWarp.buff_duration = 40
TimeWarp.cooldown_duration = 300
TimeWarp.triggers_gcd = false
------ Procs

------ Talents
local IncantersFlow = Ability:Add(116267, true, true, 236219)
local MirrorImage = Ability:Add(55342, true, true)
MirrorImage.mana_cost = 2
MirrorImage.buff_duration = 40
MirrorImage.cooldown_duration = 120
local RuneOfPower = Ability:Add(116011, true, true, 116014)
RuneOfPower.buff_duration = 12
RuneOfPower.cooldown_duration = 45
local Shimmer = Ability:Add(212653, true, true)
Shimmer.mana_cost = 2
Shimmer.cooldown_duration = 20
Shimmer.requires_charge = true
Shimmer.triggers_gcd = false
---- Arcane
local ArcaneBarrage = Ability:Add(44425, false, true)
ArcaneBarrage.cooldown_duration = 3
ArcaneBarrage.hasted_cooldown = true
ArcaneBarrage:SetVelocity(25)
ArcaneBarrage:AutoAoe()
local ArcaneBlast = Ability:Add(30451, false, true)
ArcaneBlast.mana_cost = 2.75
local ArcaneExplosion = Ability:Add(1449, false, true)
ArcaneExplosion.mana_cost = 10
ArcaneExplosion:AutoAoe()
local ArcaneMissiles = Ability:Add(5143, false, true, 7268)
ArcaneMissiles.mana_cost = 15
ArcaneMissiles:SetVelocity(50)
local ArcanePower = Ability:Add(12042, true, true)
ArcanePower.buff_duration = 10
ArcanePower.cooldown_duration = 90
local Evocation = Ability:Add(12051, true, true)
Evocation.buff_duration = 6
Evocation.cooldown_duration = 90
local PrismaticBarrier = Ability:Add(235450, true, true)
PrismaticBarrier.mana_cost = 3
PrismaticBarrier.buff_duration = 60
PrismaticBarrier.cooldown_duration = 25
local PresenceOfMind = Ability:Add(205025, true, true)
PresenceOfMind.cooldown_duration = 60
PresenceOfMind.triggers_gcd = false
------ Talents
local Amplification = Ability:Add(236628, false, true)
local ArcaneFamiliar = Ability:Add(205022, true, true, 210126)
ArcaneFamiliar.buff_duration = 3600
ArcaneFamiliar.cooldown_duration = 10
local ArcaneOrb = Ability:Add(153626, false, true, 153640)
ArcaneOrb.mana_cost = 1
ArcaneOrb.cooldown_duration = 20
ArcaneOrb:AutoAoe()
local ChargedUp = Ability:Add(205032, true, true)
ChargedUp.cooldown_duration = 40
local NetherTempest = Ability:Add(114923, false, true, 114954)
NetherTempest.mana_cost = 1.5
NetherTempest.buff_duration = 12
NetherTempest.tick_interval = 1
NetherTempest.hasted_ticks = true
NetherTempest:AutoAoe()
local Overpowered = Ability:Add(155147, false, true)
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
local BlazingBarrier = Ability:Add(235313, true, true)
BlazingBarrier.mana_cost = 3
BlazingBarrier.buff_duration = 60
BlazingBarrier.cooldown_duration = 25
local Combustion = Ability:Add(190319, true, true)
Combustion.mana_cost = 10
Combustion.buff_duration = 10
Combustion.cooldown_duration = 120
Combustion.triggers_gcd = false
local DragonsBreath = Ability:Add(31661, false, true)
DragonsBreath.mana_cost = 4
DragonsBreath.buff_duration = 4
DragonsBreath.cooldown_duration = 20
DragonsBreath:AutoAoe()
local Fireball = Ability:Add(133, false, true)
Fireball.mana_cost = 2
Fireball:SetVelocity(45)
local FireBlast = Ability:Add(108853, false, true)
FireBlast.mana_cost = 1
FireBlast.cooldown_duration = 12
FireBlast.hasted_cooldown = true
FireBlast.requires_charge = true
FireBlast.triggers_gcd = false
local Flamestrike = Ability:Add(2120, false, true)
Flamestrike.mana_cost = 2.5
Flamestrike.buff_duration = 8
Flamestrike:AutoAoe()
local Ignite = Ability:Add(12846, false, true, 12654)
Ignite.buff_duration = 9
Ignite.tick_interval = 1
Ignite:AutoAoe(false, 'apply')
local Pyroblast = Ability:Add(11366, false, true)
Pyroblast.mana_cost = 2
Pyroblast:SetVelocity(35)
local Scorch = Ability:Add(2948, false, true)
Scorch.mana_cost = 1
------ Talents
local AlexstraszasFury = Ability:Add(235870, false, true)
local BlastWave = Ability:Add(157981, false, true)
BlastWave.buff_duration = 4
BlastWave.cooldown_duration = 25
local Conflagration = Ability:Add(205023, false, true, 226757)
Conflagration.buff_duration = 8
Conflagration.tick_interval = 2
Conflagration.hasted_ticks = true
local Firestarter = Ability:Add(205026, false, true)
local FlameOn = Ability:Add(205029, false, true)
local FlamePatch = Ability:Add(205037, false, true, 205472)
local Kindling = Ability:Add(155148, false, true)
local LivingBomb = Ability:Add(44457, false, true, 217694)
LivingBomb.buff_duration = 4
LivingBomb.mana_cost = 1.5
LivingBomb.cooldown_duration = 12
LivingBomb.tick_interval = 1
LivingBomb.hasted_duration = true
LivingBomb.hasted_cooldown = true
LivingBomb.hasted_ticks = true
LivingBomb.explosion = Ability:Add(44461, false, true)
LivingBomb.explosion:AutoAoe()
LivingBomb.spread = Ability:Add(44461, false, true)
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
PhoenixFlames.cooldown_duration = 30
PhoenixFlames.requires_charge = true
PhoenixFlames:SetVelocity(50)
PhoenixFlames:AutoAoe()
local Pyroclasm = Ability:Add(269650, false, true, 269651)
Pyroclasm.buff_duration = 15
local SearingTouch = Ability:Add(269644, false, true)
------ Procs
local HeatingUp = Ability:Add(48107, true, true)
HeatingUp.buff_duration = 10
local HotStreak = Ability:Add(195283, true, true, 48108)
HotStreak.buff_duration = 15
---- Frost
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
local ConeOfCold = Ability:Add(120, false, true)
ConeOfCold.mana_cost = 4
ConeOfCold.buff_duration = 5
ConeOfCold.cooldown_duration = 12
ConeOfCold:AutoAoe()
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
local Frostbolt = Ability:Add(116, false, true, 228597)
Frostbolt.mana_cost = 2
Frostbolt:SetVelocity(35)
local FrostNova = Ability:Add(122, false, true)
FrostNova.mana_cost = 2
FrostNova.buff_duration = 8
FrostNova:AutoAoe()
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
------ Talents
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
local IceNova = Ability:Add(157997, false, true)
IceNova.buff_duration = 2
IceNova.cooldown_duration = 25
IceNova:AutoAoe()
local LonelyWinter = Ability:Add(205024, false, true)
local RayOfFrost = Ability:Add(205021, false, true)
RayOfFrost.mana_cost = 2
RayOfFrost.buff_duration = 5
RayOfFrost.cooldown_duration = 75
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
-- PvP talents
local BurstOfCold = Ability:Add(206431, true, true, 206432)
BurstOfCold.buff_duration = 6
local Frostbite = Ability:Add(198120, false, true, 198121)
Frostbite.buff_duration = 4
-- Racials

-- Covenant abilities
local MirrorsOfTorment = Ability:Add(314793, false, true) -- Venthyr
MirrorsOfTorment.cooldown_duration = 90
MirrorsOfTorment.buff_duration = 25
local ShiftingPower = Ability:Add(314791, false, true, 325130) -- Night Fae
ShiftingPower.cooldown_duration = 60
ShiftingPower:AutoAoe()
local FieldOfBlossoms = Ability:Add(319191, true, true, 342774) -- Night Fae, Dreamweaver, Redirected Anima
FieldOfBlossoms.buff_duration = 12
local GroveInvigoration = Ability:Add(322721, true, true, 342814) -- Night Fae, Niya, Redirected Anima
GroveInvigoration.buff_duration = 30
local WastelandPropriety = Ability:Add(319983, true, true, 333218)
WastelandPropriety.buff_duration = 10
-- Soulbind conduits
local SiphonedMalice = Ability:Add(337087, true, true, 337090)
SiphonedMalice.buff_duration = 10
SiphonedMalice.conduit_id = 43
-- Legendary effects
local FreezingWinds = Ability:Add(327364, true, true, 327478)
FreezingWinds.buff_duration = 12
FreezingWinds.bonus_id = 6829
local GlacialFragments = Ability:Add(327492, false, true, 327498)
GlacialFragments.bonus_id = 6830
GlacialFragments:AutoAoe()
local SlickIce = Ability:Add(327508, true, true, 327509)
SlickIce.buff_duration = 60
SlickIce.bonus_id = 6823
-- Trinket effects

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
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
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
local SpectralFlaskOfPower = InventoryItem:Add(171276)
SpectralFlaskOfPower.buff = Ability:Add(307185, true, true)
local PotionOfSpectralIntellect = InventoryItem:Add(171273)
PotionOfSpectralIntellect.buff = Ability:Add(307162, true, true)
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Player API

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:ManaDeficit()
	return self.mana_max - self.mana
end

function Player:ManaPct()
	return self.mana / self.mana_max * 100
end

function Player:ManaTimeToMax()
	local deficit = self.mana_max - self.mana
	if deficit <= 0 then
		return 0
	end
	return deficit / self.mana_regen
end

function Player:ArcaneCharges()
	if ArcaneBlast:Casting() then
		return min(4, Player.arcane_charges + 1)
	end
	return Player.arcane_charges
end

function Player:UnderAttack()
	return (Player.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
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
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
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

function Player:BonusIdEquipped(bonusId)
	local i, id, link, item
	for i = 1, 19 do
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

function Player:UpdateAbilities()
	Player.mana_base = BaseMana[UnitLevel('player')] * 5
	Player.arcane_charges_max = UnitPowerMax('player', 16)

	local _, ability, spellId, node

	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		end
		if ability.bonus_id then -- used for checking Legendary crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.conduit_id then
			node = C_Soulbinds.FindNodeIDActuallyInstalled(C_Soulbinds.GetActiveSoulbindID(), ability.conduit_id)
			if node then
				node = C_Soulbinds.GetNode(node)
				if node and node.state == 3 then
					ability.known = true
				end
			end
		end
	end

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

function Player:UpdatePet()
	self.pet = UnitGUID('pet')
	self.pet_alive = (self.pet and not UnitIsDead('pet') or (self.ability_casting and self.ability_casting.pet_family)) and true
	self.pet_active = (self.pet_alive and not self.pet_stuck or IsFlying()) and true
end

function Player:Update()
	local _, start, duration, remains, spellId, speed, max_speed
	self.ctime = GetTime()
	self.time = self.ctime - self.time_diff
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.execute_remains = max(remains and (remains / 1000 - self.ctime) or 0, self.gcd_remains)
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	self.health = UnitHealth('player')
	self.health_max = UnitHealthMax('player')
	self.mana_regen = GetPowerRegen()
	self.mana = UnitPower('player', 0) + (self.mana_regen * self.execute_remains)
	self.mana_max = UnitPowerMax('player', 0)
	if self.ability_casting then
		self.mana = self.mana - self.ability_casting:Cost()
	end
	self.mana = min(max(self.mana, 0), self.mana_max)
	if self.spec == SPEC.ARCANE then
		self.arcane_charges = UnitPower('player', 16)
	end
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdatePet()

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	if Blizzard.known then
		Player.blizzard_remains = Blizzard:Remains()
	end
end

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.health_array, 1)
	self.health_array[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 40
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.health_array[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.hostile = true
		local i
		for i = 1, 25 do
			self.health_array[i] = 0
		end
		self:UpdateHealth()
		if Opt.always_on then
			UI:UpdateCombat()
			amagicPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			amagicPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		local i
		for i = 1, 25 do
			self.health_array[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		amagicPanel:Show()
		return true
	end
end

function Target:Frozen()
	return FrostNova:Up() or WintersChill:Up() or (IceNova.known and IceNova:Up()) or (Freeze.known and Freeze:Up()) or (GlacialSpike.known and GlacialSpike:Up()) or (Frostbite.known and Frostbite:Up())
end

-- End Target API

-- Start Ability Modifications

function Ability:Cost()
	if self.mana_cost == 0 then
		return 0
	end
	local cost = self.mana_cost / 100 * Player.mana_base
	if ArcanePower.known and ArcanePower:Up() then
		cost = cost - cost * 0.60
	end
	return cost
end

function ArcaneBlast:Cost()
	if Ability.Up(RuleOfThrees) then
		return 0
	end
	return Ability.Cost(self) * (Player:ArcaneCharges() + 1)
end

function ArcaneExplosion:Cost()
	if Clearcasting:Up() then
		return 0
	end
	return Ability.Cost(self)
end

function ArcaneMissiles:Cost()
	if RuleOfThrees:Up() or Clearcasting:Up() then
		return 0
	end
	return Ability.Cost(self)
end

function RuleOfThrees:Remains()
	if ArcaneBlast:Casting() then
		return 0
	end
	return Ability.Remains(self)
end

function PresenceOfMind:Cooldown()
	if self:Up() then
		return self.cooldown_duration
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
	return Ability.Usable(self)
end

function Blizzard:Remains()
	if self:Casting() then
		return self:Duration()
	end
	return max((self.last_used or 0) + (self.ground_duration or self.buff_duration) - Player.time - Player.execute_remains, 0)
end

function BrainFreeze:Remains()
	if Ebonbolt:Casting() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function FrozenOrb:Remains()
	return max((self.last_used or 0) + self.buff_duration - Player.time - Player.execute_remains, 0)
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

function RuneOfPower:Remains()
	if self:Casting() then
		return self:Duration()
	end
	return max((self.summon_time or 0) + self.buff_duration - Player.time - Player.execute_remains, 0)
end

function Firestarter:Remains()
	if not Firestarter.known or Target.healthPercentage <= 90 then
		return 0
	end
	if Target.healthLostPerSec <= 0 then
		return 600
	end
	local health_above_90 = (Target.health - (Target.healthLostPerSec * Player.execute_remains)) - (Target.healthMax * 0.9)
	return health_above_90 / Target.healthLostPerSec
end

function SearingTouch:Remains()
	return SearingTouch.known and Target.healthPercentage < 30 and 600 or 0
end

function HeatingUp:Remains()
	if Scorch:Casting() and SearingTouch:Up() then
		if Ability.Remains(self) > 0 or Ability.Remains(HotStreak) > 0 then
			return 0
		end
		return self:Duration()
	end
	return Ability.Remains(self)
end

function HotStreak:Remains()
	if Scorch:Casting() and SearingTouch:Up() and Ability.Remains(HeatingUp) > 0 then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function Blizzard:CastSuccess(dstGUID, timeStamp)
	Ability.CastSuccess(self, dstGUID, timeStamp)
	self.ground_duration = self:Duration()
end

function ArcanePower:CastSuccess(dstGUID, timeStamp)
	Ability.CastSuccess(self, dstGUID, timeStamp)
	APL[SPEC.ARCANE]:toggle_burn_phase(true)
end

function Evocation:CastSuccess(dstGUID, timeStamp)
	Ability.CastSuccess(self, dstGUID, timeStamp)
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
actions.precombat+=/potion
actions.precombat+=/arcane_blast
]]
	if Player:TimeInCombat() == 0 then
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 300 then
			return ArcaneIntellect
		end
		if ArcaneFamiliar:Usable() and ArcaneFamiliar:Remains() < 300 then
			return ArcaneFamiliar
		end
		if not Player:InArenaOrBattleground() then
			if Opt.pot and PotionOfSpectralIntellect:Usable() then
				UseCooldown(PotionOfSpectralIntellect)
			end
		end
		if ArcaneBlast:Usable() and not ArcaneBlast:Casting() then
			return ArcaneBlast
		end
	else
		if ArcaneIntellect:Down() and ArcaneIntellect:Usable() then
			UseExtra(ArcaneIntellect)
		elseif ArcaneFamiliar:Usable() and ArcaneFamiliar:Down() then
			UseExtra(ArcaneFamiliar)
		elseif MirrorImage:Usable() and Player:UnderAttack() then
			UseExtra(MirrorImage)
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
	if ArcanePower:Ready() and Evocation:Ready(max(Player.average_burn_length, 20)) and (Player:ArcaneCharges() == 4 or (ChargedUp.known and ChargedUp:Ready() and Player:ArcaneCharges() <= 1)) then
		apl = self:burn()
		if apl then return apl end
	end
	if not Player.burn_phase then
		if (Evocation:Usable() and Player:ManaPct() < 25) or (Evocation:Channeling() and Player:ManaPct() < 85) then
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
		if Evocation:Previous() and Target.timeToDie > Player.average_burn_length and Player.burn_phase_duration > 0 then
			self:toggle_burn_phase(false)
			return
		end
	else
		self:toggle_burn_phase(true)
	end
	if ChargedUp:Usable() and Player:ArcaneCharges() <= 1 then
		UseCooldown(ChargedUp)
	end
	if NetherTempest:Usable() and NetherTempest:Refreshable() and Player:ArcaneCharges() == 4 and not (RuneOfPower:Up() and ArcanePower:Up()) then
		return NetherTempest
	end
	if RuleOfThrees.known and Overpowered.known and Player.enemies < 3 and ArcaneBlast:Usable() and RuleOfThrees:Up() then
		return ArcaneBlast
	end
	if RuneOfPower:Usable() and RuneOfPower:Down() and ArcanePower:Down() and (Player:ManaPct() >= 50 or ArcanePower:Ready()) and Player:ArcaneCharges() == 4 then
		UseCooldown(RuneOfPower)
	end
	if ArcanePower:Usable() and RuneOfPower:Remains() > 6 then
		UseCooldown(ArcanePower)
	end
	if Opt.trinket and (ArcanePower:Up() or (Target.boss and Target.timeToDie < 15)) then
		if Trinket1:Usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			UseCooldown(Trinket2)
		end
	end
	if PresenceOfMind:Usable() and ((RuneOfPower:Up() and RuneOfPower:Remains() <= (2 * ArcaneBlast:CastTime())) or (ArcanePower:Up() and ArcanePower:Remains() <= (2 * ArcaneBlast:CastTime()))) then
		UseCooldown(PresenceOfMind)
	end
	if Opt.pot and PotionOfSpectralIntellect:Usable() and ArcanePower:Up() then
		UseExtra(PotionOfSpectralIntellect)
	end
	if ArcaneOrb:Usable() and (Player:ArcaneCharges() == 0 or Player.enemies < (Resonance.known and 2 or 3)) then
		UseCooldown(ArcaneOrb)
	end
	if Player.enemies >= 3 then
		if RuleOfThrees.known and Player.enemies < 6 and ArcaneBlast:Usable() and Player:ArcaneCharges() > 3 and RuleOfThrees:Up() then
			return ArcaneBlast
		end
		if ArcaneBarrage:Usable() and Player:ArcaneCharges() == 4 then
			return ArcaneBarrage
		end
		if ArcaneExplosion:Usable() then
			return ArcaneExplosion
		end
	else
		if ArcaneMissiles:Usable() and Clearcasting:Up() and (Amplification.known or (not Overpowered.known and ArcanePummeling:AzeriteRank() >= 2) or ArcanePower:Down()) then
			return ArcaneMissiles
		end
		if ArcaneBlast:Usable() then
			return ArcaneBlast
		end
	end
	self:toggle_burn_phase(false)
	if Evocation:Usable() then
		return Evocation
	end
	if ArcaneBarrage:Usable() then
		return ArcaneBarrage
	end
end

APL[SPEC.ARCANE].conserve = function(self)
--[[
actions.conserve=charged_up,if=buff.arcane_charge.stack=0
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
	if ChargedUp:Usable() and Player:ArcaneCharges() == 0 then
		UseCooldown(ChargedUp)
	end
	if NetherTempest:Usable() and NetherTempest:Refreshable() and Player:ArcaneCharges() == 4 and not (RuneOfPower:Up() and ArcanePower:Up()) then
		return NetherTempest
	end
	if ArcaneOrb:Usable() and Player:ArcaneCharges() <= 2 and (ArcanePower:Cooldown() > 10 or Player.enemies <= 2) then
		UseCooldown(ArcaneOrb)
	end
	if RuleOfThrees.known and ArcaneBlast:Usable() and Player:ArcaneCharges() > 3 and RuleOfThrees:Up() then
		return ArcaneBlast
	end
	if RuneOfPower:Usable() and RuneOfPower:Down() and Player:ArcaneCharges() == 4 and (RuneOfPower:FullRechargeTime() <= RuneOfPower:CastTime() or RuneOfPower:FullRechargeTime() <= ArcanePower:Cooldown() or Target.timeToDie <= ArcanePower:Cooldown()) then
		UseCooldown(RuneOfPower)
	end
	if ArcaneMissiles:Usable() and Player:ManaPct() <= 95 and Clearcasting:Up() and Player.enemies < 3 then
		return ArcaneMissiles
	end
	if ArcaneBarrage:Usable() and (Player:ManaPct() <= (Opt.conserve_mana - 10) or (Player:ArcaneCharges() == 4 and RuneOfPower:Remains() < ArcaneBlast:CastTime() and (Player:ManaPct() <= Opt.conserve_mana or (ArcanePower:Cooldown() > RuneOfPower:FullRechargeTime() and Player:ManaPct() <= Opt.conserve_mana + 25))) or (ArcaneOrb.known and ArcaneOrb:Ready(Player.gcd) and not ArcanePower:Ready(10))) then
		return ArcaneBarrage
	end
	if Supernova:Usable() and Player:ManaPct() <= 95 then
		UseCooldown(Supernova)
	end
	if ArcaneBarrage:Usable() and Player.enemies >= 3 and Player:ArcaneCharges() == 4 then
		return ArcaneBarrage
	end
	if ArcaneExplosion:Usable() and Player.enemies >= 3 and (Player:ManaPct() >= Opt.conserve_mana or Player:ArcaneCharges() == 3) then
		return ArcaneExplosion
	end
	if ArcaneBlast:Usable() then
		return ArcaneBlast
	end
	if ArcaneBarrage:Usable() then
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
	if Blink:Usable() then
		UseExtra(Blink)
	elseif Shimmer:Usable() then
		UseExtra(Shimmer)
	end
	if PresenceOfMind:Usable() then
		UseCooldown(PresenceOfMind)
	end
	if Slipstream.known and ArcaneMissiles:Usable() and Clearcasting:Up() then
		return ArcaneMissiles
	end
	if ArcaneOrb:Usable() then
		UseCooldown(ArcaneOrb)
	end
	if Supernova:Usable() then
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
actions.precombat+=/potion
actions.precombat+=/pyroblast
]]
	if Player:TimeInCombat() == 0 then
		Player.combustion_rop_cutoff = 60
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 300 then
			return ArcaneIntellect
		end
		if not Player:InArenaOrBattleground() then
			if Opt.pot and PotionOfSpectralIntellect:Usable() then
				UseCooldown(PotionOfSpectralIntellect)
			end
		end
		if Pyroblast:Usable() and not (Pyroblast:Casting() or Fireball:Casting()) then
			return Pyroblast
		end
	else
		if ArcaneIntellect:Down() and ArcaneIntellect:Usable() then
			UseExtra(ArcaneIntellect)
		elseif MirrorImage:Usable() and Player:UnderAttack() then
			UseExtra(MirrorImage)
		end
	end
--[[
actions=counterspell
actions+=/call_action_list,name=items_high_priority
actions+=/rune_of_power,if=talent.firestarter.enabled&firestarter.remains>full_recharge_time|cooldown.combustion.remains>variable.combustion_rop_cutoff&buff.combustion.down|target.time_to_die<cooldown.combustion.remains&buff.combustion.down
actions+=/call_action_list,name=combustion_phase,if=(talent.rune_of_power.enabled&cooldown.combustion.remains<=action.rune_of_power.cast_time|cooldown.combustion.ready)&!firestarter.active|buff.combustion.up
actions+=/fire_blast,use_while_casting=1,use_off_gcd=1,if=(essence.memory_of_lucid_dreams.major|essence.memory_of_lucid_dreams.minor&azerite.blaster_master.enabled)&charges=max_charges&!buff.hot_streak.react&!(buff.heating_up.react&(buff.combustion.up&(action.fireball.in_flight|action.pyroblast.in_flight|action.scorch.executing)|target.health.pct<=30&action.scorch.executing))&!(!buff.heating_up.react&!buff.hot_streak.react&buff.combustion.down&(action.fireball.in_flight|action.pyroblast.in_flight))
actions+=/call_action_list,name=rop_phase,if=buff.rune_of_power.up&buff.combustion.down
actions+=/variable,name=fire_blast_pooling,value=talent.rune_of_power.enabled&cooldown.rune_of_power.remains<cooldown.fire_blast.full_recharge_time&(cooldown.combustion.remains>variable.combustion_rop_cutoff|firestarter.active)&(cooldown.rune_of_power.remains<target.time_to_die|action.rune_of_power.charges>0)|cooldown.combustion.remains<action.fire_blast.full_recharge_time+cooldown.fire_blast.duration*azerite.blaster_master.enabled&!firestarter.active&cooldown.combustion.remains<target.time_to_die|talent.firestarter.enabled&firestarter.active&firestarter.remains<cooldown.fire_blast.full_recharge_time+cooldown.fire_blast.duration*azerite.blaster_master.enabled
actions+=/variable,name=phoenix_pooling,value=talent.rune_of_power.enabled&cooldown.rune_of_power.remains<cooldown.phoenix_flames.full_recharge_time&cooldown.combustion.remains>variable.combustion_rop_cutoff&(cooldown.rune_of_power.remains<target.time_to_die|action.rune_of_power.charges>0)|cooldown.combustion.remains<action.phoenix_flames.full_recharge_time&cooldown.combustion.remains<target.time_to_die
actions+=/call_action_list,name=standard_rotation
]]
	if RuneOfPower:Usable() and ((Firestarter.known and Firestarter:Remains() > RuneOfPower:FullRechargeTime()) or (Combustion:Down() and (Combustion:Cooldown() > Player.combustion_rop_cutoff or Target.timeToDie < Combustion:Cooldown()))) then
		UseCooldown(RuneOfPower)
	end
	local apl
	if Combustion.known and ((RuneOfPower.known and Combustion:Cooldown() < RuneOfPower:CastTime() or Combustion:Ready()) and Firestarter:Down() or Combustion:Up()) then
		apl = self:combustion_phase()
		if apl then return apl end
	end
	if RuneOfPower.known and RuneOfPower:Up() and Combustion:Down() then
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
	if LivingBomb:Usable() and Player.enemies > 1 and Combustion:Down() and (Combustion:Cooldown() > LivingBomb:CooldownDuration() or Combustion:Ready()) then
		return LivingBomb
	end
	if Meteor:Usable() then
		if RuneOfPower.known then
			if (RuneOfPower:Up() and (Firestarter:Remains() > Meteor:CooldownDuration() or Firestarter:Down())) or (RuneOfPower:Cooldown() > Target.timeToDie and RuneOfPower:Charges() < 1) then
				UseCooldown(Meteor)
			end
		else
			if (Meteor:CooldownDuration() < Combustion:Cooldown() or Combustion:Ready()) and (Meteor:CooldownDuration() < Firestarter:Remains() or not Firestarter.known or not Firestarter:Up()) then
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
	if RuneOfPower:Usable() and Combustion:Down() then
		UseCooldown(RuneOfPower)
	end
	local apl = self:active_talents()
	if apl then return apl end
	if Combustion:Usable() and (not Meteor.known or Meteor:Cooldown() > 43) and (not RuneOfPower.known or RuneOfPower:Up()) then
		UseCooldown(Combustion)
	end
	if Opt.pot and Target.boss and PotionOfSpectralIntellect:Usable() then
		UseCooldown(PotionOfSpectralIntellect)
	end
	if Opt.trinket then
		if Trinket1:Usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			UseCooldown(Trinket2)
		end
	end
	if Flamestrike:Usable() and HotStreak:Up() and Player.enemies > (FlamePatch.known and 2 or 6) then
		return Flamestrike
	end
	if Pyroblast:Usable() then
		if Pyroclasm.known and Pyroclasm:Up() and Combustion:Remains() > Pyroblast:CastTime() then
			return Pyroblast
		end
		if HotStreak:Up() then
			return Pyroblast
		end
		if Scorch:Casting() and HeatingUp:Up() and Combustion:Up() then
			return Pyroblast
		end
	end
	if PhoenixFlames:Usable() then
		return PhoenixFlames
	end
	if Scorch:Usable() and (Combustion:Down() or Combustion:Remains() > Scorch:CastTime()) then
		return Scorch
	end
	if Combustion:Remains() < Player.gcd then
		if Player.enemies > 1 and LivingBomb:Usable() then
			return LivingBomb
		end
		if DragonsBreath:Usable() then
			UseExtra(DragonsBreath)
		end
	end
	if Scorch:Usable() and SearingTouch:Up() then
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
	if RuneOfPower:Down() then
		if RuneOfPower:Usable() then
			UseCooldown(RuneOfPower)
		end
		return
	end
	if Flamestrike:Usable() and HotStreak:Up() and Player.enemies > (FlamePatch.known and 1 or 4) then
		return Flamestrike
	end
	if Pyroblast:Usable() and HotStreak:Up() then
		return Pyroblast
	end
	if FireBlast:Usable() and HeatingUp:Down() and HotStreak:Down() and not FireBlast:Previous() and (FireBlast:Charges() >= 2 or (PhoenixFlames.known and PhoenixFlames:Charges() >= 1) or (AlexstraszasFury.known and DragonsBreath:Ready()) or SearingTouch:Up() or Firestarter:Up()) then
		UseExtra(FireBlast)
	end
	local apl = self:active_talents()
	if apl then return apl end
	if Pyroclasm.known and Pyroblast:Usable() and Pyroclasm:Up() and min(Pyroclasm:Remains(), RuneOfPower:Remains()) > Pyroblast:CastTime() then
		return Pyroblast
	end
	if HeatingUp:Up() then
		if FireBlast:Usable() and not FireBlast:Previous() then
			UseExtra(FireBlast)
		elseif PhoenixFlames:Usable() and not PhoenixFlames:Previous() then
			return PhoenixFlames
		end
	end
	if Scorch:Usable() and SearingTouch:Up() then
		return Scorch
	end
	if Player.enemies > 2 and DragonsBreath:Usable() then
		UseExtra(DragonsBreath)
	end
	if Flamestrike:Usable() and HotStreak:Up() and Player.enemies > (FlamePatch.known and 2 or 5) then
		return Flamestrike
	end
	if Fireball:Usable() then
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
	if Flamestrike:Usable() and HotStreak:Up() and Player.enemies > (FlamePatch.known and Firestarter:Down() and 1 or 4) then
		return Flamestrike
	end
	if Pyroblast:Usable() and HotStreak:Up() then
		if HotStreak:Remains() < Fireball:CastTime() then
			return Pyroblast
		end
		if Fireball:Previous() or Firestarter:Up() or Pyroblast:Traveling(true) > 0 then
			return Pyroblast
		end
	end
	if PhoenixFlames:Usable() then
		Player.phoenix_pooling = PhoenixFlames.known and ((RuneOfPower.known and RuneOfPower:Cooldown() < PhoenixFlames:FullRechargeTime() and Combustion:Cooldown() > Player.combustion_rop_cutoff and (RuneOfPower:Cooldown() < Target.timeToDie or RuneOfPower:Charges() > 0)) or
			(Combustion:Cooldown() < PhoenixFlames:FullRechargeTime() and Combustion:Cooldown() < Target.timeToDie))
		if not Player.phoenix_pooling and Player.enemies > 2 and PhoenixFlames:Charges() >= 3 then
			return PhoenixFlames
		end
	end
	if Pyroblast:Usable() then
		if HotStreak:Up() and SearingTouch:Up() then
			return Pyroblast
		end
		if Pyroclasm:Up() and Pyroblast:CastTime() < Pyroclasm:Remains() then
			return Pyroblast
		end
	end
	if FireBlast:Usable() then
		Player.fire_blast_pooling = (RuneOfPower.known and RuneOfPower:Cooldown() < FireBlast:FullRechargeTime() and (Combustion:Cooldown() > Player.combustion_rop_cutoff or Firestarter:Up()) and (RuneOfPower:Cooldown() < Target.timeToDie or RuneOfPower:Charges() > 0)) or
			(Combustion:Cooldown() < FireBlast:FullRechargeTime() and Firestarter:Down() and Combustion:Cooldown() < Target.timeToDie) or
			(Firestarter.known and Firestarter:Up() and Firestarter:Remains() < FireBlast:FullRechargeTime())
		if Target.timeToDie < 4 then
			UseExtra(FireBlast)
		elseif Kindling.known then
			if HeatingUp:Up() and (Combustion:Cooldown() > (FireBlast:FullRechargeTime() + 3) or Firestarter:Remains() > FireBlast:FullRechargeTime() or (not RuneOfPower.known or (RuneOfPower:Cooldown() > Target.timeToDie and RuneOfPower:Charges() < 1)) and Combustion:Cooldown() > Target.timeToDie) then
				UseExtra(FireBlast)
			end
		elseif not Player.fire_blast_pooling and HeatingUp:Up() then
			UseExtra(FireBlast)
		end
	end
	if PhoenixFlames:Usable() and not Player.phoenix_pooling and (HeatingUp:Up() or (not HotStreak:Up() and (FireBlast:Charges() > 0 or SearingTouch:Up()))) then
		return PhoenixFlames
	end
	local apl = self:active_talents()
	if apl then return apl end
	if Player.enemies > 1 and DragonsBreath:Usable() then
		UseExtra(DragonsBreath)
	end
	if Player.moving and Pyroblast:Usable() and HotStreak:Up() then
		return Pyroblast
	end
	if Scorch:Usable() and (Player.moving or SearingTouch:Up()) then
		return Scorch
	end
	if Fireball:Usable() then
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
actions.precombat+=/potion
actions.precombat+=/frostbolt
]]
	if Player:TimeInCombat() == 0 then
		if Opt.barrier and IceBarrier:Usable() and IceBarrier:Down() then
			UseExtra(IceBarrier)
		end
		if ArcaneIntellect:Usable() and ArcaneIntellect:Remains() < 300 then
			return ArcaneIntellect
		end
		if SummonWaterElemental:Usable() and not Player.pet_active then
			return SummonWaterElemental
		end
		if not Player:InArenaOrBattleground() then
			if Opt.pot and PotionOfSpectralIntellect:Usable() then
				UseCooldown(PotionOfSpectralIntellect)
			end
		end
		if Player.enemies >= 2 then
			if Blizzard:Usable() then
				return Blizzard
			end
		elseif Frostbolt:Usable() and not Frostbolt:Casting() then
			return Frostbolt
		end
	else
		if ArcaneIntellect:Down() and ArcaneIntellect:Usable() then
			UseExtra(ArcaneIntellect)
		elseif SummonWaterElemental:Usable() and not Player.pet_active then
			UseExtra(SummonWaterElemental)
		elseif MirrorImage:Usable() and Player:UnderAttack() then
			UseExtra(MirrorImage)
		elseif Opt.barrier and IceBarrier:Usable() and IceBarrier:Down() then
			UseExtra(IceBarrier)
		end
	end
--[[
actions=counterspell,if=!runeforge.disciplinary_command|cooldown.buff_disciplinary_command.ready&buff.disciplinary_command_arcane.down
actions+=/call_action_list,name=cds
actions+=/call_action_list,name=aoe,if=active_enemies>=3
actions+=/call_action_list,name=st,if=active_enemies<3
actions+=/call_action_list,name=movement
]]
	Player.use_cds = Target.boss or Target.timeToDie > Opt.cd_ttd or IcyVeins:Up() or (RuneOfPower.known and RuneOfPower:Up())
	if Player.use_cds then
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
actions.cds=potion,if=prev_off_gcd.icy_veins|fight_remains<30
actions.cds+=/deathborne
actions.cds+=/mirrors_of_torment,if=active_enemies<3&(conduit.siphoned_malice|soulbind.wasteland_propriety)
actions.cds+=/rune_of_power,if=cooldown.icy_veins.remains>12&buff.rune_of_power.down
actions.cds+=/icy_veins,if=buff.rune_of_power.down&(buff.icy_veins.down|talent.rune_of_power)&(buff.slick_ice.down|active_enemies>=2)
actions.cds+=/time_warp,if=runeforge.temporal_warp&buff.exhaustion.up&(prev_off_gcd.icy_veins|fight_remains<40)
actions.cds+=/use_items
actions.cds+=/blood_fury
actions.cds+=/berserking
actions.cds+=/lights_judgment
actions.cds+=/fireblood
actions.cds+=/ancestral_call
actions.cds+=/bag_of_tricks
]]
	if MirrorsOfTorment:Usable() and Player.enemies < 3 and (SiphonedMalice.known or WastelandPropriety.known) then
		return UseCooldown(MirrorsOfTorment)
	end
	if RuneOfPower:Usable() and not IcyVeins:Ready(12) and RuneOfPower:Down() then
		return UseCooldown(RuneOfPower)
	end
	if IcyVeins:Usable() and (not RuneOfPower.known or RuneOfPower:Down()) and (IcyVeins:Down() or RuneOfPower.known) and (Player.enemies >= 2 or (not SlickIce.known or SlickIce:Down())) then
		return UseCooldown(IcyVeins)
	end
	if Opt.pot and PotionOfSpectralIntellect:Usable() and (IcyVeins:Remains() > 20 or Target.timeToDie < 30) then
		return UseCooldown(PotionOfSpectralIntellect)
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
actions.movement=blink_any,if=movement.distance>10
actions.movement+=/ice_floes,if=buff.ice_floes.down
actions.movement+=/arcane_explosion,if=mana.pct>30&active_enemies>=2
actions.movement+=/fire_blast
actions.movement+=/ice_lance
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
actions.st=flurry,if=(remaining_winters_chill=0|debuff.winters_chill.down)&(prev_gcd.1.ebonbolt|buff.brain_freeze.react&(prev_gcd.1.glacial_spike|prev_gcd.1.frostbolt&(!conduit.ire_of_the_ascended|cooldown.radiant_spark.remains|runeforge.freezing_winds)|prev_gcd.1.radiant_spark|buff.fingers_of_frost.react=0&(debuff.mirrors_of_torment.up|buff.freezing_winds.up|buff.expanded_potential.react|buff.rune_of_power.up)))
actions.st+=/frozen_orb,if=!runeforge.freezing_winds|buff.icy_veins.up|cooldown.icy_veins.remains>12
actions.st+=/blizzard,if=buff.freezing_rain.up|active_enemies>=2
actions.st+=/ray_of_frost,if=remaining_winters_chill=1&debuff.winters_chill.remains
actions.st+=/glacial_spike,if=remaining_winters_chill&debuff.winters_chill.remains>cast_time+travel_time
actions.st+=/ice_lance,if=remaining_winters_chill&remaining_winters_chill>buff.fingers_of_frost.react&debuff.winters_chill.remains>travel_time
actions.st+=/comet_storm
actions.st+=/ice_nova
actions.st+=/radiant_spark,if=buff.freezing_winds.up&active_enemies=1
actions.st+=/radiant_spark,if=buff.brain_freeze.react&talent.glacial_spike&conduit.ire_of_the_ascended&buff.icicles.stack>=4
actions.st+=/ice_lance,if=buff.fingers_of_frost.react|debuff.frozen.remains>travel_time
actions.st+=/ebonbolt
actions.st+=/radiant_spark,if=(!talent.glacial_spike|!conduit.ire_of_the_ascended)&(!runeforge.freezing_winds|active_enemies>=2)&buff.brain_freeze.react
actions.st+=/mirrors_of_torment,if=buff.icy_veins.up|cooldown.icy_veins.remains>80|target.time_to_die<25+cooldown.icy_veins.remains
actions.st+=/shifting_power,if=buff.rune_of_power.down&(!runeforge.freezing_winds|buff.freezing_winds.down)&(soulbind.grove_invigoration|soulbind.field_of_blossoms|runeforge.freezing_winds|active_enemies>=2)
actions.st+=/arcane_explosion,if=runeforge.disciplinary_command&cooldown.buff_disciplinary_command.ready&buff.disciplinary_command_arcane.down
actions.st+=/fire_blast,if=runeforge.disciplinary_command&cooldown.buff_disciplinary_command.ready&buff.disciplinary_command_fire.down
actions.st+=/glacial_spike,if=buff.brain_freeze.react
actions.st+=/blizzard,if=runeforge.freezing_winds&(cooldown.frozen_orb.remains>cooldown.icy_veins.remains+4|cooldown.frozen_orb.remains>cooldown.rune_of_power.remains+4)
actions.st+=/frostbolt
]]
	if Flurry:Usable() and WintersChill:Down() and (Ebonbolt:Previous() or (BrainFreeze:Up() and (GlacialSpike:Previous() or Frostbolt:Previous() or (FingersOfFrost:Down() and ((MirrorsOfTorment.known and MirrorsOfTorment:Up()) or (FreezingWinds.known and FreezingWinds:Up()) or (RuneOfPower.known and RuneOfPower:Up())))))) then
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
	if MirrorsOfTorment:Usable() and Target.timeToDie > 8 and (IcyVeins:Up() or IcyVeins:Cooldown() > 80 or Target.timeToDie < (25 + IcyVeins:Cooldown())) then
		UseCooldown(MirrorsOfTorment)
	end
	if ShiftingPower:Usable() and (not RuneOfPower.known or RuneOfPower:Down()) and (not FreezingWinds.known or FreezingWinds:Down()) and (GroveInvigoration.known or FieldOfBlossoms.known or FreezingWinds.known or Player.enemies >= 2) then
		UseCooldown(ShiftingPower)
	end
	if GlacialSpike:Usable() and BrainFreeze:Up() and Target.timeToDie > (GlacialSpike:CastTime() + GlacialSpike:TravelTime()) then
		return GlacialSpike
	end
	if FreezingWinds.known and Blizzard:Usable() and ((FrozenOrb:Cooldown() > (IcyVeins:Cooldown() + 4)) or (RuneOfPower.known and FrozenOrb:Cooldown() > (RuneOfPower:Cooldown() + 4))) then
		UseCooldown(Blizzard)
	end
	if Frostbolt:Usable() then
		return Frostbolt
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
actions.aoe=frozen_orb
actions.aoe+=/blizzard
actions.aoe+=/flurry,if=(remaining_winters_chill=0|debuff.winters_chill.down)&(prev_gcd.1.ebonbolt|buff.brain_freeze.react&buff.fingers_of_frost.react=0)
actions.aoe+=/ice_nova
actions.aoe+=/comet_storm
actions.aoe+=/ice_lance,if=buff.fingers_of_frost.react|debuff.frozen.remains>travel_time|remaining_winters_chill&debuff.winters_chill.remains>travel_time
actions.aoe+=/radiant_spark,if=soulbind.combat_meditation
actions.aoe+=/mirrors_of_torment
actions.aoe+=/shifting_power,if=cooldown.frozen_orb.remains>8&(!runeforge.freezing_winds|buff.freezing_winds.down)
actions.aoe+=/fire_blast,if=runeforge.disciplinary_command&cooldown.buff_disciplinary_command.ready&buff.disciplinary_command_fire.down
actions.aoe+=/arcane_explosion,if=mana.pct>30&active_enemies>=6&!runeforge.glacial_fragments
actions.aoe+=/ebonbolt
actions.aoe+=/ice_lance,if=runeforge.glacial_fragments&talent.splitting_ice&travel_time<ground_aoe.blizzard.remains
actions.aoe+=/wait,sec=0.1,if=runeforge.glacial_fragments&talent.splitting_ice
actions.aoe+=/frostbolt
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
	if MirrorsOfTorment:Usable() and Target.timeToDie > 20 then
		UseCooldown(MirrorsOfTorment)
	end
	if ArcaneExplosion:Usable() and not GlacialFragments.known and Player.enemies >= 6 and Player:ManaPct() > 30 then
		UseCooldown(ArcaneExplosion)
	end
	if Ebonbolt:Usable() and Target.timeToDie > (Ebonbolt:CastTime() + Ebonbolt:TravelTime()) then
		return Ebonbolt
	end
	if IceLance:Usable() and GlacialFragments.known and SplittingIce.known and Player.blizzard_remains > IceLance:TravelTime() and Blizzard:Targets() > 1 then
		return IceLance
	end
	if Frostbolt:Usable() then
		return Frostbolt
	end
end

APL.Interrupt = function(self)
	if Counterspell:Usable() then
		return Counterspell
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
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

function UI:CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
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
	local glow, icon, i
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
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
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
	['blizzard'] = {
		[SPEC.ARCANE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.FIRE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		}
	},
	['kui'] = {
		[SPEC.ARCANE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[SPEC.FIRE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		}
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
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
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
	if Blizzard.known and Player.blizzard_remains > 0 then
		text_center = format('%.1fs', Player.blizzard_remains)
	end
	amagicPanel.dimmer:SetShown(dim)
	amagicPanel.text.center:SetText(text_center)
	--amagicPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL[Player.spec]:main()
	if Player.main then
		amagicPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		amagicCooldownPanel.icon:SetTexture(Player.cd.icon)
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
			amagicInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			amagicInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		amagicInterruptPanel.icon:SetShown(Player.interrupt)
		amagicInterruptPanel.border:SetShown(Player.interrupt)
		amagicInterruptPanel:SetShown(start and not notInterruptible)
	end
	amagicPanel.icon:SetShown(Player.main)
	amagicPanel.border:SetShown(Player.main)
	amagicCooldownPanel:SetShown(Player.cd)
	amagicExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Automagically
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Automagically1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
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
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
		return
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
		end
		if Opt.auto_aoe then
			if dstGUID == Player.guid or dstGUID == Player.pet then
				autoAoe:Add(srcGUID, true)
			elseif (srcGUID == Player.guid or srcGUID == Player.pet) and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:Add(dstGUID, true)
			end
		end
	end

	local ability = spellId and abilities.bySpellId[spellId]

	if APL[Player.spec].combat_event then
		APL[Player.spec]:combat_event(eventType, srcGUID, dstGUID, spellId, ability)
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
	
	if eventType == 'SPELL_SUMMON' then
		if RuneOfPower.known and (ability == RuneOfPower or spellId == 342130) then -- spellId for RoP summoned by any major CD
			RuneOfPower.summon_time = Player.time
		end
	end

	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_ABSORBED' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			ability:CastSuccess(dstGUID, timeStamp)
			if Opt.previous and amagicPanel:IsVisible() then
				amagicPreviousPanel.ability = ability
				amagicPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
				amagicPreviousPanel.icon:SetTexture(ability.icon)
				amagicPreviousPanel:Show()
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
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_ABSORBED' or eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, timeStamp, eventType)
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and amagicPanel:IsVisible() and ability == amagicPreviousPanel.ability then
			amagicPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
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

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.last_swing_taken = 0
	Player.pet_stuck = false
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		amagicPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
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

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, i, equipType, hasCooldown
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
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	amagicPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
end

function events:SPELL_UPDATE_COOLDOWN()
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

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'ARCANE_CHARGES' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName, castId, spellId)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_SUCCEEDED(srcName, castGUID, spellId)
	if srcName ~= 'player' or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = spellId and abilities.bySpellId[spellId]
	if not ability or not ability.traveling then
		return
	end
	ability.next_castGUID = castGUID
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:SOULBIND_ACTIVATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_NODE_UPDATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_PATH_CHANGED()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	Player:Update()
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
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

amagicPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	amagicPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

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
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
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
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra/Pet cooldown ability icon scale', Opt.scale.extra, 'times')
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
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
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
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra/pet cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
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
		return Status('Possible hidespec options', '|cFFFFD000arcane|r, |cFFFFD000fire|r, and |cFFFFD000frost')
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
			Opt.conserve_mana = max(min(tonumber(msg[2]) or 60, 80), 20)
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
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
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
