local function select(n, ...)
	return arg[n]
end

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
	cmd             = AceChatCmd:new({"/bulkmail", "/bm"}, BulkMailLocals.CMD_OPTIONS),
	loc             = BulkMailLocals,
})


function BulkMail:Initialize()
	self.metro = Metrognome:GetInstance("1")
	self.metro:Register("BulkMail SendNextItem", self.SendNextItem, 0.5, self)
	if not BulkMailDB.profiles then
		BulkMailDB.profiles = {}
	end
	if not BulkMailDB.profiles[self.profilePath[2]] then
		BulkMailDB.profiles[self.profilePath[2]] = {}
	end
	self.data = BulkMailDB.profiles[self.profilePath[2]]
	if not self.data then
		self.data = {}
	end
	
	if not self.data.autoSendListItems then
		self.data.autoSendListItems = {}
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
	self.sendCache = {}
	
	for _, f in self.containerFrames do
		local bag = f:GetParent():GetID()
		local slot = f:GetID()
		local itemID = select(3, string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):"))
		if self.data.autoSendListItems[itemID] then
			table.insert(self.sendCache, {bag, slot})
		else
			SetItemButtonDesaturated(f, 1)
		end
	end
end

--[[--------------------------------------------------------------------------------
  Main Processing
-----------------------------------------------------------------------------------]]

local function GetItemID(item)
	return select(3, string.find(tostring(item), "item:(%d+):"))
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

function BulkMail:ListAutoSendItems()
	for item, dest in pairs(self.data.autoSendListItems) do
		print(GetItemLink(item) .. " - " .. dest)
	end
end

function BulkMail:AddAutoSendItem(arglist)
	local destination = select(3, string.find(arglist, "([^%s]+)"))
	arglist = string.sub(arglist, string.find(arglist, "%s")+1)
	for item in string.gfind(arglist, "%bH|") do
		local itemID = GetItemID(item)
		if itemID and self.data.autoSendListItems[tostring(itemID)] ~= destination then
			print("Adding..."..itemID)
			self.data.autoSendListItems[tostring(itemID)] = destination
		else
			self.cmd:msg(self.loc.ERROR_ITEM_ALREADY_IN_AUTOSEND_LIST)
		end
	end
end

function BulkMail:ChangeAutoSendDestination(newDestination, ...)
	for _, item in ipairs(arg) do
		local itemID = GetItemID(item)
		if self.data.autoSendListItems[itemID] then
			self.data.autoSendListItems[itemID] = destination
		else
			self.cmd:msg(self.loc.ERROR_ITEM_NOT_IN_AUTOSEND_LIST)
		end
	end
end

function BulkMail:RemoveAutoSendItem(...)
	for _, item in ipairs(arg) do
		local itemID = GetItemID(item)
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

function BulkMail:SendAllItems() --for testing; this will eventually be triggered in the appropriate places
	print("start")
	self.metro:Start("BulkMail SendNextItem")
end

function BulkMail:SendNextItem()
	local i, cache = next(self.sendCache)
	if cache then
		printFull(GetTime())
		local bag, slot = unpack(cache)
		local itemID = select(3,  string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):"))
		SendMailNameEditBox:SetText(self.data.autoSendListItems[itemID])
		PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), SendMailBodyEditBox:GetText())
		self.sendCache[i] = nil
	else
		print("stop")
		self.metro:Stop("BulkMail SendNextItem")
	end
end

--[[--------------------------------------------------------------------------------
  Register the Addon
-----------------------------------------------------------------------------------]]

BulkMail:RegisterForLoad()
