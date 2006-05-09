local locals = KC_ITEMS_LOCALS.modules.linkview

local frame = AceGUI:new()
local config = {
	name	  = "BulkMail_GUIFrame",
	type	  = ACEGUI_DIALOG,
	title	  = locals.gui.title,
	isSpecial = TRUE,
	width	  = 375,
	height	  = 400,
	OnShow	  = "Build",
	OnHide	  = "Cleanup",
	elements  = {
		Items	 = {
			type	 = ACEGUI_LISTBOX,
			title	 = locals.gui.items,
			width	 = 351,
			height	 = 320,
			anchors	 = {
				topleft = {xOffset = 12, yOffset = -37}
			},
			fill		= "FillItemsListBox",
			OnItemEnter = "OnItemEnter",
			OnItemLeave = "OnItemLeave",
			OnSelect	= "OnSelect",
			OnReceiveDrag = "OnReceiveDrag",
		},
	}
}

frame:Initialize(BulkMail_GUI, config)
BulkMail.gui = frame

function frame:OnItemEnter()
	if (not self.idTable) then return; end
	GameTooltip:SetOwner(this, "ANCHOR_LEFT")
	GameTooltip:SetHyperlink(self.idTable[this.rowID])
end

function frame:OnItemLeave()
	GameTooltip:Hide()
end

function frame:FillItemsListBox()
	self.itemsTable = {}
	self.idTable = {}
	if (not self.sendCache or getn(self.sendCache) == 0) then self.itemsTable = {locals.gui.nothing}; self.idTable = nil; return; end
	for i, v in pairs(self.sendCache) do
		local link = GetContainerItemLink(v[1], v[2])
		local qty = select(2, GetContainerItemInfo)
		local itemID = select(3, string.find(link, "(item:%d+):"))
		local itemColorText = string.sub(link, 1, 10) .. select(3, string.sub(string.find(link, "(%b[])"), 2, -2))
		local itemColorQtyText = qty > 1 and itemColorText .. " (" .. qty .. ")"
		table.insert(self.itemsTable, itemColorQtyText)
		table.insert(self.idTable, itemID)
	end

	return self.itemsTable or {locals.gui.noitems}
end

function frame:AddGUIItem()
	local pattern = self.SearchBox.SearchText:GetValue()
	pattern = pattern and ace.trim(pattern) or nil
	self:BuildSearchTable(pattern)
	self:BuildSortedTable()
	self.Items:ClearList()
	self.Items:Update()
end

function frame:Build()
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
	local id = self.idTable[this.rowID]
	local link = 
	if (arg1 ~= "LeftButton") then
		
	elseif( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
		ChatFrameEditBox:Insert(self.app.common:GetTextLink(id))
	elseif (IsControlKeyDown()) then
		DressUpItemLink(id)
	else
		SetItemRef(id, self.app.common:GetTextLink(id), arg1)
	end
end
