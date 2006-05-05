local function select(n, ...)
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
	version         = "0.3.0",
	releaseDate     = "05-05-2006",
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
	self.metro:Register("BulkMail ProcessMailSendQueue", self.ProcessMailSendQueue, 0.5, self)
	
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
end

--[[--------------------------------------------------------------------------------
  Event Processing
-----------------------------------------------------------------------------------]]

function BulkMail:MAIL_SHOW()
	OpenAllBags()
	self:InitializeContainerFrames()
	self:Hook("ContainerFrameItemButton_OnClick", "BMContainerFrameItemButton_OnClick")
	self:Hook("SetItemButtonDesaturated", "BMSetItemButtonDesaturated")
	self:Hook(SendMailMailButton, "Disable", "BMSendMailMailButton_Disable")
	self:HookScript(SendMailMailButton, "OnClick", "BMSendMailMailButton_OnClick")
	self:HookScript(MailFrameTab2, "OnClick", "BMMailFrameTab2_OnClick")
	self:HookScript(SendMailNameEditBox, "OnTextChanged", "BMSendMailNameEditBox_OnTextChanged")
end

function BulkMail:MAIL_CLOSED()
	self:Unhook("ContainerFrameItemButton_OnClick")
	self:Unhook("SetItemButtonDesaturated")
	self:Unhook(SendMailMailButton, "Disable")
	self:UnhookScript(SendMailMailButton, "OnClick")
	self:UnhookScript(MailFrameTab2, "OnClick")
	self:UnhookScript(SendMailNameEditBox, "OnTextChanged")
	for _, f in pairs(self.containerFrames) do
		SetItemButtonDesaturated(f)
	end
	self.sendCache = nil
end

--[[--------------------------------------------------------------------------------
  Hooks
-----------------------------------------------------------------------------------]]
function BulkMail:BMContainerFrameItemButton_OnClick(button, ignoreModifiers)
	if self:SendCachePos(this) and (not GetContainerItemInfo(this:GetParent():GetID(), this:GetID()) or IsShiftKeyDown()) then
		self:SendCacheRemove(this)
	end
		
	if not self.cacheLock and button == "LeftButton" and not IsControlKeyDown() and not IsShiftKeyDown() and not CursorHasItem() then
		if self:SendCachePos(this) then
			self:SendCacheRemove(this)
		else
			self:SendCacheAdd(this)
		end
		SetItemButtonDesaturated(this)
	else
		return self:CallHook("ContainerFrameItemButton_OnClick", button, ignoreModifiers)
	end
end

function BulkMail:BMSetItemButtonDesaturated(itemButton, locked, r, g, b)
	if self.sendCache and table.getn(self.sendCache) > 0 then
		MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice() * table.getn(self.sendCache))
	end

	return self:CallHook("SetItemButtonDesaturated", itemButton, not self:SendCachePos(itemButton), r, g, b)
end

function BulkMail:BMSendMailMailButton_Disable()
	if not self.sendCache or table.getn(self.sendCache) < 1 then
		self:CallHook(SendMailMailButton, "Disable")
	else
		SendMailMailButton:Enable()
	end
end

function BulkMail:BMSendMailMailButton_OnClick()
	if SendMailMailButton:IsEnabled() then
		self:CallScript(SendMailMailButton, "OnClick")
	end
	
	if self.sendCache and next(self.sendCache) then

		self.pmsqDestination = SendMailNameEditBox:GetText()
		if SendMailNameEditBox:GetText() == '' then
			self.pmsqDestination = nil
		end

		self.metro:Start("BulkMail ProcessMailSendQueue")
		self.cmd:msg(string.format(self.loc.MSG_SENDING_N_ITEMS, table.getn(self.sendCache), self.pmsqDestination or self.loc.TEXT_MULTIPLE_RECIPIENTS)) --FIX!!!
	end

	return self:CallScript(SendMailMailButton, "OnClick")
end

function BulkMail:BMMailFrameTab2_OnClick()
	BulkMail:SendCacheBuild(SendMailNameEditBox:GetText())
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
		if (f.hasItem or f.SplitStack) and f:GetID() and f:GetID() > 0 then
			table.insert(self.containerFrames, f)
		end
		f = enum(f)
	end
end

function BulkMail:SendCacheBuild(destination)
	if not self.cacheLock then
		self.sendCache = {}
		for _, f in pairs(self.containerFrames) do
			local bag = f:GetParent():GetID()
			local slot = f:GetID()
			local itemID = select(3, string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):"))
			if self.data.autoSendListItems[itemID] and (destination == "" or string.lower(destination) == string.lower(self.data.autoSendListItems[itemID])) then
				self:SendCacheAdd(f)
			end
			SetItemButtonDesaturated(f)
		end
	end
end

function BulkMail:SendCachePos(frame)
	if self.sendCache then
		for i, v in pairs(self.sendCache) do
			if v[1] == frame:GetParent():GetID() and v[2] == frame:GetID() then
				return i
			end
		end
	end
	return false
end

function BulkMail:SendCacheAdd(frame)
	if not self.sendCache then
		self.sendCache = {}
	end
	if GetContainerItemInfo(frame:GetParent():GetID(), frame:GetID()) then
		table.insert(self.sendCache, {frame:GetParent():GetID(), frame:GetID()})
	end
	SendMailMailButton:Enable()
end

function BulkMail:SendCacheRemove(frame)
	local i = BulkMail:SendCachePos(frame)
	if i then
		self.sendCache[i] = nil
		table.setn(self.sendCache, table.getn(self.sendCache) - 1)
		if not self.sendCache or table.getn(self.sendCache) == 0 then
			SendMailMailButton:Disable()
		end
	end
end

function BulkMail:ListAutoSendItems()
	for item, dest in pairs(self.data.autoSendListItems) do
		self.cmd:msg(GetItemLink(item) .. " - " .. dest)
	end
end

function BulkMail:AddAutoSendItem(arglist)
	local destination = select(3, string.find(arglist, "([^%s]+)"))
	if string.find(destination, "item: (%d+)") then
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

function BulkMail:ProcessMailSendQueue()
	destination = self.pmsqDestination
	local i, cache = next(self.sendCache)
	if cache then
		self.cacheLock = true
		local bag, slot = unpack(cache)
		local itemID = select(3,  string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):"))
		SendMailNameEditBox:SetText(destination or self.data.autoSendListItems[itemID] or self.data.defaultDestination or '')
		PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), SendMailBodyEditBox:GetText())
		self.sendCache[i] = nil
		table.setn(self.sendCache, table.getn(self.sendCache) - 1)
		if self.sendCache and table.getn(self.sendCache) == 0 then
			SendMailMailButton:Disable()
		end
	else
		self.metro:Stop("BulkMail ProcessMailSendQueue")
		self.cacheLock = false
	end
end

--[[--------------------------------------------------------------------------------
  Register the Addon
-----------------------------------------------------------------------------------]]

BulkMail:RegisterForLoad()
