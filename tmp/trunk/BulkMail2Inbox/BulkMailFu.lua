if BulkMailFu then return end
BulkMailFu = AceLibrary("AceAddon-2.0"):new("AceDB-2.0", "FuBarPlugin-2.0")
local L = BulkMail and BulkMail.L or BulkMailInbox.L

BulkMailFu:RegisterDB("BulkMail2Fu")
BulkMailFu.hasIcon = true
BulkMailFu.hideWithoutStandby = true
BulkMailFu.hasNoText = true
BulkMailFu.hasNoColor = true
BulkMailFu.blizzardTooltip = true
BulkMailFu.defaultPosition = "RIGHT"
BulkMailFu.independentProfile = true

function BulkMailFu:OnEnable()
	self.opts = {}
	if BulkMail then self.opts = BulkMail.opts end
	if BulkMailInbox then
		if BulkMail then
			self.opts.args.inbox = { type = 'group', handler = BulkMailInbox, name = L["Inbox"], desc = L["BulkMailInbox Options"], args = BulkMailInbox.opts.args }
		else
			self.opts = BulkMailInbox.opts
		end
	end
	self.opts.args.profile.hidden = true
	self.opts.args.standby.hidden = true
end

function BulkMailFu:OnMenuRequest()
	AceLibrary('Dewdrop-2.0'):FeedAceOptionsTable(self.opts)
end

function BulkMailFu:OnClick()
	if BulkMail then BulkMail:OpenAutoSendEditTablet() end
end

function BulkMailFu:OnTooltipUpdate()
	if BulkMail then
		GameTooltip:AddLine(L["Hint: Click to show the AutoSend Rules editor."], 0, 1, 0, 1)
	end
end
