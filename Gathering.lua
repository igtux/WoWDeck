--[[
Small floating card shown whenever the game's own soft-interact target
is set (the thing in front of you that you could currently interact
with - herb, ore, mailbox, questgiver, etc), falling back to a real
hard "target" once you're close enough that the game promotes it from
soft-interact to an actual target (which otherwise made the card
vanish right when you got close).

Shows the object's name, your current Herbalism/Mining skill level,
and a skill-requirement line read directly from the game's own tooltip
for that object (scanned off-screen, not hardcoded) - if the tooltip
contains a red "Requires X Skill" line, that's shown as-is; otherwise
we say no restriction was found rather than guessing.
]]

-- Standard Classic-era Herbalism requirements (stable, well-documented
-- data unchanged for many years - unlike current-retail-patch data,
-- this doesn't shift from patch to patch, so hardcoding it is safe).
-- A custom/private server could have retuned individual herbs though,
-- so treat this as a solid estimate, not a guarantee.
local HERBALISM_REQUIREMENTS = {
	['Peacebloom'] = 1,
	['Silverleaf'] = 1,
	['Earthroot'] = 15,
	['Mageroyal'] = 50,
	['Briarthorn'] = 70,
	['Stranglekelp'] = 85,
	['Bruiseweed'] = 100,
	['Wild Steelbloom'] = 115,
	['Grave Moss'] = 120,
	['Kingsblood'] = 125,
	['Liferoot'] = 150,
	['Fadeleaf'] = 160,
	['Goldthorn'] = 170,
	["Khadgar's Whisker"] = 185,
	["Dragon's Teeth"] = 195,
	['Firebloom'] = 205,
	['Purple Lotus'] = 210,
	["Arthas' Tears"] = 220,
	['Sungrass'] = 230,
	['Blindweed'] = 235,
	['Ghost Mushroom'] = 245,
	['Gromsblood'] = 250,
	['Golden Sansam'] = 260,
	['Dreamfoil'] = 270,
	['Mountain Silversage'] = 280,
	['Plaguebloom'] = 285,
	['Icecap'] = 290,
	['Black Lotus'] = 300,
}

-- Classic gathering rule of thumb: an herb stops giving skill-ups once
-- your skill is roughly this far above its own requirement.
local HERB_TRIVIAL_GAP = 75

-- Returns (requiredSkill, isTrivial) if this name is a known classic
-- herb and we know your current skill, otherwise nil.
local function GetHerbSkillUpInfo(name, currentSkill)
	local required = HERBALISM_REQUIREMENTS[name]
	if not required or not currentSkill then
		return nil
	end
	local diff = currentSkill - required
	if diff < 0 then
		return nil -- shouldn't happen, the game already blocks this
	end
	return required, diff >= HERB_TRIVIAL_GAP
end

local function GetProfessionSkill(profName)
	local prof1, prof2, archaeology, fishing, cooking = GetProfessions()
	for _, index in ipairs({ prof1, prof2, archaeology, fishing, cooking }) do
		if index then
			local name, _, skillLevel, maxSkillLevel = GetProfessionInfo(index)
			if name == profName then
				return skillLevel, maxSkillLevel
			end
		end
	end
end

local DEBUG = false
local function Debug(msg)
	if DEBUG and DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage('|cff69ccf0WoWDeck debug:|r ' .. msg)
	end
end

-- A living NPC (guard, questgiver, vendor) reports a real max health;
-- gathering nodes and skinnable corpses report 0. This is what keeps
-- the card from popping profession info on every NPC you soft-target -
-- only true 0-health "units" (nodes/corpses) pass through.
local function HasNoHealth(token)
	return (UnitHealthMax(token) or 0) == 0
end

-- allowDead=true bypasses the dead-creature filter below, used by the
-- manual "Check Target" button so skinnable corpses are still checkable
-- on demand even though the automatic card no longer pops for them.
local function GetActiveNodeUnit(guidHint, allowDead)
	-- The soft-interact slot can already be cleared again by the time
	-- we poll it after the event fires (confirmed by debug: the event
	-- keeps firing, but UnitExists('softinteract') reads false right
	-- after). The event itself passes the new target's GUID though,
	-- so resolve that directly while it's still valid.
	if guidHint and guidHint ~= '' then
		local token = UnitTokenFromGUID(guidHint)
		Debug(('guidHint=%s -> token=%s'):format(tostring(guidHint), tostring(token)))
		if token then
			if not HasNoHealth(token) then
				return nil -- a living NPC, not a node - don't show profession info on it
			end
			if not allowDead and UnitIsDead(token) then
				return nil
			end
			return token
		end
	end

	local softExists = UnitExists('softinteract')
	local targetExists = UnitExists('target')
	local targetHP = targetExists and UnitHealthMax('target') or nil
	Debug(('soft=%s target=%s targetHP=%s'):format(
		tostring(softExists), tostring(targetExists), tostring(targetHP)))

	if softExists and HasNoHealth('softinteract') then
		if not allowDead and UnitIsDead('softinteract') then
			return nil
		end
		return 'softinteract'
	end
	if targetExists and (targetHP or 0) == 0 then
		if not allowDead and UnitIsDead('target') then
			return nil
		end
		return 'target'
	end
end

-- Reuses the real GameTooltip to read an object's tooltip text
-- (briefly, then hides it again) instead of creating a separate
-- scanning tooltip frame, which is more failure-prone to construct.
-- Returns a red "Requires X Skill" line if present, shown verbatim -
-- that's a real hard gate the game enforces. There used to be a
-- second heuristic here based on the title line's color (gray =
-- trivial), but that was wrong: confirmed by testing that object
-- names are just colored by faction/reaction (yellow = neutral),
-- not by skill relevance. Removed rather than keep showing a
-- confident-looking claim that isn't actually true.
local function ScanTooltip(unitToken)
	GameTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	local ok = pcall(GameTooltip.SetUnit, GameTooltip, unitToken)
	if not ok then
		GameTooltip:Hide()
		return nil
	end
	local requirement
	for i = 1, GameTooltip:NumLines() do
		local fs = _G['GameTooltipTextLeft' .. i]
		if fs then
			local text = fs:GetText()
			if text then
				local r, g, b = fs:GetTextColor()
				if not requirement and r and r > 0.8 and g < 0.3 and b < 0.3 then
					requirement = text
				end
			end
		end
	end
	GameTooltip:Hide()
	return requirement
end

local CARD_SIDE_PADDING = 24
local CARD_MIN_WIDTH = 160
local CARD_MAX_WIDTH = 440

local card = CreateFrame('Frame', 'WoWDeckInteractCard', UIParent, 'BackdropTemplate')
card:SetPoint('TOP', UIParent, 'TOP', 0, -60)
card:SetFrameStrata('HIGH')
card:EnableMouse(false)
card:SetBackdrop({
	bgFile = 'Interface/Tooltips/UI-Tooltip-Background',
	edgeFile = 'Interface/Tooltips/UI-Tooltip-Border',
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
card:SetBackdropColor(0, 0, 0, 0.85)
card:Hide()

local nameText = card:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
nameText:SetPoint('TOP', 0, -10)
card.NameText = nameText

local skillText = card:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
skillText:SetPoint('TOP', nameText, 'BOTTOM', 0, -8)
skillText:SetJustifyH('CENTER')
card.SkillText = skillText

local reqText = card:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
reqText:SetPoint('TOP', skillText, 'BOTTOM', 0, -6)
reqText:SetJustifyH('CENTER')
card.ReqText = reqText

-- Fixed height (GetStringHeight isn't a real FontString API - using it
-- was making the backdrop too short, pushing the bottom line outside
-- the visible card background). Width still fits the actual text.
local CARD_HEIGHT_WITH_SKILL = 100
local CARD_HEIGHT_NO_SKILL = 78

local function ResizeCardToContent()
	local maxWidth = nameText:GetStringWidth()
	local hasSkillLine = skillText:GetText() and skillText:GetText() ~= ''
	if hasSkillLine then
		maxWidth = math.max(maxWidth, skillText:GetStringWidth())
	end
	if reqText:GetText() and reqText:GetText() ~= '' then
		maxWidth = math.max(maxWidth, reqText:GetStringWidth())
	end
	card:SetWidth(math.max(CARD_MIN_WIDTH, math.min(CARD_MAX_WIDTH, maxWidth + CARD_SIDE_PADDING)))
	card:SetHeight(hasSkillLine and CARD_HEIGHT_WITH_SKILL or CARD_HEIGHT_NO_SKILL)
end

local lastShownUnit
local hideGen = 0

-- The game's own soft-target signal has a gap right at point-blank
-- range for some nodes (soft=false AND target=false even while
-- standing on top of them - confirmed by debug output). Rather than
-- hide instantly on that gap, wait briefly in case the signal comes
-- back; any update before the delay elapses cancels this hide.
local function ScheduleHide()
	hideGen = hideGen + 1
	local gen = hideGen
	C_Timer.After(1.5, function()
		if gen == hideGen then
			card:Hide()
			lastShownUnit = nil
		end
	end)
end

local function UpdateCardBody(guidHint, allowDead)
	local unit = GetActiveNodeUnit(guidHint, allowDead)
	if not unit then
		ScheduleHide()
		return
	end
	local name = UnitName(unit)
	if not name or name == '' then
		-- Resolved to a unit token but the name isn't available yet -
		-- don't show a useless "Unknown" card, just wait for the next
		-- update (same debounce as losing the signal entirely).
		Debug(('unit=%s resolved but name unavailable'):format(unit))
		ScheduleHide()
		return
	end
	hideGen = hideGen + 1 -- invalidate any pending hide, we have a live signal again

	Debug(('picked unit=%s name=%s'):format(unit, name))
	nameText:SetText(name)

	local lines = {}
	local herbLevel, herbMax = GetProfessionSkill('Herbalism')
	if herbLevel then
		table.insert(lines, ('Herbalism %d/%d'):format(herbLevel, herbMax))
	end
	local miningLevel, miningMax = GetProfessionSkill('Mining')
	if miningLevel then
		table.insert(lines, ('Mining %d/%d'):format(miningLevel, miningMax))
	end
	skillText:SetText(table.concat(lines, '    '))

	local requirement = ScanTooltip(unit)
	if requirement then
		reqText:SetText(requirement)
		reqText:SetTextColor(1, 0.3, 0.3)
	else
		local reqSkill, isTrivial = GetHerbSkillUpInfo(name, herbLevel)
		if reqSkill then
			if isTrivial then
				reqText:SetText(('Trivial at your skill (req %d)'):format(reqSkill))
				reqText:SetTextColor(0.7, 0.7, 0.7)
			else
				reqText:SetText(('Likely still raises your skill (req %d)'):format(reqSkill))
				reqText:SetTextColor(0.4, 1, 0.4)
			end
		else
			-- Not a known classic herb, or no hard "Requires X Skill"
			-- line to go on - whether it actually raises your skill
			-- right now isn't exposed by any API, so say that plainly
			-- instead of guessing.
			reqText:SetText('Gatherable - skill-up chance unknown')
			reqText:SetTextColor(0.75, 0.75, 0.75)
		end
	end

	ResizeCardToContent()
	card:Show()
	lastShownUnit = unit
end

local function UpdateCard(guidHint, allowDead)
	local ok, err = pcall(UpdateCardBody, guidHint, allowDead)
	if not ok then
		Debug('error: ' .. tostring(err))
	end
end

local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('PLAYER_SOFT_INTERACT_CHANGED')
eventFrame:RegisterEvent('PLAYER_TARGET_CHANGED')
eventFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
eventFrame:SetScript('OnEvent', function(_, event, oldTarget, newTarget)
	if event == 'PLAYER_SOFT_INTERACT_CHANGED' then
		UpdateCard(newTarget)
	else
		UpdateCard()
	end
end)

-- Manual check (e.g. for skinning), bypasses the dead-creature filter
-- that keeps corpses from popping the card automatically.
function WoWDeck_CheckTarget()
	UpdateCard(nil, true)
end
