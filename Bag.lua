--[[
Bag Manager: a paged list of everything in your bags, built entirely
from plain clickable buttons - no custom gamepad/joystick handling
needed, since ConsolePort's own UI cursor already navigates any
standard button on screen (the same way it navigates every other
WoWDeck button). Select an item to Use it, Sell it (only enabled with
a vendor window open), or Delete it (always confirmed first - deleting
items is irreversible).

Also has a "Find Unused Quest Items" mode: quest-class items (item
class 12, a stable long-standing Blizzard constant) that aren't
referenced by any quest currently in your log are shown as candidates
for deletion - still going through the same confirmed-delete flow,
never an automatic bulk delete, since this is a best-effort cross
reference, not a guarantee.
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

local QUEST_ITEM_CLASS_ID = 12 -- Enum.ItemClass.Questitem

local ACCENT = { 0.41, 0.80, 0.94 }
local QUEST_ACCENT = { 0.95, 0.75, 0.25 }
local BG_COLOR = { 0.06, 0.07, 0.09, 0.95 }
local HEADER_COLOR = { 0.10, 0.12, 0.16, 1 }
local BTN_COLOR = { 0.13, 0.14, 0.17, 0.95 }
local BTN_HOVER_COLOR = { 0.19, 0.22, 0.27, 1 }
local BTN_DOWN_COLOR = { 0.08, 0.09, 0.11, 1 }
local BTN_DISABLED_COLOR = { 0.08, 0.08, 0.09, 0.95 }
local TEXT_COLOR = { 0.92, 0.94, 0.97 }
local TEXT_DISABLED_COLOR = { 0.45, 0.45, 0.48 }

local bagFrame, actionFrame
local rowButtons = {}
local items = {}
local currentGroup = 0 -- 0-indexed; each group shows COLUMN_COUNT pages side by side
local filterMode = 'all' -- 'all' or 'quest'

---------------------------------------------------------------
-- Scanning
---------------------------------------------------------------

local function GetItemName(itemID)
	local ok, name = pcall(C_Item.GetItemNameByID, itemID)
	if ok and name then
		return name
	end
	return ('Item #%d'):format(itemID)
end

local function GetItemClassID(itemID)
	local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
	if ok then
		return classID
	end
end

local function ScanBags()
	wipe(items)
	local maxBag = NUM_BAG_SLOTS or 4
	for bag = 0, maxBag do
		local numSlots = C_Container.GetContainerNumSlots(bag)
		for slot = 1, numSlots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				table.insert(items, {
					bag = bag,
					slot = slot,
					itemID = info.itemID,
					name = GetItemName(info.itemID),
					hyperlink = info.hyperlink,
					icon = info.iconFileID,
					count = info.stackCount or 1,
					classID = GetItemClassID(info.itemID),
				})
			end
		end
	end
end

-- Cross-references quest-class bag items against every quest actually
-- in your log right now, via the item each quest's log entry shows
-- (the same data the default quest log's item button uses). Wrapped
-- in pcall since this is an old global API that could be renamed in
-- some client versions - if it fails, we just treat all quest-class
-- items as candidates rather than crashing.
local function GetActiveQuestItemIDs()
	local ids = {}
	local numEntries = C_QuestLog.GetNumQuestLogEntries()
	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader then
			local ok, _, _, itemID = pcall(GetQuestLogSpecialItemInfo, i)
			if ok and itemID then
				ids[itemID] = true
			end
		end
	end
	return ids
end

local function GetDisplayList()
	if filterMode ~= 'quest' then
		return items
	end
	local activeIDs = GetActiveQuestItemIDs()
	local filtered = {}
	for _, item in ipairs(items) do
		if item.classID == QUEST_ITEM_CLASS_ID and not activeIDs[item.itemID] then
			table.insert(filtered, item)
		end
	end
	return filtered
end

---------------------------------------------------------------
-- Shared flat button styling
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

local function AddButtonVisuals(b, width, height, label)
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
	b.AccentLine = accentLine

	local text = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	text:SetPoint('CENTER')
	text:SetText(label)
	text:SetTextColor(unpack(TEXT_COLOR))
	b.text = text

	b:SetScript('OnEnter', function() if b.enabled ~= false then bg:SetColorTexture(unpack(BTN_HOVER_COLOR)) end end)
	b:SetScript('OnLeave', function() if b.enabled ~= false then bg:SetColorTexture(unpack(BTN_COLOR)) end end)
	b:SetScript('OnMouseDown', function() if b.enabled ~= false then bg:SetColorTexture(unpack(BTN_DOWN_COLOR)) end end)
	b:SetScript('OnMouseUp', function() if b.enabled ~= false then bg:SetColorTexture(unpack(BTN_HOVER_COLOR)) end end)
end

local function CreateFlatButton(parent, width, height, label, onClick)
	local b = CreateFrame('Button', nil, parent)
	AddButtonVisuals(b, width, height, label)
	if onClick then
		b:SetScript('OnClick', onClick)
	end
	return b
end

-- Use/Sell must be secure action buttons: some items' on-use effect
-- casts a protected spell, and calling UseContainerItem directly from
-- addon Lua trips Blizzard's "blocked from an action only available
-- to the Blizzard UI" taint check even on a real click. A
-- SecureActionButtonTemplate with item attributes is the sanctioned
-- way around this - it's how Blizzard's own bag buttons do it.
-- Critically, the UI-transition logic must be PostClick, not OnClick -
-- SetScript("OnClick", ...) on a secure template REPLACES its built-in
-- secure click handler.
local function CreateSecureItemButton(parent, width, height, label, postClickFn)
	local b = CreateFrame('Button', nil, parent, 'SecureActionButtonTemplate')
	b:RegisterForClicks('AnyUp', 'AnyDown')
	AddButtonVisuals(b, width, height, label)
	b:SetScript('PostClick', postClickFn)
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
-- Action menu (Use / Sell / Delete / Cancel)
---------------------------------------------------------------

local function ShowActionMenu(item)
	actionFrame.item = item
	actionFrame.NameText:SetText(item.name)

	-- Attributes on secure buttons can only change outside combat.
	-- The value must be a real item name or hyperlink - "item:<id>" is
	-- macro conditional syntax, not a valid attribute value.
	if not InCombatLockdown() then
		local itemRef = item.hyperlink or item.name
		actionFrame.UseButton:SetAttribute('type', 'item')
		actionFrame.UseButton:SetAttribute('item', itemRef)
		actionFrame.SellButton:SetAttribute('type', 'item')
		actionFrame.SellButton:SetAttribute('item', itemRef)
	end

	local canSell = MerchantFrame and MerchantFrame:IsShown()
	SetButtonEnabled(actionFrame.SellButton, canSell)
	actionFrame.SellButton.text:SetText(canSell and 'Sell' or 'Sell (no vendor open)')

	bagFrame:Hide()
	actionFrame:Show()
end

---------------------------------------------------------------
-- List
---------------------------------------------------------------

local function RefreshList()
	ScanBags()
	local list = GetDisplayList()
	local totalPages = math.max(1, math.ceil(#list / PAGE_SIZE))
	local totalGroups = math.max(1, math.ceil(totalPages / COLUMN_COUNT))
	if currentGroup > totalGroups - 1 then
		currentGroup = totalGroups - 1
	end

	local groupStart = currentGroup * GROUP_SIZE
	for col = 1, COLUMN_COUNT do
		local colStart = groupStart + (col - 1) * PAGE_SIZE
		for i = 1, PAGE_SIZE do
			local item = list[colStart + i]
			local row = rowButtons[col][i]
			if item then
				row.item = item
				row.Icon:SetTexture(item.icon)
				row.text:SetText(('%s x%d'):format(item.name, item.count))
				if item.classID == QUEST_ITEM_CLASS_ID then
					row.AccentLine:SetColorTexture(QUEST_ACCENT[1], QUEST_ACCENT[2], QUEST_ACCENT[3], 0.9)
				else
					row.AccentLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.5)
				end
				row:Show()
			else
				row.item = nil
				row:Hide()
			end
		end
	end

	if filterMode == 'quest' then
		bagFrame.TitleText:SetText(('Unused Quest Items (%d)'):format(#list))
		bagFrame.CleanupButton.text:SetText('Show All Items')
		bagFrame.StatusText:SetShown(#list == 0)
		bagFrame.StatusText:SetText('No unused quest items found - nice and tidy!')
	else
		bagFrame.TitleText:SetText('Bag Manager')
		bagFrame.CleanupButton.text:SetText('Find Unused Quest Items')
		bagFrame.StatusText:Hide()
	end

	local firstPage = currentGroup * COLUMN_COUNT + 1
	local lastPage = math.min(firstPage + COLUMN_COUNT - 1, totalPages)
	bagFrame.PageText:SetText(('Pages %d-%d of %d'):format(firstPage, lastPage, totalPages))
	SetButtonEnabled(bagFrame.PrevButton, currentGroup > 0)
	SetButtonEnabled(bagFrame.NextButton, currentGroup < totalGroups - 1)
end

local function CreateRow(col, index)
	local row = CreateFrame('Button', nil, bagFrame)
	row:SetSize(COLUMN_WIDTH, ROW_HEIGHT)
	local colX = -LIST_WIDTH / 2 + COLUMN_WIDTH / 2 + (col - 1) * (COLUMN_WIDTH + COLUMN_GAP)
	row:SetPoint('TOP', colX, -HEADER_HEIGHT - (index - 1) * (ROW_HEIGHT + 6))

	local bg = row:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(BTN_COLOR))
	row.bg = bg

	local accentLine = row:CreateTexture(nil, 'ARTWORK')
	accentLine:SetPoint('BOTTOMLEFT')
	accentLine:SetPoint('BOTTOMRIGHT')
	accentLine:SetHeight(2)
	accentLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.5)
	row.AccentLine = accentLine

	local icon = row:CreateTexture(nil, 'ARTWORK')
	icon:SetSize(ROW_HEIGHT - 10, ROW_HEIGHT - 10)
	icon:SetPoint('LEFT', 10, 0)
	row.Icon = icon

	local text = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	text:SetPoint('LEFT', icon, 'RIGHT', 10, 0)
	text:SetPoint('RIGHT', -10, 0)
	text:SetJustifyH('LEFT')
	text:SetTextColor(unpack(TEXT_COLOR))
	row.text = text

	row:SetScript('OnEnter', function() bg:SetColorTexture(unpack(BTN_HOVER_COLOR)) end)
	row:SetScript('OnLeave', function() bg:SetColorTexture(unpack(BTN_COLOR)) end)
	row:SetScript('OnClick', function(self)
		if self.item then
			ShowActionMenu(self.item)
		end
	end)

	return row
end

local function CreateBagFrame()
	bagFrame = CreateFrame('Frame', 'WoWDeckBagFrame', UIParent)
	local controlRows = 3 -- prev/next, cleanup toggle, close
	local controlHeight = controlRows * (CONTROL_HEIGHT + CONTROL_GAP) + BOTTOM_PADDING
	bagFrame:SetSize(LIST_WIDTH + 60, HEADER_HEIGHT + PAGE_SIZE * (ROW_HEIGHT + 6) + controlHeight)
	bagFrame:SetPoint('CENTER')
	bagFrame:SetFrameStrata('DIALOG')
	bagFrame:SetMovable(true)
	bagFrame:EnableMouse(true)
	bagFrame:RegisterForDrag('LeftButton')
	bagFrame:SetScript('OnDragStart', bagFrame.StartMoving)
	bagFrame:SetScript('OnDragStop', bagFrame.StopMovingOrSizing)
	bagFrame:Hide()

	bagFrame.TitleText = CreatePanelChrome(bagFrame, HEADER_HEIGHT, 'Bag Manager')

	local statusText = bagFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	statusText:SetPoint('TOP', bagFrame.TitleText, 'BOTTOM', 0, -4)
	statusText:SetWidth(LIST_WIDTH)
	statusText:SetJustifyH('CENTER')
	statusText:SetTextColor(0.6, 1, 0.6)
	statusText:Hide()
	bagFrame.StatusText = statusText

	for col = 1, COLUMN_COUNT do
		rowButtons[col] = {}
		for i = 1, PAGE_SIZE do
			rowButtons[col][i] = CreateRow(col, i)
		end
	end

	local bottomY = -HEADER_HEIGHT - PAGE_SIZE * (ROW_HEIGHT + 6)

	local prevButton = CreateFlatButton(bagFrame, 100, CONTROL_HEIGHT, '< Prev', function()
		currentGroup = currentGroup - 1
		RefreshList()
	end)
	prevButton:SetPoint('TOP', -140, bottomY)
	bagFrame.PrevButton = prevButton

	local pageText = bagFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	pageText:SetPoint('TOP', 0, bottomY - 14)
	bagFrame.PageText = pageText

	local nextButton = CreateFlatButton(bagFrame, 100, CONTROL_HEIGHT, 'Next >', function()
		currentGroup = currentGroup + 1
		RefreshList()
	end)
	nextButton:SetPoint('TOP', 140, bottomY)
	bagFrame.NextButton = nextButton

	local cleanupY = bottomY - (CONTROL_HEIGHT + CONTROL_GAP)
	local cleanupButton = CreateFlatButton(bagFrame, LIST_WIDTH, CONTROL_HEIGHT, 'Find Unused Quest Items', function()
		filterMode = (filterMode == 'quest') and 'all' or 'quest'
		currentGroup = 0
		RefreshList()
	end)
	cleanupButton:SetPoint('TOP', 0, cleanupY)
	bagFrame.CleanupButton = cleanupButton

	local closeY = cleanupY - (CONTROL_HEIGHT + CONTROL_GAP)
	local closeButton = CreateFlatButton(bagFrame, 200, CONTROL_HEIGHT, 'Close', function()
		bagFrame:Hide()
	end)
	closeButton:SetPoint('TOP', 0, closeY)

	tinsert(UISpecialFrames, 'WoWDeckBagFrame')

	bagFrame:RegisterEvent('BAG_UPDATE')
	bagFrame:RegisterEvent('MERCHANT_SHOW')
	bagFrame:RegisterEvent('MERCHANT_CLOSED')
	bagFrame:SetScript('OnEvent', function()
		if bagFrame:IsShown() then
			RefreshList()
		end
	end)
	bagFrame:SetScript('OnShow', function()
		filterMode = 'all'
		RefreshList()
	end)
end

---------------------------------------------------------------
-- Action frame (Use / Sell / Delete / Cancel)
---------------------------------------------------------------

local function CreateActionFrame()
	actionFrame = CreateFrame('Frame', 'WoWDeckBagActionFrame', UIParent)
	actionFrame:SetSize(340, 340)
	actionFrame:SetPoint('CENTER')
	actionFrame:SetFrameStrata('DIALOG')
	actionFrame:SetMovable(true)
	actionFrame:EnableMouse(true)
	actionFrame:RegisterForDrag('LeftButton')
	actionFrame:SetScript('OnDragStart', actionFrame.StartMoving)
	actionFrame:SetScript('OnDragStop', actionFrame.StopMovingOrSizing)
	actionFrame:Hide()

	CreatePanelChrome(actionFrame, 56, 'Item')

	local nameText = actionFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	nameText:SetPoint('TOP', 0, -20)
	nameText:SetWidth(300)
	nameText:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
	actionFrame.NameText = nameText

	local useButton = CreateSecureItemButton(actionFrame, 260, 56, 'Use', function()
		actionFrame:Hide()
		bagFrame:Show()
	end)
	useButton:SetPoint('TOP', 0, -80)
	actionFrame.UseButton = useButton

	local sellButton = CreateSecureItemButton(actionFrame, 260, 56, 'Sell', function()
		actionFrame:Hide()
		bagFrame:Show()
	end)
	sellButton:SetPoint('TOP', useButton, 'BOTTOM', 0, -16)
	actionFrame.SellButton = sellButton

	local deleteButton = CreateFlatButton(actionFrame, 260, 56, 'Delete', function()
		local item = actionFrame.item
		if not item then return end
		StaticPopupDialogs['WOWDECK_CONFIRM_DELETE'] = {
			text = ('Delete %s? This cannot be undone.'):format(item.name),
			button1 = 'Delete',
			button2 = 'Cancel',
			whileDead = true,
			showAlert = true,
			OnAccept = function()
				C_Container.PickupContainerItem(item.bag, item.slot)
				DeleteCursorItem()
				actionFrame:Hide()
				bagFrame:Show()
			end,
			OnCancel = function()
				actionFrame:Hide()
				bagFrame:Show()
			end,
			timeout = 0,
			hideOnEscape = true,
		}
		StaticPopup_Show('WOWDECK_CONFIRM_DELETE')
	end)
	deleteButton:SetPoint('TOP', sellButton, 'BOTTOM', 0, -16)
	actionFrame.DeleteButton = deleteButton

	local cancelButton = CreateFlatButton(actionFrame, 260, 56, 'Cancel', function()
		actionFrame:Hide()
		bagFrame:Show()
	end)
	cancelButton:SetPoint('TOP', deleteButton, 'BOTTOM', 0, -16)

	tinsert(UISpecialFrames, 'WoWDeckBagActionFrame')
end

---------------------------------------------------------------

function WoWDeck_ToggleBagManager()
	if not bagFrame then
		CreateBagFrame()
		CreateActionFrame()
	end
	if bagFrame:IsShown() or actionFrame:IsShown() then
		bagFrame:Hide()
		actionFrame:Hide()
	else
		currentGroup = 0
		bagFrame:Show()
	end
end
