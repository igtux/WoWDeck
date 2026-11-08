--[[
WoWDeck
-------
Lets a ConsolePort import string be dropped into this addon's own
SavedVariables file from outside the game (no in-game typing/pasting),
then applies it with one tap by driving ConsolePort_Config's real
Import dialog (same buttons a player would click: Load, then Apply).
This reuses ConsolePort's own tested apply logic end-to-end; nothing
about bindings/cvars/action bars is reimplemented here.
]]

WoWDeckDB = WoWDeckDB or {}
local DB = WoWDeckDB

local NUMDIALOGS = STATICPOPUP_NUMDIALOGS or 4
local frame, launcher

local function Log(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage('|cff69ccf0WoWDeck:|r ' .. msg)
	end
end

local function SetStatus(text, r, g, b)
	if frame and frame.Status then
		frame.Status:SetText(text)
		frame.Status:SetTextColor(r or 1, g or 1, b or 1)
	end
end

local function FindImportPopup()
	for i = 1, NUMDIALOGS do
		local f = _G['StaticPopup' .. i]
		if f and f:IsShown() and f.which == 'CONSOLEPORT_IMPORT_DATA' then
			return f
		end
	end
end

local function DoApply(text)
	if not text or text:trim() == '' then
		SetStatus('Nothing to apply.', 0.7, 0.7, 0.7)
		return
	end
	if InCombatLockdown() then
		SetStatus('Cannot apply in combat. Try again after.', 1, 0.4, 0.4)
		return
	end
	if not C_AddOns.IsAddOnLoaded('ConsolePort_Config') then
		C_AddOns.EnableAddOn('ConsolePort_Config')
		if not C_AddOns.LoadAddOn('ConsolePort_Config') then
			SetStatus('Could not load ConsolePort_Config.', 1, 0.4, 0.4)
			return
		end
	end
	if not (ConsolePortConfig and ConsolePortConfig.Load) then
		SetStatus('ConsolePort config panel not found.', 1, 0.4, 0.4)
		return
	end

	local config = ConsolePortConfig:Load()
	if not (config and config.Import) then
		SetStatus('Import button not found.', 1, 0.4, 0.4)
		return
	end

	config.Import:Click()
	local popup = FindImportPopup()
	if not popup then
		SetStatus('Import dialog did not open.', 1, 0.4, 0.4)
		return
	end

	local editBox = popup.editBox or _G[popup:GetName() .. 'EditBox']
	local btnApply = _G[popup:GetName() .. 'Button1']
	local btnLoad = _G[popup:GetName() .. 'Button3']
	if not (editBox and btnApply and btnLoad) then
		SetStatus('Import dialog layout unexpected.', 1, 0.4, 0.4)
		popup:Hide()
		return
	end

	editBox:SetText(text)
	if not btnLoad:IsEnabled() then
		SetStatus('Config text was rejected.', 1, 0.4, 0.4)
		popup:Hide()
		return
	end

	btnLoad:Click()  -- validates + stages data (same as the "Load" button)
	btnApply:Click() -- commits via ConsolePort's own EvaluateImportData

	DB.lastApplied = text
	SetStatus('Config applied!', 0.4, 1, 0.4)
	Log('Applied pending ConsolePort config.')
end

local function CastTracking(spellName)
	local ok = pcall(CastSpellByName, spellName)
	if ok then
		SetStatus(spellName .. ' enabled.', 0.4, 1, 0.4)
	else
		SetStatus('Could not cast ' .. spellName .. ' - do you have that profession?', 1, 0.4, 0.4)
	end
end

---------------------------------------------------------------
-- UI - flat, modern styling (no default chunky WoW button skin):
-- solid-color panel, thin accent border/header, custom buttons with
-- their own hover/press color states.
---------------------------------------------------------------
local FRAME_WIDTH = 340
local SIDE_PADDING = 20
local FULL_BTN_WIDTH = FRAME_WIDTH - SIDE_PADDING * 2
local HALF_GAP = 10
local HALF_BTN_WIDTH = (FULL_BTN_WIDTH - HALF_GAP) / 2
local ROW_HEIGHT = 52
local ROW_GAP = 10
local HEADER_HEIGHT = 56

local ACCENT = { 0.41, 0.80, 0.94 }
local BG_COLOR = { 0.06, 0.07, 0.09, 0.96 }
local HEADER_COLOR = { 0.10, 0.12, 0.16, 1 }
local BTN_COLOR = { 0.13, 0.14, 0.17, 0.95 }
local BTN_HOVER_COLOR = { 0.19, 0.22, 0.27, 1 }
local BTN_DOWN_COLOR = { 0.08, 0.09, 0.11, 1 }
local TEXT_COLOR = { 0.92, 0.94, 0.97 }

local function CreateModernButton(parent, width, label, onClick)
	local b = CreateFrame('Button', nil, parent)
	b:SetSize(width, ROW_HEIGHT)

	local bg = b:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(BTN_COLOR))
	b.bg = bg

	local accent = b:CreateTexture(nil, 'ARTWORK')
	accent:SetPoint('BOTTOMLEFT')
	accent:SetPoint('BOTTOMRIGHT')
	accent:SetHeight(2)
	accent:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.85)

	local text = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	text:SetPoint('CENTER')
	text:SetText(label)
	text:SetTextColor(unpack(TEXT_COLOR))
	b.text = text

	b:SetScript('OnEnter', function(self) bg:SetColorTexture(unpack(BTN_HOVER_COLOR)) end)
	b:SetScript('OnLeave', function(self) bg:SetColorTexture(unpack(BTN_COLOR)) end)
	b:SetScript('OnMouseDown', function(self) bg:SetColorTexture(unpack(BTN_DOWN_COLOR)) end)
	b:SetScript('OnMouseUp', function(self) bg:SetColorTexture(unpack(BTN_HOVER_COLOR)) end)
	b:SetScript('OnClick', onClick)

	return b
end

-- Row specs: one full-width button, or two side by side. Height is
-- accumulated as rows are placed so the frame is sized to exactly
-- fit its content instead of a guessed constant.
local function BuildRows(parent, startY, rowSpecs)
	local y = startY
	for _, row in ipairs(rowSpecs) do
		if #row == 1 then
			local spec = row[1]
			local b = CreateModernButton(parent, FULL_BTN_WIDTH, spec.label, spec.onClick)
			b:SetPoint('TOP', parent, 'TOP', 0, y)
			if spec.key then parent[spec.key] = b end
		else
			local left, right = row[1], row[2]
			local lb = CreateModernButton(parent, HALF_BTN_WIDTH, left.label, left.onClick)
			lb:SetPoint('TOP', parent, 'TOP', -(HALF_BTN_WIDTH + HALF_GAP) / 2, y)
			if left.key then parent[left.key] = lb end

			local rb = CreateModernButton(parent, HALF_BTN_WIDTH, right.label, right.onClick)
			rb:SetPoint('TOP', parent, 'TOP', (HALF_BTN_WIDTH + HALF_GAP) / 2, y)
			if right.key then parent[right.key] = rb end
		end
		y = y - (ROW_HEIGHT + ROW_GAP)
	end
	return y
end

local function CreateMainFrame()
	frame = CreateFrame('Frame', 'WoWDeckFrame', UIParent)
	frame:SetPoint('CENTER')
	frame:SetFrameStrata('DIALOG')
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag('LeftButton')
	frame:SetScript('OnDragStart', frame.StartMoving)
	frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
	frame:Hide()

	local bg = frame:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(BG_COLOR))

	-- Thin accent border instead of the default chunky tooltip edge.
	for _, point in ipairs({ 'TOP', 'BOTTOM', 'LEFT', 'RIGHT' }) do
		local line = frame:CreateTexture(nil, 'OVERLAY')
		line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.5)
		if point == 'TOP' or point == 'BOTTOM' then
			line:SetPoint('TOPLEFT', frame, point == 'TOP' and 'TOPLEFT' or 'BOTTOMLEFT')
			line:SetPoint('TOPRIGHT', frame, point == 'TOP' and 'TOPRIGHT' or 'BOTTOMRIGHT')
			line:SetHeight(1)
		else
			line:SetPoint('TOPLEFT', frame, point == 'LEFT' and 'TOPLEFT' or 'TOPRIGHT')
			line:SetPoint('BOTTOMLEFT', frame, point == 'LEFT' and 'BOTTOMLEFT' or 'BOTTOMRIGHT')
			line:SetWidth(1)
		end
	end

	local header = frame:CreateTexture(nil, 'BORDER')
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	header:SetHeight(HEADER_HEIGHT)
	header:SetColorTexture(unpack(HEADER_COLOR))

	local headerLine = frame:CreateTexture(nil, 'ARTWORK')
	headerLine:SetPoint('TOPLEFT', header, 'BOTTOMLEFT')
	headerLine:SetPoint('TOPRIGHT', header, 'BOTTOMRIGHT')
	headerLine:SetHeight(2)
	headerLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)

	local title = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	title:SetPoint('TOP', 0, -14)
	title:SetText('WoWDeck')
	title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

	local status = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	status:SetPoint('TOP', title, 'BOTTOM', 0, -8)
	status:SetWidth(FULL_BTN_WIDTH)
	status:SetJustifyH('CENTER')
	status:SetText('Ready.')
	status:SetTextColor(unpack(TEXT_COLOR))
	frame.Status = status

	local rowSpecs = {
		{ { label = 'Apply Pending Config', key = 'ApplyButton', onClick = function() DoApply(DB.pending) end } },
		{ { label = 'Reload UI', onClick = function() ReloadUI() end } },
		{ { label = 'Keyboard', onClick = function()
			WoWDeck_ToggleKeyboard()
			frame:Hide()
		end } },
		{
			{ label = 'Track Herbs', onClick = function() CastTracking('Find Herbs') end },
			{ label = 'Track Minerals', onClick = function() CastTracking('Find Minerals') end },
		},
		{
			{ label = 'Bag Manager', onClick = function()
				WoWDeck_ToggleBagManager()
				frame:Hide()
			end },
			{ label = 'Check Target', onClick = function() WoWDeck_CheckTarget() end },
		},
		{ { label = 'Quest Manager', onClick = function()
			WoWDeck_ToggleQuestManager()
			frame:Hide()
		end } },
		{ { label = 'Close', onClick = function() frame:Hide() end } },
	}

	local finalY = BuildRows(frame, -(HEADER_HEIGHT + 20), rowSpecs)
	local totalHeight = HEADER_HEIGHT - finalY + 10 -- finalY is negative; +10 bottom padding
	frame:SetSize(FRAME_WIDTH, totalHeight)

	tinsert(UISpecialFrames, 'WoWDeckFrame')
end

local function RefreshState(showIfNew)
	if not frame then return end
	local hasNew = DB.pending and DB.pending ~= '' and DB.pending ~= DB.lastApplied
	if hasNew then
		SetStatus('New config ready - tap Apply.', 1, 0.85, 0.3)
		if showIfNew then frame:Show() end
	elseif DB.pending and DB.pending ~= '' then
		SetStatus('Already applied.', 0.6, 1, 0.6)
	else
		SetStatus('No pending config.', 0.7, 0.7, 0.7)
	end
end

-- Small always-on-screen launcher so this is reachable without any
-- keyboard/slash command - just tap it.
local function CreateLauncher()
	launcher = CreateFrame('Button', 'WoWDeckLauncher', UIParent, 'BackdropTemplate')
	launcher:SetSize(52, 52)
	local px, py = DB.launcherPoint and DB.launcherPoint.x, DB.launcherPoint and DB.launcherPoint.y
	if px and py then
		launcher:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', px, py)
	else
		launcher:SetPoint('BOTTOMLEFT', 40, 160)
	end
	launcher:SetFrameStrata('HIGH')
	launcher:SetBackdrop({
		bgFile = 'Interface/Tooltips/UI-Tooltip-Background',
		edgeFile = 'Interface/Tooltips/UI-Tooltip-Border',
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	launcher:SetBackdropColor(0.1, 0.4, 0.6, 0.9)

	local label = launcher:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	label:SetPoint('CENTER')
	label:SetText('WD')
	launcher.Label = label

	launcher:EnableMouse(true)
	launcher:SetMovable(true)
	launcher:RegisterForDrag('LeftButton')
	launcher:SetScript('OnDragStart', launcher.StartMoving)
	launcher:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		local x, y = self:GetCenter()
		local ux, uy = UIParent:GetLeft(), UIParent:GetBottom()
		DB.launcherPoint = { x = x - (ux or 0), y = y - (uy or 0) }
	end)
	launcher:SetScript('OnClick', function()
		if frame:IsShown() then
			frame:Hide()
		else
			RefreshState(false)
			frame:Show()
		end
	end)

	-- pulse the launcher when a new config is waiting
	launcher:SetScript('OnUpdate', function(self)
		local hasNew = DB.pending and DB.pending ~= '' and DB.pending ~= DB.lastApplied
		self:SetBackdropColor(hasNew and 1 or 0.1, hasNew and 0.7 or 0.4, hasNew and 0.1 or 0.6, 0.9)
	end)
end

---------------------------------------------------------------
local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('PLAYER_LOGIN')
eventFrame:SetScript('OnEvent', function()
	CreateMainFrame()
	CreateLauncher()
	RefreshState(true)
end)

SLASH_WOWDECK1 = '/wowdeck'
SlashCmdList['WOWDECK'] = function()
	if not frame then return end
	RefreshState(false)
	frame:SetShown(not frame:IsShown())
end
