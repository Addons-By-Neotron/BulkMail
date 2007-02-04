local function BuildItemLink(c,i,n)
	if(((c or "")=="") or ((i or "")=="") or ((n or "")=="")) then return "" end
	if(strlen(c)<8) then c="ff"..strlower(c) end
	return format("|c%s|Hitem:%s|h[%s]|h|r",c,i,n)
end

local function GetItemLink(item)
	local name, _, rarity = GetItemInfo(item)
	if name and rarity then
		local color = string.sub(select(4, GetItemQualityColor(rarity)), 3)
		return BuildItemLink(color, item, name) or name
	else
		return item
	end
end

BulkMail = AceLibrary("AceAddon-2.0"):new("AceDB-2.0", "AceEvent-2.0", "AceHook-2.1", "AceConsole-2.0")

local L = AceLibrary("AceLocale-2.2"):new("BulkMail")
BulkMail.L = L

local tablet   = AceLibrary("Tablet-2.0")
local gratuity = AceLibrary("Gratuity-2.0")
local metro    = AceLibrary("Metrognome-2.0")
local pt       = PeriodicTableEmbed:GetInstance("1")

function BulkMail:OnInitialize()
	self:RegisterDB("BulkMailDB")
	self:RegisterDefaults('profile', {
		tablet_data = {detached=true, },
	})
	self:RegisterDefaults('realm', {
		autoSendListItems = {},
	})
	
	local args = {
		type = "group",
		args = {
			defaultdest = {
				name  = "Default destination", type = "text",
				desc  = "Set the default recipient of autosent items",
				get   = function() return self.db.realm.defaultDestination end,
				set   = function(dest) self.db.realm.defaultDestination = dest end,
				usage = "<destination>",
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
						validate = function(name) return self.db.realm.defaultDestination or not string.find(name, "^|[cC]") or not string.find(name, "^pt:") end,
						error = L["Please supply a destination for the item(s), or set a default destination with |cff00ffaa/bulkmail defaultdest|r."],
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
	}
	
	self:RegisterChatCommand({"/bulkmail", "/bm"}, args)
	
	metro:Register("BMSend", self.Send, 0.1, self)
	
	self.containerFrames = {}
	self.destCache       = {}
	self.sendCache       = {}
	self.ptSetsCache     = {}
end

function BulkMail:OnEnable()
	self:RegisterEvent("MAIL_SHOW")
	self:RegisterEvent("MAIL_CLOSED")
end

function BulkMail:MAIL_SHOW()
	OpenAllBags()
	OpenAllBags()
	self:InitializeContainerFrames()
	self:DestCacheBuild()
	self:SecureHook("ContainerFrameItemButton_OnModifiedClick")
	self:SecureHook("SendMailFrame_CanSend")
	self:HookScript(SendMailMailButton, "OnClick", "SendMailMailButton_OnClick")
	self:HookScript(MailFrameTab2, "OnClick", "MailFrameTab2_OnClick")
	self:HookScript(SendMailNameEditBox, "OnTextChanged", "SendMailNameEditBox_OnTextChanged")

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
	BulkMail:HideGUI()
end

--[[--------------------------------------------------------------------------------
  Hooks
-----------------------------------------------------------------------------------]]
function BulkMail:ContainerFrameItemButton_OnModifiedClick(button, ignoreModifiers)
	if IsControlKeyDown() and IsShiftKeyDown() then
		self:QuickSend(this)
	end
	if IsAltKeyDown() then
		self:SendCacheToggle(this)
	else
		self:SendCacheRemove(this)
	end
end

function BulkMail:SendMailFrame_CanSend()
	if (self.sendCache and next(self.sendCache)) or GetSendMailItem() then
		SendMailMailButton:Enable()
	end
	self:RefreshGUI()
end

function BulkMail:SendMailMailButton_OnClick(frame, a1)
	self.cacheLock = true
	self.pmsqDestination = SendMailNameEditBox:GetText()
	if SendMailNameEditBox:GetText() == '' then
		self.pmsqDestination = nil
	end
	if GetSendMailItem() or self.sendCache and next(self.sendCache) then
		metro:Start("BMSend")
	else
		this = SendMailMailButton
		return self.hooks[frame].OnClick(a1)
	end
end

function BulkMail:MailFrameTab2_OnClick(frame, a1)
	BulkMail:ShowGUI()
	BulkMail:SendCacheBuild(SendMailNameEditBox:GetText())
	return self.hooks[frame].OnClick(a1)
end

function BulkMail:SendMailNameEditBox_OnTextChanged(frame, a1)
	BulkMail:SendCacheBuild(string.lower(SendMailNameEditBox:GetText()))
	return self.hooks[frame].OnTextChanged(a1)
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
	for _, dest in pairs(self.db.realm.autoSendListItems) do
		self.destCache[string.lower(dest)] = true
	end
end

function BulkMail:PTSetsCacheBuild()
	self.ptSetsCache = {}
	for set in pairs(self.db.realm.autoSendListItems) do
		if string.find(set, "^pt:") then
			table.insert(self.ptSetsCache, select(3, string.find(set, "pt:(%w+)")))
		end
	end
end

function BulkMail:GetPTSendDest(itemID)
	local sets = pt:ItemInSets(tonumber(itemID), self.ptSetsCache)
	if sets then
		return self.db.realm.autoSendListItems["pt:"..sets[1]]
	end
end

function BulkMail:SendCacheBuild(destination)
	if not self.cacheLock then
		self:SendCacheCleanUp(true)
		self:DestCacheBuild()
		self:PTSetsCacheBuild()
		if destination == '' or self.destCache[destination] then -- no need to check for an item in the autosend list if the destination string doesn't have any
			for bag, v in pairs(self.containerFrames) do
				for slot, w in pairs(v) do
					for _, f in pairs(w) do
						local itemID = select(3, string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+):"))
						local dest = self.db.realm.autoSendListItems[itemID] or self:GetPTSendDest(itemID)
						dest = dest and string.lower(dest)
						if dest and dest ~= string.lower(UnitName('player')) and (destination == "" or dest == destination) then
							self:SendCacheAdd(bag, slot)
						end
					end
				end
			end
		end
	end
	self:RefreshGUI()
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

function BulkMail:SendCacheAdd(frame, slot, squelch)
	local bag = slot and frame or frame:GetParent():GetID()
	slot = slot or frame:GetID()
	if not self.sendCache then
		self.sendCache = {}
	end
	if not self.containerFrames then
		InitializeContainerFrames()
	end
	if GetContainerItemInfo(bag, slot) and self.containerFrames[bag] and self.containerFrames[bag][slot] and not self:SendCachePos(bag, slot) then
		gratuity:SetBagItem(bag, slot)
		if not gratuity:MultiFind(2, 4, nil, true, ITEM_SOULBOUND, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP) then
			table.insert(self.sendCache, {bag, slot})
			for _, f in pairs(self.containerFrames[bag][slot]) do
				if f.SetButtonState then f:SetButtonState("PUSHED", 1) end
			end
			self:RefreshGUI()
			SendMailFrame_CanSend()
		elseif not squelch then
			self:Print(L["Item cannot be mailed: %s."], GetContainerItemLink(bag, slot))
		end
	end
	return self:UpdateSendCost()
end

function BulkMail:SendCacheRemove(frame, slot)
	local bag = slot and frame or frame:GetParent():GetID()
	slot = slot or frame:GetID()
	local i = BulkMail:SendCachePos(bag, slot)
	if i then
		self.sendCache[i] = nil
		for _, f in pairs(self.containerFrames[bag][slot]) do
			if f.SetButtonState then f:SetButtonState("NORMAL", 0) end
		end
		self:RefreshGUI()
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
		return self:SendCacheRemove(bag, slot)
	else
		return self:SendCacheAdd(bag, slot)
	end
end

function BulkMail:ListAutoSendItems()
	for itemID, dest in pairs(self.db.realm.autoSendListItems) do
		self:Print(GetItemLink(itemID) .. " - " .. dest)
	end
end

function BulkMail:AddAutoSendItem(...)
	local arg = {...}
	if string.find(arg[1], "^|[cC]") or string.find(arg[1], "^pt:") then	--first arg is an item or PT set, not a name
		table.insert(arg, 1, self.db.realm.defaultDestination)
	end

	for i = 2, #arg do
		local itemID = select(3, string.find(arg[i], "item:(%d+)")) or select(3, string.find(arg[i], "(pt:%w+)"))
		if itemID then
			self.db.realm.autoSendListItems[tostring(itemID)] = arg[1]
			self:Print("%s - %s", arg[i], arg[1])
		end
	end
end

function BulkMail:RemoveAutoSendItem(arglist)
	for itemID in string.gmatch(arglist, "item:(%d+)") do
		if self.db.realm.autoSendListItems[itemID] then
			self.db.realm.autoSendListItems[itemID] = nil
		else
			self:Print(L["This item is not currently in your autosend list.  Please use |cff00ffaa/bulkmail autosend add [destination] ITEMLINK [ITEMLINK2, ...]|r to add it."])
		end
	end
	for set in string.gmatch(arglist, "(pt:%w+)") do
		if self.db.realm.autoSendListItems[set] then
			self.db.realm.autoSendListItems[set] = nil
		else
			self:Print(L["This set is not currently in your autosend list.  Please use |cff00ffaa/bulkmail autosend add [destination] ITEMLINK [ITEMLINK2, ...]|r to add it."])
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
		self:Print(L["You must type 'confirm' to clear"])
	end
end


function BulkMail:UpdateSendCost()
	if self.sendCache and #self.sendCache > 0 then
		local numMails = #self.sendCache
		if GetSendMailItem() then
			numMails = numMails + 1
		end
		return MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice() * numMails)
	else
		return MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice())
	end
end

function BulkMail:Send()
	local cache = self.sendCache and select(2, next(self.sendCache))
	if GetSendMailItem() then
		local itemDest
		if not self.pmsqDestination then
			local packageID = SendMailPackageButton:GetID()
			itemDest = self.db.realm.autoSendListItems[tostring(packageID)] or self:GetPTSendDest(packageID)
		end
		SendMailNameEditBox:SetText(self.pmsqDestination or itemDest or self.db.realm.defaultDestination or '')
		if SendMailNameEditBox:GetText() ~= '' then
			this = SendMailMailButton
			return self.hooks[SendMailMailButton].OnClick()
		elseif not self.db.realm.defaultDestination then
			self:Print(L["No default destination set."])
			self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
			self.cacheLock = false
			return metro:Stop("BMSend")
		end
	elseif cache then
		local bag, slot = unpack(cache)
		PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		SendMailPackageButton:SetID(select(3,  string.find(GetContainerItemLink(bag, slot) or '', "item:(%d+):")) or 0)
		return self:SendCacheRemove(bag, slot)
	else
		metro:Stop("BMSend")
		return self:SendCacheCleanUp()
	end
end

function BulkMail:QuickSend(frame, slot, destination)
	local bag = slot and frame or frame:GetParent():GetID()
	slot = slot or frame:GetID()
	if bag and slot then
		PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		if GetSendMailItem() then
			SendMailNameEditBox:SetText(destination or self.db.realm.autoSendListItems[tostring(SendMailPackageButton:GetID())] or self.db.realm.defaultDestination or '')
			if SendMailNameEditBox:GetText() ~= '' then
				this = SendMailMailButton
				return self.hooks[SendMailMailButton].OnClick()
			elseif not self.db.realm.defaultDestination then
				self:Print(L["No default destination set."])
				self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
			end
		end
	else
		self:Print(L["Cannot determine the item clicked."])
	end
end

--[[--------------------------------------------------------------------------------
  GUI
-----------------------------------------------------------------------------------]]

function BulkMail:ShowGUI()
	if not tablet:IsRegistered('BulkMail') then
		tablet:Register('BulkMail', 'detachedData', self.db.profile.tablet_data,
			'dontHook', true, 'showTitleWhenDetached', true,-- 'minWidth', 350,
			'children', function()
				tablet:SetTitle("BulkMail")
				
				local cat = tablet:AddCategory('columns', 1, 'text', L["Items to be sent (Alt-Click to add/remove):"],
					'showWithoutChildren', true, 'child_indentation', 5)
				
				if #self.sendCache > 0 then
					for i, v in pairs(self.sendCache) do
						local link = GetContainerItemLink(v[1], v[2])
						local texture, qty = GetContainerItemInfo(v[1], v[2])
						local itemText = string.sub(link, 1, 10) .. string.sub(select(3, string.find(link, "(%b[])")), 2, -2)
						itemText = qty > 1 and itemText .. " (" .. qty .. ")" or itemText
						
						cat:AddLine('text', itemText,
							'checked', true, 'hasCheck', true, 'checkIcon', texture,
							'func', self.OnItemSelect, 'arg1', self, 'arg2', v[1], 'arg3', v[2])
					end
				else
					cat:AddLine('text', L["No items selected"])
				end
				
				cat = tablet:AddCategory('columns', 1)
				cat:AddLine('text', L["Drop items here for Sending"], 'justify', 'CENTER', 'func', self.OnDropClick, 'arg1', self)
				
				if #self.sendCache > 0 then
					cat = tablet:AddCategory('columns', 1)
					cat:AddLine('text', L["Clear"], 'func', self.SendCacheCleanUp, 'arg1', self)
					if SendMailMailButton:IsEnabled() and SendMailMailButton:IsEnabled() ~= 0 then
						cat:AddLine('text', L["Send"], 'func', self.OnSendClick, 'arg1', self)
					else
						cat:AddLine('text', L["Send"], 'textR', 0.5, 'textG', 0.5, 'textB', 0.5)
					end
				else
					cat = tablet:AddCategory('columns', 1, 'child_textR', 0.5, 'child_textG', 0.5, 'child_textB', 0.5)
					cat:AddLine('text', L["Clear"])
					cat:AddLine('text', L["Send"])
				end
			end)
	end
	tablet:Open('BulkMail')
end

function BulkMail:HideGUI()
	if tablet:IsRegistered('BulkMail') then
		tablet:Close('BulkMail')
	end
end

function BulkMail:RefreshGUI()
	if tablet:IsRegistered('BulkMail') then
		tablet:Refresh('BulkMail')
	end
end

function BulkMail:OnItemSelect(bag, slot)
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

function BulkMail:OnSendClick()
	if not self.sendCache then return end
	self:SendMailMailButton_OnClick()
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

function BulkMail:OnDropClick()
	if GetSendMailItem() then
		self:Print(L["WARNING: Cursor item detection is NOT well-defined when multiple items are 'locked'.   Alt-click is recommended for adding items when there is already an item in the Send Mail item frame."])
	end
	if CursorHasItem() and GetLockedContainerItem() then
		self:SendCacheAdd(GetLockedContainerItem())
		--To clear the cursor.
		PickupContainerItem(GetLockedContainerItem())
	end
	self:RefreshGUI()
end