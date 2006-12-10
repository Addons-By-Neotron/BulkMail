local L = BulkMail.L
local frame = AceGUI:new()
local config = {
	name      = "BulkMail_GUIFrame",
	type      = ACEGUI_DIALOG,
	title     = "BulkMail",
	isSpecial = TRUE,
	backdrop  = "small",
	width     = 300,
	height    = 430,
	OnShow    = "Build",
	OnHide    = "Cleanup",
	elements  = {
		Items = {
			type        = ACEGUI_LISTBOX,
			title       = L["Items to be sent (Alt-Click to add/remove):"],
			width       = 276,
			height      = 288,
			anchors     = {
				topleft = {xOffset = 12, yOffset = -37}
			},
			fill         = "FillItemsListBox",
			OnSelect    = "OnItemSelect",
			OnItemEnter = "OnItemEnter",
			OnItemLeave = "OnItemLeave",
		},
		Clear = {
			type    = ACEGUI_BUTTON,
			title   = L["Clear"],
			width   = 98,
			height  = 26,
			anchors = {
				bottomleft = {relpoint="bottomleft", xOffset = 16, yOffset = 18}
			},
			OnClick = "OnClearClick",
		},
		Send = {
			type    = ACEGUI_BUTTON,
			title   = L["Send"],
			width   = 64,
			height  = 26,
			anchors = {
				bottom = {relpoint="bottom", xOffset = 0, yOffset = 18}
			},
			OnClick = "OnSendClick",
		},
		DropBox = {
			type    = ACEGUI_OPTIONSBOX,
			width   = 276,
			height  = 56,
			anchors = {
				top = {relTo="$parentItems", relPoint = "bottom", xOffset = 0, yOffset = -2}
			},
			elements = {
				DropButton = {
					type    = ACEGUI_BUTTON,
					title   = "Drop items here for Sending",
					width   = 272,
					height  = 56,
					anchors = {
						center = {relPoint = "center", xOffset = 0, yOffset = 0}
					},
					OnClick = "OnDropClick",
					OnReceiveDrag = "OnDropClick",
				},
			},
		},
	},
}

frame:Initialize(BulkMail_GUI, config)
BulkMail.gui = frame

function frame:OnItemEnter()
	if self.bsTable then
		local bag, slot = unpack(self.bsTable[this.rowID])
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(select(3, string.find(GetContainerItemLink(bag, slot), "(item:%d+:%d+:%d+:%d+)")))
	end
end

function frame:OnItemLeave()
	GameTooltip:Hide()
end

function frame:FillItemsListBox()
	self.itemsTable = {}
	self.idTable = {}
	self.bsTable = {}
	
	local sendCache = BulkMail.sendCache
	if not sendCache or table.getn(sendCache) == 0 then
		self.itemsTable = {L["No items selected"]}
		self.idTable = nil
		self.bsTable = nil
		return self.itemsTable
	end
	
	for i, v in pairs(sendCache) do
		local link = GetContainerItemLink(v[1], v[2])
		local qty = select(2, GetContainerItemInfo(v[1], v[2]))
		local itemText = string.sub(link, 1, 10) .. string.sub(select(3, string.find(link, "(%b[])")), 2, -2)
		itemText = qty > 1 and itemText .. " (" .. qty .. ")" or itemText
		table.insert(self.itemsTable, itemText)
		table.insert(self.idTable, link)
		table.insert(self.bsTable, v)
	end

	return self.itemsTable or {L["No items selected"]}
end

function frame:Build()
	for i = 1, 16 do
		self.Items["Row"..i]:RegisterForClicks("LeftButtonDown", "RightButtonDown")
	end
end

function frame:Cleanup()
	self.itemsTable = nil
	self.idTable = nil
	self.bsTable = nil
	self.Items:ClearList()
end

function frame:OnItemSelect()
	if not self.bsTable then return end
	local bag, slot = unpack(self.bsTable[this.rowID])

	if bag and slot and arg1 == "LeftButton" then
		if IsAltKeyDown() then
			BulkMail:SendCacheToggle(bag, slot)
		elseif IsShiftKeyDown() and ChatFrameEditBox:IsVisible() then
			ChatFrameEditBox:Insert(GetContainerItemLink(bag, slot))
		elseif IsControlKeyDown() then
			DressUpItemLink(GetContainerItemLink(bag, slot))
		else
			SetItemRef(select(3, string.find(GetContainerItemLink(bag, slot), "(item:%d+:%d+:%d+:%d+)")), GetContainerItemLink(bag, slot), arg1)
		end
	end
end

function frame:OnClearClick()
	BulkMail:SendCacheCleanUp()
	self.idTable = nil
	self.bsTable = nil
	self.Items:ClearList()
end

local function GetLockedContainerItem()
	for bag=0, NUM_BAG_SLOTS do
		for slot=1, GetContainerNumSlots(bag) do
			if select(3, GetContainerItemInfo(bag, slot)) then
				return bag, slot
			end
		end
	end
end

function frame:OnSendClick()
	if not BulkMail.sendCache then return end
	BulkMail:SendMailMailButton_OnClick()
end

function frame:OnDropClick()
	if GetSendMailItem() then
		BulkMail:Print(L["WARNING: Cursor item detection is NOT well-defined when multiple items are 'locked'.   Alt-click is recommended for adding items when there is already an item in the Send Mail item frame."])
	end
	if CursorHasItem() and GetLockedContainerItem() then
		BulkMail:SendCacheAdd(GetLockedContainerItem())
		--To clear the cursor.
		PickupContainerItem(GetLockedContainerItem())
	end
	self.Items:Update()
end