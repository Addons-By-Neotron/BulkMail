BulkMail = AceLibrary('AceAddon-2.0'):new('AceDB-2.0', 'AceEvent-2.0', 'AceHook-2.1', 'AceConsole-2.0')
local self, BulkMail = BulkMail, BulkMail

local L = AceLibrary('AceLocale-2.2'):new('BulkMail')

BulkMail.L = L

local LibStub = LibStub

local pt       = LibStub:GetLibrary('LibPeriodicTable-3.1')
local abacus   = LibStub:GetLibrary("LibAbacus-3.0")
local gratuity = LibStub:GetLibrary("LibGratuity-3.0")
local QTIP     = LibStub:GetLibrary("LibQTip-1.0")
local LD       = LibStub:GetLibrary("LibDropdown-1.0")

local SUFFIX_CHAR = "\32"

local _G = _G
local strmatch = string.match
local strsub = string.sub
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local fmt = string.format
local ChatFrame1EditBox = ChatFrame1EditBox
local ClickSendMailItemButton = ClickSendMailItemButton
local GetContainerItemInfo = GetContainerItemInfo
local GetContainerItemLink = GetContainerItemLink
local GetContainerNumSlots = GetContainerNumSlots
local GetItemInfo = GetItemInfo
local GetSendMailItem = GetSendMailItem
local GetSendMailItemLink = GetSendMailItemLink
local GetSendMailPrice = GetSendMailPrice
local ITEM_BIND_ON_EQUIP = ITEM_BIND_ON_EQUIP
local ITEM_BIND_ON_PICKUP = ITEM_BIND_ON_PICKUP
local ITEM_BIND_QUEST = ITEM_BIND_QUEST
local ITEM_CONJURED = ITEM_CONJURED
local ITEM_SOULBOUND = ITEM_SOULBOUND
local IsAltKeyDown = IsAltKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local MoneyInputFrame_GetCopper = MoneyInputFrame_GetCopper
local MoneyFrame_Update = MoneyFrame_Update
local NUM_BAG_SLOTS = NUM_BAG_SLOTS
local PickupContainerItem = PickupContainerItem
local SendMailCODButton =  SendMailCODButton
local ChatEdit_GetActiveWindow = ChatEdit_GetActiveWindow
local CursorHasItem = CursorHasItem
local SetItemRef = SetItemRef
local ATTACHMENTS_MAX_SEND = ATTACHMENTS_MAX_SEND
local DressUpItemLink = DressUpItemLink
local GetAddOnInfo = GetAddOnInfo
local GetAddOnMetadata = GetAddOnMetadata
local GetAuctionItemClasses = GetAuctionItemClasses
local GetAuctionItemSubClasses = GetAuctionItemSubClasses
local GetNumAddOns = GetNumAddOns
local LoadAddOn = LoadAddOn
local MAX_CONTAINER_ITEMS = MAX_CONTAINER_ITEMS
local MailFrame = MailFrame
local MailFrameTab1 = MailFrameTab1
local MailFrameTab2 = MailFrameTab2
local MoneyInputFrame_SetCopper = MoneyInputFrame_SetCopper
local NUM_CONTAINER_FRAMES = NUM_CONTAINER_FRAMES
local SetItemButtonDesaturated = SetItemButtonDesaturated
local StaticPopup_Visible = StaticPopup_Visible
local UnitName = UnitName
local min = math.min
local print = print
local strlen = strlen
local strsplit = strsplit
local SendMailMailButton = SendMailMailButton
local SendMailMoney = SendMailMoney
local SendMailNameEditBox = SendMailNameEditBox
local SendMailSendMoneyButton = SendMailSendMoneyButton
local SendMailSubjectEditBox = SendMailSubjectEditBox
local StaticPopupDialogs = StaticPopupDialogs
local StaticPopup_Show = StaticPopup_Show
local ipairs = ipairs
local next = next
local pairs = pairs
local select = select
local setmetatable = setmetatable
local strsub = strsub
local tonumber = tonumber
local tostring = tostring
local type = type
local unpack = unpack

local auctionItemClasses, sendCache, destCache, reverseDestCache, destSendCache, rulesCache, autoSendRules, globalExclude -- tables
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
--   PT31Sets   - set is unpacked and each item is inserted as a table key
--   ItemTypes - ItemType is inserted as a table key pointing to a table of
--               desired subtype keys
-- Exclusions are processed after all include rules are handled, 
-- and will nil out the appropriate keys in the table.
rulesCache = {}
local function rulesCacheBuild()
   if next(rulesCache) and not rulesAltered then return end
   for k in pairs(rulesCache) do
      rulesCache[k] = deepDel(rulesCache[k])
   end
   for dest, rules in pairs(autoSendRules) do
      rulesCache[dest] = new()
      -- include rules
      for _, itemID in ipairs(rules.include.items) do rulesCache[dest][tonumber(itemID)] = true end
      for _, set in ipairs(rules.include.pt31Sets) do
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

      for _, set in ipairs(rules.exclude.pt31Sets) do
	 for itemID in pt:IterateSet(set) do rulesCache[dest][itemID] = nil end
      end
      for _, set in ipairs(globalExclude.pt31Sets) do
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
   local itemID = type(item) == 'number' and item or tonumber(strmatch(item, "item:(%d+)"))
   for _, xID in ipairs(globalExclude.items) do if itemID == xID then return end end
   for _, xset in ipairs(globalExclude.pt31Sets) do
      if pt:ItemInSet(itemID, xset) == true then return end
   end

   local itype, isubtype = select(6, GetItemInfo(itemID))
   for dest, rules in pairs(rulesCache) do
      local canddest
      if dest ~= UnitName('player') and (rules[itemID] or rules[itype] and rules[itype][isubtype]) then canddest = dest end
      if canddest then
	 local xrules = autoSendRules[canddest].exclude
	 for _, xID in ipairs(xrules.items) do if itemID == xID then canddest = nil end end
	 for _, xset in ipairs(xrules.pt31Sets) do
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

-- Returns the frame associated with bag, slot
local function getBagSlotFrame(bag,slot)
   if bag >= 0 and bag < NUM_CONTAINER_FRAMES and slot > 0 and slot <= MAX_CONTAINER_ITEMS then
      local bagslots = GetContainerNumSlots(bag)
      if bagslots > 0 then
	 return _G["ContainerFrame" .. (bag + 1) .. "Item" .. (bagslots - slot + 1)]
      end
   end
end

-- Shades or unshades the given bag slot
local function shadeBagSlot(bag,slot,shade)
   local frame = getBagSlotFrame(bag,slot)
   if frame then
      SetItemButtonDesaturated(frame,shade)
   end
end

-- Add a container slot to BulkMail's send queue.
sendCache = {}
local function sendCacheAdd(bag, slot, squelch)
   -- convert to (bag, slot, squelch) if called as (frame, squelch)
   if type(slot) ~= 'number' then
      bag, slot, squelch = bag:GetParent():GetID(), bag:GetID(), slot
   end
   if GetContainerItemInfo(bag, slot) and not (sendCache[bag] and sendCache[bag][slot]) then
      gratuity:SetBagItem(bag, slot)
      if not gratuity:MultiFind(2, 4, nil, true, ITEM_SOULBOUND, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP) or gratuity:Find(ITEM_BIND_ON_EQUIP, 2, 4, nil, true, true) then
	 sendCache[bag] = sendCache[bag] or new()
	 sendCache[bag][slot] = true;
	 numItems = numItems + 1
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
      if BulkMail.db.char.isSink or dest ~= '' and not destCache[dest] then
	 -- no need to check for an item in the autosend list if this character is a sink or if the destination string doesn't have any rules set
	 return BulkMail:RefreshSendQueueGUI()
      end
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

-- Organize the send queue by recipient in order to reduce fragmentation of multi-item mails
destSendCache = {}
local function organizeSendCache()
   destSendCache = deepDel(destSendCache)
   local dest
   for bag, slots in pairs(sendCache) do
      for slot in pairs(slots) do
	 dest = sendDest ~= '' and sendDest or rulesCacheDest(GetContainerItemLink(bag, slot)) or self.db.char.defaultDestination
	 if dest then
	    destSendCache = destSendCache or new()
	    destSendCache[dest] = destSendCache[dest] or new()
	    tinsert(destSendCache[dest], new(bag, slot))
	 else
	    self:Print(L["No default destination set."])
	    self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
	 end
      end
   end
end

--[[----------------------------------------------------------------------------
Setup
------------------------------------------------------------------------------]]
function BulkMail:OnInitialize()
   self:RegisterDB('BulkMail2DB')
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
      tinsert(reverseDestCache, dest)
   end

   self:RegisterDefaults('char', {
			    isSink = false,
			    attachMulti = true,
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
		  func = function() BulkMail:OpenEditQTip() end,
	       },
	       add = {
		  name = L["add"], type = 'text', aliases = L["+"],
		  desc = L["Add an item rule by itemlink or LibPeriodicTable-3.1 set manually."],
		  input = true, set = 'AddAutoSendRule', usage = L["[destination] <itemlink|Periodic.Table.Set> [itemlink2|P.T.S.2 itemlink3|P.T.S.3 ...]"], get = false,
		  validate = function(arg1) return self.db.char.defaultDestination or (not strmatch(arg1, "^|[cC]") and not pt:IsSetMulti(arg1) ~= nil) end,
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
		  func = function() self:ResetDB('realm') for i in pairs(autoSendRules) do autoSendRules[i] = nil end BulkMail:RefreshEditQTip() end, confirm = true,
	       },
	    },
	 },
	 sink = {
	    name = L["Sink"], type = 'toggle',
	    desc = L["Disable AutoSend queue auto-filling for this character."],
	    get = function() return self.db.char.isSink end,
	    set = function(v) self.db.char.isSink = v end,
	 },
	 attachmulti = {
	    name = L["Attach multiple items"], type = 'toggle',
	    desc = L["Attach as many items as possible per mail."],
	    get = function() return self.db.char.attachMulti end,
	    set = function(v) self.db.char.attachMulti = v end,
	 },
      },
   }
   self:RegisterChatCommand({"/bulkmail", "/bm"}, self.opts)

   -- LoD PT31 Sets; yanked from Baggins
   local PT31Modules
   for i = 1, GetNumAddOns() do
      local metadata = GetAddOnMetadata(i, "X-PeriodicTable-3.1-Module")
      if metadata then
	 local name, _, _, enabled = GetAddOnInfo(i)
	 if enabled then
	    LoadAddOn(name)
	 end
      end
   end
end

function BulkMail:OnEnable()
   self:RegisterEvent('MAIL_SHOW')
   self:RegisterEvent('MAIL_CLOSED')
   self:RegisterEvent('PLAYER_ENTERING_WORLD')

   -- Handle being LoD loaded while at the mailbox
   if MailFrame:IsVisible() then
      self:MAIL_SHOW()
   end
end

function BulkMail:OnDisable()
   self:UnregisterAllEvents()
   self:UnhookAll()
end

--[[----------------------------------------------------------------------------
Events
------------------------------------------------------------------------------]]
local mailIsVisible
function BulkMail:MAIL_SHOW()
   if not mailIsVisible then
      mailIsVisible = true
      if rulesAltered then rulesCacheBuild() end
      self:SecureHook('ContainerFrameItemButton_OnModifiedClick')
      self:SecureHook('SendMailFrame_CanSend')
      self:SecureHook('ContainerFrame_Update')
      self:SecureHook('MoneyInputFrame_OnTextChanged', SendMailFrame_CanSend)
      self:SecureHook('SetItemRef')
      self:HookScript(SendMailMailButton, 'OnClick', 'SendMailMailButton_OnClick')
      self:HookScript(MailFrameTab1, 'OnClick', 'MailFrameTab1_OnClick')
      self:HookScript(MailFrameTab2, 'OnClick', 'MailFrameTab2_OnClick')
      self:HookScript(SendMailNameEditBox, 'OnTextChanged', 'SendMailNameEditBox_OnTextChanged')
      
      SendMailMailButton:Enable()
   end
end

function BulkMail:MAIL_CLOSED()
   if mailIsVisible then
      mailIsVisible = nil
      self:UnhookAll()
      sendCacheCleanup()
      self:HideSendQueueGUI()
      self:CancelScheduledEvent('BM_SendLoop')
   end
end

BulkMail.PLAYER_ENTERING_WORLD = BulkMail.MAIL_CLOSED  -- MAIL_CLOSED doesn't get called if, for example, the player accepts a port with the mail window open

--[[----------------------------------------------------------------------------
Hooks
------------------------------------------------------------------------------]]
function BulkMail:ContainerFrameItemButton_OnModifiedClick(frame, button)
   if IsControlKeyDown() and IsShiftKeyDown() then
      self:QuickSend(frame:GetParent():GetID(), frame:GetID())
   elseif IsAltKeyDown() then
      sendCacheToggle(frame:GetParent():GetID(), frame:GetID())
   elseif not IsShiftKeyDown() then
      sendCacheRemove(frame:GetParent():GetID(), frame:GetID())
   end
end

function BulkMail:SendMailFrame_CanSend()
   if sendCache and next(sendCache) or GetSendMailItem() or SendMailSendMoneyButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney) > 0 then
      SendMailMailButton:Enable()
      SendMailCODButton:Enable()
   end
   self:ScheduleEvent('canSendRefresh', self.RefreshSendQueueGUI, 0.1, self)
end

function BulkMail:ContainerFrame_Update(...)
   local frame = ...
   local bag = tonumber(strsub(frame:GetName(),15))
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
	    SendMailNameEditBox:SetText(name)
	 end 
      end 
   end 
end 

function BulkMail:SendMailMailButton_OnClick(frame, a1)
   cacheLock = true
   sendDest = SendMailNameEditBox:GetText()
   local cod = SendMailCODButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney)
   if GetSendMailItem() or sendCache and next(sendCache) then
      organizeSendCache()
      self:ScheduleRepeatingEvent('BM_SendLoop', self.Send, 0.1, self, cod)
   else
      if SendMailSendMoneyButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney) and SendMailSubjectEditBox:GetText() == '' and (not sendCache or not next(sendCache)) then
	 SendMailSubjectEditBox:SetText(abacus:FormatMoneyFull(MoneyInputFrame_GetCopper(SendMailMoney)))
	 if SendMailNameEditBox:GetText() == '' then
	    if self.db.char.defaultDestination then
	       SendMailNameEditBox:SetText(self.db.char.defaultDestination)
	    else
	       self:Print(L["No default destination set."])
	       self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
	    end
	 end
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
   tinsert(reverseDestCache, dest)
   rulesAltered = true
end

function BulkMail:RemoveDestination(dest)
   autoSendRules[dest] = nil
   destCache[dest] = nil
   for i=1, #reverseDestCache do
      if reverseDestCache[i] == dest then
	 tremove(reverseDestCache, i)
	 break
      end
   end
   rulesAltered = true
end

-- Simple function for adding include rules manually via itemlink or
-- LibPeriodicTable-3.1 set name.  If the first arg is neither of these, then
-- it must be the destination; otherwise, defaultDestination is used.
-- This is the function called by /bm autosend add.
function BulkMail:AddAutoSendRule(...)
   local dest = select(1, ...)
   local start = 2
   if strmatch(dest, "^|[cC]") or pt:IsSetMulti(dest) ~= nil then
      dest = self.db.char.defaultDestination  -- first arg is an item or PT set, not a name, so use default (validation that default exists is handled by AceOptions)
      start = 1
   end
   self:AddDestination(dest)
   for i = start, select('#', ...) do
      local th = select( i, ...)
      print (i, " = ", th)
      local itemID = tonumber(strmatch(select(i, ...), "item:(%d+)"))
      if itemID then  -- is an item link
	 tinsert(autoSendRules[dest].include.items, itemID)
	 mod:RefreshEditQTip()	 
	 self:Print("%s - %s", select(i, ...), dest)
      elseif pt:IsSetMulti(select(i, ...)) ~= nil then  -- is a PT31 set
	 tinsert(autoSendRules[dest].include.pt31Sets, select(i, ...))
	 mod:RefreshEditQTip()	 
	 self:Print("%s - %s", select(i, ...), dest)
      end
   end
   rulesAltered = true
end

-- Sends the current item in the SendMailItemButton to the currently-specified
-- destination (or the default if that field is blank), then supplies items and
-- destinations from BulkMail's send queue and sends them.
local suffix = SUFFIX_CHAR  -- for ensuring subject uniqueness to help BMI's "selected item" features
function BulkMail:Send(cod)
   if StaticPopup_Visible('SEND_MONEY') then return end
   if GetSendMailItem(1) then
      SendMailNameEditBox:SetText(sendDest ~= '' and sendDest or rulesCacheDest(GetSendMailItemLink(1)) or self.db.char.defaultDestination or '')
      if SendMailNameEditBox:GetText() ~= '' then
	 if #suffix > 10 then suffix = SUFFIX_CHAR else suffix = suffix..SUFFIX_CHAR end
	 _G.this = SendMailMailButton
	 return self.hooks[SendMailMailButton].OnClick(SendMailMailButton)
      elseif not self.db.char.defaultDestination then
	 self:Print(L["No default destination set."])
	 self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
	 cacheLock = false
	 return self:CancelScheduledEvent('BM_SendLoop')
      end
      return
   end
   if destSendCache and next(destSendCache) then
      local dest, bagslots = next(destSendCache)
      local bag, slot
      for i=1, min(self.db.char.attachMulti and ATTACHMENTS_MAX_SEND or 1, #bagslots) do
	 bag, slot = unpack(tremove(bagslots))
	 PickupContainerItem(bag, slot)
	 ClickSendMailItemButton(i)
      end
      destSendCache[dest] = next(bagslots) and bagslots or del(bagslots)

      SendMailSubjectEditBox:SetText(SendMailSubjectEditBox:GetText()..suffix)
      if cod then
	 SendMailSendMoneyButton:SetChecked(nil)
	 MoneyInputFrame_SetCopper(SendMailMoney, cod)
      end
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
      PickupContainerItem(bag, slot)
      ClickSendMailItemButton()
      if GetSendMailItem(1) then
	 local dest = SendMailNameEditBox:GetText()
	 if dest == '' then
	    SendMailNameEditBox:SetText(rulesCacheDest(GetSendMailItemLink(1)) or self.db.char.defaultDestination or '')
	 end
	 if SendMailNameEditBox:GetText() ~= '' then
	    _G.this = SendMailMailButton
	    return self.hooks[SendMailMailButton].OnClick(SendMailMailButton)
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
QTip Windows -- AutoSend Edit GUI
------------------------------------------------------------------------------]]
local shown = {}  -- keeps track of collapsed/expanded state in tablet
local curRuleSet -- for adding rules via the menu dropdown
local dupeCheck = {}

local function newDest()
   StaticPopup_Show("BULKMAIL_ADD_DESTINATION")
end

local function _insertOrRemoveRule(ruletype, value)
   local removed
   for i, v in ipairs(curRuleSet[ruletype]) do
      if ruletype == "itemTypes" then
	 if v.type == value.type and v.subtype == value.subtype then
	    removed = true
	 end
      elseif v == value then
	 removed = true
      end
      if removed then
	 tremove(curRuleSet[ruletype], i)
	 rulesAltered = true   
	 if type(value) == "table" then
	    del(value)
	 end
	 break
      end
   end
   if not removed then
      tinsert(curRuleSet[ruletype], value)
      rulesAltered = true   
   end
   BulkMail:OpenEditQTip()   
end

local function _editCallbackMethod(args, val)
   -- get the value based on the type of data
   local value
   local ruletype = tremove(args, 1)
   if ruletype == "itemIDs" then
      local uniqueids = new()
      for id in val:gmatch("([^% ]+)") do
	 id = tonumber(id)
	 if id then uniqueids[id] = true end
      end
      
      for id in pairs(uniqueids) do
	 _insertOrRemoveRule("items", id)
      end
      return
   elseif ruletype == "pt31Sets" then
      value = tconcat(args, ".")
   elseif ruletype == "items" then
      value = tonumber(args[1])
   elseif ruletype == "itemTypes" then
      value = newHash('type', args[1],
		      'subtype', #args > 1 and args[2]);
   end
   _insertOrRemoveRule(ruletype, value)
end

local Ace3ConfigTable = {
   type = "group",
   handler = BulkMail,
   set = _editCallbackMethod,
   get = function() return nil end,
   args = {
      inline = {
	 type = "header",
	 name = L["Add rule"],
	 inline = true,
	 order = 0,
      },
      itemIDs = {
	 type = "input",
	 name = L["ItemID(s)"],
	 desc = L["Usage: <itemID> [itemID2, ...]"]
      }
   }
}

local menuFrame 
local PT31ConfigTable 
local ItemTypesConfigTable
local InventoryConfigTable

local function updateInventoryConfigTable()
   deepDel(InventoryConfigTable)
   InventoryConfigTable = newHash(
      'type', "group",
      'name', L["Items from Bags"],
      'desc', L["Mailable items in your bags."], 
      'args', new()
   )

   for k in pairs(dupeCheck) do dupeCheck[k] = nil end

   -- Mailable items in bags
   for bag, slot, item in bagIter() do
      local itemID = tonumber(strmatch(item or '', "item:(%d+)"))      
      if itemID and not dupeCheck[itemID] then
	 dupeCheck[itemID] = true
	 gratuity:SetBagItem(bag, slot)
	 if (not gratuity:MultiFind(2, 4, nil, true, ITEM_SOULBOUND, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP)
	  or gratuity:Find(ITEM_BIND_ON_EQUIP, 2, 4, nil, true, true)) then
	    local link = select(2, GetItemInfo(itemID))
	    local texture = select(10, GetItemInfo(itemID))
	    InventoryConfigTable.args[tostring(itemID)] = newHash(
	       "type", "toggle",
	       "name", fmt("|T%s:18|t%s", texture, link)
	    )
	 end
      end
   end
end

local function createPT31SetsConfigTable(force)
   -- LibPeriodicTable-3.1 sets
   if force then PT31ConfigTable = deepDel(PT31ConfigTable) end
   if PT31ConfigTable then return end

   PT31ConfigTable = newHash(
      'type', "group",
      'name', L["Periodic Table Set"],
      'args', new()
   )
      
   local pathtable = new()
   local curmenu, prevmenu
   for setname in pairs(pt.sets) do
      for k in ipairs(pathtable) do pathtable[k] = nil end
      curmenu = PT31ConfigTable.args
      for cat in setname:gmatch("([^%.]+)") do
	 tinsert(pathtable, cat)
	 if not curmenu[cat] then
	    curmenu[cat] = newHash('name', cat,
				   'type', 'group',
				   'args', new())
	 end
	 prevmenu, curmenu = curmenu[cat], curmenu[cat].args
      end
      prevmenu.type = "toggle"
   end
end

local function createBlizzardCategoryConfigTable(force)
   -- Blizzard item types
   if force then ItemTypesConfigTable = deepDel(ItemTypesConfigTable) end
   if ItemTypesConfigTable then return end

   ItemTypesConfigTable = newHash(
      'type', "group",
      'name', L["Item Type"],
      'args', new()
   )

   for itype, subtypes in pairs(auctionItemClasses) do
      if #subtypes == 0 then
	 ItemTypesConfigTable.args[itype] = newHash('type', "toggle", 'name', itype)
      else
	 local supertype = new()
	 ItemTypesConfigTable.args[itype] = newHash(
	    'type', "group",
	    'name', itype, 
	    'args', supertype
	 )

	 for _, isubtype in ipairs(subtypes) do
	    supertype[isubtype] = newHash('type', "toggle", 'name', isubtype)
	 end
      end
   end
end

-- Show the add new data menu
-- Fun stuff
local function _showmenu(parentFrame, args)
   -- release if if already shown
   menuFrame = menuFrame and menuFrame:Release()

   -- Create the config structures   
   createBlizzardCategoryConfigTable(force)
   createPT31SetsConfigTable(force)
   updateInventoryConfigTable()
   
   -- Inject into the overall structure
   Ace3ConfigTable.args.pt31Sets  = PT31ConfigTable
   Ace3ConfigTable.args.itemTypes = ItemTypesConfigTable
   Ace3ConfigTable.args.items     = InventoryConfigTable


   -- save the current ruleset
   curRuleSet = args 
   
   -- create the menu   
   menuFrame = LD:OpenAce3Menu(Ace3ConfigTable)

   -- Anchor the menu to the mouse
   local xpos, ypos = GetCursorPosition()
   local scale = UIParent:GetEffectiveScale()
   menuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", xpos / scale, ypos / scale)
   menuFrame:SetFrameLevel(parentFrame:GetFrameLevel()+100)
end


local function color(text, color)
   return fmt("|cff%s%s|r", color, text)
end

local function _plusminus(enabled)
   return fmt("|TInterface\\Buttons\\UI-%sButton-Up:18|t", enabled and "Minus" or "Plus")
end

local function _addIndentedCell(tooltip, text, indentation, func, arg)
   local y, x = tooltip:AddLine()
   tooltip:SetCell(y, x, text, tooltip:GetFont(), "LEFT", 1, nil, indentation)
   if func then
      tooltip:SetLineScript(y, "OnMouseUp", func, arg)
   end
   return y, x
end

local function _toggleEditHeader(frame, dest)
   menuFrame = menuFrame and menuFrame:Release()

   if IsAltKeyDown() and dest ~= "globalExclude" then
      confirmedDestToRemove = dest
      StaticPopup_Show('BULKMAIL_REMOVE_DESTINATION')
   else
      shown[dest] = not shown[dest]
   end
   BulkMail:OpenEditQTip()   
end

local function _listRulesQTip(tooltip, ruleset)
   local x, y
   local addedRule
   if ruleset then
      for ruletype, rules in pairs(ruleset) do
	 for k, rule in ipairs(rules) do
	    local checkIcon
	    local text, color = tostring(rule), "ffffff"
	    local func = function(frame)
			    menuFrame = menuFrame and menuFrame:Release()
			    if IsAltKeyDown() then
			       tremove(rules, k)
			       BulkMail:OpenEditQTip()
			       rulesAltered = true
			    end
			 end
	    
	    if ruletype == 'items' then
	       text = select(2, GetItemInfo(rule))
	       checkIcon = select(10, GetItemInfo(rule))
	    elseif ruletype == 'itemTypes' then
	       if rule.subtype and rule.subtype ~= rule.type then
		  text = fmt("|cfffadfa8Item Type: %s - %s|r", rule.type, rule.subtype)
	       else
		  text = fmt("|cfffadfa8Item Type: %s|r", rule.type)
	       end
	    elseif ruletype == 'pt31Sets' then
	       text = fmt("|cffc8c8ffPT31 Set: %s|r", rule)
	    end
	    addedRule = true
	    if(checkIcon) then
	       _addIndentedCell(tooltip, fmt("|T%s:18|t%s", checkIcon, text), 30, func)
	    else
	       _addIndentedCell(tooltip, text, 30, func)
	    end
	 end
      end
   end
   if not addedRule then
      y, x = tooltip:AddLine()
      --:SetCell(lineNum, colNum, value[, font][, justification][, colSpan][, provider][, leftPadding][, rightPadding][, maxWidth][, minWidth][, ...])      
      tooltip:SetCell(y, x, L["None"], tooltip:GetFont(), "LEFT", 1, nil, 30)
      return
   end
   
end


local function _QTipClose(tooltip)
   if not tooltip then return end
   BulkMail.editQueueTooltip = nil
   tooltip:EnableMouse(false)
   tooltip:SetScript("OnDragStart", nil)
   tooltip:SetScript("OnDragStop", nil)
   tooltip:SetMovable(false)
   tooltip:RegisterForDrag()
   tooltip:SetFrameStrata("TOOLTIP")
   QTIP:Release(tooltip)
end

local function _sendEditQueueClose()
   _QTipClose(BulkMail.editQueueTooltip)
   BulkMail.editQueueTooltip = nil
   menuFrame = menuFrame and menuFrame:Release()
end

function BulkMail:RefreshEditQTip()
   if BulkMail.editQueueTooltip then
      BulkMail:OpenEditQTip()
   end
end

function BulkMail:OpenEditQTip()
   
   local tooltip = BulkMail.editQueueTooltip
   if not tooltip then
      tooltip = QTIP:Acquire("BulkMail3EditQueueTooltip")
      tooltip:EnableMouse(true)
      tooltip:SetScript("OnDragStart", function(this) menuFrame = menuFrame and menuFrame:Release() tooltip.StartMoving(this) end)
      tooltip:SetScript("OnDragStop", tooltip.StopMovingOrSizing)
      tooltip:RegisterForDrag("LeftButton")
      tooltip:SetMovable(true)
      tooltip:SetColumnLayout(1, "LEFT")
      tooltip:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      self.editQueueTooltip = tooltip
   else
      tooltip:Clear()      
   end
   
   local y = tooltip:AddHeader();
   tooltip:SetCell(y, 1, color(L["AutoSend Rules"], "ffd200"), tooltip:GetHeaderFont(), "CENTER", 1)
   tooltip:AddLine(" ")


   for dest, rulesets in pairs(autoSendRules) do
      if destCache[dest] then
	 -- category title (destination character's name)
	 y = tooltip:AddLine(_plusminus(shown[dest]) ..dest)
	 tooltip:SetLineScript(y, "OnMouseUp", _toggleEditHeader, dest)
	 if shown[dest] then
	    _addIndentedCell(tooltip, color(L["Include"], "ffd200"), 20, _showmenu, rulesets.include)
	    _listRulesQTip(tooltip, rulesets.include)
	    -- "exclude" rules for this destination; clicking brings up menu to add new exclude rules	
	    _addIndentedCell(tooltip, color(L["Exclude"], "ffd200"), 20, _showmenu, rulesets.exclude)
	    _listRulesQTip(tooltip, rulesets.exclude)
	    tooltip:AddLine(" ")
	 end
      end
   end

   -- Global Exclude Rules
   y = tooltip:AddLine(_plusminus(shown.globalExclude)..L["Global Exclude"])
   tooltip:SetLineScript(y, "OnMouseUp", _toggleEditHeader, "globalExclude")

   if shown.globalExclude then
      _addIndentedCell(tooltip,color(L["Exclude"], "ffd200"), 20, _showmenu, globalExclude)
      _listRulesQTip(tooltip, globalExclude)
   end

   tooltip:AddLine(" ")
   tooltip:SetLineScript(tooltip:AddLine(color(L["New Destination"], "ffd200")), "OnMouseUp", newDest)
   y = tooltip:AddLine(color(L["Close"], "ffd200"))
   tooltip:SetLineScript(y, "OnMouseUp", _sendEditQueueClose)

   tooltip:AddLine(" ")
   y = tooltip:AddLine()
   tooltip:SetCell(y, 1, color(L["Hint: "]..L["Click Include/Exclude headers to modify a ruleset.  Alt-Click destinations and rules to delete them."], "ffff00"), nil, "LEFT", 1, nil, nil, nil, 250)
   
   tooltip:SetFrameStrata("DIALOG")
   -- set max height to be 90% of the screen height
   tooltip:UpdateScrolling(UIParent:GetHeight() / tooltip:GetScale() * 0.9)
   tooltip:Show()

end

--[[----------------------------------------------------------------------------
QTip Windows -- Send Queue Edit GUI
------------------------------------------------------------------------------]]

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
   if bag and slot then
      local editBox = ChatEdit_GetActiveWindow()
      if IsAltKeyDown() then
	 sendCacheToggle(bag, slot)
      elseif IsShiftKeyDown() and editBox and editBox:IsVisible() then
	 editBox:Insert(GetContainerItemLink(bag, slot))
      elseif IsControlKeyDown() and not IsShiftKeyDown() then
	 DressUpItemLink(GetContainerItemLink(bag, slot))
      else
	 SetItemRef(strmatch(GetContainerItemLink(bag, slot), "(item:%d+:%d+:%d+:%d+)"), GetContainerItemLink(bag, slot), arg1)
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

function BulkMail:HideSendQueueGUI()
   _QTipClose(BulkMail.sendQueueTooltip)
   BulkMail.sendQueueTooltip = nil
end

function BulkMail:RefreshSendQueueGUI()
   if BulkMail.sendQueueTooltip then
      BulkMail:ShowSendQueueGUI()
   end
end

function BulkMail:ShowSendQueueGUI()
   local tooltip = BulkMail.sendQueueTooltip
   if not tooltip then
      tooltip = QTIP:Acquire("BulkMail3SendQueueTooltip")
      tooltip:EnableMouse(true)
      tooltip:SetScript("OnDragStart", tooltip.StartMoving)
      tooltip:SetScript("OnDragStop", tooltip.StopMovingOrSizing)
      tooltip:RegisterForDrag("LeftButton")
      tooltip:SetMovable(true)
      tooltip:SetColumnLayout(2, "LEFT", "RIGHT")
      self.sendQueueTooltip = tooltip
      tooltip:SetPoint("LEFT", MailFrame, "RIGHT", -5, 40)
   else
      tooltip:Clear()      
   end

   local y = tooltip:AddHeader();
   tooltip:SetCell(y, 1, L["Items to be sent (Alt-Click to add/remove):"], tooltip:GetFont(), "CENTER", 2)
   tooltip:AddLine(" ")

   if sendCache and next(sendCache) then
      local itemLink, itemText, texture, qty
      for bag, slots in pairs(sendCache) do
	 for slot in pairs(slots) do
	    itemLink = GetContainerItemLink(bag, slot)
	    if itemLink then
	       itemText = GetItemInfo(itemLink)
	       texture, qty = GetContainerItemInfo(bag, slot)
	       if qty and qty > 1 then
		  itemText = fmt("|T%s:18|t |cffffd200%s (%d)|r", texture, itemText, qty)
	       else
		  itemText = fmt("|T%s:18|t |cffffd200%s|r", texture, itemText)
	       end
	       local y = _addIndentedCell(tooltip, itemText, 5, function(self)
								   onSendQueueItemSelect(bag, slot)
								end)
	       local recipient
	       if sendDest == '' or not sendDest then 
		  recipient = (rulesCacheDest(itemLink) or self.db.char.defaultDestination)
		  if not recipient or strlen(recipient) == 0 then
		     recipient = color(L["Missing"], "ff0000")
		  else
		     recipient = color(recipient, "ffd200")
		  end
	       else
		  recipient = color(sendDest, "00d2ff")
	       end
	       tooltip:SetCell(y, 2, recipient)
	    end
	 end
      end
   else
      _addIndentedCell(tooltip, color(L["No items selected"], "ffd200"), 5)
   end
   
   
   tooltip:AddLine(" ")
   local y = tooltip:AddLine();
   tooltip:SetCell(y, 1, color(L["Drop items here for Sending"], "ffd200"), tooltip:GetFont(), "CENTER", 2)
   tooltip:SetLineScript(y, "OnReceiveDrag", onDropClick)
   tooltip:SetLineScript(y, "OnMouseUp", onDropClick)
   tooltip:AddLine(" ")
   
   if sendCache and next(sendCache) then
      _addIndentedCell(tooltip, color(L["Clear"], "ffd200"), 5, sendCacheCleanup)
      if SendMailMailButton:IsEnabled() and SendMailMailButton:IsEnabled() ~= 0 then
	 _addIndentedCell(tooltip, color(L["Send"], "ffd200"), 5, onSendClick)
      else
	 _addIndentedCell(tooltip, color(L["Send"], "7f7f7f"), 5)
      end
   else
      _addIndentedCell(tooltip, color(L["Clear"], "7f7f7f"), 5)
      _addIndentedCell(tooltip, color(L["Send"],  "7f7f7f"), 5)
   end
   tooltip:AddLine(" ")

   _addIndentedCell(tooltip, color(L["Close"], "ffd200"), 5, BulkMail.HideSendQueueGUI, BulkMail)

   tooltip:SetFrameStrata("FULLSCREEN")
   -- set max height to be 90% of the screen height
   tooltip:UpdateScrolling(UIParent:GetHeight() / tooltip:GetScale() * 0.9)
   tooltip:Show()   
end


--[[----------------------------------------------------------------------------
StaticPopups
------------------------------------------------------------------------------]]
StaticPopupDialogs['BULKMAIL_ADD_DESTINATION'] = {
   text = L["BulkMail - New AutoSend Destination"],
   button1 = L["Accept"], button2 = L["Cancel"],
   hasEditBox = 1, maxLetters = 20,
   OnAccept = function(self)
		 BulkMail:AddDestination(_G[self:GetName().."EditBox"]:GetText())
		 BulkMail:RefreshEditQTip()
	      end,
   OnShow = function(self)
	       _G[self:GetName().."EditBox"]:SetFocus()
	    end,
   OnHide = function(self)
	       local activeWindow = ChatEdit_GetActiveWindow(); 
	       if ( activeWindow ) then
		  activeWindow:Insert(_G[self:GetName().."EditBox"]:SetText('')); 
	       end 
	    end,
   EditBoxOnEnterPressed = function(self)
			      BulkMail:AddDestination(_G[self:GetName()]:GetText())
			      BulkMail:RefreshEditQTip()
			      rulesAltered = true
			      self:GetParent():Hide()
			   end,
   EditBoxOnEscapePressed = function(self)
			       self:GetParent():Hide()
			    end,
   timeout = 0, exclusive = 1, whileDead = 1, hideOnEscape = 1,
}

StaticPopupDialogs['BULKMAIL_REMOVE_DESTINATION'] = {
   text = L["BulkMail - Confirm removal of destination"],
   button1 = L["Accept"], button2 = L["Cancel"],
   OnAccept = function(self)
		 BulkMail:RemoveDestination(confirmedDestToRemove)
		 BulkMail:RefreshEditQTip()
		 confirmedDestToRemove = nil
		 rulesAltered = true
	      end,
   OnHide = function(self)
	       confirmedDestToRemove = nil
	    end,
   timeout = 0, exclusive = 1, hideOnEscape = 1,
}
