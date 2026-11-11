BulkMail = LibStub("AceAddon-3.0"):NewAddon("BulkMail", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")

local mod, self, BulkMail = BulkMail, BulkMail, BulkMail

local VERSION =  " @project-version@"
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
local MagicUtil = LibStub("LibMagicUtil-1.0")

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
local ClickSendMailItemButton = ClickSendMailItemButton

local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemSubClassInfo = GetItemSubClassInfo or (C_Item and C_Item.GetItemSubClassInfo)
local IsEquippableItem = IsEquippableItem or (C_Item and C_Item.IsEquippableItem)
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
local GetItemClassInfo = GetItemClassInfo or (C_Item and C_Item.GetItemClassInfo)
local GetNumAddOns = GetNumAddOns  or C_AddOns.GetNumAddOns
local LoadAddOn = LoadAddOn or C_AddOns.LoadAddOn

-- Is this rule destination the character currently being played?
-- UnitName('player') returns only the first word of a two-part character name on
-- WoW: Forever, so a rule for "Firstname Surname" is compared against
-- "Firstname", the guard passes, and mail is queued to the sender. GetUnitName
-- returns the full name there; it is feature-detected for older clients.
local function isCurrentCharacter(dest)
    if type(dest) ~= 'string' or dest == '' then return false end
    local want = dest:lower()
    local me = UnitName('player')
    if type(me) == 'string' and me ~= '' and want == me:lower() then return true end
    if GetUnitName then
        local full = GetUnitName('player')
        if type(full) == 'string' and full ~= '' and want == full:lower() then return true end
    end
    return false
end

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
local cacheLock, sendDest, numItems, rulesAltered  -- variables

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

-- utility method to get item id.
local function linkToId(itemLink)
    return type(item) == 'number' and item or tonumber(strmatch(itemLink, "|H[^:]+:(%d+)"))
end


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
            if rsubtype and rulesCache[dest][rtype] then
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
    local itemID = linkToId(item)
    if not itemID then return end
    for _, xID in ipairs(globalExclude.items) do if itemID == xID then return end end
    for _, xset in ipairs(globalExclude.pt31Sets) do
        if pt:ItemInSet(itemID, xset) == true then return end
    end

    local quality = select(3, GetItemInfo(itemID))
    local  equippable = IsEquippableItem(itemID)

    if quality and ((equippable and quality < self.db.char.minItemLevel)
            or (not equippable and quality < self.db.char.minItemLevelMisc)) then
        return nil
    end
    local itype, isubtype = select(6, GetItemInfo(itemID)) -- old string based lookup
    local iclass, isubclass = select(12, GetItemInfo(itemID)) -- new class id based lookup

    if C_PetJournal and not iclass then
        local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, isTradeable, isUnique, obtainable, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        if name then
            iclass, isubclass = speciesID, creatureID
            itype, isubtype = petType, name
            print(iclass, isubclass, itype, isubtype)
        end
    end
    if not itype or not iclass then
        return nil
    end
    for dest, rules in pairs(rulesCache) do
        local canddest
        if not isCurrentCharacter(dest) and (rules[itemID] or
                (itype and rules[itype] and rules[itype][isubtype]) or
                (iclass and rules[iclass] and rules[iclass][isubclass])) then
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



-- Slots the user explicitly removed from the queue this mail session, keyed
-- [bag][slot] = itemID. Rebuilds from autosend rules skip these so removed
-- items don't immediately reappear.
local userExcluded = {}

local function isUserExcluded(bag, slot, itemLink)
    local id = userExcluded[bag] and userExcluded[bag][slot]
    return id ~= nil and id == linkToId(itemLink)
end

local function setUserExcluded(bag, slot, excluded)
    if excluded then
        local itemLink = GetContainerItemLink(bag, slot)
        if itemLink then
            userExcluded[bag] = userExcluded[bag] or {}
            userExcluded[bag][slot] = linkToId(itemLink)
        end
    elseif userExcluded[bag] then
        userExcluded[bag][slot] = nil
    end
end

-- Add a container slot to BulkMail's send queue.
sendCache = {}
local function sendCacheAdd(bag, slot, squelch)
    -- convert to (bag, slot, squelch) if called as (frame, squelch)
    if type(slot) ~= 'number' then
        bag, slot, squelch = bag:GetParent():GetID(), bag:GetID(), slot
    end
    local didAdd = false
    setUserExcluded(bag, slot, false)
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
    local itemId = linkToId(itemLink)
    local shouldRemove =  sendCache and sendCache[bag] and sendCache[bag][slot]
    mod:Print(fmt(L["Attempting to %s all %s."], shouldRemove and L["remove"] or L["add"], itemLink))
    for addlBag, addlSlot, item in bagIter() do
        if linkToId(item) == itemId then
            if shouldRemove then
                setUserExcluded(addlBag, addlSlot, true)
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
        setUserExcluded(bag, slot, true)
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

-- Clear button: remove everything and keep autosend from re-adding it.
local function sendCacheClearByUser()
    for bag, slots in pairs(sendCache) do
        for slot in pairs(slots) do
            setUserExcluded(bag, slot, true)
        end
    end
    sendCacheCleanup()
end

-- Populate BulkMail's send queue with container slots holding items following
-- the autosend rules for the current destination (or any destinations
-- if the destination field is blank).
local function sendCacheBuild(dest)
    if not cacheLock then
        sendCacheCleanup(true)
        local destLower = dest and dest:lower()
        -- Check destCache case-insensitively
        local destHasRules = false
        if dest ~= '' then
            for d in pairs(destCache) do
                if d:lower() == destLower then
                    destHasRules = true
                    break
                end
            end
        end
        if BulkMail.db.char.isSink or dest ~= '' and not destHasRules then
            -- no need to check for an item in the autosend list if this character is a sink or if the destination string doesn't have any rules set
            mod:RefreshSendQueueGUI()
            return
        end

        for bag, slot, item in bagIter() do
            local target = rulesCacheDest(item)
            if target then
                if (dest == '' or target:lower() == destLower) and not isUserExcluded(bag, slot, item) then
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
    if not BulkMail2DB then
        return
    end
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
        realm = {
            -- shared by both factions when shareMode == "merged" (retail only)
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
        global = {
            characters = {},         -- normalized name -> "Name-Realm", every character seen
        },
        profile = {
            ownCharactersOnly = true,
            confirmOtherRecipients = true,
            sizeMode = "free",
            freePosition = false,
            savedPos = nil,
        },
    }, "Default")
    self.db.char.minItemLevel= self.db.char.minItemLevel or 1
    self.db.char.minItemLevelMisc = self.db.char.minItemLevelMisc or 1
    destCache = new()  -- destinations for which we have rules (or are going to add rules)
    reverseDestCache = new()  -- integer-indexed table of destinations
    self:SelectRuleStore()  -- sets autoSendRules: per faction, or shared per realm on retail
    self:CheckFactionSharing()

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
                (LE_ITEM_CLASS_GEM or Enum.ItemClass.Gem), true,
                (LE_ITEM_CLASS_GLYPH or Enum.ItemClass.Glyph), true,
                (LE_ITEM_CLASS_ITEM_ENHANCEMENT or Enum.ItemClass.ItemEnhancement), true,
                (LE_ITEM_CLASS_WOW_TOKEN or Enum.ItemClass.WoWToken), true,
                (LE_ITEM_CLASS_BATTLEPET or Enum.ItemClass.Battlepet), true,
                (LE_ITEM_CLASS_QUESTITEM or Enum.ItemClass.Questitem), true, -- can't send quest items
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
                dialogControl = mod.RECIPIENT_WIDGET,
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
                        func = function() mod:OpenRulesEditor() end,
                        order = 30,
                    },
                    shareFactions = {
                        name = L["Share rules between factions"], type = 'toggle',
                        width = "full",
                        desc = L["Share one set of AutoSend rules between your Alliance and Horde characters on this realm."],
                        hidden = function() return not mod:IsCrossFactionMailSupported() end,
                        get = function() return self.db.realm.shareMode == "merged" end,
                        set = function(_, v)
                            if v then mod:OpenShareWizard() else mod:StopSharingRules() end
                        end,
                        confirm = function(_, v)
                            if not v then
                                return L["Stop sharing rules? Each faction keeps its own copy of the current rules."]
                            end
                            return false
                        end,
                        order = 35,
                    },
                    mergeFactions = {
                        name = L["Merge factions"], type = 'execute',
                        desc = L["Share one set of AutoSend rules between your Alliance and Horde characters on this realm."],
                        hidden = function()
                            return not mod:IsCrossFactionMailSupported() or self.db.realm.shareMode == "merged"
                        end,
                        func = function() mod:OpenShareWizard() end,
                        order = 36,
                    },
                    clear = {
                        name = L["Clear Realm rules"], type = 'execute',
                        desc = L["Clear all rules for this realm."],
                        func = function()
                            for i in pairs(autoSendRules) do
                                autoSendRules[i] = nil
                            end
                            wipe(destCache)
                            wipe(reverseDestCache)
                            rulesAltered = true
                            mod:RefreshRulesEditor() end,
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
                order = 4000,
            },
            attachmulti = {
                name = L["Attach multiple items"], type = 'toggle',
                desc = L["Attach as many items as possible per mail."],
                get = function() return self.db.char.attachMulti end,
                set = function(args, v) self.db.char.attachMulti = v end,
                order = 4100,
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
            ownCharactersOnly = {
                name = L["My characters only"], type = 'toggle',
                desc = L["Limit name suggestions in the mail To: field to your own characters and AutoSend destinations."],
                get = function() return self.db.profile.ownCharactersOnly end,
                set = function(_, v) mod:SetOwnCharactersOnly(v) end,
                order = 4200,
            },
            confirmOtherRecipients = {
                name = L["Confirm other players"], type = 'toggle',
                desc = L["Ask before sending mail to a character that is not yours or an AutoSend destination."],
                get = function() return self.db.profile.confirmOtherRecipients end,
                set = function(_, v) self.db.profile.confirmOtherRecipients = v end,
                order = 4300,
            },
            sizeMode = {
                name = L["Window Size"],
                type = 'select',
                desc = L["How the window height is determined. Match sets height to mail frame. Max limits height to mail frame. Free sizes to content."],
                values = {
                    free = L["Free"],
                    match = L["Match Mail Frame"],
                    max = L["Max Mail Frame"],
                },
                get = function() return self.db.profile.sizeMode end,
                set = function(_, v) self.db.profile.sizeMode = v mod:RefreshSendQueueGUI() end,
                disabled = function() return self.db.profile.freePosition end,
                order = 2500,
            },
            freePosition = {
                name = L["Free Position"],
                type = 'toggle',
                desc = L["Disable automatic anchoring to the mail frame. The window will remember its position when dragged."],
                get = function() return self.db.profile.freePosition end,
                set = function(_, v)
                    self.db.profile.freePosition = v
                    if not v then
                        self.db.profile.savedPos = nil
                    end
                    mod:RefreshSendQueueGUI()
                end,
                order = 3000,
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
                            mod:ToggleRulesEditor()
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
    self:RecordCharacter()
    if self:IsShareDecisionPending() then
        self:Print(L["Your Alliance and Horde characters on this realm have separate AutoSend rules. Open the rules editor to merge them or keep them separate."])
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
    -- Allow TSM frame detection to re-scan (TSM may create its frame lazily)
    MagicUtil:ResetTSMFrameCache()
    self:UpdateMailAutoComplete()
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
        self:RawHookScript(SendMailMailButton, 'OnClick', 'SendMailMailButton_OnClick')
        self:RawHookScript(MailFrameTab1, 'OnClick', 'MailFrameTab1_OnClick')
        self:RawHookScript(MailFrameTab2, 'OnClick', 'MailFrameTab2_OnClick')
        self:RawHookScript(SendMailNameEditBox, 'OnTextChanged', 'SendMailNameEditBox_OnTextChanged')
        self:RawHookScript(SendMailNameEditBox, 'OnTabPressed', 'SendMailNameEditBox_OnTabPressed')
        self:RegisterEvent('MAIL_SEND_SUCCESS')
        self:RegisterEvent('SECURE_TRANSFER_CANCEL')
        self:RegisterEvent('MAIL_FAILED')

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
    -- Watch for mail frame changes (e.g. TSM toggling between its UI and the default)
    mod._lastMailFrame = nil
    if not mod._mailFrameWatcher then
        mod._mailFrameWatcher = self:ScheduleRepeatingTimer("CheckMailFrameChanged", 0.2)
    end
end

function mod:CheckMailFrameChanged()
    local mailFrame, isTSM = MagicUtil:GetMailFrame()
    if mailFrame ~= mod._lastMailFrame then
        mod._lastMailFrame = mailFrame
        if isTSM then
            -- TSM active: always show the send queue alongside inbox
            rulesCacheBuild()
            sendCacheBuild(SendMailNameEditBox:GetText())
            self:ShowSendQueueGUI()
        else
            -- Switching to normal UI: show send queue only if on Send tab
            if SendMailFrame and SendMailFrame:IsShown() then
                self:ShowSendQueueGUI()
            elseif mod.sendQueueTooltip then
                self:HideSendQueueGUI()
            end
        end
    end
end

function mod:MAIL_CLOSED()
    if mailIsVisible then
        mailIsVisible = nil
        if mod._mailFrameWatcher then
            self:CancelTimer(mod._mailFrameWatcher)
            mod._mailFrameWatcher = nil
        end
        mod._lastMailFrame = nil
        self:UnhookAll()
        sendCacheCleanup()
        wipe(userExcluded)
        self:HideSendQueueGUI()
        self:StopBulkSend()
    end
end

BulkMail.PLAYER_ENTERING_WORLD = BulkMail.MAIL_CLOSED  -- MAIL_CLOSED doesn't get called if, for example, the player accepts a port with the mail window open

function mod:MAIL_SEND_SUCCESS()
    if self._sendingBulk then
        self:RefreshSendQueueGUI()
        -- Small delay to let WoW process the sent mail before loading the next one
        self:ScheduleTimer("Send", 0.1, self._sendCOD)
    end
end

function mod:SECURE_TRANSFER_CANCEL()
    if self._sendingBulk then
        self:StopBulkSend()
        SendMailNameEditBox:SetText('')
        sendDest = ''
        sendCacheCleanup()
        self:Print(L["Send cancelled."])
    end
end

function mod:MAIL_FAILED()
    if self._sendingBulk then
        self:StopBulkSend()
        SendMailNameEditBox:SetText('')
        sendDest = ''
        sendCacheCleanup()
    end
end

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
    -- Commit recipient bar if it has uncommitted text
    if mod._recipientBar and mod._recipientBar.editBox then
        local barText = mod._recipientBar.editBox:GetText()
        if barText and barText ~= "" then
            mod._updatingRecipient = true
            SendMailNameEditBox:SetText(barText)
            mod._updatingRecipient = nil
        end
    end
    sendDest = SendMailNameEditBox:GetText()
    self._sendCOD = SendMailCODButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney)
    if GetSendMailItem(1) or sendCache and next(sendCache) then
        organizeSendCache()
        self._sendingBulk = true
        self:Send(self._sendCOD)
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
        local dest = SendMailNameEditBox:GetText()
        if dest ~= '' and not self:CheckRecipient(dest, function()
                    _G.this = SendMailMailButton
                    self.hooks[frame].OnClick(frame, a1)
                end, function() cacheLock = false end) then
            return
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

function mod:SendMailNameEditBox_OnTabPressed(frame, ...)
    local list = AutoCompleteBox
    if list and list:IsShown() and list.parent == frame and not IsShiftKeyDown() then
        self:AutoCompleteTab(frame)
        return
    end
    self.hooks[frame].OnTabPressed(frame, ...)
end

function mod:SendMailNameEditBox_OnTextChanged(frame, a1)
    sendDest = cacheLock and sendDest or SendMailNameEditBox:GetText()
    sendCacheBuild(SendMailNameEditBox:GetText())
    -- Sync recipient bar if it wasn't the source of the change
    if not mod._updatingRecipient and mod._recipientBar and mod._recipientBar.editBox and mod._recipientBar.editBox:GetText() ~= SendMailNameEditBox:GetText() then
        mod._updatingRecipient = true
        mod._recipientBar.editBox:SetText(SendMailNameEditBox:GetText())
        mod._updatingRecipient = nil
    end
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
    if GetSendMailItem(1) then
        SendMailNameEditBox:SetText((sendDest ~= '' and sendDest or rulesCacheDest(GetSendMailItemLink(1)) or self.db.char.defaultDestination) or '')
        if SendMailNameEditBox:GetText() ~= '' then
            if not self:CheckRecipient(SendMailNameEditBox:GetText(), function() self:Send(cod) end, function() self:StopBulkSend() end) then
                return
            end
            if #suffix > 10 then suffix = SUFFIX_CHAR else suffix = suffix..SUFFIX_CHAR end
            _G.this = SendMailMailButton
            return self.hooks[SendMailMailButton].OnClick(SendMailMailButton)
        elseif not self.db.char.defaultDestination then
            self:Print(L["No default destination set."])
            self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
            self:StopBulkSend()
            return
        end
        return
    end
    if destSendCache and next(destSendCache) then
        local dest, bagslots = next(destSendCache)
        if not self:CheckRecipient(dest, function() self:Send(cod) end, function() self:StopBulkSend() end) then
            return
        end
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
        -- Items are now in the mail slots; set destination and trigger the actual send
        sendDest = dest
        SendMailNameEditBox:SetText(dest)
        if #suffix > 10 then suffix = SUFFIX_CHAR else suffix = suffix..SUFFIX_CHAR end
        _G.this = SendMailMailButton
        return self.hooks[SendMailMailButton].OnClick(SendMailMailButton)
    else
        SendMailNameEditBox:SetText('')
        sendDest = ''
        self._sendingBulk = false
        return sendCacheCleanup()
    end
end

function mod:StopBulkSend()
    cacheLock = false
    self._sendingBulk = false
    self._sendCOD = nil
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
                local function send()
                    _G.this = SendMailMailButton
                    return self.hooks[SendMailMailButton].OnClick(SendMailMailButton)
                end
                if not self:CheckRecipient(SendMailNameEditBox:GetText(), send) then return end
                return send()
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
Recipients: autocomplete limited to your own characters, and a confirmation
before mailing anyone else.
------------------------------------------------------------------------------]]
local function setupRecipients()
    local strlower = string.lower
    local tsort = table.sort
    local Flags = Enum and Enum.AutoCompleteEntryFlag
    local ACCOUNT_CHARACTER = Flags and Flags.AccountCharacter or 0x80
    local PRIORITY_ACCOUNT = Enum and Enum.AutoCompletePriority and Enum.AutoCompletePriority.AccountCharacter or 5
    local autoCompleteResults = (C_AutoComplete and C_AutoComplete.GetAutoCompleteResults) or GetAutoCompleteResults
    local approvedThisSession = {}
    local blizzardSource  -- SendMailNameEditBox's own autocomplete, while we override it

    local function currentRealm()
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        if not realm or realm == "" then
            realm = (GetRealmName() or ""):gsub("[%s%-]", "")
        end
        return realm
    end

    -- "Name" or "Name-Realm" -> "name-realm" (realm without spaces or dashes)
    local function normalize(name)
        name = strmatch(name or "", "^%s*(.-)%s*$")
        if name == "" then return nil end
        local char, realm = strmatch(name, "^(.-)%-(.+)$")
        if not char or char == "" then
            char, realm = name, currentRealm()
        end
        realm = realm:gsub("[%s%-]", "")
        return strlower(char .. "-" .. realm)
    end

    -- Remembers every character that logs in with BulkMail enabled.
    function mod:RecordCharacter()
        local name = (GetUnitName and GetUnitName("player")) or UnitName("player")
        local key = normalize(name)
        if key then
            self.db.global.characters[key] = name .. "-" .. currentRealm()
        end
    end

    local function isOwnCharacter(dest)
        local key = normalize(dest)
        if not key then return false end
        if mod.db.global.characters[key] then return true end
        if autoCompleteResults then
            local cursor = strlenutf8 and strlenutf8(dest) or #dest
            local ok, results = pcall(autoCompleteResults, dest, 10, cursor, true, ACCOUNT_CHARACTER, 0)
            if ok and type(results) == "table" then
                for _, r in ipairs(results) do
                    if r.name and normalize(r.name) == key then return true end
                end
            end
        end
        return false
    end

    local function isTrusted(dest)
        local key = normalize(dest)
        if not key then return true end
        if approvedThisSession[key] then return true end
        for d in pairs(destCache) do
            if normalize(d) == key then return true end
        end
        local default = mod.db.char.defaultDestination
        if default and normalize(default) == key then return true end
        return isOwnCharacter(dest)
    end

    local function notifyOptions()
        local registry = LibStub("AceConfigRegistry-3.0", true)
        if registry then registry:NotifyChange(L["Bulk Mail"] .. VERSION) end
    end

    -- Returns true when mail to dest may go out right away. Otherwise asks,
    -- and calls proceed() or cancel() once the user has answered.
    function mod:CheckRecipient(dest, proceed, cancel)
        if not self.db.profile.confirmOtherRecipients or isTrusted(dest) then return true end
        MagicUtil:ShowConfirmDialog({
            text = fmt(L["%s is not one of your characters. Send the mail anyway?"], dest),
            acceptText = L["Send"],
            checkboxText = L["Don't ask again"],
            onAccept = function(dontAsk)
                approvedThisSession[normalize(dest)] = true
                if dontAsk then
                    mod.db.profile.confirmOtherRecipients = false
                    notifyOptions()
                    mod:Print(L["You won't be asked again. Turn on Confirm other players in the options to undo this."])
                end
                proceed()
            end,
            onCancel = cancel,
        })
        return false
    end

    -- Autocomplete source: the game's results, plus characters BulkMail has
    -- seen and AutoSend destinations that start with the typed text.
    local function recipientSource(text, numResults, cursorPosition, allowFullMatch, include, exclude)
        local results
        if autoCompleteResults then
            results = autoCompleteResults(text, numResults, cursorPosition, allowFullMatch, include, exclude)
        end
        results = type(results) == "table" and results or {}
        local prefix = strlower(text or "")
        if prefix == "" then return results end

        local have = {}
        for _, r in ipairs(results) do
            if r.name then have[normalize(r.name) or ""] = true end
        end
        local function add(display)
            if #results >= numResults then return end
            local key = normalize(display)
            if key and not have[key] and strlower(display):sub(1, #prefix) == prefix then
                have[key] = true
                results[#results + 1] = { name = display, priority = PRIORITY_ACCOUNT }
            end
        end

        local realm = strlower(currentRealm())
        local names = {}
        for _, full in pairs(mod.db.global.characters) do
            local char, r = strmatch(full, "^(.-)%-(.+)$")
            names[#names + 1] = (char and strlower(r) == realm) and char or full
        end
        tsort(names)
        for _, n in ipairs(names) do add(n) end

        local dests = {}
        for d in pairs(destCache) do dests[#dests + 1] = d end
        tsort(dests)
        for _, d in ipairs(dests) do add(d) end
        return results
    end

    function mod:ApplyRecipientAutoComplete(box)
        if not box or not AutoCompleteEditBox_SetAutoCompleteSource then return end
        local include, exclude
        if self.db.profile.ownCharactersOnly then
            include, exclude = ACCOUNT_CHARACTER, 0
        elseif AUTOCOMPLETE_LIST and AUTOCOMPLETE_LIST.MAIL then
            include, exclude = AUTOCOMPLETE_LIST.MAIL.include, AUTOCOMPLETE_LIST.MAIL.exclude
        else
            return
        end
        AutoCompleteEditBox_SetAutoCompleteSource(box, recipientSource, include, exclude)
    end

    function mod:SetOwnCharactersOnly(value)
        self.db.profile.ownCharactersOnly = value and true or false
        self:UpdateMailAutoComplete()
        notifyOptions()
    end

    -- Blizzard's Tab only moves the highlight through the suggestions and
    -- Enter takes it. Tab takes the highlighted name here; Shift-Tab and the
    -- arrow keys still move through the list. Returns true when handled.
    function mod:AutoCompleteTab(box)
        local list = AutoCompleteBox
        if list and list:IsShown() and list.parent == box and not IsShiftKeyDown()
            and AutoCompleteEditBox_OnEnterPressed then
            return AutoCompleteEditBox_OnEnterPressed(box)
        end
        return AutoCompleteEditBox_OnTabPressed and AutoCompleteEditBox_OnTabPressed(box)
    end

    -- Blizzard's To: field is only touched while the option is on, so other
    -- mail addons keep their own suggestions otherwise.
    function mod:UpdateMailAutoComplete()
        local box = SendMailNameEditBox
        if box then
            if self.db.profile.ownCharactersOnly then
                if not blizzardSource then
                    blizzardSource = { source = box.autoCompleteSource, params = box.autoCompleteParams }
                end
                self:ApplyRecipientAutoComplete(box)
            elseif blizzardSource then
                box.autoCompleteSource, box.autoCompleteParams = blizzardSource.source, blizzardSource.params
                blizzardSource = nil
            end
        end
        if self._recipientBar then
            self:ApplyRecipientAutoComplete(self._recipientBar.editBox)
            if self._recipientBar.ownOnly then
                self._recipientBar.ownOnly:SetChecked(self.db.profile.ownCharactersOnly)
            end
        end
        if self._destInput then self:ApplyRecipientAutoComplete(self._destInput) end
    end

    -- An AceGUI edit box with name completion, for name fields in the
    -- options (dialogControl = RECIPIENT_WIDGET). It wraps AceGUI's own
    -- EditBox and adds the autocomplete handlers on top of its scripts.
    local AceGUI = LibStub("AceGUI-3.0", true)
    if AceGUI and AutoCompleteEditBox_SetAutoCompleteSource then
        local widgetType = "BulkMail-RecipientEditBox"
        mod.RECIPIENT_WIDGET = widgetType
        AceGUI:RegisterWidgetType(widgetType, function()
            local widget = AceGUI:Create("EditBox")
            widget.type = widgetType
            local box = widget.editbox
            box.addHighlightedText = true
            box.autoCompleteContext = "mail"

            local onEnter = box:GetScript("OnEnterPressed")
            box:SetScript("OnEnterPressed", function(self, ...)
                if AutoCompleteEditBox_OnEnterPressed(self) then return end
                if onEnter then onEnter(self, ...) end
            end)
            local onEscape = box:GetScript("OnEscapePressed")
            box:SetScript("OnEscapePressed", function(self, ...)
                if AutoCompleteEditBox_OnEscapePressed(self) then return end
                if onEscape then onEscape(self, ...) end
            end)
            box:SetScript("OnTabPressed", function(self) mod:AutoCompleteTab(self) end)
            box:SetScript("OnArrowPressed", AutoCompleteEditBox_OnArrowPressed)
            box:HookScript("OnTextChanged", AutoCompleteEditBox_OnTextChanged)
            box:HookScript("OnChar", AutoCompleteEditBox_OnChar)
            box:HookScript("OnKeyDown", AutoCompleteEditBox_OnKeyDown)
            box:HookScript("OnKeyUp", AutoCompleteEditBox_OnKeyUp)
            box:HookScript("OnEditFocusGained", function(self) mod:ApplyRecipientAutoComplete(self) end)
            box:HookScript("OnEditFocusLost", AutoCompleteEditBox_OnEditFocusLost)
            return widget
        end, 1)
    end
end
setupRecipients()

local function _addIndentedCell(tooltip, text, indentation, func, arg)
    local y, x = tooltip:AddLine()
    tooltip:SetCell(y, x, text, tooltip:GetFont(), "LEFT", 1, nil, indentation)
    if func then
        tooltip:SetLineScript(y, "OnMouseUp", func, arg)
    end
    return y, x
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

--[[----------------------------------------------------------------------------
AutoSend Rules Editor
------------------------------------------------------------------------------]]
-- Wrapped in a function so its locals don't count against the main chunk's
-- 200 local variable limit.
local function setupRulesEditor()
    local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
    local GetItemIcon = GetItemIcon or (C_Item and C_Item.GetItemIconByID)
    local strfind, strlower = string.find, string.lower
    local tsort = table.sort

    local ICON_TYPE    = [[Interface\Icons\INV_Misc_Bag_07]]
    local ICON_SET     = [[Interface\Icons\INV_Misc_Book_09]]
    local ICON_UNKNOWN = [[Interface\Icons\INV_Misc_QuestionMark]]
    local TAG_ITEM = { 0.6, 0.8, 1 }
    local TAG_TYPE = { 0.98, 0.87, 0.66 }
    local TAG_SET  = { 0.78, 0.78, 1 }

    local WIDTH, HEIGHT = 940, 500

    local GLOBAL = {}  -- sentinel for the global exclude list (never collides with a name)
    local editor
    local selectedDest             -- destination name or GLOBAL
    local selectedTab = "include"  -- "include" or "exclude"
    local pickerMode = "bags"      -- "bags", "types" or "sets"
    local typeClass                -- item class being browsed in the type picker
    local setPath                  -- set group being browsed in the set picker ("A.B")
    local searchFilter             -- lowercased search text, or nil
    local sortedSets, sortedSetsLower

    ---------------------------------------------------------------------------
    -- Rule data helpers
    ---------------------------------------------------------------------------
    local function currentRuleset()
        if selectedDest == GLOBAL then
            return globalExclude
        elseif selectedDest and destCache[selectedDest] then
            return autoSendRules[selectedDest][selectedTab]
        end
    end

    local function findItem(rs, id)
        for i, v in ipairs(rs.items) do
            if tonumber(v) == id then return i end
        end
    end

    local function findSet(rs, set)
        for i, v in ipairs(rs.pt31Sets) do
            if v == set then return i end
        end
    end

    local function findType(rs, itype, isubtype)
        isubtype = isubtype or nil  -- old rules store "whole class" as subtype = false
        for i, v in ipairs(rs.itemTypes) do
            if v.type == itype and (v.subtype or nil) == isubtype then return i end
        end
    end

    local function commit()
        rulesAltered = true
        mod:RefreshRulesEditor()
    end

    local function addItem(id)
        local rs = currentRuleset()
        if rs and id and not findItem(rs, id) then
            tinsert(rs.items, id)
            commit()
        end
    end

    local function toggleItem(id)
        local rs = currentRuleset()
        if not rs then return end
        local idx = findItem(rs, id)
        if idx then tremove(rs.items, idx) else tinsert(rs.items, id) end
        commit()
    end

    local function toggleSet(set)
        local rs = currentRuleset()
        if not rs then return end
        local idx = findSet(rs, set)
        if idx then tremove(rs.pt31Sets, idx) else tinsert(rs.pt31Sets, set) end
        commit()
    end

    local function toggleType(itype, isubtype)
        local rs = currentRuleset()
        if not rs then return end
        local idx = findType(rs, itype, isubtype)
        if idx then
            tremove(rs.itemTypes, idx)
        else
            tinsert(rs.itemTypes, { type = itype, subtype = isubtype or nil })
        end
        commit()
    end

    local function removeRule(kind, value)
        local rs = currentRuleset()
        if not rs then return end
        local idx
        if kind == "items" then
            idx = findItem(rs, value)
        elseif kind == "pt31Sets" then
            idx = findSet(rs, value)
        else
            idx = findType(rs, value.type, value.subtype)
        end
        if idx then
            tremove(rs[kind], idx)
            commit()
        end
    end

    local function addItemsFromText(text)
        local rs = currentRuleset()
        if not rs or not text then return end
        local ids = {}
        for id in text:gmatch("item:(%d+)") do ids[#ids + 1] = id end
        -- strip links so their extra numbers aren't read as IDs, then take plain numbers
        text = text:gsub("|H.-|h.-|h", " "):gsub("item:[%d:%-]*", " ")
        for id in text:gmatch("%d+") do ids[#ids + 1] = id end
        local changed
        for _, id in ipairs(ids) do
            id = tonumber(id)
            if id and id > 0 and not findItem(rs, id) then
                tinsert(rs.items, id)
                changed = true
            end
        end
        if changed then commit() end
    end

    local function dropCursorItem()
        local kind, id = GetCursorInfo()
        if kind == "item" and id then
            ClearCursor()
            addItem(tonumber(id))
        end
    end

    local function countRules(rs)
        return #rs.items + #rs.pt31Sets + #rs.itemTypes
    end

    ---------------------------------------------------------------------------
    -- Display helpers
    ---------------------------------------------------------------------------
    local function qualityText(name, quality)
        local qc = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if qc and qc.hex then
            return qc.hex .. name .. "|r"
        end
        return name
    end

    local function itemDisplay(id)
        local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(id)
        icon = icon or (GetItemIcon and GetItemIcon(id)) or ICON_UNKNOWN
        if name then
            return qualityText(name, quality), icon, name
        end
        return color("item:" .. id, "808080"), icon
    end

    local function className(itype)
        return GetItemClassInfo(itype) or tostring(itype)
    end

    local function subclassName(itype, isubtype)
        return GetItemSubClassInfo(itype, isubtype) or tostring(isubtype)
    end

    local function typeRuleText(itype, isubtype)
        if isubtype then
            return className(itype) .. " - " .. subclassName(itype, isubtype)
        end
        return fmt(L["All %s"], className(itype))
    end

    local function matches(text)
        return not searchFilter or strfind(strlower(text), searchFilter, 1, true) ~= nil
    end

    local function byText(a, b)
        return a.sortKey < b.sortKey
    end

    ---------------------------------------------------------------------------
    -- Scrolling list widget
    ---------------------------------------------------------------------------
    local function rowOnEnter(row)
        local e = row.entry
        if not e then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if e.itemID then
            GameTooltip:SetHyperlink("item:" .. e.itemID)
        elseif e.tooltip then
            e.tooltip(GameTooltip)
        elseif row.text.IsTruncated and row.text:IsTruncated() then
            GameTooltip:AddLine(row.text:GetText(), 1, 1, 1)
        elseif not e.hint then
            GameTooltip:Hide()
            return
        end
        if e.hint then
            GameTooltip:AddLine(e.hint, 0, 1, 0)
        end
        GameTooltip:Show()
    end

    local function hideTooltip()
        GameTooltip:Hide()
    end

    local function fillRow(row, e)
        row.entry = e
        row.text:SetText(e.text or "")
        if e.icon then
            row.icon:SetTexture(e.icon)
            row.icon:Show()
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        else
            row.icon:Hide()
            row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
        end
        row.tag:SetText(e.tag or "")
        local c = e.tagColor
        if c then
            row.tag:SetTextColor(c[1], c[2], c[3])
        else
            row.tag:SetTextColor(0.6, 0.6, 0.6)
        end
        row.check:SetShown(e.checked and true or false)
        row.remove:SetShown(e.onRemove ~= nil)
        row.selected:SetShown(e.selected and true or false)
        row:Show()
        if GameTooltip:IsOwned(row) then rowOnEnter(row) end
    end

    local listCount = 0
    local function createList(parent, rowHeight, numRows)
        listCount = listCount + 1
        local list = CreateFrame("Frame", nil, parent)
        list:SetHeight(rowHeight * numRows)
        list.items = {}
        list.rows = {}

        local scroll = CreateFrame("ScrollFrame", "BulkMailRulesEditorList" .. listCount, list, "FauxScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -24, 0)
        scroll:SetScript("OnVerticalScroll", function(self, offset)
            FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, function() list:Refresh() end)
        end)
        list.scroll = scroll
        list.scrollBar = _G[scroll:GetName() .. "ScrollBar"]

        list:EnableMouseWheel(true)
        list:SetScript("OnMouseWheel", function(_, delta)
            if scroll:IsShown() then
                list.scrollBar:SetValue(list.scrollBar:GetValue() - delta * rowHeight * 3)
            end
        end)
        list:EnableMouse(true)
        list:SetScript("OnReceiveDrag", function() if list.onDrop then list.onDrop() end end)
        list:SetScript("OnMouseUp", function() if list.onDrop and CursorHasItem() then list.onDrop() end end)

        list.empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        list.empty:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -12)
        list.empty:SetPoint("TOPRIGHT", list, "TOPRIGHT", -8, -12)
        list.empty:SetJustifyH("CENTER")

        for i = 1, numRows do
            local row = CreateFrame("Button", nil, list)
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("RIGHT", list, "RIGHT", -24, 0)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")

            row.selected = row:CreateTexture(nil, "BACKGROUND")
            row.selected:SetAllPoints()
            row.selected:SetTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]])
            row.selected:SetBlendMode("ADD")
            row.selected:SetVertexColor(1, 0.82, 0, 0.7)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(rowHeight - 4, rowHeight - 4)
            row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
            row.remove:SetSize(rowHeight, rowHeight)
            row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.remove:SetScript("OnClick", function()
                local e = row.entry
                if e and e.onRemove then e.onRemove(e) end
            end)
            row.remove:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L["Remove"], 1, 1, 1)
                GameTooltip:Show()
            end)
            row.remove:SetScript("OnLeave", hideTooltip)

            row.check = row:CreateTexture(nil, "OVERLAY")
            row.check:SetTexture([[Interface\Buttons\UI-CheckBox-Check]])
            row.check:SetSize(rowHeight, rowHeight)
            row.check:SetPoint("RIGHT", row, "RIGHT", 0, 0)

            row.tag = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            row.tag:SetPoint("RIGHT", row, "RIGHT", -(rowHeight + 2), 0)
            row.tag:SetJustifyH("RIGHT")

            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.text:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)

            row:SetScript("OnClick", function(self, button)
                if list.onDrop and CursorHasItem() then
                    list.onDrop()
                    return
                end
                local e = self.entry
                if e and e.onClick then e.onClick(e, button) end
            end)
            row:SetScript("OnReceiveDrag", function() if list.onDrop then list.onDrop() end end)
            row:SetScript("OnEnter", rowOnEnter)
            row:SetScript("OnLeave", hideTooltip)
            row:Hide()
            list.rows[i] = row
        end

        -- items: array of entries, or of raw values when decorate(value) builds
        -- the entry (only called for visible rows, which keeps huge lists cheap)
        function list:SetItems(items, decorate, emptyText)
            self.items = items
            self.decorate = decorate
            self.empty:SetText(emptyText or L["None"])
            self:Refresh()
        end

        function list:ResetScroll()
            FauxScrollFrame_SetOffset(scroll, 0)
            self.scrollBar:SetValue(0)
        end

        function list:Refresh()
            if self.refreshing then return end
            self.refreshing = true
            local items = self.items
            local n = #items
            FauxScrollFrame_Update(scroll, n, numRows, rowHeight)
            local offset = FauxScrollFrame_GetOffset(scroll)
            local maxOffset = math.max(0, n - numRows)
            if offset > maxOffset then
                offset = maxOffset
                FauxScrollFrame_SetOffset(scroll, offset)
            end
            for i = 1, numRows do
                local row = self.rows[i]
                local item = items[i + offset]
                if item ~= nil then
                    fillRow(row, self.decorate and self.decorate(item) or item)
                else
                    row.entry = nil
                    row:Hide()
                end
            end
            self.empty:SetShown(n == 0)
            self.refreshing = nil
        end

        return list
    end

    ---------------------------------------------------------------------------
    -- Widget helpers
    ---------------------------------------------------------------------------
    local function createInset(parent)
        local f = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
                edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            f:SetBackdropColor(0, 0, 0, 0.5)
            f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        end
        return f
    end

    local function createButton(parent, text, width, onClick)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end

    local function setActive(button, active)
        if active then
            button:LockHighlight()
            button:SetNormalFontObject("GameFontHighlight")
        else
            button:UnlockHighlight()
            button:SetNormalFontObject("GameFontNormal")
        end
    end

    local function createInput(parent, width, template)
        local box = CreateFrame("EditBox", nil, parent, template or "InputBoxTemplate")
        box:SetSize(width, 20)
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", box.ClearFocus)
        return box
    end

    local function createLabel(parent, text, font)
        local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
        fs:SetText(text or "")
        fs:SetJustifyH("LEFT")
        return fs
    end

    ---------------------------------------------------------------------------
    -- List contents
    ---------------------------------------------------------------------------
    local function selectDest(e)
        if selectedDest ~= e.value then
            selectedDest = e.value
            editor.ruleList:ResetScroll()
        end
        mod:RefreshRulesEditor()
    end

    local function confirmRemoveDest(e)
        StaticPopup_Show("BULKMAIL_REMOVE_DESTINATION", nil, nil, e.value)
    end

    local function refreshDestList()
        local data = {}
        local n = countRules(globalExclude)
        data[1] = {
            text = color(L["Global Exclude"], "ff7f7f"),
            icon = [[Interface\Icons\INV_Misc_Lockbox_1]],
            tag = n > 0 and tostring(n) or nil,
            value = GLOBAL,
            selected = selectedDest == GLOBAL,
            onClick = selectDest,
            tooltip = function(tt)
                tt:AddLine(L["Global Exclude"])
                tt:AddLine(L["Items matching these rules are never auto-sent. Applies to this character only."], 1, 1, 1, true)
            end,
        }
        local default = mod.db.char.defaultDestination
        default = default and strlower(default)
        local dests = {}
        for dest in pairs(destCache) do
            local rules = autoSendRules[dest]
            local inc, exc = countRules(rules.include), countRules(rules.exclude)
            local text = dest
            if default == strlower(dest) then
                text = text .. color(" (" .. L["default"] .. ")", "808080")
            end
            dests[#dests + 1] = {
                text = text,
                sortKey = strlower(dest),
                tag = exc > 0 and fmt("%d/%d", inc, exc) or tostring(inc),
                value = dest,
                selected = selectedDest == dest,
                onClick = selectDest,
                onRemove = confirmRemoveDest,
                tooltip = function(tt)
                    tt:AddLine(dest)
                    tt:AddLine(fmt(L["%d include rules, %d exclude rules"], inc, exc), 1, 1, 1)
                end,
            }
        end
        tsort(dests, byText)
        for _, e in ipairs(dests) do data[#data + 1] = e end
        editor.destList:SetItems(data)
    end

    local function refreshRuleList()
        local rs = currentRuleset()
        local data = {}
        if rs then
            for _, rule in ipairs(rs.itemTypes) do
                data[#data + 1] = {
                    text = typeRuleText(rule.type, rule.subtype),
                    icon = ICON_TYPE, tag = L["Type"], tagColor = TAG_TYPE,
                    onRemove = function() removeRule("itemTypes", rule) end,
                }
            end
            for _, set in ipairs(rs.pt31Sets) do
                data[#data + 1] = {
                    text = set,
                    icon = ICON_SET, tag = L["Set"], tagColor = TAG_SET,
                    onRemove = function() removeRule("pt31Sets", set) end,
                    tooltip = function(tt)
                        tt:AddLine(L["Periodic Table Set"])
                        tt:AddLine(set, 1, 1, 1, true)
                    end,
                }
            end
            for _, id in ipairs(rs.items) do
                id = tonumber(id)
                local text, icon = itemDisplay(id)
                data[#data + 1] = {
                    text = text, icon = icon, itemID = id,
                    tag = L["Item"], tagColor = TAG_ITEM,
                    onRemove = function() removeRule("items", id) end,
                }
            end
        end
        editor.ruleList:SetItems(data, nil, L["No rules yet. Drop an item here or pick rules on the right."])
    end

    local function refreshBagPicker(rs)
        local data, seen = {}, {}
        for bag, slot, link in bagIter() do
            local id = tonumber(strmatch(link, "item:(%d+)"))
            if id and not seen[id] then
                seen[id] = true
                local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(link)
                name = name or strmatch(link, "%[(.-)%]") or tostring(id)
                if matches(name) and isItemMailable(bag, slot) then
                    data[#data + 1] = {
                        text = qualityText(name, quality),
                        sortKey = strlower(name),
                        icon = icon or GetContainerItemInfo(bag, slot),
                        itemID = id,
                        checked = rs and findItem(rs, id) ~= nil,
                        hint = L["Click to add or remove this rule."],
                        onClick = function() toggleItem(id) end,
                    }
                end
            end
        end
        tsort(data, byText)
        editor.picker:SetItems(data, nil, L["No mailable items in your bags."])
    end

    local function typeEntry(rs, itype, isubtype, text)
        return {
            text = text, sortKey = strlower(text), icon = ICON_TYPE,
            checked = rs and findType(rs, itype, isubtype) ~= nil,
            hint = L["Click to add or remove this rule."],
            onClick = function() toggleType(itype, isubtype) end,
        }
    end

    local function refreshTypePicker(rs)
        local data = {}
        if searchFilter then
            -- flat search across classes and subclasses
            for itype, subtypes in pairs(auctionItemClasses) do
                local cname = className(itype)
                local classMatch = matches(cname)
                if classMatch then
                    data[#data + 1] = typeEntry(rs, itype, nil, typeRuleText(itype))
                end
                for _, isubtype in ipairs(subtypes) do
                    local sname = subclassName(itype, isubtype)
                    if classMatch or matches(sname) then
                        data[#data + 1] = typeEntry(rs, itype, isubtype, cname .. " - " .. sname)
                    end
                end
            end
            tsort(data, byText)
        elseif typeClass and auctionItemClasses[typeClass] then
            local subs = {}
            for _, isubtype in ipairs(auctionItemClasses[typeClass]) do
                subs[#subs + 1] = typeEntry(rs, typeClass, isubtype, subclassName(typeClass, isubtype))
            end
            tsort(subs, byText)
            data[1] = {
                text = color("< " .. L["Back"], "ffd200"),
                onClick = function()
                    typeClass = nil
                    editor.picker:ResetScroll()
                    mod:RefreshRulesEditor()
                end,
            }
            data[2] = typeEntry(rs, typeClass, nil, typeRuleText(typeClass))
            for _, e in ipairs(subs) do data[#data + 1] = e end
        else
            for itype, subtypes in pairs(auctionItemClasses) do
                local cname = className(itype)
                local e
                if #subtypes == 0 then
                    e = typeEntry(rs, itype, nil, cname)
                else
                    local count = 0
                    if rs then
                        for _, rule in ipairs(rs.itemTypes) do
                            if rule.type == itype then count = count + 1 end
                        end
                    end
                    e = {
                        text = cname, sortKey = strlower(cname), icon = ICON_TYPE,
                        tag = (count > 0 and (count .. " ") or "") .. ">",
                        onClick = function()
                            typeClass = itype
                            editor.picker:ResetScroll()
                            mod:RefreshRulesEditor()
                        end,
                    }
                end
                data[#data + 1] = e
            end
            tsort(data, byText)
        end
        editor.picker:SetItems(data, nil, L["No matches."])
    end

    -- Periodic Table covers every expansion. On the classic game versions,
    -- sets with none of their items in this client are left out of the
    -- picker. Each set is checked once per session.
    local IS_RETAIL = WOW_PROJECT_ID == nil or WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
    local itemExists = (C_Item and C_Item.DoesItemExistByID)
        or (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local setInGame = {}

    local function isSetInGame(name, depth)
        if IS_RETAIL or not itemExists then return true end
        local known = setInGame[name]
        if known ~= nil then return known end
        local raw = pt.sets[name]
        local found = false
        if raw == false then
            found = false  -- an empty group PT built on request
        elseif type(raw) ~= "string" then
            found = true  -- not loaded yet; keep it
        elseif strsub(raw, 1, 2) == "m," then
            if (depth or 0) > 8 then return true end
            for child in string.gmatch(strsub(raw, 3), "[^,]+") do
                if child ~= name and isSetInGame(child, (depth or 0) + 1) then
                    found = true
                    break
                end
            end
        else
            for id in string.gmatch(raw, "(%-?%d+)[^,]*") do
                id = tonumber(id)
                -- negative ids are spells or enchants, which can't be checked
                if not id or id <= 0 or itemExists(id) then
                    found = true
                    break
                end
            end
        end
        setInGame[name] = found
        return found
    end

    local function getSortedSets()
        if not sortedSets then
            sortedSets, sortedSetsLower = {}, {}
            for name in pairs(pt.sets) do
                if isSetInGame(name) then
                    sortedSets[#sortedSets + 1] = name
                end
            end
            tsort(sortedSets)
            for i, name in ipairs(sortedSets) do
                sortedSetsLower[i] = strlower(name)
            end
        end
        return sortedSets, sortedSetsLower
    end

    local function setEntry(rs, name, text)
        return {
            text = text, sortKey = strlower(text), icon = ICON_SET,
            checked = rs and findSet(rs, name) ~= nil,
            hint = L["Click to add or remove this rule."],
            tooltip = function(tt)
                tt:AddLine(L["Periodic Table Set"])
                tt:AddLine(name, 1, 1, 1, true)
            end,
            onClick = function() toggleSet(name) end,
        }
    end

    local function browseSets(path)
        setPath = path
        editor.picker:ResetScroll()
        mod:RefreshRulesEditor()
    end

    -- Sets are browsed by their dotted names, a level at a time, like the
    -- item types; a search lists matching sets by full name.
    local function refreshSetPicker(rs)
        local names, lower = getSortedSets()
        if searchFilter then
            local data = {}
            for i, name in ipairs(names) do
                if strfind(lower[i], searchFilter, 1, true) then
                    data[#data + 1] = name
                end
            end
            editor.picker:SetItems(data, function(name)
                return setEntry(rs, name, name)
            end, L["No matches."])
            return
        end

        local prefix = setPath and (setPath .. ".") or ""
        local plen = #prefix
        local children, order = {}, {}
        for _, name in ipairs(names) do
            if plen == 0 or strsub(name, 1, plen) == prefix then
                local rest = strsub(name, plen + 1)
                local seg = strmatch(rest, "^([^%.]+)")
                if seg then
                    local child = children[seg]
                    if not child then
                        child = { path = prefix .. seg }
                        children[seg] = child
                        order[#order + 1] = seg
                    end
                    if rest ~= seg then child.group = true end
                end
            end
        end

        local data = {}
        for _, seg in ipairs(order) do
            local child = children[seg]
            if child.group then
                local count = 0
                if rs then
                    local under = child.path .. "."
                    for _, v in ipairs(rs.pt31Sets) do
                        if v == child.path or strsub(v, 1, #under) == under then count = count + 1 end
                    end
                end
                data[#data + 1] = {
                    text = seg, sortKey = strlower(seg), icon = ICON_SET,
                    tag = (count > 0 and (count .. " ") or "") .. ">",
                    tooltip = function(tt) tt:AddLine(child.path) end,
                    onClick = function() browseSets(child.path) end,
                }
            else
                data[#data + 1] = setEntry(rs, child.path, seg)
            end
        end
        tsort(data, byText)

        if setPath then
            local top = {
                {
                    text = color("< " .. L["Back"], "ffd200"),
                    onClick = function() browseSets(strmatch(setPath, "^(.+)%.[^%.]+$")) end,
                },
            }
            if pt.sets[setPath] and isSetInGame(setPath) then
                top[2] = setEntry(rs, setPath, fmt(L["All %s"], strmatch(setPath, "([^%.]+)$")))
            end
            for _, e in ipairs(data) do top[#top + 1] = e end
            data = top
        end
        editor.picker:SetItems(data, nil, L["No matches."])
    end

    local function refreshPicker()
        local rs = currentRuleset()
        if pickerMode == "types" then
            refreshTypePicker(rs)
        elseif pickerMode == "sets" then
            refreshSetPicker(rs)
        else
            refreshBagPicker(rs)
        end
        setActive(editor.modeBags, pickerMode == "bags")
        setActive(editor.modeTypes, pickerMode == "types")
        setActive(editor.modeSets, pickerMode == "sets")
    end

    local function setPickerMode(mode)
        pickerMode = mode
        typeClass = nil
        setPath = nil
        searchFilter = nil
        editor.search:SetText("")
        editor.search:ClearFocus()
        editor.picker:ResetScroll()
        refreshPicker()
    end

    local function setTab(tab)
        selectedTab = tab
        editor.ruleList:ResetScroll()
        mod:RefreshRulesEditor()
    end

    local function refreshAll()
        if selectedDest ~= GLOBAL and not (selectedDest and destCache[selectedDest]) then
            -- pick the first destination alphabetically, or the global list if there are none
            local first
            for dest in pairs(destCache) do
                if not first or strlower(dest) < strlower(first) then first = dest end
            end
            selectedDest = first or GLOBAL
        end

        if selectedDest == GLOBAL then
            editor.destTitle:SetText(L["Global Exclude"])
            editor.tabInclude:Hide()
            editor.tabExclude:Hide()
            editor.globalNote:Show()
        else
            editor.destTitle:SetText(selectedDest)
            editor.tabInclude:Show()
            editor.tabExclude:Show()
            editor.globalNote:Hide()
            local rules = autoSendRules[selectedDest]
            editor.tabInclude:SetText(fmt("%s (%d)", L["Include"], countRules(rules.include)))
            editor.tabExclude:SetText(fmt("%s (%d)", L["Exclude"], countRules(rules.exclude)))
            setActive(editor.tabInclude, selectedTab == "include")
            setActive(editor.tabExclude, selectedTab == "exclude")
        end

        editor.mergeFactions:SetShown(mod:IsCrossFactionMailSupported() and mod.db.realm.shareMode ~= "merged")

        refreshDestList()
        refreshRuleList()
        refreshPicker()
    end

    local function addDestinationFromInput()
        local box = editor.destInput
        local name = strmatch(box:GetText() or "", "^%s*(.-)%s*$")
        if name == "" then return end
        local existing
        for dest in pairs(destCache) do
            if strlower(dest) == strlower(name) then existing = dest break end
        end
        if not existing then
            mod:AddDestination(name)
        end
        selectedDest = existing or name
        selectedTab = "include"
        box:SetText("")
        box:ClearFocus()
        editor.ruleList:ResetScroll()
        mod:RefreshRulesEditor()
    end

    ---------------------------------------------------------------------------
    -- Frame construction
    ---------------------------------------------------------------------------
    local refreshPending
    local function scheduleRefresh()
        if refreshPending then return end
        refreshPending = true
        C_Timer.After(0.25, function()
            refreshPending = nil
            if editor and editor:IsShown() then refreshAll() end
        end)
    end

    local function createEditor()
        local f = MagicUtil:CreateDialogWindow("BulkMailRulesEditorFrame", WIDTH, HEIGHT, {
            title = L["Bulk Mail"] .. " - " .. L["AutoSend Rules"],
            header = true, closeButton = true, strata = "HIGH", opaque = true,
        })
        editor = f

        local top, bottom = -36, 16
        local paneHeight = HEIGHT + top - bottom

        -- Left: destinations
        local left = createInset(f)
        left:SetPoint("TOPLEFT", f, "TOPLEFT", 16, top)
        left:SetSize(200, paneHeight)
        local leftTitle = createLabel(left, L["Destinations"])
        leftTitle:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -10)

        f.mergeFactions = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
        f.mergeFactions:SetSize(96, 18)
        f.mergeFactions:SetPoint("TOPRIGHT", left, "TOPRIGHT", -6, -6)
        f.mergeFactions:SetText(L["Merge factions"])
        f.mergeFactions:SetNormalFontObject("GameFontNormalSmall")
        f.mergeFactions:SetHighlightFontObject("GameFontHighlightSmall")
        f.mergeFactions:SetScript("OnClick", function() mod:OpenShareWizard(true) end)
        f.mergeFactions:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Merge factions"])
            GameTooltip:AddLine(L["Share one set of AutoSend rules between your Alliance and Horde characters on this realm."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        f.mergeFactions:SetScript("OnLeave", hideTooltip)

        f.destList = createList(left, 20, 18)
        f.destList:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -28)
        f.destList:SetPoint("RIGHT", left, "RIGHT", -6, 0)

        local newLabel = createLabel(left, L["New Destination"], "GameFontNormalSmall")
        newLabel:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 10, 34)
        f.destInput = createInput(left, 128, "AutoCompleteEditBoxTemplate,InputBoxTemplate")
        f.destInput:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 16, 10)
        if AutoCompleteEditBox_SetAutoCompleteSource and AUTOCOMPLETE_LIST and AUTOCOMPLETE_LIST.MAIL then
            local box = f.destInput
            mod:ApplyRecipientAutoComplete(box)
            mod._destInput = box
            box.addHighlightedText = true
            box.autoCompleteContext = "mail"
            box:SetScript("OnTextChanged", AutoCompleteEditBox_OnTextChanged)
            box:SetScript("OnTabPressed", function(self) mod:AutoCompleteTab(self) end)
            box:SetScript("OnEditFocusLost", AutoCompleteEditBox_OnEditFocusLost)
            box:SetScript("OnEscapePressed", function(self)
                if not AutoCompleteEditBox_OnEscapePressed(self) then self:ClearFocus() end
            end)
            box:SetScript("OnEnterPressed", function(self)
                if not AutoCompleteEditBox_OnEnterPressed(self) then addDestinationFromInput() end
            end)
        else
            f.destInput:SetScript("OnEnterPressed", addDestinationFromInput)
        end
        local addDest = createButton(left, L["Add"], 46, addDestinationFromInput)
        addDest:SetPoint("LEFT", f.destInput, "RIGHT", 4, 0)

        -- Middle: rules of the selected destination
        local mid = createInset(f)
        mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
        mid:SetSize(300, paneHeight)
        f.destTitle = createLabel(mid, "", "GameFontNormalLarge")
        f.destTitle:SetPoint("TOPLEFT", mid, "TOPLEFT", 10, -10)
        f.destTitle:SetPoint("RIGHT", mid, "RIGHT", -10, 0)
        f.destTitle:SetWordWrap(false)

        f.tabInclude = createButton(mid, L["Include"], 110, function() setTab("include") end)
        f.tabInclude:SetPoint("TOPLEFT", mid, "TOPLEFT", 10, -34)
        f.tabExclude = createButton(mid, L["Exclude"], 110, function() setTab("exclude") end)
        f.tabExclude:SetPoint("LEFT", f.tabInclude, "RIGHT", 4, 0)
        f.globalNote = createLabel(mid, L["Items matching these rules are never auto-sent. Applies to this character only."], "GameFontHighlightSmall")
        f.globalNote:SetPoint("TOPLEFT", mid, "TOPLEFT", 10, -34)
        f.globalNote:SetPoint("RIGHT", mid, "RIGHT", -10, 0)
        f.globalNote:SetHeight(24)

        f.ruleList = createList(mid, 22, 15)
        f.ruleList:SetPoint("TOPLEFT", mid, "TOPLEFT", 6, -62)
        f.ruleList:SetPoint("RIGHT", mid, "RIGHT", -6, 0)
        f.ruleList.onDrop = dropCursorItem

        local drop = CreateFrame("Button", nil, mid, BACKDROP_TEMPLATE)
        drop:SetPoint("BOTTOMLEFT", mid, "BOTTOMLEFT", 8, 8)
        drop:SetPoint("BOTTOMRIGHT", mid, "BOTTOMRIGHT", -8, 8)
        drop:SetHeight(40)
        if drop.SetBackdrop then
            drop:SetBackdrop({
                bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
                edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            drop:SetBackdropColor(0.2, 0.2, 0.2, 0.6)
            drop:SetBackdropBorderColor(1, 0.82, 0, 0.6)
        end
        drop:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
        local dropText = drop:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        dropText:SetPoint("CENTER")
        dropText:SetText(L["Drop an item here to add it"])
        drop:SetScript("OnReceiveDrag", dropCursorItem)
        drop:SetScript("OnClick", dropCursorItem)

        -- Right: add rule picker
        local right = createInset(f)
        right:SetPoint("TOPLEFT", mid, "TOPRIGHT", 8, 0)
        right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, bottom)
        local rightTitle = createLabel(right, L["Add rule"])
        rightTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -10)

        f.modeBags = createButton(right, L["Bags"], 68, function() setPickerMode("bags") end)
        f.modeBags:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -30)
        f.modeTypes = createButton(right, L["Types"], 68, function() setPickerMode("types") end)
        f.modeTypes:SetPoint("LEFT", f.modeBags, "RIGHT", 2, 0)
        f.modeSets = createButton(right, L["Sets"], 68, function() setPickerMode("sets") end)
        f.modeSets:SetPoint("LEFT", f.modeTypes, "RIGHT", 2, 0)

        f.search = createInput(right, 196, "SearchBoxTemplate")
        f.search:SetPoint("TOPLEFT", right, "TOPLEFT", 16, -58)
        f.search:SetPoint("RIGHT", right, "RIGHT", -10, 0)
        f.search:HookScript("OnTextChanged", function(self)
            local text = strmatch(self:GetText() or "", "^%s*(.-)%s*$")
            local filter = text ~= "" and strlower(text) or nil
            if filter ~= searchFilter then
                searchFilter = filter
                f.picker:ResetScroll()
                refreshPicker()
            end
        end)

        f.picker = createList(right, 20, 15)
        f.picker:SetPoint("TOPLEFT", right, "TOPLEFT", 6, -84)
        f.picker:SetPoint("RIGHT", right, "RIGHT", -6, 0)

        local idLabel = createLabel(right, L["ItemID(s)"], "GameFontNormalSmall")
        idLabel:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 10, 34)
        f.idInput = createInput(right, 140)
        f.idInput:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 16, 10)
        local function addIDs()
            addItemsFromText(f.idInput:GetText())
            f.idInput:SetText("")
            f.idInput:ClearFocus()
        end
        f.idInput:SetScript("OnEnterPressed", addIDs)
        local addID = createButton(right, L["Add"], 46, addIDs)
        addID:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -10, 9)
        f.idInput:SetPoint("RIGHT", addID, "LEFT", -6, 0)

        f:SetScript("OnShow", function(self)
            sortedSets, sortedSetsLower = nil, nil  -- pick up LoD PT sets
            self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            self:RegisterEvent("BAG_UPDATE")
        end)
        f:SetScript("OnHide", function(self)
            self:UnregisterAllEvents()
            if f.destInput:HasFocus() then f.destInput:ClearFocus() end
        end)
        f:SetScript("OnEvent", scheduleRefresh)
        f:Hide()
    end

    ---------------------------------------------------------------------------
    -- Cross-faction rule sharing (retail only)
    --
    -- Rules normally live per faction and realm (db.factionrealm). Retail can
    -- mail across factions, so there the rules can instead live in db.realm,
    -- shared by every character on the realm. db.realm.shareMode records the
    -- choice: nil (not decided), "merged" or "separate".
    ---------------------------------------------------------------------------
    local CROSS_FACTION_MAIL = WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
    local FACTION_COLORS = { Alliance = "4a9eff", Horde = "ff4a4a" }
    local FACTIONS = { "Alliance", "Horde" }
    local RULE_KINDS = { "itemTypes", "pt31Sets", "items" }
    local SIDES = { "include", "exclude" }
    local sharePending, shareDeferred
    local wizard, wizardPlan

    local function factionText(faction)
        local name = faction
        if faction == "Alliance" then
            name = FACTION_ALLIANCE or faction
        elseif faction == "Horde" then
            name = FACTION_HORDE or faction
        end
        return color(name, FACTION_COLORS[faction] or "aaaaaa")
    end

    local function ruleKey(kind, v)
        if kind == "items" then
            return "i:" .. tostring(tonumber(v) or v)
        elseif kind == "pt31Sets" then
            return "s:" .. tostring(v)
        end
        return "t:" .. tostring(v.type) .. ":" .. tostring(v.subtype or "*")
    end

    local function copyRule(kind, v)
        if kind == "items" then
            return tonumber(v) or v
        elseif kind == "itemTypes" then
            return { type = v.type, subtype = v.subtype or nil }
        end
        return v
    end

    local function emptyRuleset()
        return { items = {}, pt31Sets = {}, itemTypes = {} }
    end

    local function removeKey(rs, kind, key)
        local list = rs[kind]
        for i = #list, 1, -1 do
            if ruleKey(kind, list[i]) == key then tremove(list, i) end
        end
    end

    local function hasKey(rs, kind, key)
        for _, v in ipairs(rs[kind]) do
            if ruleKey(kind, v) == key then return true end
        end
    end

    -- Raw saved rules may lack empty subtables (AceDB strips defaults), so
    -- every access goes through this.
    local function rawRules(rules, side, kind)
        local rs = type(rules) == "table" and rules[side]
        local list = type(rs) == "table" and rs[kind]
        return type(list) == "table" and list or {}
    end

    local function countDest(rules)
        local n = 0
        for _, side in ipairs(SIDES) do
            for _, kind in ipairs(RULE_KINDS) do
                n = n + #rawRules(rules, side, kind)
            end
        end
        return n
    end

    -- Every faction's rule store on this realm that has any destinations.
    local function factionSources()
        local sources = {}
        local suffix = " - " .. mod.db.keys.realm
        local all = mod.db.sv.factionrealm
        if type(all) == "table" then
            for key, data in pairs(all) do
                if key:sub(-#suffix) == suffix and type(data) == "table" and type(data.autoSendRules) == "table" then
                    local dests, count = 0, 0
                    for _, rules in pairs(data.autoSendRules) do
                        if type(rules) == "table" then
                            dests = dests + 1
                            count = count + countDest(rules)
                        end
                    end
                    if dests > 0 then
                        sources[#sources + 1] = {
                            faction = key:sub(1, -#suffix - 1), key = key,
                            rules = data.autoSendRules, dests = dests, count = count,
                        }
                    end
                end
            end
        end
        tsort(sources, function(a, b) return a.faction < b.faction end)
        return sources
    end

    local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

    local function destNamesSorted(merged)
        local names = {}
        for dest in pairs(merged) do names[#names + 1] = dest end
        tsort(names)
        return names
    end

    local function sortedFactions(set)
        local list = {}
        for f in pairs(set or {}) do list[#list + 1] = f end
        tsort(list)
        return list
    end

    -- true when the two rules don't both come from the same single faction
    local function spansFactions(a, b)
        local n, all = 0, {}
        for f in pairs(a or {}) do if not all[f] then all[f] = true n = n + 1 end end
        for f in pairs(b or {}) do if not all[f] then all[f] = true n = n + 1 end end
        return n > 1
    end

    -- does rule `broad` match everything rule `narrow` matches?
    local function covers(broad, narrow)
        if broad.kind == "items" then return false end
        if narrow.kind == "items" then
            local id = tonumber(narrow.value)
            if not id then return false end
            if broad.kind == "pt31Sets" then
                local ok, inSet = pcall(pt.ItemInSet, pt, id, broad.value)
                return ok and inSet and true or false
            end
            if not GetItemInfoInstant then return false end
            local classID, subclassID = select(6, GetItemInfoInstant(id))
            if classID ~= broad.value.type then return false end
            return broad.value.subtype == nil or broad.value.subtype == subclassID
        elseif narrow.kind == "itemTypes" and broad.kind == "itemTypes" then
            return broad.value.subtype == nil and narrow.value.subtype ~= nil
                    and broad.value.type == narrow.value.type
        end
        return false
    end

    local function overlapConflict(narrow, broad, playerFaction)
        local narrowWins = {
            dest = narrow.dest, factions = sortedFactions(narrow.factions),
            -- broad destination stops matching the narrower thing
            apply = function(m)
                local ex = m[broad.dest].exclude
                if narrow.kind == "items" then
                    if not hasKey(ex, "items", narrow.key) then tinsert(ex.items, tonumber(narrow.value)) end
                elseif not hasKey(ex, "itemTypes", narrow.key) then
                    tinsert(ex.itemTypes, { type = narrow.value.type, subtype = narrow.value.subtype })
                end
            end,
        }
        local broadWins = {
            dest = broad.dest, factions = sortedFactions(broad.factions),
            apply = function(m) removeKey(m[narrow.dest].include, narrow.kind, narrow.key) end,
        }
        local options = { narrowWins, broadWins }
        tsort(options, function(a, b) return a.dest < b.dest end)
        local choice = 1
        for i, opt in ipairs(options) do
            for _, f in ipairs(opt.factions) do
                if f == playerFaction then choice = i end
            end
        end
        return {
            type = "dest", overlap = true, key = narrow.key, kind = narrow.kind, value = narrow.value,
            broadKind = broad.kind, broadValue = broad.value,
            options = options, choice = choice,
        }
    end

    -- Union of all sources, plus the conflicts that only appear because two
    -- factions disagree (overlaps within one faction are left as they were).
    local function buildMergePlan(sources)
        local merged, seen = {}, {}
        local ruleInfo = {}     -- key -> { kind, value }
        local incDests = {}     -- key -> destinations including it, in order
        local factionsBy = {}   -- dest -> side -> key -> { faction = true }

        for _, src in ipairs(sources) do
            for dest, rules in pairs(src.rules) do
                if type(rules) == "table" then
                    local m = merged[dest]
                    if not m then
                        m = { include = emptyRuleset(), exclude = emptyRuleset() }
                        merged[dest] = m
                        seen[dest] = { include = {}, exclude = {} }
                        factionsBy[dest] = { include = {}, exclude = {} }
                    end
                    for _, side in ipairs(SIDES) do
                        for _, kind in ipairs(RULE_KINDS) do
                            for _, v in ipairs(rawRules(rules, side, kind)) do
                                local key = ruleKey(kind, v)
                                if not seen[dest][side][key] then
                                    seen[dest][side][key] = true
                                    tinsert(m[side][kind], copyRule(kind, v))
                                    ruleInfo[key] = ruleInfo[key] or { kind = kind, value = copyRule(kind, v) }
                                    if side == "include" then
                                        incDests[key] = incDests[key] or {}
                                        tinsert(incDests[key], dest)
                                    end
                                end
                                local fset = factionsBy[dest][side]
                                fset[key] = fset[key] or {}
                                fset[key][src.faction] = true
                            end
                        end
                    end
                end
            end
        end

        local playerFaction = UnitFactionGroup("player")
        local conflicts = {}

        -- same rule included for different destinations by different factions
        local keys = {}
        for key, dests in pairs(incDests) do
            if #dests > 1 then keys[#keys + 1] = key end
        end
        tsort(keys)
        for _, key in ipairs(keys) do
            local dests = incDests[key]
            tsort(dests)
            local allFactions, options, choice = {}, {}, nil
            for i, dest in ipairs(dests) do
                local factions = {}
                for f in pairs(factionsBy[dest].include[key]) do
                    factions[#factions + 1] = f
                    allFactions[f] = true
                end
                tsort(factions)
                options[i] = { dest = dest, factions = factions }
                if not choice and factionsBy[dest].include[key][playerFaction] then choice = i end
            end
            local nFactions = 0
            for _ in pairs(allFactions) do nFactions = nFactions + 1 end
            if nFactions > 1 then
                local info = ruleInfo[key]
                for _, opt in ipairs(options) do
                    -- winner keeps the rule, everyone else loses it
                    opt.apply = function(m)
                        for _, o in ipairs(options) do
                            if o.dest ~= opt.dest then removeKey(m[o.dest].include, info.kind, key) end
                        end
                    end
                end
                conflicts[#conflicts + 1] = {
                    type = "dest", key = key, kind = info.kind, value = info.value,
                    options = options, choice = choice or 1,
                }
            end
        end

        -- overlapping rules: a broader rule (whole class, subclass, PT set) for
        -- one destination covers a narrower rule (subclass, item) for another.
        -- Set vs set and set vs type overlaps aren't detected.
        local includes = {}  -- { dest, key, kind, value, factions }
        for _, dest in ipairs(destNamesSorted(merged)) do
            for _, kind in ipairs(RULE_KINDS) do
                for _, v in ipairs(merged[dest].include[kind]) do
                    local key = ruleKey(kind, v)
                    includes[#includes + 1] = { dest = dest, key = key, kind = kind, value = v, factions = factionsBy[dest].include[key] }
                end
            end
        end
        local seenOverlap = {}
        for _, narrow in ipairs(includes) do
            for _, broad in ipairs(includes) do
                if narrow.dest ~= broad.dest and narrow.key ~= broad.key
                        and spansFactions(narrow.factions, broad.factions)
                        and covers(broad, narrow) then
                    local id = narrow.key .. "|" .. narrow.dest .. "|" .. broad.dest
                    if not seenOverlap[id] then
                        seenOverlap[id] = true
                        conflicts[#conflicts + 1] = overlapConflict(narrow, broad, playerFaction)
                    end
                end
            end
        end

        -- one faction includes a rule for a destination that another excludes
        local destNames = {}
        for dest in pairs(merged) do destNames[#destNames + 1] = dest end
        tsort(destNames)
        for _, dest in ipairs(destNames) do
            for _, kind in ipairs(RULE_KINDS) do
                for _, v in ipairs(merged[dest].exclude[kind]) do
                    local key = ruleKey(kind, v)
                    local inc = factionsBy[dest].include[key]
                    local exc = factionsBy[dest].exclude[key]
                    local disagree = false
                    for f in pairs(inc or {}) do
                        if not exc[f] then disagree = true end
                    end
                    if disagree then
                        conflicts[#conflicts + 1] = {
                            type = "side", dest = dest, key = key, kind = kind, value = v,
                            options = { { side = "include" }, { side = "exclude" } },
                            choice = 2,  -- exclusions win today, so keep that by default
                        }
                    end
                end
            end
        end

        return { merged = merged, conflicts = conflicts, sources = sources }
    end

    local function notifyOptions()
        local registry = LibStub("AceConfigRegistry-3.0", true)
        if registry then registry:NotifyChange(L["Bulk Mail"] .. VERSION) end
    end

    function mod:SelectRuleStore()
        if CROSS_FACTION_MAIL and self.db.realm.shareMode == "merged" then
            autoSendRules = self.db.realm.autoSendRules
        else
            autoSendRules = self.db.factionrealm.autoSendRules
        end
        wipe(destCache)
        wipe(reverseDestCache)
        for dest in pairs(autoSendRules) do
            destCache[dest] = true
            tinsert(reverseDestCache, dest)
        end
        rulesAltered = true
    end

    -- Writes the merged rules to the realm store. The per-faction stores are
    -- left untouched as a backup.
    local function applyMergePlan(plan)
        local merged = plan.merged
        for _, c in ipairs(plan.conflicts) do
            if c.type == "dest" then
                c.options[c.choice].apply(merged)
            end
        end
        for _, c in ipairs(plan.conflicts) do
            if c.type == "side" then
                local m = merged[c.dest]
                if c.options[c.choice].side == "exclude" then
                    removeKey(m.include, c.kind, c.key)
                elseif hasKey(m.include, c.kind, c.key) then
                    removeKey(m.exclude, c.kind, c.key)
                end
            end
        end
        local store = mod.db.realm.autoSendRules
        for dest in pairs(store) do store[dest] = nil end
        for dest, m in pairs(merged) do store[dest] = m end
        mod.db.realm.shareMode = "merged"
        sharePending = nil
        mod:SelectRuleStore()
        mod:RefreshRulesEditor()
        notifyOptions()
    end

    -- Called at load: with no rules anywhere there is nothing to decide, so
    -- start out shared. Otherwise the wizard asks (even when only one faction
    -- has rules, since merging makes the other faction start using them).
    function mod:CheckFactionSharing()
        sharePending = nil
        if not CROSS_FACTION_MAIL or self.db.realm.shareMode then return end
        local sources = factionSources()
        if #sources == 0 then
            applyMergePlan(buildMergePlan(sources))
        else
            sharePending = true
        end
    end

    function mod:IsShareDecisionPending()
        return sharePending
    end

    function mod:IsCrossFactionMailSupported()
        return CROSS_FACTION_MAIL
    end

    -- Go back to one rule set per faction; every faction gets a copy of the
    -- shared rules so nobody loses anything.
    function mod:StopSharingRules()
        if self.db.realm.shareMode ~= "merged" then return end
        local shared = self.db.realm.autoSendRules
        local realm = self.db.keys.realm
        local targets = { [self.db.keys.factionrealm] = true }
        for _, faction in ipairs(FACTIONS) do targets[faction .. " - " .. realm] = true end
        for key in pairs(targets) do
            local copy = {}
            for dest, rules in pairs(shared) do
                local c = { include = emptyRuleset(), exclude = emptyRuleset() }
                for _, side in ipairs(SIDES) do
                    for _, kind in ipairs(RULE_KINDS) do
                        for _, v in ipairs(rawRules(rules, side, kind)) do
                            tinsert(c[side][kind], copyRule(kind, v))
                        end
                    end
                end
                copy[dest] = c
            end
            if key == self.db.keys.factionrealm then
                local store = self.db.factionrealm.autoSendRules
                for dest in pairs(store) do store[dest] = nil end
                for dest, c in pairs(copy) do store[dest] = c end
            else
                local all = self.db.sv.factionrealm
                all[key] = type(all[key]) == "table" and all[key] or {}
                all[key].autoSendRules = copy
            end
        end
        for dest in pairs(shared) do shared[dest] = nil end
        self.db.realm.shareMode = "separate"
        sharePending = nil
        self:SelectRuleStore()
        self:RefreshRulesEditor()
        notifyOptions()
    end

    ---------------------------------------------------------------------------
    -- Share wizard
    ---------------------------------------------------------------------------
    local function plainRuleText(kind, value)
        if kind == "items" then
            local text, icon = itemDisplay(tonumber(value))
            return text, icon
        elseif kind == "pt31Sets" then
            return value, ICON_SET
        end
        return typeRuleText(value.type, value.subtype), ICON_TYPE
    end

    local function conflictRuleText(c)
        local text, icon = plainRuleText(c.kind, c.value)
        if c.overlap then
            text = text .. color(" " .. fmt(L["(in %s)"], (plainRuleText(c.broadKind, c.broadValue))), "808080")
        end
        return text, icon
    end

    local function optionLabel(c, opt)
        if c.type == "side" then
            return opt.side == "include" and fmt(L["Send to %s"], c.dest) or fmt(L["Don't send to %s"], c.dest)
        end
        local f = {}
        for i, faction in ipairs(opt.factions) do f[i] = factionText(faction) end
        return opt.dest .. " (" .. tconcat(f, ", ") .. ")"
    end

    local function finishWizard(openEditor)
        wizard.decided = true
        wizard:Hide()
        if openEditor then mod:OpenRulesEditor() end
    end

    local refreshWizard

    local function wizardMerge()
        local nConflicts = #wizardPlan.conflicts
        applyMergePlan(wizardPlan)
        local dests = 0
        for _ in pairs(wizardPlan.merged) do dests = dests + 1 end
        mod:Print(fmt(L["AutoSend rules merged: %d destinations, %d conflicts resolved. All your characters on this realm now share them."], dests, nConflicts))
        finishWizard(wizard.openEditorAfter)
    end

    local function cycleChoice(c, step)
        c.choice = (c.choice - 1 + step) % #c.options + 1
        refreshWizard()
    end

    local function preferDest(e)
        for _, c in ipairs(wizardPlan.conflicts) do
            if c.type == "dest" then
                for i, opt in ipairs(c.options) do
                    if opt.dest == e.value then c.choice = i end
                end
            end
        end
        refreshWizard()
    end

    function refreshWizard()
        local plan = wizardPlan
        local conflicts = plan.conflicts

        -- intro page: what each faction has
        local summary = {}
        for _, src in ipairs(plan.sources) do
            summary[#summary + 1] = {
                text = factionText(src.faction),
                tag = fmt(L["%d destinations, %d rules"], src.dests, src.count),
            }
            local names = {}
            for dest, rules in pairs(src.rules) do
                if type(rules) == "table" then names[#names + 1] = dest end
            end
            tsort(names)
            for _, dest in ipairs(names) do
                summary[#summary + 1] = { text = "    " .. dest, tag = tostring(countDest(src.rules[dest])) }
            end
        end
        wizard.summary:SetItems(summary)
        if #conflicts > 0 then
            wizard.introNote:SetText(fmt(L["%d rules conflict between your factions. You'll choose how to resolve them on the next page."], #conflicts))
            wizard.mergeButton:SetText(L["Next"])
        else
            wizard.introNote:SetText(L["No conflicts found. The rules can be merged as they are."])
            wizard.mergeButton:SetText(L["Merge rules"])
        end

        -- conflict page: destinations to prefer, and each conflicting rule
        local involved, order = {}, {}
        for _, c in ipairs(conflicts) do
            if c.type == "dest" then
                for i, opt in ipairs(c.options) do
                    local d = involved[opt.dest]
                    if not d then
                        d = { total = 0, wins = 0, factions = {} }
                        involved[opt.dest] = d
                        order[#order + 1] = opt.dest
                    end
                    d.total = d.total + 1
                    if c.choice == i then d.wins = d.wins + 1 end
                    for _, f in ipairs(opt.factions) do d.factions[f] = true end
                end
            end
        end
        tsort(order, function(a, b) return strlower(a) < strlower(b) end)
        local destData = {}
        for _, dest in ipairs(order) do
            local d = involved[dest]
            local f = {}
            for faction in pairs(d.factions) do f[#f + 1] = factionText(faction) end
            tsort(f)
            destData[#destData + 1] = {
                text = dest, value = dest,
                tag = fmt("%d/%d", d.wins, d.total),
                selected = d.wins == d.total,
                hint = L["Click to send every conflicting rule to this character."],
                tooltip = function(tt)
                    tt:AddLine(dest)
                    tt:AddLine(tconcat(f, ", "))
                    tt:AddLine(fmt(L["Gets %d of the %d conflicting rules it is set up for."], d.wins, d.total), 1, 1, 1)
                end,
                onClick = preferDest,
            }
        end
        wizard.destList:SetItems(destData, nil, L["None"])

        local ruleData = {}
        for _, c in ipairs(conflicts) do
            local text, icon = conflictRuleText(c)
            local choice = c.options[c.choice]
            local tag
            if c.type == "side" then
                text = text .. color(" - " .. c.dest, "808080")
                tag = choice.side == "include" and color(L["Send"], "40ff40") or color(L["Don't send"], "ff6060")
            else
                tag = color(choice.dest, "40ff40")
            end
            ruleData[#ruleData + 1] = {
                text = text, icon = icon, tag = tag,
                hint = L["Click for the next choice, right-click for the previous one."],
                tooltip = function(tt)
                    tt:AddLine(text)
                    for i, opt in ipairs(c.options) do
                        if i == c.choice then
                            tt:AddLine("> " .. optionLabel(c, opt), 0.25, 1, 0.25)
                        else
                            tt:AddLine("   " .. optionLabel(c, opt), 0.8, 0.8, 0.8)
                        end
                    end
                end,
                onClick = function(_, button) cycleChoice(c, button == "RightButton" and -1 or 1) end,
            }
        end
        wizard.ruleList:SetItems(ruleData)
    end

    local function showWizardPage(page)
        wizard.intro:SetShown(page == "intro")
        wizard.resolve:SetShown(page == "resolve")
        refreshWizard()
    end

    local function createWizard()
        local f = MagicUtil:CreateDialogWindow("BulkMailShareWizardFrame", 600, 460, {
            title = L["Share AutoSend rules between factions"],
            header = true, closeButton = true, strata = "HIGH", opaque = true,
        })
        wizard = f

        -- Page 1: overview
        local intro = CreateFrame("Frame", nil, f)
        intro:SetAllPoints()
        f.intro = intro
        local introText = createLabel(intro, L["On retail you can mail items between your Alliance and Horde characters. BulkMail can use one shared set of AutoSend rules for all your characters on this realm, instead of a separate set per faction."], "GameFontHighlight")
        introText:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -36)
        introText:SetPoint("RIGHT", f, "RIGHT", -24, 0)

        local summaryInset = createInset(intro)
        summaryInset:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -96)
        summaryInset:SetPoint("RIGHT", f, "RIGHT", -24, 0)
        summaryInset:SetHeight(232)
        local summaryTitle = createLabel(summaryInset, L["Current rules"])
        summaryTitle:SetPoint("TOPLEFT", summaryInset, "TOPLEFT", 10, -8)
        f.summary = createList(summaryInset, 20, 10)
        f.summary:SetPoint("TOPLEFT", summaryInset, "TOPLEFT", 6, -26)
        f.summary:SetPoint("RIGHT", summaryInset, "RIGHT", -6, 0)

        f.introNote = createLabel(intro, "", "GameFontNormal")
        f.introNote:SetPoint("TOPLEFT", summaryInset, "BOTTOMLEFT", 0, -10)
        f.introNote:SetPoint("RIGHT", f, "RIGHT", -24, 0)

        local keep = createButton(intro, L["Keep separate"], 130, function()
            mod.db.realm.shareMode = "separate"
            sharePending = nil
            notifyOptions()
            mod:Print(L["AutoSend rules stay separate per faction. Use Merge factions in the rules editor to merge them later."])
            finishWizard(f.openEditorAfter)
        end)
        keep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
        local later = createButton(intro, L["Decide later"], 130, function()
            shareDeferred = true
            finishWizard(f.openEditorAfter)
        end)
        later:SetPoint("LEFT", keep, "RIGHT", 6, 0)
        f.mergeButton = createButton(intro, L["Merge rules"], 150, function()
            if #wizardPlan.conflicts > 0 then
                showWizardPage("resolve")
            else
                wizardMerge()
            end
        end)
        f.mergeButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 20)

        -- Page 2: conflicts
        local resolve = CreateFrame("Frame", nil, f)
        resolve:SetAllPoints()
        f.resolve = resolve
        local resolveText = createLabel(resolve, L["These rules send the same items to different characters, but an item can only go to one of them. Click a rule to change its destination, or click a character on the left to send every conflicting rule there."], "GameFontHighlight")
        resolveText:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -36)
        resolveText:SetPoint("RIGHT", f, "RIGHT", -24, 0)

        local left = createInset(resolve)
        left:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -96)
        left:SetSize(180, 290)
        local leftTitle = createLabel(left, L["Send all to"])
        leftTitle:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -8)
        f.destList = createList(left, 20, 12)
        f.destList:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -26)
        f.destList:SetPoint("RIGHT", left, "RIGHT", -6, 0)

        local right = createInset(resolve)
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
        right:SetPoint("RIGHT", f, "RIGHT", -24, 0)
        right:SetHeight(290)
        local rightTitle = createLabel(right, L["Conflicting rules"])
        rightTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -8)
        f.ruleList = createList(right, 22, 11)
        f.ruleList:SetPoint("TOPLEFT", right, "TOPLEFT", 6, -26)
        f.ruleList:SetPoint("RIGHT", right, "RIGHT", -6, 0)

        local back = createButton(resolve, L["Back"], 130, function() showWizardPage("intro") end)
        back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
        f.resolveMerge = createButton(resolve, L["Merge rules"], 150, wizardMerge)
        f.resolveMerge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 20)

        f:Hide()
        -- set after the initial Hide so creating the frame doesn't count as a
        -- choice. Closing without choosing (X, ESC) asks again next login.
        f:SetScript("OnHide", function()
            f:UnregisterAllEvents()
            if not f.decided then shareDeferred = true end
        end)
        f:SetScript("OnShow", function() f:RegisterEvent("GET_ITEM_INFO_RECEIVED") end)
        local pending
        f:SetScript("OnEvent", function()
            if pending then return end
            pending = true
            C_Timer.After(0.25, function()
                pending = nil
                if f:IsShown() and wizardPlan then refreshWizard() end
            end)
        end)
    end

    -- Offer to merge this realm's per-faction rules. With no rules anywhere
    -- there is nothing to decide, so it merges right away.
    function mod:OpenShareWizard(openEditorAfter)
        if not CROSS_FACTION_MAIL or self.db.realm.shareMode == "merged" then
            if openEditorAfter then self:OpenRulesEditor() end
            return
        end
        local sources = factionSources()
        if #sources == 0 then
            applyMergePlan(buildMergePlan(sources))
            self:Print(L["AutoSend rules are now shared by all your characters on this realm."])
            if openEditorAfter then self:OpenRulesEditor() end
            return
        end
        wizardPlan = buildMergePlan(sources)
        if not wizard then createWizard() end
        wizard.decided = nil
        wizard.openEditorAfter = openEditorAfter
        wizard:Show()
        wizard:Raise()
        showWizardPage("intro")
    end

    function mod:RefreshRulesEditor()
        if rulesAltered and mailIsVisible then
            sendCacheCleanup(true)
            rulesCacheBuild()
            sendCacheBuild(SendMailNameEditBox:GetText())
        end
        if editor and editor:IsShown() then
            refreshAll()
        end
    end

    function mod:OpenRulesEditor()
        if sharePending and not shareDeferred then
            mod:OpenShareWizard(true)
            return
        end
        if not editor then createEditor() end
        editor:Show()
        editor:Raise()
        refreshAll()
    end

    function mod:ToggleRulesEditor()
        if editor and editor:IsShown() then
            editor:Hide()
        else
            mod:OpenRulesEditor()
        end
    end

    -- old names, in case anything external still calls them
    mod.OpenEditTooltipGUI = mod.OpenRulesEditor
    mod.RefreshEditTooltipGUI = mod.RefreshRulesEditor
end
setupRulesEditor()

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
    if mod._recipientBar then
        mod._recipientBar:Hide()
        mod._recipientBar:SetParent(nil)
    end
end

function mod:RefreshSendQueueGUI()
    if BulkMail.sendQueueTooltip then
        mod:ShowSendQueueGUI()
    end
    updateSendCost()
end

local function _createOrAttachRecipientBar(tooltip)
    local bar = mod._recipientBar
    if not bar then
        local template = (TooltipBackdropTemplateMixin and "TooltipBackdropTemplate") or (BackdropTemplateMixin and "BackdropTemplate")
        bar = CreateFrame("Frame", nil, UIParent, template)
        bar:SetHeight(30)

        if TooltipBackdropTemplateMixin and GameTooltip.layoutType then
            bar.layoutType = GameTooltip.layoutType
            bar.NineSlice:SetCenterColor(GameTooltip.NineSlice:GetCenterColor())
            bar.NineSlice:SetBorderColor(GameTooltip.NineSlice:GetBorderColor())
        elseif bar.SetBackdrop then
            local backdrop = GameTooltip:GetBackdrop()
            bar:SetBackdrop(backdrop)
            if backdrop then
                bar:SetBackdropColor(GameTooltip:GetBackdropColor())
                bar:SetBackdropBorderColor(GameTooltip:GetBackdropBorderColor())
            end
        end

        local label = bar:CreateFontString(nil, nil, "GameFontNormal")
        label:SetTextColor(1, 210/255, 0, 1)
        label:SetText(L["To"]..": ")
        label:SetPoint("LEFT", bar, "LEFT", 8, 0)

        -- Switches the suggestions between your own characters and everyone.
        local ownOnly = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
        ownOnly:SetSize(22, 22)
        local ownLabel = ownOnly.Text or ownOnly.text or ownOnly:CreateFontString(nil, "ARTWORK")
        ownLabel:SetFontObject("GameFontHighlightSmall")
        ownLabel:ClearAllPoints()
        ownLabel:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
        ownLabel:SetText(L["Mine only"])
        ownOnly:SetPoint("RIGHT", ownLabel, "LEFT", 0, 0)
        ownOnly:SetChecked(mod.db.profile.ownCharactersOnly)
        ownOnly:SetScript("OnClick", function(self)
            mod:SetOwnCharactersOnly(self:GetChecked())
        end)
        ownOnly:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Only suggest my characters"])
            GameTooltip:AddLine(L["Limit name suggestions in the mail To: field to your own characters and AutoSend destinations."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        ownOnly:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.ownOnly = ownOnly

        local editBox = CreateFrame("EditBox", "BulkMailRecipientEditBox", bar, "AutoCompleteEditBoxTemplate,InputBoxTemplate")
        editBox:SetHeight(20)
        editBox:SetPoint("LEFT", label, "RIGHT", 5, 0)
        editBox:SetPoint("RIGHT", ownOnly, "LEFT", -4, 0)
        editBox:SetAutoFocus(false)
        mod:ApplyRecipientAutoComplete(editBox)
        editBox.addHighlightedText = true
        editBox.autoCompleteContext = "mail"

        editBox:SetScript("OnTextChanged", function(self, userInput)
            AutoCompleteEditBox_OnTextChanged(self, userInput)
            if mod._updatingRecipient then return end
            mod._updatingRecipient = true
            SendMailNameEditBox:SetText(self:GetText())
            mod._updatingRecipient = nil
            sendDest = self:GetText()
            sendCacheBuild(sendDest)
        end)
        editBox:SetScript("OnTabPressed", function(self)
            mod:AutoCompleteTab(self)
        end)
        editBox:SetScript("OnEditFocusLost", function(self)
            AutoCompleteEditBox_OnEditFocusLost(self)
            mod._updatingRecipient = true
            SendMailNameEditBox:SetText(self:GetText())
            mod._updatingRecipient = nil
        end)
        editBox:SetScript("OnEnterPressed", function(self)
            if not AutoCompleteEditBox_OnEnterPressed(self) then
                mod._updatingRecipient = true
                SendMailNameEditBox:SetText(self:GetText())
                mod._updatingRecipient = nil
                self:ClearFocus()
            end
        end)
        editBox:SetScript("OnEscapePressed", function(self)
            if not AutoCompleteEditBox_OnEscapePressed(self) then
                self:ClearFocus()
            end
        end)

        bar.editBox = editBox
        bar:EnableMouse(true)
        mod._recipientBar = bar
    end

    -- Sync current recipient into the edit box (but don't disturb active typing)
    if not bar.editBox:HasFocus() then
        local currentDest = sendDest or SendMailNameEditBox:GetText() or ""
        mod._updatingRecipient = true
        bar.editBox:SetText(currentDest)
        mod._updatingRecipient = nil
    end

    bar:ClearAllPoints()
    bar:SetParent(tooltip)
    bar:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, 4)
    bar:SetPoint("TOPRIGHT", tooltip, "BOTTOMRIGHT", 0, 4)
    bar:Show()
end

function mod:ShowSendQueueGUI()
    local tooltip = BulkMail.sendQueueTooltip
    if not tooltip then
        tooltip = QTIP:Acquire("BulkMail3SendQueueTooltip")
        tooltip.OnRelease = function() BulkMail.sendQueueTooltip = nil end
        tooltip:EnableMouse(true)
        tooltip:SetScript("OnDragStart", tooltip.StartMoving)
        tooltip:SetScript("OnDragStop", function()
            tooltip:StopMovingOrSizing()
            if mod.db.profile.freePosition then
                local point, _, relPoint, x, y = tooltip:GetPoint()
                mod.db.profile.savedPos = { point = point, relPoint = relPoint, x = x, y = y }
            end
        end)
        tooltip:RegisterForDrag("LeftButton")
        tooltip:SetMovable(true)
        tooltip:SetColumnLayout(2, "LEFT", "RIGHT")
        self.sendQueueTooltip = tooltip
    else
        tooltip:Clear()
    end
    -- Position the send queue
    if mod.db.profile.freePosition and mod.db.profile.savedPos then
        local saved = mod.db.profile.savedPos
        tooltip:ClearAllPoints()
        tooltip:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        -- Always re-anchor to the current mail frame (may change when TSM toggles)
        -- When TSM is active and inbox is showing, anchor to the right of the inbox
        local mailFrame, isTSM = MagicUtil:GetMailFrame()
        tooltip:ClearAllPoints()
        local inboxGUI = BulkMailInbox and BulkMailInbox.inboxGUI
        local inboxToolbar = BulkMailInbox and BulkMailInbox._toolbar
        if isTSM and inboxGUI and inboxGUI:IsShown() then
            local anchor = inboxToolbar and inboxToolbar:IsShown() and inboxToolbar or inboxGUI
            tooltip:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 5, 0)
        elseif isTSM then
            tooltip:SetPoint("TOPLEFT", mailFrame, "TOPRIGHT", 5, 0)
        else
            tooltip:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 5, 0)
        end
    end

    local y = tooltip:AddHeader();
    tooltip:SetCell(y, 1, L["Item Send Queue"], tooltip:GetFont(), "CENTER", 2)

    tooltip:AddLine(" ")
    if sendCache and next(sendCache) then
        local itemLink, itemText, texture, qty, info
        for bag, slots in pairs(sendCache) do
            for slot in pairs(slots) do
                itemLink = GetContainerItemLink(bag, slot)
                if itemLink then
                    if C_Container then
                        info = C_Container.GetContainerItemInfo(bag, slot)
                        itemText = info.itemName
                        texture = info.iconFileID
                        qty = info.stackCount
                    else
                        if itemLink then
                            itemText = GetItemInfo(itemLink)
                            texture, qty = GetContainerItemInfo(bag, slot)
                        end
                    end
                    if qty and qty > 1 then
                        itemText = fmt("|T%s:18|t |cffffd200%s (%d)|r", texture, itemText, qty)
                    elseif itemText then
                        itemText = fmt("|T%s:18|t |cffffd200%s|r", texture, itemText)
                    else
                        itemText = itemLink -- shouldn't happen
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
        _addIndentedCell(tooltip, color(L["Clear"], "ffd200"), 5, sendCacheClearByUser)
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
    tooltip:SetClampedToScreen(true)
    _createOrAttachRecipientBar(tooltip)
    tooltip:Show()
    -- UpdateScrolling needs valid bounds, so call after Show()
    if tooltip:GetTop() then
        local sizeMode = not mod.db.profile.freePosition and mod.db.profile.sizeMode or "free"
        local mailFrameH
        if sizeMode == "match" or sizeMode == "max" then
            local mailFrame = MagicUtil:GetMailFrame()
            if mailFrame and mailFrame:GetHeight() and mailFrame:GetHeight() > 0 then
                mailFrameH = mailFrame:GetHeight() / tooltip:GetScale()
            end
        end

        if mailFrameH and (sizeMode == "match" or sizeMode == "max") then
            tooltip:UpdateScrolling(mailFrameH)
        else
            tooltip:UpdateScrolling(UIParent:GetHeight() / tooltip:GetScale() * 0.8)
        end

        if sizeMode == "match" and mailFrameH then
            tooltip:SetHeight(mailFrameH)
        end
    end
end


--[[----------------------------------------------------------------------------
StaticPopups
------------------------------------------------------------------------------]]
StaticPopupDialogs['BULKMAIL_REMOVE_DESTINATION'] = {
    text = L["BulkMail - Confirm removal of destination"],
    button1 = L["Accept"], button2 = L["Cancel"],
    OnAccept = function(self)
        if self.data then
            mod:RemoveDestination(self.data)
            rulesAltered = true
            mod:RefreshRulesEditor()
        end
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
