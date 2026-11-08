--[[
Quest Manager: a list of everything in your quest log, 3 pages shown
side by side at once. Select a quest to abandon it - if the quest has
an associated quest item still in your bags, abandoning also offers
to delete that item in the same step, since an abandoned quest's item
usually has no further purpose. Still a single explicit confirmation
naming both consequences; nothing happens automatically.

Quests well below your level are marked using Blizzard's own quest
difficulty color (the same gray used for trivial quest givers, via
GetQuestDifficultyColor) - a "Low-Level Only" filter can show just
those as candidates for cleanup.
]]

local PAGE_SIZE = 10
local COLUMN_COUNT = 3
local COLUMN_WIDTH = 320
local COLUMN_GAP = 24
local ROW_HEIGHT = 44
local HEADER_HEIGHT = 56
local CONTROL_HEIGHT = 44
local CONTROL_GAP = 8
local BOTTOM_PADDING = 16

local GROUP_SIZE = COLUMN_COUNT * PAGE_SIZE
local LIST_WIDTH = COLUMN_COUNT * COLUMN_WIDTH + (COLUMN_COUNT - 1) * COLUMN_GAP

local ACCENT = { 0.41, 0.80, 0.94 }
local LOW_LEVEL_ACCENT = { 0.55, 0.55, 0.58 }
local BG_COLOR = { 0.06, 0.07, 0.09, 0.95 }
local HEADER_COLOR = { 0.10, 0.12, 0.16, 1 }
local BTN_COLOR = { 0.13, 0.14, 0.17, 0.95 }
local BTN_HOVER_COLOR = { 0.19, 0.22, 0.27, 1 }
local BTN_DOWN_COLOR = { 0.08, 0.09, 0.11, 1 }
local BTN_DISABLED_COLOR = { 0.08, 0.08, 0.09, 0.95 }
local TEXT_COLOR = { 0.92, 0.94, 0.97 }
local TEXT_DISABLED_COLOR = { 0.45, 0.45, 0.48 }

local questFrame, actionFrame
local rowButtons = {}
local quests = {}
local currentGroup = 0 -- 0-indexed; each group shows COLUMN_COUNT pages side by side
local filterMode = 'all' -- 'all' or 'lowlevel'

local DEBUG = false
local function Debug(msg)
	if DEBUG and DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage('|cff69ccf0WoWDeck Quests debug:|r ' .. msg)
	end
end

---------------------------------------------------------------
-- Scanning
---------------------------------------------------------------

-- Uses Blizzard's own quest difficulty color (the same gray shown on
-- trivial quest givers/markers) rather than inventing our own level
-- gap threshold - gray is the one difficulty tier where all three
-- color channels are equal, unlike green/yellow/orange/red.
local function IsLowLevelQuest(level)
	if not level then return false end
	-- This client returns a single color table ({r=,g=,b=}), not three
	-- separate numbers - handle both forms since other client flavors
	-- this addon targets may differ.
	local ok, a, b2, c2 = pcall(GetQuestDifficultyColor, level)
	if not ok or not a then return false end
	local r, g, b
	if type(a) == 'table' then
		r, g, b = a.r, a.g, a.b
	else
		r, g, b = a, b2, c2
	end
	if not (r and g and b) then return false end
	return math.abs(r - g) < 0.05 and math.abs(g - b) < 0.05 and r < 0.75
end

local function ScanQuests()
	wipe(quests)
	local numEntries = C_QuestLog.GetNumQuestLogEntries()
	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader then
			local itemName, itemIcon, itemID
			local ok = pcall(function()
				itemName, itemIcon, itemID = GetQuestLogSpecialItemInfo(i)
			end)
			table.insert(quests, {
				questID = info.questID,
				title = info.title,
				level = info.level,
				itemID = ok and itemID or nil,
				itemName = ok and itemName or nil,
				isLowLevel = IsLowLevelQuest(info.level),
			})
		end
	end
	Debug(('numEntries=%d scannedQuests=%d'):format(numEntries, #quests))
end

local function GetDisplayList()
	if filterMode ~= 'lowlevel' then
		return quests
	end
	local filtered = {}
	for _, quest in ipairs(quests) do
		if quest.isLowLevel then
			table.insert(filtered, quest)
		end
	end
	return filtered
end

-- Finds and deletes every copy of the given item currently in bags.
local function DeleteItemFromBags(itemID)
	local maxBag = NUM_BAG_SLOTS or 4
	for bag = 0, maxBag do
		local numSlots = C_Container.GetContainerNumSlots(bag)
		for slot = 1, numSlots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID then
				C_Container.PickupContainerItem(bag, slot)
				DeleteCursorItem()
			end
		end
	end
end

-- Calling SetAbandonQuest+AbandonQuest back-to-back silently did
-- nothing (confirmed: entry count unchanged, no error, yet the same
-- quest abandons fine through the real quest log UI). A working
-- community addon (Questorcism) documents the actual fix: call
-- SetSelectedQuest first, and space all three calls apart with small
-- delays - calling them synchronously back-to-back apparently hits a
-- taint/throttle issue that fails silently instead of erroring.
local function AbandonQuestSequence(quest, onDone)
	local before = C_QuestLog.GetNumQuestLogEntries()
	pcall(C_QuestLog.SetSelectedQuest, quest.questID)
	C_Timer.After(0.15, function()
		pcall(C_QuestLog.SetAbandonQuest, quest.questID)
		C_Timer.After(0.15, function()
			pcall(C_QuestLog.AbandonQuest)
			C_Timer.After(0.15, function()
				local after = C_QuestLog.GetNumQuestLogEntries()
				Debug(('abandon "%s" questID=%s entries %d->%d'):format(
					quest.title, tostring(quest.questID), before, after))
				if quest.itemID then
					DeleteItemFromBags(quest.itemID)
				end
				if onDone then onDone(before, after) end
			end)
		end)
	end)
end

-- Processes a list one at a time (not in parallel) - abandoning
-- several quests simultaneously risks the same throttling issue this
-- whole fix is working around.
local function AbandonQuestsSequentially(questList, index, onAllDone)
	index = index or 1
	if index > #questList then
		if onAllDone then onAllDone() end
		return
	end
	AbandonQuestSequence(questList[index], function()
		AbandonQuestsSequentially(questList, index + 1, onAllDone)
	end)
end

---------------------------------------------------------------
-- Shared flat button styling (duplicated per-file to keep each
-- WoWDeck module self-contained)
---------------------------------------------------------------

local function SetButtonEnabled(b, enabled)
	b.enabled = enabled
	b:EnableMouse(enabled)
	if enabled then
		b.text:SetTextColor(unpack(TEXT_COLOR))
		b.bg:SetColorTexture(unpack(BTN_COLOR))
	else
		b.text:SetTextColor(unpack(TEXT_DISABLED_COLOR))
		b.bg:SetColorTexture(unpack(BTN_DISABLED_COLOR))
	end
end

local function CreateFlatButton(parent, width, height, label, onClick)
	local b = CreateFrame('Button', nil, parent)
	b:SetSize(width, height)

	local bg = b:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(BTN_COLOR))
	b.bg = bg

	local accentLine = b:CreateTexture(nil, 'ARTWORK')
	accentLine:SetPoint('BOTTOMLEFT')
	accentLine:SetPoint('BOTTOMRIGHT')
	accentLine:SetHeight(2)
	accentLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)

	local text = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	text:SetPoint('CENTER')
	text:SetText(label)
	text:SetTextColor(unpack(TEXT_COLOR))
	b.text = text

	b:SetScript('OnEnter', function() if b.enabled ~= false then bg:SetColorTexture(unpack(BTN_HOVER_COLOR)) end end)
	b:SetScript('OnLeave', function() if b.enabled ~= false then bg:SetColorTexture(unpack(BTN_COLOR)) end end)
	b:SetScript('OnMouseDown', function() if b.enabled ~= false then bg:SetColorTexture(unpack(BTN_DOWN_COLOR)) end end)
	b:SetScript('OnMouseUp', function() if b.enabled ~= false then bg:SetColorTexture(unpack(BTN_HOVER_COLOR)) end end)
	if onClick then
		b:SetScript('OnClick', onClick)
	end

	return b
end

local function CreatePanelChrome(parent, headerHeight, titleText)
	local bg = parent:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(BG_COLOR))

	for _, point in ipairs({ 'TOP', 'BOTTOM', 'LEFT', 'RIGHT' }) do
		local line = parent:CreateTexture(nil, 'OVERLAY')
		line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.5)
		if point == 'TOP' or point == 'BOTTOM' then
			line:SetPoint('TOPLEFT', parent, point == 'TOP' and 'TOPLEFT' or 'BOTTOMLEFT')
			line:SetPoint('TOPRIGHT', parent, point == 'TOP' and 'TOPRIGHT' or 'BOTTOMRIGHT')
			line:SetHeight(1)
		else
			line:SetPoint('TOPLEFT', parent, point == 'LEFT' and 'TOPLEFT' or 'TOPRIGHT')
			line:SetPoint('BOTTOMLEFT', parent, point == 'LEFT' and 'BOTTOMLEFT' or 'BOTTOMRIGHT')
			line:SetWidth(1)
		end
	end

	local header = parent:CreateTexture(nil, 'BORDER')
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	header:SetHeight(headerHeight)
	header:SetColorTexture(unpack(HEADER_COLOR))

	local headerLine = parent:CreateTexture(nil, 'ARTWORK')
	headerLine:SetPoint('TOPLEFT', header, 'BOTTOMLEFT')
	headerLine:SetPoint('TOPRIGHT', header, 'BOTTOMRIGHT')
	headerLine:SetHeight(2)
	headerLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)

	local title = parent:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	title:SetPoint('TOP', 0, -14)
	title:SetText(titleText)
	title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

	return title
end

---------------------------------------------------------------
-- Action menu (Abandon / Cancel)
---------------------------------------------------------------

local function ShowActionMenu(quest)
	actionFrame.quest = quest
	actionFrame.NameText:SetText(quest.title)
	if quest.itemID then
		actionFrame.ItemText:SetText('Tied item: ' .. (quest.itemName or ('#' .. quest.itemID)))
		actionFrame.ItemText:Show()
	else
		actionFrame.ItemText:Hide()
	end

	questFrame:Hide()
	actionFrame:Show()
end

---------------------------------------------------------------
-- List
---------------------------------------------------------------

local function RefreshListBody()
	ScanQuests()
	local list = GetDisplayList()
	Debug(('displayList=%d filterMode=%s'):format(#list, filterMode))
	local totalPages = math.max(1, math.ceil(#list / PAGE_SIZE))
	local totalGroups = math.max(1, math.ceil(totalPages / COLUMN_COUNT))
	if currentGroup > totalGroups - 1 then
		currentGroup = totalGroups - 1
	end

	local groupStart = currentGroup * GROUP_SIZE
	for col = 1, COLUMN_COUNT do
		local colStart = groupStart + (col - 1) * PAGE_SIZE
		for i = 1, PAGE_SIZE do
			local quest = list[colStart + i]
			local row = rowButtons[col][i]
			if quest then
				row.quest = quest
				local levelText = quest.level and ('[%d] '):format(quest.level) or ''
				local itemSuffix = ''
				if quest.itemID then
					itemSuffix = ('  |cffaaaaaa(deletes %s)|r'):format(quest.itemName or ('item #' .. quest.itemID))
				end
				row.text:SetText(levelText .. quest.title .. itemSuffix)
				if quest.isLowLevel then
					row.AccentLine:SetColorTexture(LOW_LEVEL_ACCENT[1], LOW_LEVEL_ACCENT[2], LOW_LEVEL_ACCENT[3], 0.9)
					row.text:SetTextColor(LOW_LEVEL_ACCENT[1], LOW_LEVEL_ACCENT[2], LOW_LEVEL_ACCENT[3])
				else
					row.AccentLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.5)
					row.text:SetTextColor(unpack(TEXT_COLOR))
				end
				row:Show()
			else
				row.quest = nil
				row:Hide()
			end
		end
	end

	if filterMode == 'lowlevel' then
		questFrame.TitleText:SetText(('Low-Level Quests (%d)'):format(#list))
		questFrame.FilterButton.text:SetText('Show All Quests')
		SetButtonEnabled(questFrame.AbandonAllButton, #list > 0)
		questFrame.AbandonAllButton.text:SetText(#list > 0
			and ('Abandon All Low-Level Quests (%d)'):format(#list)
			or 'No low-level quests to abandon')
	else
		questFrame.TitleText:SetText('Quest Manager')
		questFrame.FilterButton.text:SetText('Show Low-Level Only')
		SetButtonEnabled(questFrame.AbandonAllButton, false)
		questFrame.AbandonAllButton.text:SetText('Filter to Low-Level first')
	end

	if DEBUG then
		questFrame.StatusText:SetText(('DEBUG: quests=%d displayList=%d rowButtons[1]=%s'):format(
			#quests, #list, tostring(rowButtons[1] and #rowButtons[1] or 'nil')))
		questFrame.StatusText:Show()
	elseif filterMode == 'lowlevel' then
		questFrame.StatusText:SetShown(#list == 0)
		questFrame.StatusText:SetText('No low-level quests found.')
	else
		questFrame.StatusText:Hide()
	end

	local firstPage = currentGroup * COLUMN_COUNT + 1
	local lastPage = math.min(firstPage + COLUMN_COUNT - 1, totalPages)
	questFrame.PageText:SetText(('Pages %d-%d of %d'):format(firstPage, lastPage, totalPages))
	SetButtonEnabled(questFrame.PrevButton, currentGroup > 0)
	SetButtonEnabled(questFrame.NextButton, currentGroup < totalGroups - 1)
end

local function RefreshList()
	local ok, err = pcall(RefreshListBody)
	if not ok then
		Debug('error: ' .. tostring(err))
		if questFrame and questFrame.StatusText then
			questFrame.StatusText:SetText('ERROR: ' .. tostring(err))
			questFrame.StatusText:SetTextColor(1, 0.3, 0.3)
			questFrame.StatusText:Show()
		end
	end
end

local function CreateRow(col, index)
	local row = CreateFrame('Button', nil, questFrame)
	row:SetSize(COLUMN_WIDTH, ROW_HEIGHT)
	local colX = -LIST_WIDTH / 2 + COLUMN_WIDTH / 2 + (col - 1) * (COLUMN_WIDTH + COLUMN_GAP)
	row:SetPoint('TOP', colX, -HEADER_HEIGHT - (index - 1) * (ROW_HEIGHT + 6))

	local bg = row:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(BTN_COLOR))

	local accentLine = row:CreateTexture(nil, 'ARTWORK')
	accentLine:SetPoint('BOTTOMLEFT')
	accentLine:SetPoint('BOTTOMRIGHT')
	accentLine:SetHeight(2)
	accentLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.5)
	row.AccentLine = accentLine

	local text = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	text:SetPoint('LEFT', 14, 0)
	text:SetPoint('RIGHT', -14, 0)
	text:SetJustifyH('LEFT')
	text:SetTextColor(unpack(TEXT_COLOR))
	row.text = text

	row:SetScript('OnEnter', function() bg:SetColorTexture(unpack(BTN_HOVER_COLOR)) end)
	row:SetScript('OnLeave', function() bg:SetColorTexture(unpack(BTN_COLOR)) end)
	row:SetScript('OnClick', function(self)
		if self.quest then
			ShowActionMenu(self.quest)
		end
	end)

	return row
end

local function CreateQuestFrame()
	questFrame = CreateFrame('Frame', 'WoWDeckQuestFrame', UIParent)
	local controlRows = 4 -- prev/next, filter toggle, abandon-all, close
	local controlHeight = controlRows * (CONTROL_HEIGHT + CONTROL_GAP) + BOTTOM_PADDING
	questFrame:SetSize(LIST_WIDTH + 60, HEADER_HEIGHT + PAGE_SIZE * (ROW_HEIGHT + 6) + controlHeight)
	questFrame:SetPoint('CENTER')
	questFrame:SetFrameStrata('DIALOG')
	questFrame:SetMovable(true)
	questFrame:EnableMouse(true)
	questFrame:RegisterForDrag('LeftButton')
	questFrame:SetScript('OnDragStart', questFrame.StartMoving)
	questFrame:SetScript('OnDragStop', questFrame.StopMovingOrSizing)
	questFrame:Hide()

	questFrame.TitleText = CreatePanelChrome(questFrame, HEADER_HEIGHT, 'Quest Manager')

	local statusText = questFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	statusText:SetPoint('TOP', questFrame.TitleText, 'BOTTOM', 0, -4)
	statusText:SetWidth(LIST_WIDTH)
	statusText:SetJustifyH('CENTER')
	statusText:SetTextColor(0.6, 1, 0.6)
	statusText:Hide()
	questFrame.StatusText = statusText

	for col = 1, COLUMN_COUNT do
		rowButtons[col] = {}
		for i = 1, PAGE_SIZE do
			rowButtons[col][i] = CreateRow(col, i)
		end
	end

	local bottomY = -HEADER_HEIGHT - PAGE_SIZE * (ROW_HEIGHT + 6)

	local prevButton = CreateFlatButton(questFrame, 100, CONTROL_HEIGHT, '< Prev', function()
		currentGroup = currentGroup - 1
		RefreshList()
	end)
	prevButton:SetPoint('TOP', -140, bottomY)
	questFrame.PrevButton = prevButton

	local pageText = questFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	pageText:SetPoint('TOP', 0, bottomY - 14)
	questFrame.PageText = pageText

	local nextButton = CreateFlatButton(questFrame, 100, CONTROL_HEIGHT, 'Next >', function()
		currentGroup = currentGroup + 1
		RefreshList()
	end)
	nextButton:SetPoint('TOP', 140, bottomY)
	questFrame.NextButton = nextButton

	local filterY = bottomY - (CONTROL_HEIGHT + CONTROL_GAP)
	local filterButton = CreateFlatButton(questFrame, LIST_WIDTH, CONTROL_HEIGHT, 'Show Low-Level Only', function()
		filterMode = (filterMode == 'lowlevel') and 'all' or 'lowlevel'
		currentGroup = 0
		RefreshList()
	end)
	filterButton:SetPoint('TOP', 0, filterY)
	questFrame.FilterButton = filterButton

	-- Only does anything while the Low-Level filter is active, so you
	-- always see the exact list you're about to mass-abandon before
	-- this button can even be pressed - never a surprise bulk action.
	local abandonAllY = filterY - (CONTROL_HEIGHT + CONTROL_GAP)
	local abandonAllButton = CreateFlatButton(questFrame, LIST_WIDTH, CONTROL_HEIGHT, 'Filter to Low-Level first', function()
		if filterMode ~= 'lowlevel' then return end
		local lowLevelQuests = GetDisplayList()
		if #lowLevelQuests == 0 then return end

		local nameLines = {}
		for i = 1, math.min(10, #lowLevelQuests) do
			local quest = lowLevelQuests[i]
			local line = '- ' .. quest.title
			if quest.itemID then
				line = line .. (' (deletes: %s)'):format(quest.itemName or ('item #' .. quest.itemID))
			end
			table.insert(nameLines, line)
		end
		if #lowLevelQuests > 10 then
			table.insert(nameLines, ('...and %d more'):format(#lowLevelQuests - 10))
		end

		local text = ('Abandon all %d low-level quests? This cannot be undone.\n\n%s')
			:format(#lowLevelQuests, table.concat(nameLines, '\n'))

		StaticPopupDialogs['WOWDECK_CONFIRM_ABANDON_ALL'] = {
			text = text,
			button1 = 'Abandon All',
			button2 = 'Cancel',
			whileDead = true,
			showAlert = true,
			OnAccept = function()
				if questFrame and questFrame.StatusText then
					questFrame.StatusText:SetText(('Abandoning %d quests...'):format(#lowLevelQuests))
					questFrame.StatusText:SetTextColor(1, 0.85, 0.3)
					questFrame.StatusText:Show()
				end
				AbandonQuestsSequentially(lowLevelQuests, 1, function()
					RefreshList()
				end)
			end,
			timeout = 0,
			hideOnEscape = true,
		}
		StaticPopup_Show('WOWDECK_CONFIRM_ABANDON_ALL')
	end)
	abandonAllButton:SetPoint('TOP', 0, abandonAllY)
	questFrame.AbandonAllButton = abandonAllButton

	local closeY = abandonAllY - (CONTROL_HEIGHT + CONTROL_GAP)
	local closeButton = CreateFlatButton(questFrame, 200, CONTROL_HEIGHT, 'Close', function()
		questFrame:Hide()
	end)
	closeButton:SetPoint('TOP', 0, closeY)

	tinsert(UISpecialFrames, 'WoWDeckQuestFrame')

	questFrame:RegisterEvent('QUEST_LOG_UPDATE')
	questFrame:SetScript('OnEvent', function()
		if questFrame:IsShown() then
			RefreshList()
		end
	end)
	questFrame:SetScript('OnShow', RefreshList)
end

---------------------------------------------------------------
-- Action frame (Abandon / Cancel)
---------------------------------------------------------------

local function CreateActionFrame()
	actionFrame = CreateFrame('Frame', 'WoWDeckQuestActionFrame', UIParent)
	actionFrame:SetSize(360, 260)
	actionFrame:SetPoint('CENTER')
	actionFrame:SetFrameStrata('DIALOG')
	actionFrame:SetMovable(true)
	actionFrame:EnableMouse(true)
	actionFrame:RegisterForDrag('LeftButton')
	actionFrame:SetScript('OnDragStart', actionFrame.StartMoving)
	actionFrame:SetScript('OnDragStop', actionFrame.StopMovingOrSizing)
	actionFrame:Hide()

	CreatePanelChrome(actionFrame, 56, 'Quest')

	local nameText = actionFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	nameText:SetPoint('TOP', 0, -20)
	nameText:SetWidth(320)
	nameText:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
	actionFrame.NameText = nameText

	local itemText = actionFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	itemText:SetPoint('TOP', nameText, 'BOTTOM', 0, -8)
	itemText:SetWidth(320)
	itemText:SetJustifyH('CENTER')
	itemText:Hide()
	actionFrame.ItemText = itemText

	local abandonButton = CreateFlatButton(actionFrame, 280, 56, 'Abandon Quest', function()
		local quest = actionFrame.quest
		if not quest then return end

		local text
		if quest.itemID then
			text = ('Abandon "%s" and delete its tied item (%s)? This cannot be undone.')
				:format(quest.title, quest.itemName or ('#' .. quest.itemID))
		else
			text = ('Abandon "%s"? This cannot be undone.'):format(quest.title)
		end

		StaticPopupDialogs['WOWDECK_CONFIRM_ABANDON'] = {
			text = text,
			button1 = 'Abandon',
			button2 = 'Cancel',
			whileDead = true,
			showAlert = true,
			OnAccept = function()
				actionFrame:Hide()
				questFrame:Show()
				if questFrame.StatusText then
					questFrame.StatusText:SetText('Abandoning...')
					questFrame.StatusText:SetTextColor(1, 0.85, 0.3)
					questFrame.StatusText:Show()
				end
				AbandonQuestSequence(quest, function(before, after)
					RefreshList()
					if questFrame.StatusText then
						if after < before then
							questFrame.StatusText:SetText('Quest abandoned.')
							questFrame.StatusText:SetTextColor(0.4, 1, 0.4)
						else
							questFrame.StatusText:SetText('Abandon may not have gone through - check your quest log.')
							questFrame.StatusText:SetTextColor(1, 0.4, 0.4)
						end
						questFrame.StatusText:Show()
					end
				end)
			end,
			OnCancel = function()
				actionFrame:Hide()
				questFrame:Show()
			end,
			timeout = 0,
			hideOnEscape = true,
		}
		StaticPopup_Show('WOWDECK_CONFIRM_ABANDON')
	end)
	abandonButton:SetPoint('TOP', 0, -84)
	actionFrame.AbandonButton = abandonButton

	local cancelButton = CreateFlatButton(actionFrame, 280, 56, 'Cancel', function()
		actionFrame:Hide()
		questFrame:Show()
	end)
	cancelButton:SetPoint('TOP', abandonButton, 'BOTTOM', 0, -16)

	tinsert(UISpecialFrames, 'WoWDeckQuestActionFrame')
end

---------------------------------------------------------------

function WoWDeck_ToggleQuestManager()
	if not questFrame then
		CreateQuestFrame()
		CreateActionFrame()
	end
	if questFrame:IsShown() or actionFrame:IsShown() then
		questFrame:Hide()
		actionFrame:Hide()
	else
		currentGroup = 0
		filterMode = 'all'
		questFrame:Show()
	end
end
