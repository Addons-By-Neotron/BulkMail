--[[--------------------------------------------------------------------------------
  Global/Local functions
-----------------------------------------------------------------------------------]]
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
	version         = "0.5.1",
	releaseDate     = "05-27-2006",
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
	if not Bagnon then
		OpenAllBags()
		OpenAllBags()
	end
	self:InitializeContainerFrames()
	self:DestCacheBuild()
	self:Hook("ContainerFrameItemButton_OnClick", "BMContainerFrameItemButton_OnClick")
	self:Hook("SendMailFrame_CanSend", "BMSendMailFrame_CanSend")
	self:HookScript(SendMailMailButton, "OnClick", "BMSendMailMailButton_OnClick")
	self:HookScript(MailFrameTab2, "OnClick", "BMMailFrameTab2_OnClick")
	self:HookScript(SendMailNameEditBox, "OnTextChanged", "BMSendMailNameEditBox_OnTextChanged")
	SendMailMailButton:Enable()
end

function BulkMail:MAIL_CLOSED()
	self:Unhook("ContainerFrameItemButton_OnClick")
	self:Unhook("SendMailFrame_CanSend")
	self:UnhookScript(SendMailMailButton, "OnClick")
	self:UnhookScript(MailFrameTab2, "OnClick")
	self:UnhookScript(SendMailNameEditBox, "OnTextChanged")
	self:SendCacheCleanUp()
	for bag, slot in pairs(self.containerFrames) do
		for _, f in pairs(slot) do
			if f.SetButtonState then f:SetButtonState("NORMAL", 0) end
		end
	end
	BulkMail.gui:Hide()
end

--[[--------------------------------------------------------------------------------
  Hooks
-----------------------------------------------------------------------------------]]
function BulkMail:BMContainerFrameItemButton_OnClick(button, ignoreModifiers)
	if IsAltKeyDown() then
		self:SendCacheToggle(this)
	else
		self:SendCacheRemove(this)
		return self:CallHook("ContainerFrameItemButton_OnClick", button, ignoreModifiers)
	end
end

function BulkMail:BMSendMailFrame_CanSend()
	self:CallHook("SendMailFrame_CanSend")
	if (self.sendCache and next(self.sendCache)) or GetSendMailItem() then
		SendMailMailButton:Enable()
	end
	if SendMailMailButton:IsEnabled() and SendMailMailButton:IsEnabled() ~= 0 then
		self.gui.Send:Enable()
	else
		self.gui.Send:Disable()
	end
end

function BulkMail:BMSendMailMailButton_OnClick()
	self.cacheLock = true
	self.pmsqDestination = SendMailNameEditBox:GetText()
	if SendMailNameEditBox:GetText() == '' then
		self.pmsqDestination = nil
	end
	if GetSendMailItem() or self.sendCache and next(self.sendCache) then
		self.metro:Start("BMSend")
	else
		return self:CallScript(SendMailMailButton, "OnClick")
	end
end

function BulkMail:BMMailFrameTab2_OnClick()
	BulkMail:SendCacheBuild(SendMailNameEditBox:GetText())
	BulkMail.gui:Show()
	return self:CallScript(MailFrameTab2, "OnClick")
end

function BulkMail:BMSendMailNameEditBox_OnTextChanged()
	BulkMail:SendCacheBuild(SendMailNameEditBox:GetText())
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
		local bag, slot = f and f:GetParent() and f:GetParent():GetID() or -1, f and f:GetID() or -1
		if bag >= 0 and bag <= NUM_BAG_SLOTS and slot > 0 and not f:GetParent().nextSlotCost and not f.GetInventorySlot then
			self.containerFrames[bag] = self.containerFrames[bag] or {}
			self.containerFrames[bag][slot] = self.containerFrames[bag][slot] or {}
			table.insert(self.containerFrames[bag][slot], f)
		end
		f = enum(f)
	end
end

function BulkMail:DestCacheBuild()
	self.destCache = {}
	for _, name in pairs(self.data.autoSendListItems) do
		if not self.destCache.name then
			table.insert(self.destCache, name)
		end
	end
end

function BulkMail:SendCacheBuild(destination)
	if not self.cacheLock then
		self:SendCacheCleanUp()
		self.sendCache = {}
		self:DestCacheBuild()
		if destination ~= '' and not self.destCache.destination then return end -- no need to check for an item in the autosend list if the destination string doesn't have any
		for bag, v in pairs(self.containerFrames) do
			for slot, w in pairs(v) do
				for _, f in pairs(w) do
					local itemID = select(3, string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):"))
					if self.data.autoSendListItems[itemID] and (destination == "" or string.lower(destination) == self.data.autoSendListItems[itemID]) then
						self:SendCacheAdd(bag, slot)
					end
				end
			end
		end
	end
	BulkMail.gui.Items:ClearList()
	BulkMail.gui.Items:Update()
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
	if not self.containerFrames then
		InitializeContainerFrames()
	end
	if GetContainerItemInfo(bag, slot) and self.containerFrames[bag] and self.containerFrames[bag][slot] and not self:SendCachePos(bag, slot) then
		table.insert(self.sendCache, {bag, slot})
		for _, f in pairs(self.containerFrames[bag][slot]) do
			if f.SetButtonState then f:SetButtonState("PUSHED", 1) end
		end
		BulkMail.gui.Items:ClearList()
		BulkMail.gui.Items:Update()
		SendMailFrame_CanSend()
	end
	self:UpdateSendCost()
end

function BulkMail:SendCacheRemove(frame, slot)
	local bag = slot and frame or frame:GetParent():GetID()
	slot = slot or frame:GetID()
	local i = BulkMail:SendCachePos(bag, slot)
	if i then
		self.sendCache[i] = nil
		table.setn(self.sendCache, table.getn(self.sendCache) - 1)
		for _, f in pairs(self.containerFrames[bag][slot]) do
			if f.SetButtonState then f:SetButtonState("NORMAL", 0) end
		end
		BulkMail.gui.Items:ClearList()
		BulkMail.gui.Items:Update()
		self:UpdateSendCost()
		SendMailFrame_CanSend()
	end
end

function BulkMail:SendCacheCleanUp()
	if self.sendCache then
		for _, cache in pairs(self.sendCache) do
			self:SendCacheRemove(unpack(cache))
		end
		self.sendCache = nil
		self.cacheLock = false
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
	if string.find(destination, "^|[cC]") then	--first arg is an item, not a name
		if self.data.defaultDestination and self.data.defaultDestination ~= "" then
			destination = self.data.defaultDestination
		else
			return self.cmd:msg(self.loc.ERROR_NO_DESTINATION_SUPPLIED_NO_DEFAULT_DESTINATION_SET)
		end
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
	for itemID, dest in pairs(self.data.autoSendListItems) do
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
		self.data.defaultDestination = string.lower(name)
	end
	if self.data.defaultDestination and self.data.defaultDestination ~= '' then
		self.cmd:msg(string.format(self.loc.MSG_DEFAULT_DESTINATION, self.data.defaultDestination))
	else
		self.cmd:msg(self.loc.MSG_NO_DEFAULT_DESTINATION)
	end
end


function BulkMail:UpdateSendCost()
	if self.sendCache and table.getn(self.sendCache) > 0 then
		local numMails = table.getn(self.sendCache)
		if GetSendMailItem() then
			numMails = numMails + 1
		end
		MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice() * numMails)
	else
		MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice())
	end
end
	

function BulkMail:Send()
	local _, cache = next(self.sendCache)
	if GetSendMailItem() then
		SendMailNameEditBox:SetText(self.pmsqDestination or self.data.autoSendListItems[tostring(SendMailPackageButton:GetID())] or self.data.defaultDestination or '')
		if SendMailNameEditBox:GetText() ~= '' then
			SendMailFrame_SendMail()
		elseif not self.data.DefaultDestination then
			self.cmd:msg(self.loc.MSG_NO_DEFAULT_DESTINATION)
			self.cmd:msg(self.loc.MSG_ENTER_NAME_OR_SET_DEFAULT_DESTINATION)
			self.cacheLock = nil
			self.metro:Stop("BMSend")
		end
	elseif cache then
		local bag, slot = unpack(cache)
		PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		SendMailPackageButton:SetID(select(3,  string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):")) or 0)
		self:SendCacheRemove(bag, slot)
	else
		self.metro:Stop("BMSend")
		self:SendCacheCleanUp()
	end
end

function BulkMail:ShowGUI()
	BulkMail.gui:Show()
end
--[[--------------------------------------------------------------------------------
  Register the Addon
-----------------------------------------------------------------------------------]]

BulkMail:RegisterForLoad()
