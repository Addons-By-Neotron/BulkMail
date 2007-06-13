if BulkMailFu then return end
BulkMailFu = AceLibrary("AceAddon-2.0"):new("AceDB-2.0", "FuBarPlugin-2.0")
local L = BulkMail and BulkMail.L or BulkMailInbox.L

local tablet  = AceLibrary('Tablet-2.0')
local dewdrop = AceLibrary('Dewdrop-2.0')

function BulkMailFu:OnInitialize()
	self:RegisterDB("BulkMail2DB")
	self.hasIcon = true
	self.hideWithoutStandby = true
	self.hasNoText = true
	self.defaultPosition = "RIGHT"
	self:SetIcon(true)
end

function BulkMailFu:ToString()
	return "BulkMail"
end

function BulkMailFu:OnMenuRequest()
	local bmfuopts = {}
	if BulkMail then bmfuopts = BulkMail.opts end
	if BulkMailInbox then
		if BulkMail then
			bmfuopts.args.inbox = { type = 'group', name = L["Inbox"], desc = L["BulkMailInbox Options"], args = BulkMailInbox.opts.args }
		else
			bmfuopts = BulkMailInbox.opts
		end
	end
	dewdrop:FeedAceOptionsTable(bmfuopts)
end

function BulkMailFu:OnClick()
	if BulkMail then tablet:Open('BM_AutoSendEditTablet') end
end

function BulkMailFu:OnTooltipUpdate()
	if BulkMail then
		tablet:SetHint(L["Click to show AutoSend Rules interface."])
	end
end
