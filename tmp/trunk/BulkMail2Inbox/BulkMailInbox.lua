BulkMailInbox = AceLibrary('AceAddon-2.0'):new('AceDB-2.0', 'AceEvent-2.0', 'AceHook-2.1', 'AceConsole-2.0')
local self, BulkMailInbox = BulkMailInbox, BulkMailInbox
local L = AceLibrary('AceLocale-2.2'):new('BulkMailInbox')
BulkMailInbox.L = L

local tablet = AceLibrary('Tablet-2.0')
local abacus = AceLibrary('Abacus-2.0')

local _G = _G

local sortFields, markTable  -- tables
local ibIndex, ibAttachIndex, inboxItems, inboxCash, cleanPass, cashOnly, markOnly, takeAllInProgress  -- variables

--[[----------------------------------------------------------------------------
  Table Handling
------------------------------------------------------------------------------]]
local newHash, del
do
	local list = setmetatable({}, {__mode='k'})
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
	
	function del(t)
		for k in pairs(t) do
			t[k] = nil
		end
		list[t] = true
		return nil
	end
end

--[[----------------------------------------------------------------------------
  Local Processing
------------------------------------------------------------------------------]]
-- Build a table with info about all items and money in the Inbox
local inboxCache = {}
local function inboxCacheBuild()
	for k in ipairs(inboxCache) do inboxCache[k] = del(inboxCache[k]) end
	inboxCash, inboxItems = 0, 0
	for i = 1, GetInboxNumItems() do
		local _, _, sender, subject, money, cod, daysLeft, numItems, _, wasReturned = GetInboxHeaderInfo(i)
		if money > 0 then
			table.insert(inboxCache, newHash(
				'index', i, 'sender', sender, 'bmid', daysLeft..subject..0, 'returnable', not wasReturned, 'cod', cod,
				'daysLeft', daysLeft, 'itemLink', L["Cash"], 'money', money, 'texture', "Interface\\Icons\\INV_Misc_Coin_01"
			))
			inboxCash = inboxCash + money
		end
		if numItems then
			for j=1, ATTACHMENTS_MAX_SEND do
				if GetInboxItem(i,j) then
					table.insert(inboxCache, newHash(
						'index', i, 'attachment', j, 'sender', sender, 'bmid', daysLeft..subject..j, 'returnable', not wasReturned, 'cod', cod,
						'daysLeft', daysLeft, 'itemLink', GetInboxItemLink(i,j), 'qty', select(3, GetInboxItem(i,j)), 'texture', (select(2, GetInboxItem(i,j)))
					))
					inboxItems = inboxItems + 1
				end
			end
		end
	end
	table.sort(inboxCache, function(a,b)
		local sf = sortFields[BulkMailInbox.db.char.sortField]
		if a and b then
			a, b = a[sf], b[sf]
			a = type(a) == "nil" and 0 or type(a) == "boolean" and tostring(a) or a
			b = type(b) == "nil" and 0 or type(b) == "boolean" and tostring(b) or b
			if sf == "index" then
				if a < b then return true end
			else
				if a > b then return true end
			end
		end
	end)
end

local function takeAll(cash, mark)
	cashOnly = cash
	markOnly = mark
	ibIndex = GetInboxNumItems()
	ibAttachIndex = 0
	takeAllInProgress = true
	lastMoneyIndex = 0
	inboxCacheBuild()
	BulkMailInbox:MAIL_INBOX_UPDATE()
end

--[[----------------------------------------------------------------------------
  Setup
------------------------------------------------------------------------------]]
function BulkMailInbox:OnInitialize()
	self:RegisterDB('BulkMail2InboxDB')
	self:RegisterDefaults('profile', {
		tablet_data = { detached = true, anchor = "TOPLEFT", offsetx = 340, offsety = -104 }
	})
	self:RegisterDefaults('char', {
		altDel = false,
		ctrlRet = true,
		shiftTake = true,
		takeAll = true,
		inboxUI = true,
		sortField = 1,
	})

	sortFields = { 'itemLink', 'qty', 'returnable', 'sender', 'daysLeft', 'index' }
	markTable = {}
	inboxCash = 0
	invFull = false

	self.opts = {
		type = 'group',
		args = {
			altdel = {
				name = L["Alt-click Delete"], type = 'toggle', aliases = L["alt"],
				desc = L["Enable Alt-Click on inbox items to delete the mail in which they are contained."],
				get = function() return self.db.char.altDel end,
				set = function(v) self.db.char.altDel = v end,
			},
			ctrlret = {
				name = L["Ctrl-click Return"], type = 'toggle', aliases = L["ctrl"],
				desc = L["Enable Ctrl-click on inbox items to return the mail in which they are contained."],
				get = function() return self.db.char.ctrlRet end,
				set = function(v) self.db.char.ctrlRet = v end,
			},
			shifttake = {
				name = L["Shift-click Take"], type = 'toggle', aliases = L["shift"],
				desc = L["Enable Shift-click on inbox items to take them."],
				get = function() return self.db.char.shiftTake end,
				set = function(v) self.db.char.shiftTake = v end,
			},
			takeall = {
				name = L["Take All"], type = 'toggle', aliases = L["ta"],
				desc = L["Enable 'Take All' button in inbox."],
				get = function() return self.db.char.takeAll end,
				set = function(v) self.db.char.takeAll = v; self:UpdateTakeAllButton() end,
			},
			gui = {
				name = L["Show Inbox GUI"], type = 'toggle',
				desc = L["Show the Inbox Items GUI"],
				get = function() return self.db.char.inboxUI end,
				set = function(v) self.db.char.inboxUI = v; self:RefreshInboxGUI() end,
			},
		},
	}
	self:RegisterChatCommand({"/bulkmailinbox", "/bmi"}, self.opts) 
end

function BulkMailInbox:OnEnable()
	self:UpdateTakeAllButton()
	self:RegisterEvent('MAIL_SHOW')
	self:RegisterEvent('MAIL_CLOSED')
	self:RegisterEvent('PLAYER_ENTERING_WORLD')
	self:RegisterEvent('UI_ERROR_MESSAGE')
	self:RegisterEvent('MAIL_INBOX_UPDATE')

	-- Handle being LoD loaded while at the mailbox
	if MailFrame:IsVisible() then
		self:MAIL_SHOW()
	end
	self:RegisterInboxGUI()
end

function BulkMailInbox:OnDisable()
	self:UnregisterAllEvents()
	if tablet:IsRegistered('BMI_InboxTablet') then tablet:Unregister('BMI_InboxTablet') end
end

--[[----------------------------------------------------------------------------
  Events
------------------------------------------------------------------------------]]
function BulkMailInbox:MAIL_SHOW()
	ibIndex = GetInboxNumItems()

	self:SecureHook('CheckInbox', 'RefreshInboxGUI')
	self:SecureHook(GameTooltip, 'SetInboxItem')
	self:Hook('InboxFrame_OnClick', nil, true)
	self:SecureHookScript(MailFrameTab1, 'OnClick', 'ShowInboxGUI')
	self:SecureHookScript(MailFrameTab2, 'OnClick', 'HideInboxGUI')

	self:ShowInboxGUI()
end

function BulkMailInbox:MAIL_CLOSED()
	takeAllInProgress = false
	self:HideInboxGUI()
	GameTooltip:Hide()
	self:UnhookAll()
end
BulkMailInbox.PLAYER_ENTERING_WORLD = BulkMailInbox.MAIL_CLOSED  -- MAIL_CLOSED doesn't get called if, for example, the player accepts a port with the mail window open

function BulkMailInbox:UI_ERROR_MESSAGE(msg)  -- prevent infinite loop when inventory is full
	if msg == ERR_INV_FULL then
		invFull = true
	end
end

-- Take next inbox item or money; skip past CoD items and letters.
local prevSubject = ''
function BulkMailInbox:MAIL_INBOX_UPDATE()
	if not takeAllInProgress then return self:ScheduleEvent('BMI_RefreshInboxGUI', self.RefreshInboxGUI, .5, self) end
	local numMails = GetInboxNumItems()
	cashOnly = cashOnly or invFull
	if ibIndex <= 0 then
		if cleanPass or numMails <= 0 then
			takeAllInProgress = false
			invFull = false
			return self:RefreshInboxGUI()
		else
			ibIndex = numMails
			ibAttachIndex = 0
			cleanPass = true
			return self:ScheduleEvent('BMI_takeAll', takeAll, .1, cashOnly, markOnly)
		end
	end
	
	local curIndex, curAttachIndex = ibIndex, ibAttachIndex
	local subject, money, cod, daysLeft = select(4, GetInboxHeaderInfo(curIndex))

	if subject then
		prevSubject = subject
	else
		subject = prevSubject
	end

	if curAttachIndex == ATTACHMENTS_MAX_SEND then
		ibIndex = ibIndex - 1
		ibAttachIndex = 0
	else
		ibAttachIndex = ibAttachIndex + 1
	end

	if curAttachIndex > 0 and not GetInboxItem(curIndex, curAttachIndex) or markOnly and not markTable[daysLeft..subject..curAttachIndex] then
		return self:MAIL_INBOX_UPDATE()
	end

	if curAttachIndex == 0 and money > 0 then
		cleanPass = false
		if GetInboxInvoiceInfo(curIndex) then
			TakeInboxMoney(curIndex)
		else
			TakeInboxMoney(curIndex)
			return self:MAIL_INBOX_UPDATE()
		end
	elseif not cashOnly and cod == 0 then
		cleanPass = false
		if not invFull then
			TakeInboxItem(curIndex, curAttachIndex)
		end
	end
	return self:MAIL_INBOX_UPDATE()
end

--[[----------------------------------------------------------------------------
  Hooks
------------------------------------------------------------------------------]]
function BulkMailInbox:SetInboxItem(tooltip, index, attachment, ...)
	if takeAllInProgress then return end
	local money, _, _, _, _, wasReturned, _, canReply = select(5, GetInboxHeaderInfo(index))
	if self.db.char.shiftTake then tooltip:AddLine(L["Shift - Take Item"]) end
	if wasReturned then 
		if self.db.char.altDel then
			tooltip:AddLine(L["Alt - Delete Containing Mail"])
		end
	elseif canReply and self.db.char.ctrlRet then
		tooltip:AddLine(L["Ctrl - Return Containing Mail"])
	end
end

function BulkMailInbox:InboxFrame_OnClick(index, attachment, ...)
	takeAllInProgress = false
	local _, _, _, _, money, cod, _, hasItem, _, wasReturned, _, canReply = GetInboxHeaderInfo(index)
 	if self.db.char.shiftTake and IsShiftKeyDown() then
		if money > 0 then TakeInboxMoney(index)
		elseif cod > 0 then return
		elseif hasItem then TakeInboxItem(index, attachment) end
	elseif self.db.char.ctrlRet and IsControlKeyDown() and not wasReturned and canReply then ReturnInboxItem(index)
	elseif self.db.char.altDel and IsAltKeyDown() and wasReturned then DeleteInboxItem(index)
	elseif this:GetObjectType() == 'CheckButton' then self.hooks.InboxFrame_OnClick(index, ...) end
	self:ScheduleEvent(self.RefreshInboxGUI, 0.1, self)
end

--[[----------------------------------------------------------------------------
  Inbox GUI
------------------------------------------------------------------------------]]
-- Update/Create the Take All button
function BulkMailInbox:UpdateTakeAllButton()
	if self.db.char.takeAll then
		if _G.BMI_TakeAllButton then return end
		local bmiTakeAllButton = CreateFrame("Button", "BMI_TakeAllButton", InboxFrame, "UIPanelButtonTemplate")
		bmiTakeAllButton:SetWidth(120)
		bmiTakeAllButton:SetHeight(25)
		bmiTakeAllButton:SetPoint("CENTER", InboxFrame, "TOP", -15, -410)
		bmiTakeAllButton:SetText("Take All")
		bmiTakeAllButton:SetScript("OnClick", function() takeAll() end)
	else
		if _G.BMI_TakeAllButton then _G.BMI_TakeAllButton:Hide() end
		_G.BMI_TakeAllButton = nil
	end
end

-- Inbox Items Tablet
local function highlightSameMailItems(index, ...)
	if self.db.char.altDel and IsAltKeyDown() or self.db.char.ctrlRet and IsControlKeyDown() then
		for i = 1, select('#', ...) do
			row = select(i, ...)
			if row.col6 and row.col6:GetText() == index then
				row.highlight:Show()
			end
		end
	end
end

local function unhighlightSameMailItems(index, ...)
	for i = 1, select('#', ...) do
		row = select(i, ...)
		if row.col6 and row.col6:GetText() == index then
			row.highlight:Hide()
		end
	end
end

function BulkMailInbox:RegisterInboxGUI()
	if not self.db.char.inboxUI then return self:HideInboxGUI() end
	if not tablet:IsRegistered('BMI_InboxTablet') then
		tablet:Register('BMI_InboxTablet', 'detachedData', self.db.profile.tablet_data, 'strata', "HIGH", 'maxHeight', 850,
			'cantAttach', true, 'dontHook', true, 'showTitleWhenDetached', true, 'children', function()
				tablet:SetTitle(string.format(L["BulkMailInbox -- Inbox Items (%d mails, %d items, %s)"], GetInboxNumItems(), inboxItems, abacus:FormatMoneyShort(inboxCash)))
				local hlcol = 'text'..self.db.char.sortField
				local cat = tablet:AddCategory('columns', 6,
					'func', function() self.db.char.sortField = sortFields[self.db.char.sortField+1] and self.db.char.sortField+1 or 1 self:RefreshInboxGUI() end,
					'text',  L["Items (Inbox click actions apply)"],
					'text2', L["Qty."],
					'text3', L["Returnable"],
					'text4', L["Sender"],
					'text5', L["TTL"],
					'text6', L["Mail #"],
					hlcol..'R', 1, hlcol..'G', 0.8, hlcol..'B', 0
				)
				if inboxCache and next(inboxCache) then
					for i, info in pairs(inboxCache) do
						cat:AddLine(
							'checked', true, 'hasCheck', true, 'checkIcon', not markTable[info.bmid] and info.texture,
							'func', function()
								if not IsModifierKeyDown() then
									markTable[info.bmid] = not markTable[info.bmid] and true or nil
									self:RefreshInboxGUI()
								else
									self:InboxFrame_OnClick(info.index, info.attachment)
								end
							end,
							'onEnterFunc', function()  -- contributed by bigzero
								GameTooltip:SetOwner(_G.this, 'ANCHOR_RIGHT', 7, -18)
								GameTooltip:SetInboxItem(info.index, info.attachment)
								if IsShiftKeyDown() then
									GameTooltip_ShowCompareItem()
								end
								if info.money then
									GameTooltip:AddLine(ENCLOSED_MONEY, "", 1, 1, 1)
									SetTooltipMoney(GameTooltip, info.money)
									SetMoneyFrameColor('GameTooltipMoneyFrame', HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
								end 
								if info.cod > 0 then
									GameTooltip:AddLine(COD_AMOUNT, "", 1, 1, 1)
									SetTooltipMoney(GameTooltip, info.cod)
									SetMoneyFrameColor('GameTooltipMoneyFrame', HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
								end 
								GameTooltip:Show()
								highlightSameMailItems(this.col6 and this.col6:GetText(), this:GetParent():GetChildren())
							end,
							'onLeaveFunc', function()
								unhighlightSameMailItems(this.col6 and this.col6:GetText(), this:GetParent():GetChildren())
							end,
							'indentation', markTable[info.bmid] and 0 or 10,
							'text',  info.itemLink or L["Cash"],
							'text2', info.money and abacus:FormatMoneyFull(info.money) or info.qty,
							'text3', info.returnable and L["Yes"] or L["No"],
							'text4', info.sender,
							'text5', string.format("%0.1f", info.daysLeft),
							'text6', info.index,
							'textR', markTable[info.bmid] and 1, 'textG', markTable[info.bmid] and 1, 'textB', markTable[info.bmid] and 1,
							'text2R', markTable[info.bmid] and 1, 'text2G', markTable[info.bmid] and 1, 'text2B', markTable[info.bmid] and 1,
							'text3R', markTable[info.bmid] and 1, 'text3G', markTable[info.bmid] and 1, 'text3B', markTable[info.bmid] and 1,
							'text4R', markTable[info.bmid] and 1, 'text4G', markTable[info.bmid] and 1, 'text4B', markTable[info.bmid] and 1,
							'text5R', markTable[info.bmid] and 1, 'text5G', markTable[info.bmid] and 1, 'text5B', markTable[info.bmid] and 1,
							'text6R', markTable[info.bmid] and 1, 'text6G', markTable[info.bmid] and 1, 'text6B', markTable[info.bmid] and 1,
							hlcol..'R', 1, hlcol..'G', 1, hlcol..'B', markTable[info.bmid] and 1 or 0.5
						)
					end
				else
					cat:AddLine('text', L["No items"])
				end
				cat = tablet:AddCategory('columns', 1)
				cat:AddLine()
				cat:AddLine('text', L["Take All"], 'func', takeAll)
				cat:AddLine('text', L["Take Cash"], 'func', inboxCash > 0 and function() takeAll(true) end,
					'textR', inboxCash <= 0 and 0.5, 'textG', inboxCash <= 0 and 0.5, 'textB', inboxCash <= 0 and 0.5)
				cat:AddLine('text', L["Take Selected"], 'func', next(markTable) and function() takeAll(false, true) end,
					'textR', not next(markTable) and 0.5, 'textG', not next(markTable) and 0.5, 'textB', not next(markTable) and 0.5
				)
				cat:AddLine('text', L["Clear Selected"], 'func', next(markTable) and function() for i in pairs(markTable) do markTable[i] = nil end end,
					'textR', not next(markTable) and 0.5, 'textG', not next(markTable) and 0.5, 'textB', not next(markTable) and 0.5
				)
				cat:AddLine('text', L["Close"], 'func', function() BulkMailInbox:ScheduleEvent(function() tablet:Close('BMI_InboxTablet') end, 0) end)  -- WTF
			end
		)
	end
end

function BulkMailInbox:ShowInboxGUI()
	if not self.db.char.inboxUI then return end
	if not tablet:IsRegistered('BMI_InboxTablet') then
		self:RegisterInboxGUI()
	end
	if not inboxCache or not next(inboxCache) then
		self:RefreshInboxGUI()
	end
	tablet:Open('BMI_InboxTablet')
end

function BulkMailInbox:HideInboxGUI()
	if tablet:IsRegistered('BMI_InboxTablet') then
		tablet:Close('BMI_InboxTablet')
	end
end

function BulkMailInbox:RefreshInboxGUI()
	if not self.db.char.inboxUI then return end
	if not tablet:IsRegistered('BMI_InboxTablet') then
		self:RegisterInboxGUI()
	end
	inboxCacheBuild()
	tablet:Refresh('BMI_InboxTablet')
end
