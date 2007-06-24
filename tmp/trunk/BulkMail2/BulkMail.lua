BulkMail = AceLibrary('AceAddon-2.0'):new('AceDB-2.0', 'AceEvent-2.0', 'AceHook-2.1', 'AceConsole-2.0')
local self, BulkMail = BulkMail, BulkMail

local L = AceLibrary('AceLocale-2.2'):new('BulkMail')
BulkMail.L = L

local tablet   = AceLibrary('Tablet-2.0')
local gratuity = AceLibrary('Gratuity-2.0')
local abacus   = AceLibrary('Abacus-2.0')
local pt       = AceLibrary('PeriodicTable-3.0')
local dewdrop  = AceLibrary('Dewdrop-2.0')

local _G = getfenv(0)

local auctionItemClasses, sendCache, destCache, reverseDestCache, rulesCache, autoSendRules, globalExclude
local cacheLock, sendDest, numItems, rulesAltered, confirmedDestToRemove  -- variables

--[[----------------------------------------------------------------------------
  Table Handling
------------------------------------------------------------------------------]]
local new, del, newHash, newSet, deepDel
do
	local list = setmetatable({}, {__mode='k'})
	function new(...)
		local t = next(list)
		if t then
			list[t] = nil
			for i = 1, select('#', ...) do
				t[i] = select(i, ...)
			end
			return t
		else
			return { ... }
		end
	end

	function newHash(...)
		local t = next(list)
		if t then
			list[t] = nil
		else
			t = {}
		end
		for i = 1, select('#', ...), 2 do
			t[select(i, ...)] = select(i+1, ...)
		end
		return t
	end
	
	function newSet(...)
		local t = next(list)
		if t then
			list[t] = nil
		else
			t = {}
		end
		for i = 1, select('#', ...) do
			t[select(i, ...)] = true
		end
		return t
	end

	function del(t)
		for k in pairs(t) do
			t[k] = nil
		end
		list[t] = true
		return nil
	end

	function deepDel(t)
		if type(t) ~= "table" then
			return nil
		end
		for k,v in pairs(t) do
			t[k] = deepDel(v)
		end
		return del(t)
	end
end

--[[----------------------------------------------------------------------------
  Local Processing
------------------------------------------------------------------------------]]
-- Bag iterator, shamelessly stolen from PeriodicTable-2.0 (written by Tekkub)
local iterbag, iterslot
local function iter()
	if iterslot > GetContainerNumSlots(iterbag) then iterbag, iterslot = iterbag + 1, 1 end
	if iterbag > NUM_BAG_SLOTS then return end
	for b = iterbag,NUM_BAG_SLOTS do
		for s = iterslot,GetContainerNumSlots(b) do
			iterslot = s + 1
			local link = GetContainerItemLink(b,s)
			if link then return b, s, link end
		end
		iterbag, iterslot = b + 1, 1
	end
end
local function bagIter()
	iterbag, iterslot = 0, 1
	return iter
end

-- Unpacks the UI-friendly autoSendRules table into rulesCache, a simple
-- item/rules lookup table, in the following manner:
--   ItemIDs   - inserted as table keys
--   PT3Sets   - set is unpacked and each item is inserted as a table key
--   ItemTypes - ItemType is inserted as a table key pointing to a table of
--               desired subtype keys
-- Exclusions are processed after all include rules are handled, 
-- and will nil out the appropriate keys in the table.
rulesCache = new()
local function rulesCacheBuild()
	if next(rulesCache) and not rulesAltered then return end
	for k in pairs(rulesCache) do
		rulesCache[k] = deepDel(rulesCache[k])
	end
	for dest, rules in pairs(autoSendRules) do
		rulesCache[dest] = new()
		-- include rules
		for _, itemID in ipairs(rules.include.items) do rulesCache[dest][tonumber(itemID)] = true end
		for _, set in ipairs(rules.include.pt3Sets) do
			for itemID in pt:IterateSet(set) do rulesCache[dest][tonumber(itemID)] = true end
		end
		for _, itemTypeTable in ipairs(rules.include.itemTypes) do
			local itype, isubtype = itemTypeTable.type, itemTypeTable.subtype
			if isubtype then 
				rulesCache[dest][itype] = rulesCache[dest][itype] or new()
				rulesCache[dest][itype][isubtype] = true 
			else  -- need to add all subtypes individually
				if rulesCache[dest][itype] then rulesCache[dest][itype] = del(rulesCache[dest][itype]) end
				rulesCache[dest][itype] = newSet(unpack(auctionItemClasses[itype]))
			end
		end	
		-- exclude rules
		for _, itemID in ipairs(rules.exclude.items) do rulesCache[dest][tonumber(itemID)] = nil end
		for _, itemID in ipairs(globalExclude.items) do rulesCache[dest][tonumber(itemID)] = nil end

		for _, set in ipairs(rules.exclude.pt3Sets) do
			for itemID in pt:IterateSet(set) do rulesCache[dest][itemID] = nil end
		end
		for _, set in ipairs(globalExclude.pt3Sets) do
			for itemID in pt:IterateSet(set) do rulesCache[dest][itemID] = nil end
		end

		for _, itemTypeTable in ipairs(rules.exclude.itemTypes) do
			local rtype, rsubtype = itemTypeTable.type, itemTypeTable.subtype
			if rsubtype ~= rtype and rulesCache[dest][rtype] then
				rulesCache[dest][rtype][rsubtype] = nil
			else
				rulesCache[dest][rtype] = nil
			end
		end	
		for _, itemTypeTable in ipairs(globalExclude.itemTypes) do
			local rtype, rsubtype = itemTypeTable.type, itemTypeTable.subtype
			if rsubtype ~= rtype and rulesCache[dest][rtype] then
				rulesCache[dest][rtype][rsubtype] = nil
			else
				rulesCache[dest][rtype] = nil
			end
		end
	end
	rulesAltered = false
end

-- Returns the autosend destination of an itemID, according to the
-- rulesCache, or nil if no rules for this item are found.
local function rulesCacheDest(item)
	if not item then return end
	local rdest
	local itemID = type(item) == 'number' and item or tonumber(string.match(item, "item:(%d+)"))
	for _, xID in ipairs(globalExclude.items) do if itemID == xID then return end end
	for _, xset in ipairs(globalExclude.pt3Sets) do
		if pt:ItemInSet(itemID, xset) == true then return end
	end

	local itype, isubtype = select(6, GetItemInfo(itemID))
	for dest, rules in pairs(rulesCache) do
		local canddest
		if dest ~= UnitName('player') and (rules[itemID] or rules[itype] and rules[itype][isubtype]) then canddest = dest end
		if canddest then
			local xrules = autoSendRules[canddest].exclude
			for _, xID in ipairs(xrules.items) do if itemID == xID then canddest = nil end end
			for _, xset in ipairs(xrules.pt3Sets) do
				if pt:ItemInSet(itemID, xset) == true then canddest = nil end
			end
		end
		rdest = canddest or rdest
	end
	return rdest
end

-- Updates the "Postage" field in the Send Mail frame to reflect the total
-- price of all the items that BulkMail will send.
local function updateSendCost()
	if sendCache and next(sendCache) then
		local numMails = numItems
		if GetSendMailItem() then
			numMails = numMails + 1
		end
		return MoneyFrame_Update('SendMailCostMoneyFrame', GetSendMailPrice() * numMails)
	else
		return MoneyFrame_Update('SendMailCostMoneyFrame', GetSendMailPrice())
	end
end

--returns the frame associated with bag, slot
local function getBagSlotFrame(bag,slot)
	if bag >= 0 and bag < NUM_CONTAINER_FRAMES and slot > 0 and slot <= MAX_CONTAINER_ITEMS then
		local bagslots = GetContainerNumSlots(bag)
		if bagslots > 0 then
			return _G["ContainerFrame" .. (bag + 1) .. "Item" .. (bagslots - slot + 1)]
		end
	end
end

--shades or unshades the given bag slot
local function shadeBagSlot(bag,slot,shade)
	local frame = getBagSlotFrame(bag,slot)
	if frame then
		SetItemButtonDesaturated(frame,shade)
	end
end

-- Add a container slot to BulkMail's send queue.
local function sendCacheAdd(bag, slot, squelch)
	-- convert to (bag, slot, squelch) if called as (frame, squelch)
	if type(slot) ~= 'number' then
		bag, slot, squelch = bag:GetParent():GetID(), bag:GetID(), slot
	end
	sendCache = sendCache or new()
	BulkMail.sendCache = sendCache
	if GetContainerItemInfo(bag, slot) and not (sendCache[bag] and sendCache[bag][slot]) then
		gratuity:SetBagItem(bag, slot)
		if not gratuity:MultiFind(2, 4, nil, true, ITEM_SOULBOUND, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP) then
			sendCache[bag] = sendCache[bag] or new()
			sendCache[bag][slot] = true; numItems = numItems + 1
			shadeBagSlot(bag,slot,true)
			if not squelch then BulkMail:RefreshSendQueueGUI() end
			SendMailFrame_CanSend()
		elseif not squelch then
			BulkMail:Print(L["Item cannot be mailed: %s."], GetContainerItemLink(bag, slot))
		end
	end
	updateSendCost()
end

-- Remove a container slot from BulkMail's send queue.
local function sendCacheRemove(bag, slot)
	bag, slot = slot and bag or bag:GetParent():GetID(), slot or bag:GetID()  -- convert to (bag, slot) if called as (frame)
	if sendCache and sendCache[bag] then
		if sendCache[bag][slot] then
			sendCache[bag][slot] = nil
			numItems = numItems - 1
			shadeBagSlot(bag,slot,false)
		end
		if not next(sendCache[bag]) then sendCache[bag] = del(sendCache[bag]) end
	end
	BulkMail:RefreshSendQueueGUI()
	updateSendCost()
	SendMailFrame_CanSend()
end

-- Toggle a container slot's presence in BulkMail's send queue.
local function sendCacheToggle(bag, slot)
	bag, slot = slot and bag or bag:GetParent():GetID(), slot or bag:GetID()  -- convert to (bag, slot) if called as (frame)
	if sendCache and sendCache[bag] and sendCache[bag][slot] then
		return sendCacheRemove(bag, slot)
	else
		return sendCacheAdd(bag, slot)
	end
end

-- Removes all entries in BulkMail's send queue.
-- If passed with the argument 'true', will only remove the entries created by
-- BulkMail (used for refreshing the list as the destination changes without
-- clearing the items the user has added manually this session).
local function sendCacheCleanup(autoOnly)
	if sendCache then
		for bag, slots in pairs(sendCache) do
			for slot in pairs(slots) do
				local item = GetContainerItemLink(bag, slot)
				if not autoOnly or rulesCacheDest(item) then
					sendCacheRemove(bag, slot)
				end
			end
		end
	end
	cacheLock = false
	BulkMail:RefreshSendQueueGUI()
end

-- Populate BulkMail's send queue with container slots holding items following
-- the autosend rules for the current destination (or any destinations
-- if the destination field is blank).
local function sendCacheBuild(dest)
	if not cacheLock then
		sendCacheCleanup(true)
		if BulkMail.db.char.isSink or dest ~= '' and not destCache[dest] then return BulkMail:RefreshSendQueueGUI() end  -- no need to check for an item in the autosend list if this character is a sink or if the destination string doesn't have any rules set
		for bag, slot, item in bagIter() do
			local target = rulesCacheDest(item)
			if target then
				if dest == '' or dest == target then 
					sendCacheAdd(bag, slot, true)
				end
			end
		end
	end
	BulkMail:RefreshSendQueueGUI()
end

--[[----------------------------------------------------------------------------
  Setup
------------------------------------------------------------------------------]]
function BulkMail:OnInitialize()
	self:RegisterDB('BulkMail2DB')
	self:RegisterDefaults('profile', {
		tablet_data = { detached = true, anchor = "TOPLEFT", offsetx = 340, offsety = -104 }
	})
	self:RegisterDefaults('realm', {
		autoSendRules = {
			['*'] = {
				include = {
					['*'] = {},
				},
				exclude = {
					['*'] = {},
				},
			},
		},
	})
	autoSendRules = self.db.realm.autoSendRules  -- local variable for speed/convenience
	
	destCache = new()  -- destinations for which we have rules (or are going to add rules)
	reverseDestCache = new()  -- integer-indexed table of destinations
	for dest in pairs(autoSendRules) do
		destCache[dest] = true
		table.insert(reverseDestCache, dest)
	end

	self:RegisterDefaults('char', {
		isSink = false,
		globalExclude = {
			['*'] = {}
		},
	})
	globalExclude = self.db.char.globalExclude  -- local variable for speed/convenience

	auctionItemClasses = {}  -- local itemType value association table
	for i, itype in ipairs({GetAuctionItemClasses()}) do
		auctionItemClasses[itype] = {GetAuctionItemSubClasses(i)}
	end

	numItems = 0
	rulesAltered = true
	
	self.opts = {
		type = 'group',
		args = {
			defaultdest = {
				name = L["Default destination"], type = 'text', aliases = L["dd"],
				desc = L["Set the default recipient of your AutoSend rules"],
				get = function() return self.db.char.defaultDestination end,
				set = function(dest) self.db.char.defaultDestination = dest end,
				usage = "<destination>",
			},
			autosend = {
				name = L["AutoSend"], type = 'group', aliases = L["as"],
				desc = L["AutoSend Options"],
				args = {
					edit = {
						name = L["edit"], type = 'execute', aliases = L["rules, list, ls"],
						desc = L["Edit AutoSend definitions."],
						func = function() tablet:Open('BM_AutoSendEditTablet') end,
					},
					add = {
						name = L["add"], type = 'text', aliases = L["+"],
						desc = L["Add an item rule by itemlink or PeriodicTable-3.0 set manually."],
						input = true, set = 'AddAutoSendRule', usage = L["[destination] <itemlink|Periodic.Table.Set> [itemlink2|P.T.S.2 itemlink3|P.T.S.3 ...]"], get = false,
						validate = function(arg1) return self.db.char.defaultDestination or (not string.match(arg1, "^|[cC]") and not pt:IsSetMulti(arg1) ~= nil) end,
						error = L["Please supply a destination for the item(s), or set a default destination with |cff00ffaa/bulkmail defaultdest|r."],
					},
					rmdest = {
						name = L["rmdest"], type = 'text', aliases = L["rmd"],
						desc = "Remove all rules corresponding to a particular destination.",
						input = true, set = 'RemoveDestination', usage = L["<destination>"], get = false, validate = reverseDestCache,
					},
					clear = {
						name = L["clear"], type = 'execute',
						desc = L["Clear all rules for this realm."],
						func = function() self:ResetDB('realm') for i in pairs(autoSendRules) do autoSendRules[i] = nil end tablet:Refresh('BM_AutoSendEditTablet') end, confirm = true,
					},
				},
			},
			sink = {
				name = L["Sink"], type = 'toggle',
				desc = L["Disable AutoSend queue auto-filling for this character."],
				get = function() return self.db.char.isSink end,
				set = function(v) self.db.char.isSink = v end,
			},
		},
	}
	self:RegisterChatCommand({"/bulkmail", "/bm"}, self.opts)

	-- LoD PT3 Sets; yanked from Baggins
	local PT3Modules
	for i = 1, GetNumAddOns() do
		local metadata = GetAddOnMetadata(i, "X-PeriodicTable-3.0-Module")
		if metadata then
			local name, _, _, enabled = GetAddOnInfo(i)
			if enabled then
				LoadAddOn(name)
			end
		end
	end
end

function BulkMail:OnEnable()
	self:RegisterAutoSendEditTablet()
	self:RegisterAddRuleDewdrop()
	self:RegisterEvent('MAIL_SHOW')
	self:RegisterEvent('MAIL_CLOSED')
	self:RegisterEvent('PLAYER_ENTERING_WORLD')

	-- Handle being LoD loaded while at the mailbox
	if MailFrame:IsVisible() then
		self:MAIL_SHOW()
	end
	self:RegisterSendQueueGUI()
end

function BulkMail:OnDisable()
	self:UnregisterAllEvents()
	if dewdrop:IsRegistered('BM_AddRuleDD') then dewdrop:Unregister('BM_AddRuleDD') end
	if tablet:IsRegistered('BM_AutoSendEditTablet') then tablet:Unregister('BM_AutoSendEditTablet') end
	if tablet:IsRegistered('BM_SendQueueTablet') then tablet:Unregister('BM_SendQueueTablet') end
end

--[[----------------------------------------------------------------------------
  Events
------------------------------------------------------------------------------]]
function BulkMail:MAIL_SHOW()
	if rulesAltered then rulesCacheBuild() end
	self:SecureHook('ContainerFrameItemButton_OnModifiedClick')
	self:SecureHook('SendMailFrame_CanSend')
	self:SecureHook('ContainerFrame_Update')
	self:SecureHook('MoneyInputFrame_OnTextChanged', SendMailFrame_CanSend)
	self:Hook('SetItemRef', true)
	self:HookScript(SendMailMailButton, 'OnClick', 'SendMailMailButton_OnClick')
	self:HookScript(MailFrameTab1, 'OnClick', 'MailFrameTab1_OnClick')
	self:HookScript(MailFrameTab2, 'OnClick', 'MailFrameTab2_OnClick')
	self:HookScript(SendMailNameEditBox, 'OnTextChanged', 'SendMailNameEditBox_OnTextChanged')

	SendMailMailButton:Enable()
end

function BulkMail:MAIL_CLOSED()
	self:UnhookAll()
	sendCacheCleanup()
	self:HideSendQueueGUI()
end
BulkMail.PLAYER_ENTERING_WORLD = BulkMail.MAIL_CLOSED  -- MAIL_CLOSED doesn't get called if, for example, the player accepts a port with the mail window open

--[[----------------------------------------------------------------------------
  Hooks
------------------------------------------------------------------------------]]
function BulkMail:ContainerFrameItemButton_OnModifiedClick(button, ignoreModifiers)
	if IsControlKeyDown() and IsShiftKeyDown() then
		self:QuickSend(_G.this)
	elseif IsAltKeyDown() then
		sendCacheToggle(_G.this)
	elseif not IsShiftKeyDown() then
		sendCacheRemove(_G.this)
	end
end

function BulkMail:SendMailFrame_CanSend()
	if sendCache and next(sendCache) or GetSendMailItem() or SendMailSendMoneyButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney) > 0 then
		SendMailMailButton:Enable()
		SendMailCODButton:Enable()
	end
	self:ScheduleEvent('BM_canSendRefresh', self.RefreshSendQueueGUI, 0.1, self)
end

function BulkMail:ContainerFrame_Update(...)
	local frame = ...
	local bag = tonumber(string.sub(frame:GetName(),15))
	if bag then bag = bag - 1 else return end
	if bag and sendCache and sendCache[bag] then
		for slot, send in pairs(sendCache[bag]) do
			if send then
				shadeBagSlot(bag,slot,true)
			end
		end
	end
end

-- This allows for ctrl-clicking name links to fill the To: field.  Contributed by bigzero.
function BulkMail:SetItemRef(link, ...)
	if SendMailNameEditBox:IsVisible() and IsControlKeyDown() then 
		if strsub(link, 1, 6) == 'player' then 
			local name = strsplit(":", strsub(link, 8))
			if name and strlen(name) > 0 then 
				return SendMailNameEditBox:SetText(name) 
			end 
		end 
	end 
	self.hooks['SetItemRef'](link,...) 
end 

function BulkMail:SendMailMailButton_OnClick(frame, a1)
	cacheLock = true
	sendDest = SendMailNameEditBox:GetText()
	local cod = SendMailCODButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney)
	if GetSendMailItem() or sendCache and next(sendCache) then
		self:ScheduleRepeatingEvent('BM_SendLoop', self.Send, 0.1, self, cod)
	else
		if SendMailSendMoneyButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney) and SendMailSubjectEditBox:GetText() == '' then
			SendMailSubjectEditBox:SetText(abacus:FormatMoneyFull(MoneyInputFrame_GetCopper(SendMailMoney)))
		end
		_G.this = SendMailMailButton
		return self.hooks[frame].OnClick(frame, a1)
	end
end

function BulkMail:MailFrameTab1_OnClick(frame, a1)
	self:HideSendQueueGUI()
	return self.hooks[frame].OnClick(frame, a1)
end

function BulkMail:MailFrameTab2_OnClick(frame, a1)
	rulesCacheBuild()
	self:ShowSendQueueGUI()
	sendCacheBuild(SendMailNameEditBox:GetText())
	return self.hooks[frame].OnClick(frame, a1)
end

function BulkMail:SendMailNameEditBox_OnTextChanged(frame, a1)
	sendCacheBuild(SendMailNameEditBox:GetText())
	sendDest = cacheLock and sendDest or SendMailNameEditBox:GetText()
	return self.hooks[frame].OnTextChanged(frame, a1)
end

--[[----------------------------------------------------------------------------
  Public Functions
------------------------------------------------------------------------------]]
function BulkMail:AddDestination(dest)
	local _ = autoSendRules[dest]  -- trigger the table creation by accessing it
	destCache[dest] = true
	table.insert(reverseDestCache, dest)
	rulesAltered = true
end

function BulkMail:RemoveDestination(dest)
	autoSendRules[dest] = nil
	destCache[dest] = nil
	for i=1, #reverseDestCache do
		if reverseDestCache[i] == dest then
			table.remove(reverseDestCache, i)
			break
		end
	end
	rulesAltered = true
end

-- Simple function for adding include rules manually via itemlink or
-- PeriodicTable-3.0 set name.  If the first arg is neither of these, then
-- it must be the destination; otherwise, defaultDestination is used.
-- This is the function called by /bm autosend add.
function BulkMail:AddAutoSendRule(...)
	local dest = select(1, ...)
	local start = 2
	if string.match(dest, "^|[cC]") or pt:IsSetMulti(dest) ~= nil then
		dest = self.db.char.defaultDestination  -- first arg is an item or PT set, not a name, so use default (validation that default exists is handled by AceOptions)
		start = 1
	end
	self:AddDestination(dest)
	for i = start, select('#', ...) do
		local itemID = tonumber(string.match(select(i, ...), "item:(%d+)"))
		if itemID then  -- is an item link
			table.insert(autoSendRules[dest].include.items, itemID)
			tablet:Refresh('BM_AutoSendEditTablet')
			self:Print("%s - %s", select(i, ...), dest)
		elseif pt:IsSetMulti(select(i, ...)) ~= nil then  -- is a PT3 set
			table.insert(autoSendRules[dest].include.pt3Sets, select(i, ...))
			tablet:Refresh('BM_AutoSendEditTablet')
			self:Print("%s - %s", select(i, ...), dest)
		end
	end
	rulesAltered = true
end

-- Sends the current item in the SendMailItemButton to the currently-specified
-- destination (or the default if that field is blank), then supplies items and
-- destinations from BulkMail's send queue and sends them.
local suffix = "\255"  -- for ensuring subject uniqueness to help BMI's "Selected" features
function BulkMail:Send(cod)
	if StaticPopup_Visible('SEND_MONEY') then return end
	if GetSendMailItem() then
		SendMailNameEditBox:SetText(sendDest ~= '' and sendDest or rulesCacheDest(SendMailPackageButton:GetID()) or self.db.char.defaultDestination or '')
		if SendMailNameEditBox:GetText() ~= '' then
			if #suffix > 10 then suffix = "\255" else suffix = suffix.."\255" end
			_G.this = SendMailMailButton
			return self.hooks[SendMailMailButton].OnClick()
		elseif not self.db.char.defaultDestination then
			self:Print(L["No default destination set."])
			self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
			cacheLock = false
			return self:CancelScheduledEvent('BM_SendLoop')
		end
		return
	end
	if sendCache and next(sendCache) then
		local bag, slot = next(sendCache)
		slot = next(slot)
		PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		local itemLink = GetContainerItemLink(bag, slot)
		if itemLink then
			SendMailPackageButton:SetID(tonumber(string.match(itemLink, "item:(%d+):")) or 0)
		end
		SendMailSubjectEditBox:SetText(SendMailSubjectEditBox:GetText()..suffix)
		if cod then
			SendMailSendMoneyButton:SetChecked(nil)
			MoneyInputFrame_SetCopper(SendMailMoney, cod)
		end
		return sendCacheRemove(bag, slot)
	else
		self:CancelScheduledEvent('BM_SendLoop')
		SendMailNameEditBox:SetText('')
		return sendCacheCleanup()
	end
end

-- Send the container slot's item immediately to its autosend destination
-- (or the default destination if no destination specified).
-- This can be done whenever the mailbox is open, and is run when the user
-- Ctrl-Shift-LeftClicks an item in his bag.
function BulkMail:QuickSend(bag, slot)
	bag, slot = slot and bag or bag:GetParent():GetID(), slot or bag:GetID()  -- convert to (bag, slot) if called as (frame)
	if bag and slot then
		local itemLink = GetContainerItemLink(bag, slot)
		PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		if itemLink then
			SendMailPackageButton:SetID(tonumber(string.match(itemLink, "item:(%d+):")) or 0)
		end
		if GetSendMailItem() then
			local dest = SendMailNameEditBox:GetText()
			if dest == '' then
				SendMailNameEditBox:SetText(rulesCacheDest(SendMailPackageButton:GetID()) or self.db.char.defaultDestination or '')
			end
			if SendMailNameEditBox:GetText() ~= '' then
				_G.this = SendMailMailButton
				return self.hooks[SendMailMailButton].OnClick()
			elseif not self.db.char.defaultDestination then
				self:Print(L["No default destination set."])
				self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
			end
		end
	else
		self:Print(L["Cannot determine the item clicked."])
	end
end

--[[----------------------------------------------------------------------------
  Mailbox SendQueue GUI (original Tablet conversion by Kemayo)
------------------------------------------------------------------------------]]
local function tabletClose(tabletID)
	tablet:Close(tabletID)
end
local function uiClose(tabletID)
	BulkMail:ScheduleEvent(tabletClose, 0, tabletID)
end

local function getLockedContainerItem()
	for bag=0, NUM_BAG_SLOTS do
		for slot=1, GetContainerNumSlots(bag) do
			if select(3, GetContainerItemInfo(bag, slot)) then
				return bag, slot
			end
		end
	end
end

local function onSendQueueItemSelect(bag, slot)
	if bag and slot and arg1 == 'LeftButton' then
		if IsAltKeyDown() then
			sendCacheToggle(bag, slot)
		elseif IsShiftKeyDown() and ChatFrameEditBox:IsVisible() then
			ChatFrameEditBox:Insert(GetContainerItemLink(bag, slot))
		elseif IsControlKeyDown() and not IsShiftKeyDown() then
			DressUpItemLink(GetContainerItemLink(bag, slot))
		else
			SetItemRef(string.match(GetContainerItemLink(bag, slot), "(item:%d+:%d+:%d+:%d+)"), GetContainerItemLink(bag, slot), arg1)
		end
	end
end

local function onDropClick()
	if GetSendMailItem() then
		BulkMail:Print(L["WARNING: Cursor item detection is NOT well-defined when multiple items are 'locked'.   Alt-click is recommended for adding items when there is already an item in the Send Mail item frame."])
	end
	if CursorHasItem() and getLockedContainerItem() then
		sendCacheAdd(getLockedContainerItem())
		PickupContainerItem(getLockedContainerItem())  -- clears the cursor
	end
	BulkMail:RefreshSendQueueGUI()
end

local function onSendClick()
	if sendCache then BulkMail:SendMailMailButton_OnClick() end
end

function BulkMail:RegisterSendQueueGUI()
	if not tablet:IsRegistered('BM_SendQueueTablet') then
		tablet:Register('BM_SendQueueTablet', 'detachedData', self.db.profile.tablet_data, 'strata', "HIGH",
			'cantAttach', true, 'dontHook', true, 'showTitleWhenDetached', true, 'children', function()
				tablet:SetTitle("BulkMail Send Queue")
				
				local cat = tablet:AddCategory('columns', 2, 'text', L["Items to be sent (Alt-Click to add/remove):"],
					'showWithoutChildren', true, 'child_indentation', 5)
				
				if sendCache and next(sendCache) then
					local itemLink, itemText, texture, qty
					for bag, slots in pairs(sendCache) do
						for slot in pairs(slots) do
							itemLink = GetContainerItemLink(bag, slot)
							if itemLink then
								itemText = GetItemInfo(itemLink)
								texture, qty = GetContainerItemInfo(bag, slot)
								if qty and qty > 1 then
									itemText = string.format("%s(%d)", itemText, qty)
								end						
								cat:AddLine('text', itemText, 'text2', sendDest == '' and (rulesCacheDest(itemLink) or self.db.char.defaultDestination),
									'checked', true, 'hasCheck', true, 'checkIcon', texture,
									'func', onSendQueueItemSelect, 'arg1', bag, 'arg2', slot
								)
							end
						end
					end
				else
					cat:AddLine('text', L["No items selected"])
				end
				
				cat = tablet:AddCategory('columns', 1)
				cat:AddLine('text', L["Drop items here for Sending"], 'justify', "CENTER", 'func', onDropClick)
				
				if sendCache and next(sendCache) then
					cat = tablet:AddCategory('columns', 1)
					cat:AddLine('text', L["Clear"], 'func', sendCacheCleanup)
					if SendMailMailButton:IsEnabled() and SendMailMailButton:IsEnabled() ~= 0 then
						cat:AddLine('text', L["Send"], 'func', onSendClick)
					else
						cat:AddLine('text', L["Send"], 'textR', 0.5, 'textG', 0.5, 'textB', 0.5)
					end
				else
					cat = tablet:AddCategory('columns', 1, 'child_textR', 0.5, 'child_textG', 0.5, 'child_textB', 0.5)
					cat:AddLine('text', L["Clear"])
					cat:AddLine('text', L["Send"])
				end
				cat = tablet:AddCategory('columns', 1)
				cat:AddLine()
				cat:AddLine('text', L["Close"], 'func', uiClose, 'arg1', 'BM_SendQueueTablet')
			end
		)
	end
end
function BulkMail:ShowSendQueueGUI()
	if not tablet:IsRegistered('BM_SendQueueTablet') then
		self:RegisterSendQueueGUI()
	end
	tablet:Open('BM_SendQueueTablet')
end
function BulkMail:HideSendQueueGUI()
	if tablet:IsRegistered('BM_SendQueueTablet') then
		tablet:Close('BM_SendQueueTablet')
	end
end

function BulkMail:RefreshSendQueueGUI()
	if not tablet:IsRegistered('BM_SendQueueTablet') then
		self:RegisterSendQueueGUI()
	end
	tablet:Refresh('BM_SendQueueTablet')
end

--[[----------------------------------------------------------------------------
  AutoSend Edit GUI
------------------------------------------------------------------------------]]
local shown = {}  -- keeps track of collapsed/expanded state in tablet
local curRuleSet -- for adding rules via the dewdrop
local itemInputDDTable, itemTypesDDTable, pt3SetsDDTable, bagItemsDDTable  -- dewdrop tables

local function addRule(ruletype, value)
	table.insert(curRuleSet[ruletype], value)
	tablet:Refresh('BM_AutoSendEditTablet')
	rulesAltered = true
end

local function createStaticARDTables()
	if itemInputDDTable and itemTypesDDTable and pt3SetsDDTable then return end
	-- User-specified item IDs
	itemInputDDTable = newHash('text', L["Item ID"], 'hasArrow', true, 'hasEditBox', true,
		'tooltipTitle', L["ItemID(s)"], 'tooltipText', L["Usage: <itemID> [itemID2, ...]"],
		'editBoxFunc', function(...)
			for i=1, select('#', ...) do
				local item = select(i, ...)
				if GetItemInfo(item) then
					addRule("items", tonumber(item))
				end
			end
		end
	)

	-- Blizzard item types
	itemTypesDDTable = newHash('text', L["Item Type"], 'hasArrow', true, 'subMenu', new())
	for itype, subtypes in pairs(auctionItemClasses) do
		itemTypesDDTable.subMenu[itype] = newHash('text', itype, 'hasArrow', #subtypes > 0, 'func', addRule, 'arg1', "itemTypes", 'arg2', newHash('type', itype, 'subtype', #subtypes == 0 and itype))
		if #subtypes > 0 then
			local supertype = itemTypesDDTable.subMenu[itype]
			supertype.subMenu = new()
			for _, isubtype in ipairs(subtypes) do
				supertype.subMenu[isubtype] = newHash('text', isubtype, 'func', addRule, 'arg1', "itemTypes", 'arg2', newHash('type', itype, 'subtype', isubtype))
			end
		end
	end

	-- PeriodicTable-3.0 sets
	pt3SetsDDTable = newHash('text', L["Periodic Table Set"], 'hasArrow', true, 'subMenu', new())
	local sets = pt:getUpgradeData()
	local pathtable = new()
	local curmenu, prevmenu
	for setname in pairs(sets) do
		for k in ipairs(pathtable) do pathtable[k] = nil end
		curmenu = pt3SetsDDTable.subMenu
		for cat in setname:gmatch("([^%.]+)") do
			table.insert(pathtable, cat)
			if not curmenu[cat] then
				curmenu[cat] = newHash('text', cat, 'hasArrow', true, 'subMenu', new(), 'func', addRule, 'arg1', "pt3Sets", 'arg2', table.concat(pathtable, '.'))
			end
			prevmenu, curmenu = curmenu[cat], curmenu[cat].subMenu
		end
		prevmenu.hasArrow = nil  -- leaf
	end
end

bagItemsDDTable = newHash(
	'text', L["Items from Bags"], 'hasArrow', true, 'subMenu', new(), 
	'tooltipTitle', L["Bag Items"], 'tooltipText', L["Mailable items in your bags."]
)
local dupeCheck = new()
local function updateDynamicARDTables()
	for k in pairs(dupeCheck) do dupeCheck[k] = nil end
	for k in ipairs(bagItemsDDTable.subMenu) do bagItemsDDTable.subMenu[k] = nil end
	-- Mailable items in bags
	for bag, slot, item in bagIter() do
		local itemID = tonumber(string.match(item or '', "item:(%d+)"))
		if itemID and not dupeCheck[itemID] then
			dupeCheck[itemID] = true
			gratuity:SetBagItem(bag, slot)
			if not gratuity:MultiFind(2, 4, nil, true, ITEM_SOULBOUND, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP) then
				table.insert(bagItemsDDTable.subMenu, newHash(
					'text', select(2, GetItemInfo(itemID)),
					'checked', true, 'checkIcon', select(10, GetItemInfo(itemID)),
					'func', addRule, 'arg1', "items", 'arg2', itemID
				))
			end
		end
	end
end

function BulkMail:RegisterAddRuleDewdrop()
	-- Create table for Dewdrop and register
	createStaticARDTables()
	updateDynamicARDTables()
	dewdrop:Register('BM_AddRuleDD', 'children', function() dewdrop:FeedTable(new(newHash('text', L["Add rule"], 'isTitle', true), bagItemsDDTable, itemInputDDTable, itemTypesDDTable, pt3SetsDDTable)) end, 'cursorX', true, 'cursorY', true)
end

local function headerClickFunc(dest)
	if IsAltKeyDown() then
		confirmedDestToRemove = dest
		StaticPopup_Show('BULKMAIL_REMOVE_DESTINATION')
	else
		shown[dest] = not shown[dest]
	end
	tablet:Refresh('BM_AutoSendEditTablet')
end

local function includeFunc(arg)
	curRuleSet = arg
	updateDynamicARDTables()
	dewdrop:Open('BM_AddRuleDD')
end

local function excludeFunc(arg)
	curRuleSet = arg
	updateDynamicARDTables()
	dewdrop:Open('BM_AddRuleDD')
end

local function globalExcludeFunc()
	shown.globalExclude = not shown.globalExclude
	tablet:Refresh('BM_AutoSendEditTablet')
end

local function newDest()
	StaticPopup_Show("BULKMAIL_ADD_DESTINATION")
end

-- rules list prototype; used for listing both include- and exclude rules
local argTable = {}
local args = {}
local function listRules(category, ruleset)
	for k in pairs(args) do args[k] = nil end
	for k in pairs(argTable) do argTable[k] = nil end
	if not ruleset or not next(ruleset) then
		category:AddLine('text', L["None"], 'indentation', 20, 'textR', 1, 'textG', 1, 'textB', 1)
		return
	end
	for ruletype, rules in pairs(ruleset) do
		for k, rule in ipairs(rules) do
			args.text, args.textR, args.textG, args.textB = tostring(rule), 1, 1, 1
			args.indentation = 20
			args.hasCheck = false
			args.func = function(ruleset, id)
				if IsAltKeyDown() then
					table.remove(rules, k)
					tablet:Refresh('BM_AutoSendEditTablet')
					rulesAltered = true
				end
			end
			args.arg1, args.args2 = rules, k
			if ruletype == 'items' then
				args.text = select(2, GetItemInfo(rule))
				args.hasCheck = true
				args.checked = true
				args.checkIcon = select(10, GetItemInfo(rule))
			elseif ruletype == 'itemTypes' then
				if rule.subtype and rule.subtype ~= rule.type then
					args.text = string.format("Item Type: %s - %s", rule.type, rule.subtype)
				else
					args.text = string.format("Item Type: %s", rule.type)
				end
				args.textR, args.textG, args.textB = 250/255, 223/255, 168/255
			elseif ruletype == 'pt3Sets' then
				args.text = string.format("PT3 Set: %s", rule)
				args.textR, args.textG, args.textB = 200/255, 200/255, 255/255
			end
			for arg, val in pairs(args) do
				table.insert(argTable, arg)
				table.insert(argTable, val)
			end
			category:AddLine(unpack(argTable))
		end
	end
end

local function fillAutoSendEditTablet()
	local cat
	tablet:SetTitle(L["AutoSend Rules"])
	-- categories; one per destination character
	for dest, rulesets in pairs(autoSendRules) do
		if destCache[dest] then
			-- category title (destination character's name)
			cat = tablet:AddCategory(
				'id', dest, 'text', dest, 'showWithoutChildren', true, 'hideBlankLine', true,
				'checked', true, 'hasCheck', true, 'checkIcon', string.format("Interface\\Buttons\\UI-%sButton-Up", shown[dest] and "Minus" or "Plus"),
				'func', headerClickFunc, 'arg1', dest
			)
			-- rules lists; collapsed/expanded by clicking the destination characters' names
			if shown[dest] then
				-- "include" rules for this destination; clicking brings up menu to add new include rules
				cat:AddLine('text', L["Include"], 'indentation', 10, 'func', includeFunc, 'arg1', rulesets.include)
				listRules(cat, rulesets.include)
				-- "exclude" rules for this destination; clicking brings up menu to add new exclude rules
				cat:AddLine('text', L["Exclude"], 'indentation', 10, 'func', excludeFunc, 'arg1', rulesets.exclude)
				listRules(cat, rulesets.exclude)
				cat:AddLine()
				cat:AddLine()
			end
		end
	end

	-- Global Exclude Rules
	cat = tablet:AddCategory(
		'id', "globalExclude", 'text', L["Global Exclude"], 'showWithoutChildren', true, 'hideBlankLine', true,
		'checked', true, 'hasCheck', true, 'checkIcon', string.format("Interface\\Buttons\\UI-%sButton-Up", shown[dest] and "Minus" or "Plus"),
		'func', globalExcludeFunc
	)
	if shown.globalExclude then
		cat:AddLine('text', L["Exclude"], 'indentation', 10, 'func', function() curRuleSet = globalExclude dewdrop:Open('BM_AddRuleDD') end)
		listRules(cat, globalExclude)
	end

	cat = tablet:AddCategory('id', "actions")
	cat:AddLine('text', L["New Destination"], 'func', newDest)
	cat:AddLine('text', L["Close"], 'func', uiClose, 'arg1', 'BM_AutoSendEditTablet')
	tablet:SetHint(L["Click Include/Exclude headers to modify a ruleset.  Alt-Click destinations and rules to delete them."])
end

local dataTable = {}
function BulkMail:RegisterAutoSendEditTablet()
	tablet:Register('BM_AutoSendEditTablet',
		'children', fillAutoSendEditTablet, 'data', dataTable,
		'cantAttach', true, 'clickable', true,
		'showTitleWhenDetached', true, 'showHintWhenDetached', true,
		'dontHook', true, 'strata', "DIALOG"
	)
end

function BulkMail:OpenAutoSendEditTablet()
	tablet:Open("BM_AutoSendEditTablet")
end

--[[----------------------------------------------------------------------------
  StaticPopups
------------------------------------------------------------------------------]]
StaticPopupDialogs['BULKMAIL_ADD_DESTINATION'] = {
	text = L["BulkMail - New AutoSend Destination"],
	button1 = L["Accept"], button2 = L["Cancel"],
	hasEditBox = 1, maxLetters = 20,
	OnAccept = function()
		BulkMail:AddDestination(_G[this:GetParent():GetName().."EditBox"]:GetText())
		tablet:Refresh('BM_AutoSendEditTablet')
	end,
	OnShow = function()
		_G[this:GetName().."EditBox"]:SetFocus()
	end,
	OnHide = function()
		if ChatFrameEditBox:IsVisible() then
			ChatFrameEditBox:SetFocus()
		end
		_G[this:GetName().."EditBox"]:SetText('')
	end,
	EditBoxOnEnterPressed = function()
		BulkMail:AddDestination(_G[this:GetParent():GetName().."EditBox"]:GetText())
		tablet:Refresh('BM_AutoSendEditTablet')
		rulesAltered = true
		_G.this:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function()
		_G.this:GetParent():Hide()
	end,
	timeout = 0, exclusive = 1, whileDead = 1, hideOnEscape = 1,
}
StaticPopupDialogs['BULKMAIL_REMOVE_DESTINATION'] = {
	text = L["BulkMail - Confirm removal of destination"],
	button1 = L["Accept"], button2 = L["Cancel"],
	OnAccept = function()
		BulkMail:RemoveDestination(confirmedDestToRemove)
		tablet:Refresh('BM_AutoSendEditTablet')
		confirmedDestToRemove = nil
		rulesAltered = true
	end,
	OnHide = function()
		confirmedDestToRemove = nil
	end,
	timeout = 0, exclusive = 1, hideOnEscape = 1,
}
