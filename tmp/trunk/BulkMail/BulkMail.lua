BulkMail = AceAddon:new({
	name            = BulkMailLocals.NAME,
	description     = BulkMailLocals.DESCRIPTION,
	version         = "0.1.0",
	releaseDate     = "04-23-2006",
	aceCompatible   = "103",
	author          = "Mynithrosil of Feathermoon",
	email           = "hyperactiveChipmunk@gmail.com",
	website         = "http://hyperactiveChipmunk.wowinterface.com",
	category        = "other",
	db              = AceDatabase:new("BulkMailDB"),
	defaults        = DEFAULT_OPTIONS,
	cmd             = AceChatCmd:new(BulkMailLocals.COMMANDS, BulkMailLocals.CMD_OPTIONS),
	loc             = BulkMailLocals,
})

function BulkMail:Initialize()
	if not self.data then
		self.data = {}
	end

	if not self.charData then
		self.charData = {}
	end

	if not self.charData.autoSendListItems then
		self.charData.autoSendListItems = {}
	end
	
end

--[[--------------------------------------------------------------------------------
  Addon Enabling/Disabling
-----------------------------------------------------------------------------------]]

function BulkMail:Enable()
	self:RegisterEvent("MAIL_SHOW")
	--self:Hook("SomeFunction", "ProcessSomeFunction")
	--self:Hook(SomeObject, "SomeMethod", "ProcessSomeObjectMethod")
	--self:HookScript(SomeFrame, "OnShow", "ProcessOnShow")
end

-- Disable() is not needed if all you are doing in Enable() is registering events
-- and hooking functions. Ace will automatically unregister and unhook these.
function BulkMail:Disable()
end

--[[--------------------------------------------------------------------------------
  Event Processing
-----------------------------------------------------------------------------------]]

function BulkMail:MAIL_SHOW()
	OpenAllBags()
	self:InitializeContainerFrames()
	
	local bag, slot, itemID
	for k, f in self.containerFrames do
		bag = f:GetParent():GetID()
		slot = f:GetID()
		_, _, itemID = string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):")
		if not self.charData.autoSendListItems[itemID] then
			SetItemButtonDesaturated(f, 1)
		end
	end
end

--[[--------------------------------------------------------------------------------
  Main Processing
-----------------------------------------------------------------------------------]]

local function GetItemID(item)
	if type(item) ~= 'number' then
		_, _, item = string.find(tostring(item), "item:(%d+):")
	end
	return item
end
		
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

function BulkMail:AddAutoSendItem(item, destination)
	local itemID = GetItemID(item)
	if not self.charData.autoSendListItems[itemID] then
		print("Adding..."..itemID)
		self.charData.autoSendListItems[tostring(itemID)] = destination
	else
		self.cmd:msg(self.loc.ERROR_ITEM_ALREADY_IN_AUTOSEND_LIST)
	end
end

function BulkMail:ChangeAutoSendDestination(item, newDestination)
	local itemID = GetItemID(item)
	if self.charData.autoSendListItems[itemID] then
		self.charData.autoSendListItems[itemID] = destination
	else
		self.cmd:msg(self.loc.ERROR_ITEM_NOT_IN_AUTOSEND_LIST)
	end
end

function BulkMail:RemoveAutoSendItem(item)
	local itemID = GetItemID(item)
	if self.charData.autoSendListItems[itemID] then
		self.charData.autoSendListItems[itemID] = nil
	else
		self.cmd:msg(self.loc.ERROR_ITEM_NOT_IN_AUTOSEND_LIST)
	end
end

function BulkMail:RemoveAutoSendDestination(destination)
	for itemID, dest in self.charData.autoSendListItems do
		if destination == dest then
			self.charData.autoSendListItems[itemID] = nil
		end
	end
end

function BulkMail:SendAllItems()
	local bag, slot, itemID, itemName, itemCount
	for k, f in self.containerFrames do
		bag = f:GetParent():GetID()
		slot = f:GetID()
		_, _, itemID = string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):")
		if self.charData.autoSendListItems[itemID] then
			SendMailNameEditBox:SetText(self.charData.autoSendListItems[itemID])
			PickupContainerItem(bag, slot)
			ClickSendMailItemButton()
			SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), SendMailBodyEditBox:GetText())
		end
	end
end

--[[--------------------------------------------------------------------------------
  Register the Addon
-----------------------------------------------------------------------------------]]

BulkMail:RegisterForLoad()
