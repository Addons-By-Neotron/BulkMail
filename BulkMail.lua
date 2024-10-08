BulkMail = LibStub("AceAddon-3.0"):NewAddon("BulkMail", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")

local mod, self, BulkMail = BulkMail, BulkMail, BulkMail

local VERSION = " v7.0.0"
local LibStub = LibStub

local L        = LibStub("AceLocale-3.0"):GetLocale("BulkMail", false)
local pt       = LibStub("LibPeriodicTable-3.1")
local abacus   = LibStub("LibAbacus-3.0")
local gratuity = LibStub("LibGratuity-3.0")
local QTIP     = LibStub("LibQTip-1.0")
local LD       = LibStub("LibDropdown-1.0")
local AC       = LibStub("AceConfig-3.0")
local ACD      = LibStub("AceConfigDialog-3.0")
local ACONS    = LibStub("AceConsole-3.0")
local DB       = LibStub("AceDB-3.0")
local LDB      = LibStub("LibDataBroker-1.1", true)

BulkMail.L = L

local SUFFIX_CHAR = "\32"
function CompatGetAuctionItemSubClasses(i)
    return {GetAuctionItemSubClasses(i)}
end

local _G = _G
local strmatch = string.match
local strsub = string.sub
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local fmt = string.format
local ChatFrame1EditBox = ChatFrame1EditBox
local ClickSendMailItemButton = ClickSendMailItemButton

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
local SendMailCODButton =  SendMailCODButton
local ChatEdit_GetActiveWindow = ChatEdit_GetActiveWindow
local CursorHasItem = CursorHasItem
local SetItemRef = SetItemRef
local ATTACHMENTS_MAX_SEND = ATTACHMENTS_MAX_SEND
local DressUpItemLink = DressUpItemLink
local GetAddOnInfo = GetAddOnInfo or C_AddOns.GetAddOnInfo
local GetAddOnMetadata = GetAddOnMetadata or C_AddOns.GetAddOnMetadata
local GetAuctionItemSubClasses = (C_AuctionHouse and C_AuctionHouse.GetAuctionItemSubClasses) or CompatGetAuctionItemSubClasses
local GetNumAddOns = GetNumAddOns  or C_AddOns.GetNumAddOns
local LoadAddOn = LoadAddOn or C_AddOns.LoadAddOn
local NUM_CONTAINER_FRAMES = NUM_CONTAINER_FRAMES
local MailFrame = MailFrame
local MailFrameTab1 = MailFrameTab1
local MailFrameTab2 = MailFrameTab2
local MoneyInputFrame_SetCopper = MoneyInputFrame_SetCopper
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
local tonumber = tonumber
local tostring = tostring
local type = type
local unpack = unpack
local NUM_LE_ITEM_CLASSES = _G.NUM_LE_ITEM_CLASSES or _G.NUM_LE_ITEM_CLASSS or 19
local auctionItemClasses, sendCache, destCache, reverseDestCache, destSendCache, rulesCache, autoSendRules, globalExclude -- tables
local cacheLock, sendDest, numItems, rulesAltered, confirmedDestToRemove  -- variables

local GetContainerItemInfo = GetContainerItemInfo
local GetContainerItemLink = GetContainerItemLink
local GetContainerNumSlots = GetContainerNumSlots
local PickupContainerItem = PickupContainerItem

-- Dragonlands changes.
if not GetContainerNumSlots then
    -- Reagent bag is bag #5
    NUM_BAG_SLOTS = NUM_BAG_SLOTS + 1

    GetContainerNumSlots = C_Container.GetContainerNumSlots
    GetContainerItemLink = C_Container.GetContainerItemLink
    GetContainerItemInfo = function(bag, slot)
        local item = C_Container.GetContainerItemInfo(bag, slot)
        if item == nil then return end
        return item.iconFileID, item.stackCount, item.isLocked, item.quality, item.isReadable, item.hasLoot,
        item.hyperLink, item.isFiltered, item.hasNoValue, item.itemID, item.isBound
    end
    PickupContainerItem = C_Container.PickupContainerItem
end

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
            if rsubtype and rulesCache[dest][rtype] then
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
    if not itemID then return end
    for _, xID in ipairs(globalExclude.items) do if itemID == xID then return end end
    for _, xset in ipairs(globalExclude.pt31Sets) do
        if pt:ItemInSet(itemID, xset) == true then return end
    end

    local quality = select(3, GetItemInfo(itemID))
    local  equippable = IsEquippableItem(itemID)

    if (equippable and quality < self.db.char.minItemLevel)
            or (not equippable and quality < self.db.char.minItemLevelMisc) then
        return nil
    end
    local itype, isubtype = select(6, GetItemInfo(itemID)) -- old string based lookup
    local iclass, isubclass = select(12, GetItemInfo(itemID)) -- new class id based lookup
    for dest, rules in pairs(rulesCache) do
        local canddest
        if string.lower(dest) ~= string.lower(UnitName('player')) and (rules[itemID] or
                (rules[itype] and rules[itype][isubtype]) or
                (rules[iclass] and rules[iclass][isubclass])) then
            canddest = dest
        end
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

-- Returns the frame associated with bag, slot
local function getBagSlotFrame(bag,slot)
    if bag >= 0 and bag < NUM_CONTAINER_FRAMES and slot > 0 then
        local bagslots = GetContainerNumSlots(bag)
        if bagslots >= slot then
            return _G["ContainerFrame" .. (bag + 1) .. "Item" .. (bagslots - slot + 1)]
        end
    end
end

-- Shades or unshades the given bag slot
local function shadeBagSlot(bag,slot,shade)
    local frame = getBagSlotFrame(bag, slot)
    if frame ~= nil then
        SetItemButtonDesaturated(frame, shade)
    end
end

-- Updates the "Postage" field in the Send Mail frame to reflect the total
-- price of all the items that BulkMail will send.
local function updateSendCost()
    if sendCache and next(sendCache) then
        local basePrice = 0
        for slot = 1,8 do
            if GetSendMailItem(slot) ~= nil then
                basePrice = GetSendMailPrice()
                break
            end
        end
        MoneyFrame_Update('SendMailCostMoneyFrame', basePrice + 30 * numItems)
    else
        MoneyFrame_Update('SendMailCostMoneyFrame', GetSendMailPrice())
    end
end

local function findPattern (str, pattern)
	return string.find(str, pattern)
end

local function findExact(str, pattern)
	if (str == pattern) then
		return string.find(str, pattern)
	end
end
local function dumpTable(tbl, indent)
    if not indent then indent = 0 end
    if type(tbl) ~= 'table' then return tostring(tbl) end

    local formatStr = string.rep("  ", indent) -- Create an indentation string
    local endFormatStr = string.rep("  ", indent - 1)
    local result = "{\n"

    for k, v in pairs(tbl) do
        local formattedKey = type(k) == "number" and k or '"' .. k .. '"'
        result = result .. formatStr .. "[" .. formattedKey .. "] = "
        if type(v) == "table" then
            result = result .. dumpTable(v, indent + 1) .. ",\n"
        else
            result = result .. tostring(v) .. ",\n"
        end
    end

    return result .. endFormatStr .. "}"
end

local function simpleFind(tt, exact, text)
    if not tt or not tt.lines then
        return
    end
    local searchFunction = exact and findExact or findPattern
    for _,data in ipairs(tt.lines) do
--        if exact then
--            print(data.leftText, "[", text, "]", searchFunction(data.leftText, text))
--        end
        if data.args then
            for _,field in ipairs(data.args) do
                if field.field == "leftText" then
                    -- print("Matching ", text, "with tooltip line", field.stringVal)
                    if searchFunction(field.stringVal, text) then
                        return true
                    end
                    break
                end
            end
        elseif data.leftText then
            if searchFunction(data.leftText, text) then
                return true
            end
        end
    end
end

local function multiFind(tt, exact, t1, t2, t3, t4, t5, t6)
    local found = simpleFind(tt, exact, t1)
    if not found and t2 then
        return multiFind(tt, exact, t2, t3, t4, t5, t6)
    end
    return found
end

local function isItemMailable(bag, slot)
    if _G.C_TooltipInfo == nil then
        local item = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if item then
            return not C_Item.IsBound(item)
        end
        gratuity:SetBagItem(bag, slot)
        return not gratuity:MultiFind(2, 7, false, false, ITEM_SOULBOUND, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP)
                or gratuity:Find(ITEM_BIND_ON_EQUIP, 2, 7, false, false, true)
    end
    local tt = C_TooltipInfo.GetBagItem(bag, slot)
    return not (multiFind(tt, false, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP)
            or simpleFind(tt, true, ITEM_SOULBOUND))
            or simpleFind(tt, true, ITEM_BIND_ON_EQUIP)

end



-- Add a container slot to BulkMail's send queue.
sendCache = {}
local function sendCacheAdd(bag, slot, squelch)
    -- convert to (bag, slot, squelch) if called as (frame, squelch)
    if type(slot) ~= 'number' then
        bag, slot, squelch = bag:GetParent():GetID(), bag:GetID(), slot
    end
    local didAdd = false
    if GetContainerItemInfo(bag, slot) and not (sendCache[bag] and sendCache[bag][slot]) then
        if isItemMailable(bag, slot) then
            sendCache[bag] = sendCache[bag] or new()
            sendCache[bag][slot] = true;
            numItems = numItems + 1
            shadeBagSlot(bag,slot,true)
            if not squelch then mod:RefreshSendQueueGUI() end
            SendMailFrame_CanSend()
            didAdd = true
        elseif not squelch then
            mod:Print(fmt(L["Item cannot be mailed: %s."], GetContainerItemLink(bag, slot)))
        end
    end
    if not squelch and didAdd then
        updateSendCost()
    end
    return didAdd
end

-- Remove a container slot from BulkMail's send queue.
local function sendCacheRemove(bag, slot, isBulk)
    bag, slot = slot and bag or bag:GetParent():GetID(), slot or bag:GetID()  -- convert to (bag, slot) if called as (frame)
    if sendCache and sendCache[bag] then
        if sendCache[bag][slot] then
            sendCache[bag][slot] = nil
            numItems = numItems - 1
            shadeBagSlot(bag,slot,false)
        end
        if not next(sendCache[bag]) then sendCache[bag] = del(sendCache[bag]) end
    end
    if not isBulk then
        mod:RefreshSendQueueGUI()
        updateSendCost()
        SendMailFrame_CanSend()
    end
end

local function bulkToggleBagItem(bag, slot, itemLink)
    itemLink = itemLink or GetContainerItemLink(bag, slot)

    if not itemLink then return end
    local itemId = tonumber(strmatch(itemLink, "item:(%d+)"))
    local shouldRemove =  sendCache and sendCache[bag] and sendCache[bag][slot]
    mod:Print(fmt(L["Attempting to %s all %s."], shouldRemove and L["remove"] or L["add"], itemLink))
    for addlBag, addlSlot, item in bagIter() do
        if tonumber(strmatch(item, "item:(%d+)")) == itemId then
            if shouldRemove then
                sendCacheRemove(addlBag, addlSlot, true)
            elseif not sendCacheAdd(addlBag, addlSlot, true) then
                mod:Print(fmt(L["Item cannot be mailed: %s."], GetContainerItemLink(addlBag, addlSlot)))
            end
        end
    end
    mod:RefreshSendQueueGUI()
    updateSendCost()
    SendMailFrame_CanSend()
end

-- Toggle a container slot's presence in BulkMail's send queue.
local function sendCacheToggle(bag, slot)
    bag, slot = slot and bag or bag:GetParent():GetID(), slot or bag:GetID()  -- convert to (bag, slot) if called as (frame)
    local result
    if sendCache and sendCache[bag] and sendCache[bag][slot] then
        result = sendCacheRemove(bag, slot)
    else
        result = sendCacheAdd(bag, slot)
    end
    return result
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
                if autoOnly ~= true or rulesCacheDest(item) then
                    sendCacheRemove(bag, slot, true)
                end
            end
        end
    end
    cacheLock = false
    mod:RefreshSendQueueGUI()
    updateSendCost()
    SendMailFrame_CanSend()
end

-- Populate BulkMail's send queue with container slots holding items following
-- the autosend rules for the current destination (or any destinations
-- if the destination field is blank).
local function sendCacheBuild(dest)
    if not cacheLock then
        sendCacheCleanup(true)
        if BulkMail.db.char.isSink or dest ~= '' and not destCache[dest] then
            -- no need to check for an item in the autosend list if this character is a sink or if the destination string doesn't have any rules set
            mod:RefreshSendQueueGUI()
            return
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
    mod:RefreshSendQueueGUI()
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
A little color never hurts
------------------------------------------------------------------------------]]
local function color(text, color)
    return fmt("|cff%s%s|r", color, text)
end


--[[----------------------------------------------------------------------------
Setup
------------------------------------------------------------------------------]]

local function _convertAce2ToAce3Realm(realm)
    -- This could be more elegant but I hate lua patterns so ... whatever :P
    startPos = realm:find(" - Horde", 1, true)
    if startPos then
        return "Horde - ".. realm:sub(1, startPos-1)
    end
    startPos = realm:find(" - Alliance", 1, true)
    return "Alliance - ".. realm:sub(1, startPos-1)
end

local function _convertBulkMail2DB()
    mod:Print("Converting BulkMail 2 configuration...")
    local startPos
    BulkMail3DB = new()
    if BulkMail2DB.realms then
        BulkMail3DB.factionrealm = new()
        for realm, data in pairs(BulkMail2DB.realms) do
            realm = _convertAce2ToAce3Realm(realm)
            BulkMail3DB.factionrealm[realm] = data
        end
    end
    if BulkMail2DB.chars then
        BulkMail3DB.char = new()
        for char, data in pairs(BulkMail2DB.chars) do
            BulkMail3DB.char[char] = data
        end
    end
end

function mod:OnInitialize()
    -- Convert BulkMail2 config to new format
    if not BulkMail3DB then
        _convertBulkMail2DB()
    end
    _convertAce2ToAce3Realm = nil
    _convertBulkMail2DB = nil

    self.db = DB:New("BulkMail3DB", {
        factionrealm = {
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
        },
        char = {
            isSink = false,
            attachMulti = true,
            globalExclude = {
                ['*'] = {}
            },
        },
    }, "Default")
    self.db.char.minItemLevel= self.db.char.minItemLevel or 1
    self.db.char.minItemLevelMisc = self.db.char.minItemLevelMisc or 1
    autoSendRules = self.db.factionrealm.autoSendRules  -- local variable for speed/convenience

    destCache = new()  -- destinations for which we have rules (or are going to add rules)
    reverseDestCache = new()  -- integer-indexed table of destinations
    for dest in pairs(autoSendRules) do
        destCache[dest] = true
        tinsert(reverseDestCache, dest)
    end

    globalExclude = self.db.char.globalExclude  -- local variable for speed/convenience


    local obsoletes
    if GetItemClassInfo(Enum.ItemClass.Battlepet) then
        -- retail
        obsoletes = newHash(
                Enum.ItemClass.Reagent, true,
                Enum.ItemClass.Projectile, true,
                Enum.ItemClass.Quiver, true,
                Enum.ItemClass.Questitem, true, -- can't send quest items
                Enum.ItemClass.Key, true,
                10, true,  -- Money
                14,  true -- Permanent
        )
    else
        -- classic
        obsoletes = newHash(
                LE_ITEM_CLASS_GEM, true,
                LE_ITEM_CLASS_GLYPH, true,
                LE_ITEM_CLASS_ITEM_ENHANCEMENT, true,
                LE_ITEM_CLASS_WOW_TOKEN, true,
                LE_ITEM_CLASS_BATTLEPET, true,
                LE_ITEM_CLASS_QUESTITEM, true, -- can't send quest items
                10, true,  -- Money
                14,  true -- Permanent
        )
    end

    auctionItemClasses = {}  -- local itemType value association table
    for i = 0, NUM_LE_ITEM_CLASSES-1 do
        if not obsoletes[i] then
            auctionItemClasses[i] = GetAuctionItemSubClasses(i)
        end
    end
    numItems = 0
    rulesAltered = true

    local itemQualities = {}
    for k in pairs(Enum.ItemQuality) do
        local v = Enum.ItemQuality[k]
        if v < Enum.ItemQuality.Rare then
            itemQualities[v] = k
        end
    end
    self.opts = {
        type = 'group',
        handler = mod,
        args = {
            defaultdest = {
                name = L["Default destination"], type = 'input',
                desc = L["Set the default recipient of your AutoSend rules"],
                get = function() return self.db.char.defaultDestination end,
                set = function(args, dest) self.db.char.defaultDestination = dest end,
            },
            autosend = {
                name = L["Auto Send Commands"], type = 'group',
                desc = L["AutoSend Options"],
                args = {
                    edit = {
                        name = L["Edit Destinations"], type = 'execute',
                        desc = L["Edit AutoSend definitions."],
                        func = function() mod:OpenEditTooltipGUI() end,
                        order = 30,
                    },
                    clear = {
                        name = L["Clear Realm rules"], type = 'execute',
                        desc = L["Clear all rules for this realm."],
                        func = function()
                            self.db.factionrealm = new()
                            for i in pairs(autoSendRules) do
                                autoSendRules[i] = nil
                            end
                            mod:RefreshEditTooltipGUI() end,
                        confirm = true,
                        order = 40
                    },
                },
            },
            sink = {
                name = L["Sink"], type = 'toggle',
                desc = L["Disable AutoSend queue auto-filling for this character."],
                get = function() return self.db.char.isSink end,
                set = function(args,v) self.db.char.isSink = v end,
            },
            attachmulti = {
                name = L["Attach multiple items"], type = 'toggle',
                desc = L["Attach as many items as possible per mail."],
                get = function() return self.db.char.attachMulti end,
                set = function(args, v) self.db.char.attachMulti = v end,
            },
            attachItemLevelMin = {
                name = L["Min Matched Equipped Quality"], type = 'select',
                desc = L["The minimum quality level matched for automatic destinations for equippable items / gear."],
                values = itemQualities,
                get = function() return self.db.char.minItemLevel  end,
                set = function(args, v) self.db.char.minItemLevel = v end,
            },
            attachItemLevelMinMisc = {
                name = L["Min Matched Quality"], type = 'select',
                desc = L["The minimum quality level matched for automatic destinations."],
                values = itemQualities,
                get = function() return self.db.char.minItemLevelMisc  end,
                set = function(args, v) self.db.char.minItemLevelMisc = v end,
            },
        },
    }

    -- set up LDB
    if LDB then
        self.ldb =
        LDB:NewDataObject("BulkMail",
                {
                    type =  "data source",
                    label = L["Bulk Mail"]..VERSION,
                    icon = [[Interface\Addons\BulkMail2\icon]],
                    tooltiptext = color(L["Bulk Mail"]..VERSION.."\n\n", "ffff00")..color(L["Hint: Click to show the AutoSend Rules editor."].."\n"..
                            L["Middle click to open the config panel."].."\n"..
                            L["Right click to open the config menu."], "ffd200"),
                    OnClick = function(clickedframe, button)
                        if button == "LeftButton" then
                            mod:OpenEditTooltipGUI(clickedframe)
                        elseif button == "MiddleButton" then
                            mod:ToggleConfigDialog()
                        elseif button == "RightButton" then
                            mod:OpenConfigMenu(clickedframe)
                        end
                    end,
                })
    end

    self._mainConfig = self:OptReg(L["Bulk Mail"]..VERSION, self.opts,  { "bm", "bulkmail" })

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

function mod:OnEnable()
    self:RegisterEvent('MAIL_SHOW')
    self:RegisterEvent('MAIL_CLOSED')
    self:RegisterEvent('PLAYER_ENTERING_WORLD')
    if not _G.GetContainerItemInfo then
        self:RegisterEvent('PLAYER_INTERACTION_MANAGER_FRAME_HIDE')
    end
    -- Handle being LoD loaded while at the mailbox
    if MailFrame:IsVisible() then
        self:MAIL_SHOW()
    end
end

function mod:OnDisable()
    self:UnregisterAllEvents()
    self:UnhookAll()
end

--[[----------------------------------------------------------------------------
Events
------------------------------------------------------------------------------]]
local mailIsVisible

function mod:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(_, type)
    if type == Enum.PlayerInteractionType.MailInfo then
        mod:MAIL_CLOSED()
    end
end

function mod:MAIL_SHOW()
    if not mailIsVisible then
        mailIsVisible = true
        if rulesAltered then rulesCacheBuild() end
        if ContainerFrameItemButton_OnModifiedClick then
            self:SecureHook('ContainerFrameItemButton_OnModifiedClick')
            self:SecureHook('ContainerFrame_Update')
        else
            self:SecureHook('HandleModifiedItemClick')
            for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
                self:SecureHook(frame, "Update", 'ContainerFrame_Update')
            end
        end
        self:SecureHook('SendMailFrame_CanSend')
        self:SecureHook('MoneyInputFrame_OnTextChanged', SendMailFrame_CanSend)
        self:SecureHook('SetItemRef')
        self:HookScript(SendMailMailButton, 'OnClick', 'SendMailMailButton_OnClick')
        self:HookScript(MailFrameTab1, 'OnClick', 'MailFrameTab1_OnClick')
        self:HookScript(MailFrameTab2, 'OnClick', 'MailFrameTab2_OnClick')
        self:HookScript(SendMailNameEditBox, 'OnTextChanged', 'SendMailNameEditBox_OnTextChanged')

        SendMailMailButton:Enable()
        
        --[[
        -- This should have its own config option somewhere.
        -- Ideally, this operation should be done without the
        -- mail window opening to the user. The user should
        -- simply hold shift, right click on the mailbox,
        -- and BulkMail mails all items without ever opening
        -- the mail frame to the user. The only thing the user
        -- would see is 'Mail Sent' along with the sound.
        
        -- Note: There should likely be a config option to print
        -- to the chat frame of what items were sent and to where.
        ]]--
        if IsShiftKeyDown() then
            mod:MailFrameTab2_OnClick(MailFrameTab2)
            mod:SendMailMailButton_OnClick(MailFrameTab2)
        end
    end
end

function mod:MAIL_CLOSED()
    if mailIsVisible then
        mailIsVisible = nil
        self:UnhookAll()
        sendCacheCleanup()
        self:HideSendQueueGUI()
        self:CancelTimer(self.BM_SendLoop)
    end
end

BulkMail.PLAYER_ENTERING_WORLD = BulkMail.MAIL_CLOSED  -- MAIL_CLOSED doesn't get called if, for example, the player accepts a port with the mail window open

--[[----------------------------------------------------------------------------
Hooks
------------------------------------------------------------------------------]]
function mod:ContainerFrameItemButton_OnModifiedClick(frame, button)
    mod:HandleItemClick(button, frame:GetParent():GetID(), frame:GetID())
end

function mod:HandleItemClick(button, bag, slot, itemLink)
    local handled = false
    if IsControlKeyDown() and IsShiftKeyDown() then
        self:QuickSend(bag, slot, itemLink)
        handled = true
    elseif IsAltKeyDown() then
        if button == "LeftButton" then
            bulkToggleBagItem(bag, slot, itemLink)
        else
            sendCacheToggle(bag, slot)
        end
        handled = true
    elseif not IsShiftKeyDown() then
        sendCacheRemove(bag, slot)
        handled = true
    end
    return handled
end

function mod:HandleModifiedItemClick(itemLink, itemLocation)
    if itemLocation ~= nil then
        local bag, slot = itemLocation:GetBagAndSlot()
        mod:HandleItemClick(GetMouseButtonClicked(), bag, slot, itemLink)
    end
end


function mod:SendMailFrame_CanSend()
    if sendCache and next(sendCache) or GetSendMailItem(1) or SendMailSendMoneyButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney) > 0 then
        SendMailMailButton:Enable()
        SendMailCODButton:Enable()
    end
end

function mod:ContainerFrame_Update(...)
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
function mod:SetItemRef(link, ...)
    if SendMailNameEditBox:IsVisible() and IsControlKeyDown() then
        if strsub(link, 1, 6) == 'player' then
            local name = strsplit(":", strsub(link, 8))
            if name and strlen(name) > 0 then
                SendMailNameEditBox:SetText(name)
            end
        end
    end
end

function mod:SendMailMailButton_OnClick(frame, a1)
    cacheLock = true
    sendDest = SendMailNameEditBox:GetText()
    local cod = SendMailCODButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney)
    if GetSendMailItem(1) or sendCache and next(sendCache) then
        organizeSendCache()
        self.sendLoopTimer = self:ScheduleRepeatingTimer("Send", 0.1, cod)
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

function mod:MailFrameTab1_OnClick(frame, a1)
    self:HideSendQueueGUI()
    return self.hooks[frame].OnClick(frame, a1)
end

function mod:MailFrameTab2_OnClick(frame, a1)
    rulesCacheBuild()
    sendCacheBuild(SendMailNameEditBox:GetText())
    self:ShowSendQueueGUI()
    self:ScheduleTimer(updateSendCost, 0.01)
    return self.hooks[frame].OnClick(frame, a1)
end

function mod:SendMailNameEditBox_OnTextChanged(frame, a1)
    sendDest = cacheLock and sendDest or SendMailNameEditBox:GetText()
    sendCacheBuild(SendMailNameEditBox:GetText())
    return self.hooks[frame].OnTextChanged(frame, a1)
end

--[[----------------------------------------------------------------------------
Public Functions
------------------------------------------------------------------------------]]
function mod:AddDestination(dest)
    local _ = autoSendRules[dest]  -- trigger the table creation by accessing it
    destCache[dest] = true
    tinsert(reverseDestCache, dest)
    rulesAltered = true
end

function mod:RemoveDestination(dest)
    autoSendRules[dest] = nil
    destCache[dest] = nil
    for i=1, #reverseDestCache do
        if reverseDestCache[i] == dest then
            tremove(reverseDestCache, i)
            rulesAltered = true
            break
        end
    end
end

-- Sends the current item in the SendMailItemButton to the currently-specified
-- destination (or the default if that field is blank), then supplies items and
-- destinations from BulkMail's send queue and sends them.
local suffix = SUFFIX_CHAR  -- for ensuring subject uniqueness to help BMI's "selected item" features
function mod:Send(cod)
    if StaticPopup_Visible('SEND_MONEY') then return end
    if GetSendMailItem(1) then
        SendMailNameEditBox:SetText((sendDest ~= '' and sendDest or rulesCacheDest(GetSendMailItemLink(1)) or self.db.char.defaultDestination) or '')
        if SendMailNameEditBox:GetText() ~= '' then
            if #suffix > 10 then suffix = SUFFIX_CHAR else suffix = suffix..SUFFIX_CHAR end
            _G.this = SendMailMailButton
            return self.hooks[SendMailMailButton].OnClick(SendMailMailButton)
        elseif not self.db.char.defaultDestination then
            self:Print(L["No default destination set."])
            self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
            cacheLock = false
            self:CancelTimer(self.sendLoopTimer, true)
            self.sendLoopTimer = nil
            return
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
        self:CancelTimer(self.sendLoopTimer, true)
        self.sendLoopTimer = nil
        SendMailNameEditBox:SetText('')
        sendDest = ''
        return sendCacheCleanup()
    end
end

-- Send the container slot's item immediately to its autosend destination
-- (or the default destination if no destination specified).
-- This can be done whenever the mailbox is open, and is run when the user
-- Ctrl-Shift-LeftClicks an item in his bag.
function mod:QuickSend(bag, slot)
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
            if type(value) == "table" then
                del(value)
            end
            break
        end
    end
    if not removed then
        tinsert(curRuleSet[ruletype], value)
    end
    rulesAltered = true
    mod:RefreshEditTooltipGUI()
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
            if isItemMailable(bag, slot) then
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
        local iname = GetItemClassInfo(itype)
        if #subtypes == 0 then
            ItemTypesConfigTable.args[itype] = newHash('type', "toggle", 'name', iname)
        else
            local supertype = new()
            ItemTypesConfigTable.args[itype] = newHash(
                    'type', "group",
                    'name', iname,
                    'args', supertype
            )

            for _, isubtype in ipairs(subtypes) do
                local name = GetItemSubClassInfo(itype, isubtype)
                supertype[isubtype] = newHash('type', "toggle", 'name', name)
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
    mod:RefreshEditTooltipGUI()
end

local function _namesForItemRule(rule)
    if type(rule) == "string" then
        return rule.type, rule.subtype
    else
        local subtype
        if rule.subtype ~= nil then
            subtype = GetItemSubClassInfo(rule.type, rule.subtype)
        end
        return GetItemClassInfo(rule.type), subtype
    end
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
                        mod:RefreshEditTooltipGUI()
                        rulesAltered = true
                    end
                end

                if ruletype == 'items' then
                    text = select(2, GetItemInfo(rule))
                    checkIcon = select(10, GetItemInfo(rule))
                elseif ruletype == 'itemTypes' then
                    local name, subtype = _namesForItemRule(rule)
                    if subtype ~= nil then
                        text = fmt("|cfffadfa8Item Type: %s - %s|r", name, subtype)
                    else
                        text = fmt("|cfffadfa8Item Type: %s|r", name)
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

function mod:RefreshEditTooltipGUI()
    if rulesAltered then
        sendCacheCleanup(true)
        rulesCacheBuild()
        sendCacheBuild(SendMailNameEditBox:GetText())
        mod:RefreshSendQueueGUI()
    end
    if BulkMail.editQueueTooltip then
        mod:OpenEditTooltipGUI()
    end
end

function mod:OpenEditTooltipGUI(parentframe)
    local tooltip = BulkMail.editQueueTooltip
    if not tooltip then
        tooltip = QTIP:Acquire("BulkMail3EditQueueTooltip")
        tooltip:EnableMouse(true)
        tooltip:SetScript("OnDragStart", function(this) menuFrame = menuFrame and menuFrame:Release() tooltip.StartMoving(this) end)
        tooltip:SetScript("OnDragStop", tooltip.StopMovingOrSizing)
        tooltip:RegisterForDrag("LeftButton")
        tooltip:SetMovable(true)
        tooltip:SetColumnLayout(1, "LEFT")
        if parentframe then
            tooltip:SetPoint("TOPLEFT", parentframe, "BOTTOMLEFT", 0, 0)
        else
            tooltip:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
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
    tooltip:SetCell(y, 1, color(L["Hint: "]..L["Click Include/Exclude headers to modify a ruleset.  Alt-Click destinations and rules to delete them."], "ffff00"), tooltip:GetFont(), "LEFT", 1, nil, nil, nil, 250)

    tooltip:SetFrameStrata("DIALOG")
    -- set max height to be 90% of the screen height
    tooltip:UpdateScrolling(UIParent:GetHeight() / tooltip:GetScale() * 0.9)
    tooltip:SetClampedToScreen(true)
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
        local itemLink = GetContainerItemLink(bag, slot)
        local editBox = ChatEdit_GetActiveWindow()
        if IsAltKeyDown() then
            sendCacheToggle(bag, slot)
        elseif IsShiftKeyDown() and editBox and editBox:IsVisible() then
            editBox:Insert(itemLink)
        elseif IsControlKeyDown() and not IsShiftKeyDown() then
            DressUpItemLink(itemLink)
        else
            local itemString = string.match(itemLink, "item[%-?%d:]+")
            SetItemRef(itemString, itemLink, arg1)
        end
    end
end

local function onDropClick()
    if GetSendMailItem(1) then
        mod:Print(L["WARNING: Cursor item detection is NOT well-defined when multiple items are 'locked'.   Alt-click is recommended for adding items when there is already an item in the Send Mail item frame."])
    end
    if CursorHasItem() and getLockedContainerItem() then
        sendCacheAdd(getLockedContainerItem())
        PickupContainerItem(getLockedContainerItem())  -- clears the cursor
    end
    mod:RefreshSendQueueGUI()
end

local function onSendClick()
    if sendCache then mod:SendMailMailButton_OnClick() end
end

function mod:HideSendQueueGUI()
    _QTipClose(BulkMail.sendQueueTooltip)
    BulkMail.sendQueueTooltip = nil
end

function mod:RefreshSendQueueGUI()
    if BulkMail.sendQueueTooltip then
        mod:ShowSendQueueGUI()
    end
    updateSendCost()
end

function mod:ShowSendQueueGUI()
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
    tooltip:SetCell(y, 1, L["Item Send Queue"], tooltip:GetFont(), "CENTER", 2)

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
                            recipient = color(recipient, "80ff80")
                        end
                    else
                        recipient = color(sendDest, "00d2ff")
                    end
                    tooltip:SetCell(y, 2, recipient, tooltip:GetFont())
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
    y = tooltip:AddLine(" ")
    y = tooltip:AddLine(L["Alt-Right Click item to add/remove."])
    y = tooltip:AddLine(L["Alt-Left Click item to bulk add/remove."])
    tooltip:SetFrameStrata("FULLSCREEN")
    -- set max height to be 80% of the screen height
    tooltip:UpdateScrolling(UIParent:GetHeight() / tooltip:GetScale() * 0.8)
    tooltip:SetClampedToScreen(true)
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
        mod:AddDestination(_G[self:GetName().."EditBox"]:GetText())
        mod:RefreshEditTooltipGUI()
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
        mod:AddDestination(_G[self:GetName()]:GetText())
        mod:RefreshEditTooltipGUI()
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
        mod:RemoveDestination(confirmedDestToRemove)
        mod:RefreshEditTooltipGUI()
        confirmedDestToRemove = nil
        rulesAltered = true
    end,
    OnHide = function(self)
        confirmedDestToRemove = nil
    end,
    timeout = 0, exclusive = 1, hideOnEscape = 1,
}


-- Convenience function for registering options tables
function mod:OptReg(optname, tbl, cmd)
    local regtable
    local configPanes = self.configPanes or new()
    self.configPanes = configPanes
    AC:RegisterOptionsTable(optname, tbl, cmd)
    regtable = ACD:AddToBlizOptions(optname, L["Bulk Mail"])
    configPanes[#configPanes+1] = optname
    return regtable
end

function mod:OpenConfigMenu(parentframe)
    -- create the menu
    local frame = LD:OpenAce3Menu(mod.opts)

    -- Anchor the menu to the mouse
    frame:SetPoint("TOPLEFT", parentframe, "BOTTOMLEFT", 0, 0)
    frame:SetFrameLevel(parentframe:GetFrameLevel()+100)
end

function mod:ToggleConfigDialog()
    InterfaceOptionsFrame_OpenToCategory(self._mainConfig)
end
