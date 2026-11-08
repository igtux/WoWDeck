--[[
Small on-screen keyboard for WoWDeck.
Lets you tap out short text (slash commands, chat) without a physical
keyboard. Send submits the text exactly like typing it into chat and
pressing enter - slash commands work the same way.
]]

local KEY_SIZE, GAP = 56, 8
local KEY_FONT_SIZE = 20
local SECTION_GAP = 14
local HEADER_HEIGHT = 44
local DISPLAY_HEIGHT = 36

local DISPLAY_Y = -(HEADER_HEIGHT + SECTION_GAP)
local CHANNEL_ROW_Y = DISPLAY_Y - DISPLAY_HEIGHT - SECTION_GAP
local FIRST_KEY_ROW_Y = CHANNEL_ROW_Y - KEY_SIZE - SECTION_GAP

local ACCENT = { 0.41, 0.80, 0.94 }
local BG_COLOR = { 0.06, 0.07, 0.09, 0.80 }
local HEADER_COLOR = { 0.10, 0.12, 0.16, 0.88 }
local KEY_COLOR = { 0.14, 0.15, 0.18, 0.85 }
local KEY_HOVER_COLOR = { 0.20, 0.23, 0.28, 1 }
local KEY_DOWN_COLOR = { 0.09, 0.10, 0.12, 1 }
local SEND_COLOR = { 0.14, 0.30, 0.26, 1 }
local SEND_HOVER_COLOR = { 0.18, 0.42, 0.36, 1 }
local TEXT_COLOR = { 0.92, 0.94, 0.97 }

local ROWS = {
	{ '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' },
	{ 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p' },
	{ 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l' },
	{ 'z', 'x', 'c', 'v', 'b', 'n', 'm' },
}

local keyboardFrame

local function RunCommand(text)
	if not text or text:trim() == '' then return end
	local editBox = ChatFrame1EditBox
	editBox:SetText(text)
	ChatEdit_SendText(editBox, 0)
end

-- A flat, modern key button with its own hover/press feedback, bigger
-- and better separated than the default WoW button skin for easier
-- touch accuracy.
local function CreateKey(parent, width, label, onClick, accented)
	local baseColor = accented and SEND_COLOR or KEY_COLOR
	local hoverColor = accented and SEND_HOVER_COLOR or KEY_HOVER_COLOR

	local b = CreateFrame('Button', nil, parent)
	b:SetSize(width, KEY_SIZE)

	local bg = b:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(baseColor))

	local accentLine = b:CreateTexture(nil, 'ARTWORK')
	accentLine:SetPoint('BOTTOMLEFT')
	accentLine:SetPoint('BOTTOMRIGHT')
	accentLine:SetHeight(2)
	accentLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], accented and 1 or 0.6)

	local text = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	text:SetPoint('CENTER')
	text:SetText(label)
	text:SetTextColor(unpack(TEXT_COLOR))
	local font, _, flags = text:GetFont()
	text:SetFont(font, KEY_FONT_SIZE, flags)

	b:SetScript('OnEnter', function() bg:SetColorTexture(unpack(hoverColor)) end)
	b:SetScript('OnLeave', function() bg:SetColorTexture(unpack(baseColor)) end)
	b:SetScript('OnMouseDown', function() bg:SetColorTexture(unpack(KEY_DOWN_COLOR)) end)
	b:SetScript('OnMouseUp', function() bg:SetColorTexture(unpack(hoverColor)) end)
	b:SetScript('OnClick', onClick)

	return b
end

local function CreateKeyRow(parent, keys, rowIndex, display)
	local count = #keys
	local totalWidth = count * KEY_SIZE + (count - 1) * GAP
	local startX = -totalWidth / 2 + KEY_SIZE / 2
	for i, char in ipairs(keys) do
		local b = CreateKey(parent, KEY_SIZE, char, function()
			display:SetText((display:GetText() or '') .. char)
		end)
		b:SetPoint('TOP', parent, 'TOP', startX + (i - 1) * (KEY_SIZE + GAP), FIRST_KEY_ROW_Y - (rowIndex - 1) * (KEY_SIZE + GAP))
	end
end

-- Quick chat-channel senders: type the message first, then tap one of
-- these to prefix and send it immediately - no separate Send tap
-- needed, since by the time you pick the channel the message is done.
local function CreateChannelRow(parent, yOffset, display)
	local defs = {
		{ label = '/say', width = 110 },
		{ label = '/party', width = 120 },
		{ label = '/r', width = 90 },
	}

	local totalWidth = 0
	for _, d in ipairs(defs) do totalWidth = totalWidth + d.width + GAP end
	totalWidth = totalWidth - GAP

	local cursorX = -totalWidth / 2
	for _, d in ipairs(defs) do
		local prefix = d.label .. ' '
		local b = CreateKey(parent, d.width, d.label, function()
			local message = display:GetText() or ''
			RunCommand(prefix .. message)
			display:SetText('')
		end)
		b:SetPoint('TOP', parent, 'TOP', cursorX + d.width / 2, yOffset)
		cursorX = cursorX + d.width + GAP
	end

	return totalWidth
end

local function CreateFunctionRow(parent, yOffset, display)
	local defs = {
		{ label = '/', width = 64, onClick = function() display:SetText((display:GetText() or '') .. '/') end },
		{ label = 'Space', width = 140, onClick = function() display:SetText((display:GetText() or '') .. ' ') end },
		{ label = '<-', width = 88, onClick = function()
			local t = display:GetText() or ''
			display:SetText(t:sub(1, -2))
		end },
		{ label = 'Clear', width = 108, onClick = function() display:SetText('') end },
		{ label = 'Send', width = 120, accented = true, onClick = function()
			RunCommand(display:GetText())
			display:SetText('')
		end },
	}

	local totalWidth = 0
	for _, d in ipairs(defs) do totalWidth = totalWidth + d.width + GAP end
	totalWidth = totalWidth - GAP

	local cursorX = -totalWidth / 2
	for _, d in ipairs(defs) do
		local b = CreateKey(parent, d.width, d.label, d.onClick, d.accented)
		b:SetPoint('TOP', parent, 'TOP', cursorX + d.width / 2, yOffset)
		cursorX = cursorX + d.width + GAP
	end

	return totalWidth
end

local function CreateKeyboardFrame()
	local frame = CreateFrame('Frame', 'WoWDeckKeyboard', UIParent)
	frame:SetPoint('CENTER', 0, -120)
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
	title:SetPoint('TOP', 0, -12)
	title:SetText('WoWDeck Keyboard')
	title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

	local display = CreateFrame('EditBox', nil, frame, 'InputBoxTemplate')
	display:SetSize(540, DISPLAY_HEIGHT)
	display:SetPoint('TOP', 0, DISPLAY_Y)
	display:SetAutoFocus(false)
	local dFont, _, dFlags = display:GetFont()
	display:SetFont(dFont, 20, dFlags)
	display:SetText('')
	display:SetScript('OnEnterPressed', function(self)
		RunCommand(self:GetText())
		self:SetText('')
	end)

	CreateChannelRow(frame, CHANNEL_ROW_Y, display)

	for i, row in ipairs(ROWS) do
		CreateKeyRow(frame, row, i, display)
	end

	local functionRowY = FIRST_KEY_ROW_Y - #ROWS * (KEY_SIZE + GAP)
	local functionRowWidth = CreateFunctionRow(frame, functionRowY, display)

	local closeBtn = CreateFrame('Button', nil, frame, 'UIPanelCloseButton')
	closeBtn:SetPoint('TOPRIGHT', -4, -4)
	closeBtn:SetScript('OnClick', function() frame:Hide() end)

	-- Size the frame to fit its widest row plus the key grid height,
	-- instead of a guessed constant.
	local widestKeyRow = 10 * KEY_SIZE + 9 * GAP
	local contentWidth = math.max(widestKeyRow, functionRowWidth, 560)
	frame:SetWidth(contentWidth + 60)
	frame:SetHeight(-functionRowY + KEY_SIZE + 30)

	tinsert(UISpecialFrames, 'WoWDeckKeyboard')
	return frame
end

function WoWDeck_ToggleKeyboard()
	if not keyboardFrame then
		keyboardFrame = CreateKeyboardFrame()
	end
	keyboardFrame:SetShown(not keyboardFrame:IsShown())
end
