BulkMail = AceLibrary("AceAddon-2.0"):new("AceDB-2.0", "AceEvent-2.0", "AceHook-2.1", "AceConsole-2.0")

local L = AceLibrary("AceLocale-2.2"):new("BulkMail")
BulkMail.L = L

local tablet   = AceLibrary("Tablet-2.0")
local gratuity = AceLibrary("Gratuity-2.0")
local pt       = AceLibrary("PeriodicTable-3.0")
local dewdrop  = AceLibrary("Dewdrop-2.0")

local containerFrames, destCache, sendCache, ptSetsCache, autoSendRules --tables
local cacheLock, pmsqDest --variables
--[[--------------------------------------------------------------------------------
  Local Processing
-----------------------------------------------------------------------------------]]
-- Creates containerFrames, a table consisting of all frames which are container buttons.
-- We'll use this for highlighting and click detection across as many addons as we can.
local function initializeContainerFrames()
	local enum = EnumerateFrames
	local f = enum()
	containerFrames = {}
	while f do
		local bag, slot = f and f:GetParent() and f:GetParent():GetID() or -1, f and f:GetID() or -1
		if bag >= 0 and bag <= NUM_BAG_SLOTS and slot > 0 and f.SplitStack and not f:GetParent().nextSlotCost and not f.GetInventorySlot then
			containerFrames[bag] = containerFrames[bag] or {}
			containerFrames[bag][slot] = containerFrames[bag][slot] or {}
			table.insert(containerFrames[bag][slot], f)
		end
		f = enum(f)
	end
end

-- Creates destCache, a lookup table for all destinations with autosend items.
-- Vastly improves performance when typing in destinations, allowing us to
-- forego checking the autosend list every time a new character is typed.
local function destCacheBuild()
	destCache = {}
	for _, dest in pairs(BulkMail.db.realm.autoSendListItems) do
		destCache[string.lower(dest)] = true
	end
	for _, dest in pairs(autoSendRules) do
		destCache[string.lower(dest)] = true
	end
end

-- Create a table of PT sets for which the user has autosend destinations.
local function ptSetsCacheBuild()
	ptSetsCache = {}
	for set in pairs(BulkMail.db.realm.autoSendListItems) do
		if string.match(set, "^pt:") then
			table.insert(ptSetsCache, string.match(set, "pt:(%w+)"))
		end
	end
end

-- Check if this item is part of a PT autosend set and return its destination.
local function getPTSendDest(itemID)
	local sets = pt:ItemInSets(tonumber(itemID), ptSetsCache)
	if sets then
		return BulkMail.db.realm.autoSendListItems["pt:"..sets[1]]
	end
end

-- Updates the "Postage" field in the Send Mail frame to reflect the total
-- price of all the items that BulkMail will send.
local function updateSendCost()
	if sendCache and #sendCache > 0 then
		local numMails = #sendCache
		if GetSendMailItem() then
			numMails = numMails + 1
		end
		return MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice() * numMails)
	else
		return MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice())
	end
end

-- Returns the position in the sendCache of an item.
-- Used mostly as a boolean check for items in BulkMail's send queue,
-- but the return value is helpful for GUI purposes.
local function sendCachePos(bag, slot)
	bag, slot = slot and bag or bag:GetParent():GetID(), slot or bag:GetID()  -- convert to (bag, slot) if called as (frame)
	if sendCache and next(sendCache) then
		for i, v in pairs(sendCache) do
			if v[1] == bag and v[2] == slot then
				return i
			end
		end
	end
end

-- Add a container slot to BulkMail's send queue.
local function sendCacheAdd(bag, slot, squelch)
	-- convert to (bag, slot, squelch) if called as (frame, squelch)
	if type(slot) ~= "number" then
		bag, slot, squelch = bag:GetParent():GetID(), bag:GetID(), slot
	end

	if not sendCache then
		sendCache = {}
	end
	if not containerFrames then
		initializeContainerFrames()
	end
	if GetContainerItemInfo(bag, slot) and containerFrames[bag] and containerFrames[bag][slot] and not sendCachePos(bag, slot) then
		gratuity:SetBagItem(bag, slot)
		if not gratuity:MultiFind(2, 4, nil, true, ITEM_SOULBOUND, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP) then
			table.insert(sendCache, {bag, slot})
			for _, f in pairs(containerFrames[bag][slot]) do
				if f.SetButtonState then f:SetButtonState("PUSHED", 1) end
			end
			BulkMail:RefreshGUI()
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
	local i = sendCachePos(bag, slot)
	if i then
		sendCache[i] = nil
		for _, f in pairs(containerFrames[bag][slot]) do
			if f.SetButtonState then f:SetButtonState("NORMAL", 0) end
		end
		BulkMail:RefreshGUI()
		updateSendCost()
		SendMailFrame_CanSend()
	end
end

-- Toggle a container slot's presence in BulkMail's send queue.
local function sendCacheToggle(bag, slot)
	bag, slot = slot and bag or bag:GetParent():GetID(), slot or bag:GetID()  -- convert to (bag, slot) if called as (frame)
	if sendCachePos(bag, slot) then
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
	if sendCache and next(sendCache) then
		for _, cache in pairs(sendCache) do
			local bag, slot = cache[1], cache[2]
			if not autoOnly or BulkMail.db.realm.autoSendListItems[string.match(GetContainerItemLink(bag, slot), "item:(%d+)")] then
				sendCacheRemove(bag, slot)
			end
		end
	end
	cacheLock = false
end

-- Populate BulkMail's send queue with container slots holding items in
-- the autosend list for the current destination (or the default destination
-- if the destination field is blank.
local function sendCacheBuild(destination)
	if not cacheLock then
		sendCacheCleanup(true)
		destCacheBuild()
		ptSetsCacheBuild()
		if destination == '' or destCache[destination] then  -- no need to check for an item in the autosend list if the destination string doesn't have any autosends to its name
			for bag, v in pairs(containerFrames) do
				for slot, w in pairs(v) do
					for _, f in pairs(w) do
						local itemID = string.match(GetContainerItemLink(bag, slot) or "", "item:(%d+):")
						local dest = BulkMail.db.realm.autoSendListItems[itemID] or getPTSendDest(itemID)
						dest = dest and string.lower(dest)
						if dest and dest ~= string.lower(UnitName('player')) and (destination == "" or dest == destination) then
							sendCacheAdd(bag, slot)
						end
					end
				end
			end
		end
	end
	BulkMail:RefreshGUI()
end

--[[--------------------------------------------------------------------------------
  Setup
-----------------------------------------------------------------------------------]]
function BulkMail:OnInitialize()
	self:RegisterDB("BulkMailDB")
	self:RegisterDefaults('profile', {
		tablet_data = {detached=true,},
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
	autoSendRules = self.db.realm.autoSendRules
	-- Converting old 'realm' level defaultDest setting to new 'char' level setting
	if self.db.realm.defaultDestination and not self.db.char.defaultDestination then
		self.db.char.defaultDestination = self.db.realm.defaultDestination
	end

	self:RegisterChatCommand({"/bulkmail", "/bm"}, {
		type = "group",
		args = {
			defaultdest = {
				name  = "Default destination", type = "text",
				desc  = "Set the default recipient of autosent items",
				get   = function() return self.db.char.defaultDestination end,
				set   = function(dest) self.db.char.defaultDestination = dest end,
				usage = "<destination>",
			},
			autosend = {
				name = L["AutoSend"], type = "group",
				desc = L["AutoSend Options"], aliases = "as",
				args = {
					edit = {
						name = L["edit"],
						type = "execute",
						desc = L["Edit AutoSend definitions."],
						func = function() tablet:Open("BMAutoSendEdit") end,
					},
					list = {
						name  = L["list"], type = "execute",
						desc  = L["Print current AutoSend list."],
						aliases = "ls",
						func  = "ListAutoSendItems",
					},
					add = {
						name  = L["add"], type = "text",
						desc  = L["Add items to the AutoSend list."],
						input = true,
						set   = "AddAutoSendItem",
						get   = false,
						validate = function(name) return self.db.char.defaultDestination or not string.match(name, "^|[cC]") or not string.match(name, "^pt:") end,
						error = L["Please supply a destination for the item(s), or set a default destination with |cff00ffaa/bulkmail defaultdest|r."],
						usage = L["[destination] <item> [item2 item3 ...]"],
					},
					rm = {
						name  = L["remove"], type = "text",
						aliases = "rm, delete, del",
						desc  = L["Remove items from the AutoSend list."],
						input = true,
						set   = "RemoveAutoSendItem",
						get   = false,
						usage = L["<item> [item2 item3 ...]"],
					},
					rmdest = {
						name  = L["rmdest"], type = "text",
						desc  = "Remove all items corresponding to a particular destination from your AutoSend list.",
						input = true,
						set   = "RemoveAutoSendDestination",
						get   = false,
						usage = L["<destination>"],
					},
					clear = {
						name  = L["clear"], type = "text",
						desc  = L["Clear AutoSend list completely."],
						set   = "ClearAutoSendList",
						get   = false,
						validate = function(confirm) if confirm == "CONFIRM" then return true end end,
						error = L["You must type 'CONFIRM' to clear."],
						usage = "CONFIRM",
					},
				},
			},
		},
	})
end

function BulkMail:OnEnable()
	self:RegisterAutoSendEditTablet()
	self:RegisterEvent("MAIL_SHOW")
	self:RegisterEvent("MAIL_CLOSED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function BulkMail:OnDisable()
	self:UnregisterAllEvents()
	tablet:Unregister("BMAutoSendEdit")
end

--[[--------------------------------------------------------------------------------
  Console Functions
-----------------------------------------------------------------------------------]]
function BulkMail:ListAutoSendItems()
	for itemID, dest in pairs(self.db.realm.autoSendListItems) do
		self:Print("%s - %s", (select(2, GetItemInfo(itemID))) or itemID, dest)
	end
end

function BulkMail:AddAutoSendItem(...)
	local arg = {...}
	local dest
	if string.match(arg[1], "^|[cC]") then  -- first arg is an item or PT set, not a name
		dest = self.db.char.defaultDestination
	else
		dest = table.remove(arg, 1)
	end
	for i = 1, #arg do  -- cycle through all items supplied in the commandline
		local itemID = string.match(arg[i], "item:(%d+)")
		if itemID then
			table.insert(autoSendRules[dest].include.items, itemID)
			tablet:Refresh("BMAutoSendEdit")
			self:Print("%s - %s", select(2, GetItemInfo(itemID)) or itemID, dest)
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
	autoSendRules[destination] = nil
end

function BulkMail:ClearAutoSendList(confirm)
	if string.lower(confirm) == "confirm" then
		self:ResetDB("realm")
	else
		self:Print(L["You must type 'confirm' to clear"])
	end
end

--[[--------------------------------------------------------------------------------
  Events
-----------------------------------------------------------------------------------]]
function BulkMail:MAIL_SHOW()
	OpenAllBags()  -- make sure container frames are all seen before we run through them
	OpenAllBags()  -- in case previous line closed bags (if it was called while a bag was open)
	initializeContainerFrames()
	destCacheBuild()

	self:SecureHook("ContainerFrameItemButton_OnModifiedClick")
	self:SecureHook("SendMailFrame_CanSend")
	self:HookScript(SendMailMailButton, "OnClick", "SendMailMailButton_OnClick")
	self:HookScript(MailFrameTab2, "OnClick", "MailFrameTab2_OnClick")
	self:HookScript(SendMailNameEditBox, "OnTextChanged", "SendMailNameEditBox_OnTextChanged")

	SendMailMailButton:Enable()
end

function BulkMail:MAIL_CLOSED()
	self:UnhookAll()
	sendCacheCleanup()
	if containerFrames then
		for bag, slot in pairs(containerFrames) do
			for _, f in pairs(slot) do
				if f.SetButtonState then f:SetButtonState("NORMAL", 0) end
			end
		end
	end
	BulkMail:HideGUI()
end
BulkMail.PLAYER_ENTERING_WORLD = BulkMail.MAIL_CLOSED  -- MAIL_CLOSED doesn't get called if, for example, the player accepts a port with the mail window open

--[[--------------------------------------------------------------------------------
  Hooks
-----------------------------------------------------------------------------------]]
function BulkMail:ContainerFrameItemButton_OnModifiedClick(button, ignoreModifiers)
	if IsControlKeyDown() and IsShiftKeyDown() then
		self:QuickSend(this)
	end
	if IsAltKeyDown() then
		sendCacheToggle(this)
	else
		sendCacheRemove(this)
	end
end

function BulkMail:SendMailFrame_CanSend()
	if (sendCache and next(sendCache)) or GetSendMailItem() then
		SendMailMailButton:Enable()
	end
	self:RefreshGUI()
end

function BulkMail:SendMailMailButton_OnClick(frame, a1)
	cacheLock = true
	pmsqDest = SendMailNameEditBox:GetText()
	if SendMailNameEditBox:GetText() == '' then
		pmsqDest = nil
	end
	if GetSendMailItem() or sendCache and next(sendCache) then
		self:ScheduleRepeatingEvent("BMSendLoop", self.Send, 0.1, self)
	else
		this = SendMailMailButton
		return self.hooks[frame].OnClick(a1)
	end
end

function BulkMail:MailFrameTab2_OnClick(frame, a1)
	self:ShowGUI()
	sendCacheBuild(string.lower(SendMailNameEditBox:GetText()))
	return self.hooks[frame].OnClick(a1)
end

function BulkMail:SendMailNameEditBox_OnTextChanged(frame, a1)
	sendCacheBuild(string.lower(SendMailNameEditBox:GetText()))
	return self.hooks[frame].OnTextChanged(a1)
end

--[[--------------------------------------------------------------------------------
  Actions
-----------------------------------------------------------------------------------]]
-- Sends the current item in the SendMailItemButton to the currently-specified
-- destination (or the default if that field is blank), then supplies items and
-- destinations from BulkMail's send queue and sends them.
function BulkMail:Send()
	local cache = sendCache and select(2, next(sendCache))
	if GetSendMailItem() then
		local itemDest
		if not pmsqDest then
			local packageID = SendMailPackageButton:GetID()
			itemDest = self.db.realm.autoSendListItems[tostring(packageID)] or getPTSendDest(packageID)
		end
		SendMailNameEditBox:SetText(pmsqDest or itemDest or self.db.char.defaultDestination or '')
		if SendMailNameEditBox:GetText() ~= '' then
			this = SendMailMailButton
			return self.hooks[SendMailMailButton].OnClick()
		elseif not self.db.char.defaultDestination then
			self:Print(L["No default destination set."])
			self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
			cacheLock = false
			return self:CancelScheduledEvent("BMSendLoop")
		end
	elseif cache then
		local bag, slot = cache[1], cache[2]
		local itemLink = GetContainerItemLink(bag, slot)
		PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		if itemLink then
			SendMailPackageButton:SetID(string.match(itemLink, "item:(%d+):") or 0)
		end
		return sendCacheRemove(bag, slot)
	else
		self:CancelScheduledEvent("BMSendLoop")
		return sendCacheCleanup()
	end
end

-- Send the container slot's item immediately to its autosend destination
-- (or the default destination if no destination specified).
-- This can be done whenever the mailbox is open, and is run when the user
-- Ctrl-Shift-LeftClicks on an item.
function BulkMail:QuickSend(bag, slot, dest)
	-- convert to (bag, slot, dest) if called as (frame, dest)
	if type(slot) ~= "number" then
		bag, slot, dest = bag:GetParent():GetID(), bag:GetID(), slot
	end

	if bag and slot then
		PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		if GetSendMailItem() then
			SendMailNameEditBox:SetText(dest or self.db.realm.autoSendListItems[tostring(SendMailPackageButton:GetID())] or self.db.char.defaultDestination or '')
			if SendMailNameEditBox:GetText() ~= '' then
				this = SendMailMailButton
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

--[[--------------------------------------------------------------------------------
  Mailbox GUI (rewritten for tablet by Kemayo)
-----------------------------------------------------------------------------------]]
local function getLockedContainerItem()
	for bag=0, NUM_BAG_SLOTS do
		for slot=1, GetContainerNumSlots(bag) do
			if select(3, GetContainerItemInfo(bag, slot)) then
				return bag, slot
			end
		end
	end
end

function BulkMail:ShowGUI()
	if not tablet:IsRegistered('BulkMail') then
		tablet:Register('BulkMail', 'detachedData', self.db.profile.tablet_data,
			'dontHook', true, 'showTitleWhenDetached', true, 'children', function()

			tablet:SetTitle("BulkMail")
			
			local cat = tablet:AddCategory('columns', 1, 'text', L["Items to be sent (Alt-Click to add/remove):"],
				'showWithoutChildren', true, 'child_indentation', 5)
			
			if sendCache and #sendCache > 0 then
				for i, v in pairs(sendCache) do
					local v1, v2 = v[1], v[2]
					local itemLink = GetContainerItemLink(v1, v2)
					local itemText = itemLink and GetItemInfo(itemLink)
					local texture, qty = GetContainerItemInfo(v1, v2)
					if qty and qty > 1 then
						itemText = string.format("%s(%d)", itemText, qty)
					end						
					cat:AddLine('text', itemText,
						'checked', true, 'hasCheck', true, 'checkIcon', texture,
						'func', self.OnItemSelect, 'arg1', self, 'arg2', v1, 'arg3', v2)
				end
			else
				cat:AddLine('text', L["No items selected"])
			end
			
			cat = tablet:AddCategory('columns', 1)
			cat:AddLine('text', L["Drop items here for Sending"], 'justify', 'CENTER', 'func', self.OnDropClick, 'arg1', self)
			
			if sendCache and #sendCache > 0 then
				cat = tablet:AddCategory('columns', 1)
				cat:AddLine('text', L["Clear"], 'func', sendCacheCleanup, 'arg1')
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

function BulkMail:OnSendClick()
	if not sendCache then return end
	self:SendMailMailButton_OnClick()
end

function BulkMail:OnDropClick()
	if GetSendMailItem() then
		self:Print(L["WARNING: Cursor item detection is NOT well-defined when multiple items are 'locked'.   Alt-click is recommended for adding items when there is already an item in the Send Mail item frame."])
	end
	if CursorHasItem() and getLockedContainerItem() then
		sendCacheAdd(getLockedContainerItem())
		PickupContainerItem(getLockedContainerItem())  -- clears the cursor
	end
	self:RefreshGUI()
end

--[[--------------------------------------------------------------------------------
  AutoSend Edit GUI
-----------------------------------------------------------------------------------]]
local shown = {}
local showAddRuleMenu -- functions

local function addNewDest(dest)
	local _ = autoSendRules[dest]
	tablet:Refresh("BMAutoSendEdit")
end

local confirmedDestToRemove
local function removeConfirmedDest()
	autoSendRules[confirmedDestToRemove] = nil
	tablet:Refresh("BMAutoSendEdit")
end

local function showAddRuleMenu(ruleset)
	BulkMail:PrintLiteral(ruleset)
end

function BulkMail:RegisterAutoSendEditTablet()
	tablet:Register("BMAutoSendEdit",
		"children", function() self:FillAutoSendEditTablet() end, "data", {},
		"cantAttach", true, "clickable", true,
		"showTitleWhenDetached", true, "showHintWhenDetached", true,
		"dontHook", true, "strata", "DIALOG")
end

function BulkMail:FillAutoSendEditTablet()
	local cat
	tablet:SetTitle(L["AutoSend Rules"])
	-- categories; one per destination character
	for dest, rulesets in pairs(autoSendRules) do
		-- category title (destination character's name)
		cat = tablet:AddCategory(
			'id', dest, 'text', dest, 'showWithoutChildren', true,
			'checked', true, 'hasCheck', true, 'checkIcon', string.format("Interface\\Buttons\\UI-%sButton-Up", shown.dest and "Minus" or "Plus"),
			'func', function(dest)
				if IsControlKeyDown() then
					confirmedDestToRemove = dest
					StaticPopup_Show("BULKMAIL_REMOVE_DESTINATION")
				else
					shown.dest = not shown.dest
				end
				tablet:Refresh("BMAutoSendEdit")
			end, 'arg1', dest)
		-- rules list prototype
		local function listRules(ruleset)
			if not ruleset then return end
			for ruletype, rules in pairs(ruleset) do
				for k, rule in ipairs(rules) do
					cat:AddLine(
						'text', ruletype == "items" and select(2, GetItemInfo(rule)) or rule,
						'indentation', 15,
						'func', function(ruleset, id)
							if IsControlKeyDown() then
								table.remove(rules, k)
								tablet:Refresh("BMAutoSendEdit")
							end
						end, 'arg1', rules, 'arg2', k)
				end
			end
		end
		if shown.dest then
			-- "include" rules for this destination; clicking brings up menu to add new include rules (not yet implemented)
			cat:AddLine('text', L["Include"], 'indentation', 5, 'func', showAddRuleMenu, 'arg1', rulesets.include) 
			listRules(rulesets.include)
			-- "exclude" rules for this destination; clicking brings up menu to add new exclude rules (not yet implemented)
			cat:AddLine('text', L["Exclude"], 'indentation', 5, 'func', showAddRuleMenu, 'arg1', rulesets.exclude)
			listRules(rulesets.exclude)
		end
	end

	cat = tablet:AddCategory('id', "actions")
	cat:AddLine('text', L["New Destination"], 'func', function() StaticPopup_Show("BULKMAIL_ADD_DESTINATION") end)
	cat:AddLine('text', L["Close"], 'func', function() self:ScheduleEvent(function() tablet:Close("BMAutoSendEdit") end, 0.01) end)  -- WTF
end

StaticPopupDialogs["BULKMAIL_ADD_DESTINATION"] = {
	text = L["BulkMail - New AutoSend Destination"],
	button1 = L["Accept"],
	button2 = L["Cancel"],
	hasEditBox = 1,
	maxLetters = 20,
	OnAccept = function()
		addNewDest(getglobal(this:GetParent():GetName().."EditBox"):GetText())
	end,
	OnShow = function()
		getglobal(this:GetName().."EditBox"):SetFocus()
	end,
	OnHide = function()
		if ( ChatFrameEditBox:IsVisible() ) then
			ChatFrameEditBox:SetFocus()
		end
		getglobal(this:GetName().."EditBox"):SetText("")
	end,
	EditBoxOnEnterPressed = function()
		addNewDest(getglobal(this:GetParent():GetName().."EditBox"):GetText())
		this:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function()
		this:GetParent():Hide()
	end,
	timeout = 0,
	exclusive = 1,
	whileDead = 1,
	hideOnEscape = 1
}
StaticPopupDialogs["BULKMAIL_REMOVE_DESTINATION"] = {
	text = L["Confirm removal of destination"],
	button1 = L["Accept"],
	button2 = L["Cancel"],
	OnAccept = function()
		removeConfirmedDest()
		confirmedDestToRemove = nil
	end,
	OnHide = function()
		confirmedDestToRemove = nil
	end,
	timeout = 0,
	exclusive = 1,
	hideOnEscape = 1
}
