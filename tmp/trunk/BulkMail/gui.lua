local frame = AceGUI:new()
local config = {
	name	  = "BulkMail_GUIFrame",
	type	  = ACEGUI_DIALOG,
	title	  = BulkMailLocals.gui.title,
	isSpecial = TRUE,
	backdrop  = "small",
	width	  = 300,
	height	  = 430,
	OnShow	  = "Build",
	OnHide	  = "Cleanup",
	elements  = {
		Items	 = {
			type	 = ACEGUI_LISTBOX,
			title	 = BulkMailLocals.gui.items,
			width	 = 276,
			height	 = 345,
			anchors	 = {
				topleft = {xOffset = 12, yOffset = -37}
			},
			fill		= "FillItemsListBox",
			OnItemEnter = "OnItemEnter",
			OnItemLeave = "OnItemLeave",
			OnSelect	= "OnItemSelect",
			OnClick     = "OnItemsClick",
		},
		Clear	= {
			type	= ACEGUI_BUTTON,
			title	= BulkMailLocals.gui.clear,
			width	= 98,
			height	= 26,
			anchors = {
				bottomleft = {xOffset = 16, yOffset = 18}
			},
			OnClick	= "OnClearClick",
		},
	},
}

frame:Initialize(BulkMail_GUI, config)
BulkMail.gui = frame

function frame:OnItemEnter()
	if (not self.bsTable) then return; end
	local bag, slot = unpack(self.bsTable[this.rowID])
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(select(3, string.find(GetContainerItemLink(bag, slot), "(item:%d+:%d+:%d+:%d+)")))
end

function frame:OnItemLeave()
	GameTooltip:Hide()
end

function frame:FillItemsListBox()
	self.itemsTable = {}
	self.idTable = {}
	self.bsTable = {}
	local sendCache = BulkMail.sendCache
	if (not sendCache or getn(sendCache) == 0) then self.itemsTable = {BulkMailLocals.gui.noitems}; self.idTable = nil self.bsTable = nil; return self.itemsTable; end
	for i, v in pairs(sendCache) do
		local link = GetContainerItemLink(v[1], v[2])
		local qty = select(2, GetContainerItemInfo(v[1], v[2]))
		local itemText = string.sub(link, 1, 10) .. string.sub(select(3, string.find(link, "(%b[])")), 2, -2)
		itemText = qty > 1 and itemText .. " (" .. qty .. ")" or itemText
		table.insert(self.itemsTable, itemText)
		table.insert(self.idTable, link)
		table.insert(self.bsTable, v)
	end

	return self.itemsTable or {BulkMailLocals.gui.noitems}
end

function frame:Build()
	self.Items:RegisterForDrag("LeftButton")
	for i = 1, 18 do
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
	if (not self.bsTable) then return; end
	local bag, slot = unpack(self.bsTable[this.rowID])

	if (arg1 ~= "LeftButton") then
	elseif( IsAltKeyDown() ) then
		BulkMail:SendCacheToggle(bag, slot)
	elseif( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
		ChatFrameEditBox:Insert(GetContainerItemLink(bag, slot))
	elseif (IsControlKeyDown()) then
		DressUpItemLink(GetContainerItemLink(bag, slot))
	else
		SetItemRef(select(3, string.find(GetContainerItemLink(bag, slot), "(item:%d+:%d+:%d+:%d+)")), GetContainerItemLink(bag, slot), arg1)
	end
end

function frame:OnItemsClick()
	if CursorHasItem() then
		print(this:GetParent():GetID())
		print(this:GetID())
		BulkMail:SendCacheAdd(this)
		self.Items:Update()
	end
end

function frame:OnClearClick()
	for i, v in pairs(BulkMail.sendCache) do
		BulkMail:SendCacheRemove(unpack(v))
	end
	self.idTable = nil
	self.bsTable = nil
	self.Items:ClearList()
end
