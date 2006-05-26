if not ace:LoadTranslation("BulkMail") then

BulkMailLocals = {
	NAME = "BulkMail",
    DESCRIPTION = "Bulk mail sending made easy",
    COMMANDS = {"/bm", "/bulkmail"},
    CMD_OPTIONS= {},

	MSG_SENDING_N_ITEMS = "Sending %d item(s) to %s.",
	MSG_DEFAULT_DESTINATION = "Default destination for autosend items is |cffffff78%s|r.",
	MSG_NO_DEFAULT_DESTINATION = "No default destination set.",
	MSG_ENTER_NAME_OR_SET_DEFAULT_DESTINATION = "Enter a name in the To: field or set a default destination with /bm defaultdest.",
	
	TEXT_MULTIPLE_RECIPIENTS = "multiple recipients",

	ERROR_ITEM_ALREADY_IN_AUTOSEND_LIST = "This item is already in your autosend list.  Please remove it first or use |cff00ffaa/bulkmail autosend add|r to change its AutoSend destination.",
	ERROR_ITEM_NOT_IN_AUTOSEND_LIST = "This item is not currently in your autosend list.  Please use |cff00ffaa/bulkmail autosend add [destination] ITEMLINK [ITEMLINK2, ...]|r to add it.",
	ERROR_TYPE_CONFIRM_ON_CLEAR = "You must type 'confirm' to clear",
}

BulkMailLocals.CMD_OPTIONS = {
	{
		option		=	"defaultdest",
		desc		=	"Set the default recipient of autosent items",
		method		=	"SetDefaultDestination",
	},
	{
		option		=	"autosend",
		desc		=	"AutoSend options",
		args		=	{
			{
				option		=	"add",
				desc		=	"add items to your AutoSend list (Usage: /bulkmail autosend add <destination> <item> [item2 item3 ...]",
				method		=	"AddAutoSendItem",
				input		=	true,
			},
			{
				option		=	"rm",
				desc		=	"remove items from your AutoSend list (Usage: /bulkmail autosend del <item> [item2 item3 ...]",
				method		=	"RemoveAutoSendItem",
				input		=	true,
			},
			{
				option		=	"rmdest",
				desc		=	"remove all items corresponding to a particular destination from your AutoSend list (Usage: /bulkmail autosend rmdest <destination>",
				method		=	"RemoveAutoSendDestination",
				input		=	true,
			},
			{
				option		=	"ls",
				desc		=	"print AutoSend list",
				method		=	"ListAutoSendItems",
				input		=	false,
			},
			{
				option		=	"clear",
				desc		=	"clear AutoSend list (type 'confirm')",
				method		=	"ClearAutoSendList",
				input		=	true,
			},
		}
	},
--	{
--		option		=	"gui",
--		desc		=	"Show BulkMail GUI",
--		method		=	"ShowGUI",
--	},
}

BulkMailLocals.gui = {
	title   = "BulkMail",
	items   = "Items to be sent (Alt-Click to add/remove):",
	noitems = "No items selected",
	clear   = "Clear",
	send    = "Send",
	dropBox = "Drop items here for Sending"
}
end
