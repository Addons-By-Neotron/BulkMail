local metro = Metrognome:GetInstance("1")
local compost = CompostLib:GetInstance("compost-1")

local function GetItemLink(item)
	local name, _, rarity = GetItemInfo(item)
	if name and rarity then
		local color = string.sub(select(4, GetItemQualityColor(rarity)), 3)
		return ace.BuildItemLink(color, item, name) or name
	else
		return item
	end
end

BulkMail = AceLibrary("AceAddon-2.0"):new("AceDB-2.0", "AceEvent-2.0", "AceHook-2.0", "AceConsole-2.0")

local L = AceLibrary("AceLocale-2.0"):new("BulkMail")
BulkMail.L = L

function BulkMail:OnInitialize()
	self:RegisterDB("BulkMailDB")
	self:RegisterDefaults('realm', {
		autoSendListItems = {},
		defaultDestination = nil,
	})
	self:RegisterChatCommand({"/bulkmail", "/bm"}, {
		type = "group",
		args = {
			defaultdest = {
				name  = "Default destination", type = "text",
				desc  = "Set the default recipient of autosent items",
				get   = function() return self.db.realm.defaultDestination end,
				set   = function(dest) self.db.realm.defaultDestination = dest end,
				usage = "<destnation>",
			},
			
			autosend = {
				name = "AutoSend", type = "group",
				desc = "AutoSend Options", aliases = "as",
				args = {
					list = {
						name  = "list", type = "execute",
						desc  = "Print current AutoSend list.",
						aliases = "ls",
						func  = "ListAutoSendItems",
					},
					add = {
						name  = "add", type = "text",
						desc  = "Add items to the AutoSend list.",
						input = true,
						set   = "AddAutoSendItem",
						get   = false,
						validate = function(name) return self.db.realm.defaultDestination or not string.find(name, "^|[cC]") end,
						error = L"Please supply a destination for the item(s), or set a default destination with |cff00ffaa/bulkmail defaultdest|r.",
						usage = "[destination] <item> [item2 item3 ...]",
					},
					rm = {
						name  = "remove", type = "text",
						aliases = "rm, delete, del",
						desc  = "Remove items from the AutoSend list.",
						input = true,
						set   = "RemoveAutoSendItem",
						get   = false,
						usage = "<item> [item2 item3 ...]",
					},
					rmdest = {
						name  = "rmdest", type = "text",
						desc  = "Remove all items corresponding to a particular destination from your AutoSend list.",
						input = true,
						set   = "RemoveAutoSendDestination",
						get   = false,
						usage = "<destination>",
					},
					clear = {
						name  = "clear", type = "text",
						desc  = "Clear AutoSend list completely.",
						set   = "ClearAutoSendList",
						get   = false,
						validate = function(confirm) if confirm == "CONFIRM" then return true end end,
						error = "You must type 'CONFIRM' to clear.",
						usage = "CONFIRM",
					},
				},				
			},
		},
	})

	metro:Register("BMSend", self.Send, 0.1, self)
	
	self.containerFrames = {}
	self.destCache       = {}
	self.sendCache       = {}
end

function BulkMail:OnEnable()
	self:RegisterEvent("MAIL_SHOW")
	self:RegisterEvent("MAIL_CLOSED")
end

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
	self:UnhookAll()
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
		return self.hooks.ContainerFrameItemButton_OnClick.orig(button, ignoreModifiers)
	end
end

function BulkMail:BMSendMailFrame_CanSend()
	self.hooks.SendMailFrame_CanSend.orig()
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
		metro:Start("BMSend")
	else
		return self.hooks[SendMailMailButton].OnClick.orig()
	end
end

function BulkMail:BMMailFrameTab2_OnClick()
	BulkMail:SendCacheBuild(SendMailNameEditBox:GetText())
	BulkMail.gui:Show()
	return self.hooks[MailFrameTab2].OnClick.orig()
end

function BulkMail:BMSendMailNameEditBox_OnTextChanged()
	BulkMail:SendCacheBuild(SendMailNameEditBox:GetText())
	return self.hooks[SendMailNameEditBox].OnTextChanged.orig()
end

--[[--------------------------------------------------------------------------------
  Main Processing
-----------------------------------------------------------------------------------]]

function BulkMail:InitializeContainerFrames() --creates self.containerFrames, a table consisting of all frames which are container buttons
	local enum = EnumerateFrames
	local f = enum()
	self.containerFrames = compost:Erase(self.containerFrames)
	while f do
		local bag, slot = f and f:GetParent() and f:GetParent():GetID() or -1, f and f:GetID() or -1
		if bag >= 0 and bag <= NUM_BAG_SLOTS and slot > 0 and not f:GetParent().nextSlotCost and not f.GetInventorySlot then
			self.containerFrames[bag] = self.containerFrames[bag] or compost:Acquire()
			self.containerFrames[bag][slot] = self.containerFrames[bag][slot] or compost:Acquire()
			table.insert(self.containerFrames[bag][slot], f)
		end
		f = enum(f)
	end
end

function BulkMail:DestCacheBuild()
	self.destCache = compost:Erase(self.destCache)
	for _, dest in pairs(self.db.realm.autoSendListItems) do
		self.destCache[dest] = 1
	end
end

function BulkMail:SendCacheBuild(destination)
	if not self.cacheLock then
		self:SendCacheCleanUp(true)
		self:DestCacheBuild()
		if destination ~= '' and not self.destCache[destination] then return end -- no need to check for an item in the autosend list if the destination string doesn't have any
		for bag, v in pairs(self.containerFrames) do
			for slot, w in pairs(v) do
				for _, f in pairs(w) do
					local itemID = select(3, string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):"))
					local dest = self.db.realm.autoSendListItems[itemID]
					if dest and dest ~= UnitName('player') and (destination == "" or string.lower(dest) == string.lower(destination)) then
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
	if self.sendCache and next(self.sendCache) then
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
		self.sendCache = compost:Acquire()
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

function BulkMail:SendCacheCleanUp(autoOnly)
	if self.sendCache and next(self.sendCache) then
		for _, cache in pairs(self.sendCache) do
			if not autoOnly or self.db.realm.autoSendListItems[select(3, string.find(GetContainerItemLink(unpack(cache)), "item:(%d+)"))] then
				self:SendCacheRemove(unpack(cache))
			end
		end

	end
	self.cacheLock = false
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
	for itemID, dest in pairs(self.db.realm.autoSendListItems) do
		self:Print(GetItemLink(itemID) .. " - " .. dest)
	end
end

function BulkMail:AddAutoSendItem(...)
	if string.find(arg[1], "^|[cC]") then	--first arg is an item, not a name
		table.insert(arg, 1, self.db.realm.defaultDestination)
	end

	for i = 2, table.getn(arg) do
		local itemID = select(3, string.find(arg[i], "item:(%d+)"))
		if itemID then
			self.db.realm.autoSendListItems[tostring(itemID)] = arg[1]
			self:Print("%s - %s", arg[i], arg[1])
		end
	end
end

function BulkMail:RemoveAutoSendItem(arglist)
	for itemID in string.gfind(arglist, "item:(%d+)") do
		if self.db.realm.autoSendListItems[itemID] then
			self.db.realm.autoSendListItems[itemID] = nil
		else
			self:Print(L"This item is not currently in your autosend list.  Please use |cff00ffaa/bulkmail autosend add [destination] ITEMLINK [ITEMLINK2, ...]|r to add it.")
		end
	end
end

function BulkMail:RemoveAutoSendDestination(destination)
	for itemID, dest in pairs(self.db.realm.autoSendListItems) do
		if destination == dest then
			self.db.realm.autoSendListItems[itemID] = nil
		end
	end
end

function BulkMail:ClearAutoSendList(confirm)
	if string.lower(confirm) == "confirm" then
		self.db.realm.autoSendListItems = {}
	else
		self:Print(L"You must type 'confirm' to clear")
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
	local cache = self.sendCache and select(2, next(self.sendCache))
	if GetSendMailItem() then
		SendMailNameEditBox:SetText(self.pmsqDestination or self.db.realm.autoSendListItems[tostring(SendMailPackageButton:GetID())] or self.db.realm.defaultDestination)
		if SendMailNameEditBox:GetText() ~= '' then
			SendMailFrame_SendMail()
		elseif self.db.realm.defaultDestination == '' then
			self:Print(L"No default destination set.")
			self:Print(L"Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r.")
			self.cacheLock = false
			metro:Stop("BMSend")
		end
	elseif cache then
		local bag, slot = unpack(cache)
		PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		SendMailPackageButton:SetID(select(3,  string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):")) or 0)
		self:SendCacheRemove(bag, slot)
	else
		metro:Stop("BMSend")
		self:SendCacheCleanUp()
	end
end

function BulkMail:ShowGUI()
	BulkMail.gui:Show()
end