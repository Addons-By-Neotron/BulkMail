local L = AceLibrary("AceLocale-2.0"):new("BulkMail")

L:RegisterTranslations("enUS", function()
	return {
		["Default destination for autosend items is |cffffff78%s|r."] = true,
		["No default destination set."] = true,
		["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."] = true,
		["WARNING: Cursor item detection is NOT well-defined when multiple items are 'locked'.   Alt-click is recommended for adding items when there is already an item in the Send Mail item frame."] = true,
		["Item recipient is this character.  Not sending."] = true,
		["Item cannot be mailed: %s."] = true,
		["Cannot determine the item clicked."] = true,

		["This item or set is already in your autosend list.  Please remove it first or use |cff00ffaa/bulkmail autosend add|r to change its AutoSend destination."] = true,
		["This item or set is not currently in your autosend list.  Please use |cff00ffaa/bulkmail autosend add [destination] ITEMLINK [ITEMLINK2, ...]|r to add it."] = true,
		["You must type 'confirm' to clear"] = true,
		["Please supply a destination for the item(s), or set a default destination with |cff00ffaa/bulkmail defaultdest|r."] = true,
		
		["Items to be sent (Alt-Click to add/remove):"] = true,
		["No items selected"] = true,
		["Clear"] = true,
		["Send"] = true,
		["Drop items here for Sending"] = true,
	}
end)