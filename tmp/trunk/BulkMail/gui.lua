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
			OnSelect	= "OnSelect",
			OnClick     = "OnClick",
		},
	},
}

frame:Initialize(BulkMail_GUI, config)
BulkMail.gui = frame

function frame:OnItemEnter()
	if (not self.idTable) then return; end
	local bag, slot = unpack(self.idTable[this.rowID])
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(select(3, string.find(GetContainerItemLink(bag, slot), "(item:%d+)")))
end

function frame:OnItemLeave()
	GameTooltip:Hide()
end

function frame:FillItemsListBox()
	self.itemsTable = {}
	self.idTable = {}
	local sendCache = BulkMail.sendCache
	if (not sendCache or getn(sendCache) == 0) then self.itemsTable = {BulkMailLocals.gui.noitems}; self.idTable = nil; return; end
	for i, v in pairs(sendCache) do
		local link = GetContainerItemLink(v[1], v[2])
		local qty = select(2, GetContainerItemInfo(v[1], v[2]))
		local itemColorText = string.sub(link, 1, 10) .. string.sub(select(3, string.find(link, "(%b[])")), 2, -2)
		local itemColorQtyText = qty > 1 and itemColorText .. " (" .. qty .. ")"
		table.insert(self.itemsTable, itemColorQtyText or itemColorText)
		table.insert(self.idTable, v)
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
	self.Items:ClearList()
end

function frame:OnSelect()
	if (not self.idTable) then return; end
	local bag, slot = unpack(self.idTable[this.rowID])
	local id = self.idTable[this.rowID]

	if (arg1 ~= "LeftButton") then
	elseif( IsAltKeyDown() ) then
		BulkMail:SendCacheToggle(bag, slot)
	elseif( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
		ChatFrameEditBox:Insert(GetContainerItemLink(bag, slot))
	elseif (IsControlKeyDown()) then
		DressUpItemLink(GetContainerItemLink(bag, slot))
	else
		SetItemRef(id, GetContainerItemLink(bag, slot), arg1)
	end
end

function frame:OnClick()
	print("foo")
	if CursorHasItem() then
		print(this:GetParent():GetID())
		print(this:GetID())
		BulkMail:SendCacheAdd(this)
		self.Items:Update()
	end
end
