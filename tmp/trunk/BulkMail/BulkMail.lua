function select(n, ...)
	return arg[n]
end

local function GetItemLink(item)
	local name, _, rarity = GetItemInfo(item)
	if name and rarity then
		local color = string.sub(select(4, GetItemQualityColor(rarity)), 3)
		return ace.BuildItemLink(color, item, name) or name
	else
		return item
	end
end

BulkMail = AceAddon:new({
	name            = BulkMailLocals.NAME,
	description     = BulkMailLocals.DESCRIPTION,
	version         = "0.4.5",
	releaseDate     = "05-09-2006",
	aceCompatible   = "103",
	author          = "Mynithrosil of Feathermoon",
	email           = "hyperactiveChipmunk@gmail.com",
	website         = "http://hyperactiveChipmunk.wowinterface.com",
	category        = "other",
	db              = AceDatabase:new("BulkMailDB"),
	defaults        = DEFAULT_OPTIONS,
	cmd             = AceChatCmd:new({"/bulkmail", "/bm"}, BulkMailLocals.CMD_OPTIONS),
	loc             = BulkMailLocals,
})


function BulkMail:Initialize()
	self.metro = Metrognome:GetInstance("1")
	self.metro:Register("BMSend", self.Send, 0.5, self)
	
	BulkMailDB.profiles = BulkMailDB.profiles or {}
	BulkMailDB.profiles[self.profilePath[2]] = BulkMailDB.profiles[self.profilePath[2]] or {}
	
	self.data = BulkMailDB.profiles[self.profilePath[2]]
	self.data = self.data or {}
	
	self.data.autoSendListItems = self.data.autoSendListItems or {}
	self.data.defaultDestination = self.data.defaultDestination or ''
end

--[[--------------------------------------------------------------------------------
  Addon Enabling/Disabling
-----------------------------------------------------------------------------------]]

function BulkMail:Enable()
	self:RegisterEvent("MAIL_SHOW")
	self:RegisterEvent("MAIL_CLOSED")
	self.containerFrames = {}
end

--[[--------------------------------------------------------------------------------
  Event Processing
-----------------------------------------------------------------------------------]]

function BulkMail:MAIL_SHOW()
	OpenAllBags()
	self:InitializeContainerFrames()
	self:Hook("ContainerFrameItemButton_OnClick", "BMContainerFrameItemButton_OnClick")
	self:Hook("SendMailFrame_CanSend", "BMSendMailFrame_CanSend")
	self:HookScript(SendMailMailButton, "OnClick", "BMSendMailMailButton_OnClick")
	self:HookScript(MailFrameTab2, "OnClick", "BMMailFrameTab2_OnClick")
	self:HookScript(SendMailNameEditBox, "OnTextChanged", "BMSendMailNameEditBox_OnTextChanged")
end

function BulkMail:MAIL_CLOSED()
	self:Unhook("ContainerFrameItemButton_OnClick")
	self:Unhook("SendMailFrame_CanSend")
	self:UnhookScript(SendMailMailButton, "OnClick")
	self:UnhookScript(MailFrameTab2, "OnClick")
	self:UnhookScript(SendMailNameEditBox, "OnTextChanged")
	for bag, v in pairs(self.containerFrames) do
		for slot, f in pairs(v) do
			f:SetButtonState("NORMAL", 0)
		end
	end
	BulkMail.gui:Hide()
	self.sendCache = nil
	self.cacheLock = false
end

--[[--------------------------------------------------------------------------------
  Hooks
-----------------------------------------------------------------------------------]]
function BulkMail:BMContainerFrameItemButton_OnClick(button, ignoreModifiers)
	if IsAltKeyDown() then
		self:SendCacheToggle(this)
	else
		return self:CallHook("ContainerFrameItemButton_OnClick", button, ignoreModifiers)
	end
end

function BulkMail:BMSendMailFrame_CanSend()
	self:CallHook("SendMailFrame_CanSend")
	if (self.sendCache and next(self.sendCache)) or GetSendMailItem() then
		SendMailMailButton:Enable()
	end
end

function BulkMail:BMSendMailMailButton_OnClick()
	self.cacheLock = true
	self.pmsqDestination = SendMailNameEditBox:GetText()
	if SendMailNameEditBox:GetText() == '' then
		self.pmsqDestination = nil
	end
	if self.sendCache and next(self.sendCache) then
		self.metro:Start("BMSend")
	else
		return self:CallScript(SendMailMailButton, "OnClick")
	end
end

function BulkMail:BMMailFrameTab2_OnClick()
	BulkMail:SendCacheBuild(SendMailNameEditBox:GetText())
	BulkMail.gui:Show()
	SendMailFrame_CanSend()
	return self:CallScript(MailFrameTab2, "OnClick")
end

function BulkMail:BMSendMailNameEditBox_OnTextChanged()
	BulkMail:SendCacheBuild(SendMailNameEditBox:GetText())
	SendMailFrame_CanSend()
	return self:CallScript(SendMailNameEditBox, "OnTextChanged")
end

--[[--------------------------------------------------------------------------------
  Main Processing
-----------------------------------------------------------------------------------]]

function BulkMail:InitializeContainerFrames() --creates self.containerFrames, a table consisting of all frames which are container buttons
	local enum = EnumerateFrames
	local f = enum()
	self.containerFrames = {}
	while f do
		if f.SplitStack and not f:GetParent().nextSlotCost and not f.GetInventorySlot then
			local bag, slot = f:GetParent():GetID(), f:GetID()
			self.containerFrames[bag] = self.containerFrames[bag] or {}
			table.insert(self.containerFrames[bag][slot], f)
		end
		f = enum(f)
	end
end

function BulkMail:SendCacheBuild(destination)
	if not self.cacheLock then
		self.sendCache = {}
		for bag, v in pairs(self.containerFrames) do
			for slot, w in pairs(v) do
				for _, f in pairs(w) do
					local itemID = select(3, string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):"))
					if self.data.autoSendListItems[itemID] and (destination == "" or string.lower(destination) == string.lower(self.data.autoSendListItems[itemID])) then
						self:SendCacheAdd(bag, slot)
					end
				end
			end
		end
	end
	SendMailFrame_CanSend()
	MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice() * table.getn(self.sendCache))
end

function BulkMail:SendCachePos(frame, slot)
	local bag = slot and frame or frame:GetParent():GetID()
	slot = slot or frame:GetID()
	if self.sendCache then
		for i, v in pairs(self.sendCache) do
			if v[1] == bag and v[2] == slot then
				return i
			end
		end
	end
end

function BulkMail:SendCacheAdd(frame, slot)
	local bag = slot and frame or frame:GetParent():GetID()
	slot = slot or frame:GetID()
	if not self.sendCache then
		self.sendCache = {}
	end
	if GetContainerItemInfo(bag, slot) then
		table.insert(self.sendCache, {bag, slot})
		for _, f in pairs(self.containerFrames[bag][slot]) do
			f:SetButtonState("PUSHED", 1)
		end
		BulkMail.gui.Items:ClearList()
		BulkMail.gui.Items:Update()
		SendMailMailButton:Enable()
	end
	SendMailFrame_CanSend()
	MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice() * table.getn(self.sendCache))
end

function BulkMail:SendCacheRemove(frame, slot)
	local bag = slot and frame or frame:GetParent():GetID()
	slot = slot or frame:GetID()
	local i = BulkMail:SendCachePos(bag, slot)
	if i then
		self.sendCache[i] = nil
		table.setn(self.sendCache, table.getn(self.sendCache) - 1)
		for _, f in pairs(self.containerFrames[bag][slot]) do
			f:SetButtonState("NORMAL", 0)
		end
		BulkMail.gui.Items:ClearList()
		BulkMail.gui.Items:Update()
		SendMailFrame_CanSend()
		if table.getn(self.sendCache) > 0 then
			MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice() * table.getn(self.sendCache))
		end
	end
end

function BulkMail:SendCacheToggle(frame, slot)
	local bag = slot and frame or frame:GetParent():GetID()
	slot = slot or frame:GetID()
	if self:SendCachePos(bag, slot) then
		self:SendCacheRemove(bag, slot)
	else
		self:SendCacheAdd(bag, slot)
	end
end

function BulkMail:ListAutoSendItems()
	for item, dest in pairs(self.data.autoSendListItems) do
		self.cmd:msg(GetItemLink(item) .. " - " .. dest)
	end
end

function BulkMail:AddAutoSendItem(arglist)
	local destination = select(3, string.find(arglist, "([^%s]+)"))
	if string.find(destination, "^|[cC]") then
		destination = self.data.defaultDestination
	else
		arglist = string.sub(arglist, string.find(arglist, "%s")+1)
	end		
	for itemID in string.gfind(arglist, "item:(%d+)") do
		if itemID and self.data.autoSendListItems[tostring(itemID)] ~= destination then
			self.data.autoSendListItems[tostring(itemID)] = destination
		else
			self.cmd:msg(self.loc.ERROR_ITEM_ALREADY_IN_AUTOSEND_LIST)
		end
	end
end

function BulkMail:RemoveAutoSendItem(arglist)
	for itemID in string.gfind(arglist, "item:(%d+)") do
		if self.data.autoSendListItems[itemID] then
			self.data.autoSendListItems[itemID] = nil
		else
			self.cmd:msg(self.loc.ERROR_ITEM_NOT_IN_AUTOSEND_LIST)
		end
	end
end

function BulkMail:RemoveAutoSendDestination(destination)
	for itemID, dest in self.data.autoSendListItems do
		if destination == dest then
			self.data.autoSendListItems[itemID] = nil
		end
	end
end

function BulkMail:ClearAutoSendList(confirm)
	if string.lower(confirm) == "confirm" then
		self.data.autoSendListItems = {}
	else
		self.cmd:msg(self.loc.ERROR_TYPE_CONFIRM_ON_CLEAR)
	end
end

function BulkMail:SetDefaultDestination(name)
	if name ~= '' then
		self.data.defaultDestination = name
	end
	if self.data.defaultDestination and self.data.defaultDestination ~= '' then
		self.cmd:msg(string.format(self.loc.MSG_DEFAULT_DESTINATION, self.data.defaultDestination))
	else
		self.cmd:msg(self.loc.MSG_NO_DEFAULT_DESTINATION)
	end
end

function BulkMail:Send()
	local i, cache = next(self.sendCache)
	if cache then
		if not GetSendMailItem() then
			local bag, slot = unpack(cache)
			PickupContainerItem(bag, slot)
			ClickSendMailItemButton()
			SendMailPackageButton:SetID(select(3,  string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):")))
			self.sendCache[i] = nil
			table.setn(self.sendCache, table.getn(self.sendCache) - 1)
		end
		SendMailNameEditBox:SetText(self.pmsqDestination or self.data.autoSendListItems[tostring(SendMailPackageButton:GetID())] or self.data.defaultDestination or '')
		SendMailFrame_SendMail()
	else
		self.metro:Stop("BMSend")
		self.cacheLock = false
		self.sendCache = nil
	end
end
--[[--------------------------------------------------------------------------------
  Register the Addon
-----------------------------------------------------------------------------------]]

BulkMail:RegisterForLoad()
