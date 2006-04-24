if not ace:LoadTranslation("BulkMail") then

BulkMailLocals = {
	NAME = "BulkMail",
    DESCRIPTION = "Bulk mail sending made easy",
    COMMANDS = {"/bm", "/bulkmail"},
    CMD_OPTIONS= {},

	ERROR_ITEM_ALREADY_IN_AUTOSEND_LIST="This item is already in your autosend list.  Please remove it first or use |cff00ffaa/bulkmail autosend change <destination> <item> [item2, ...]|r to change its autosend destination.",
	ERROR_ITEM_NOT_IN_AUTOSEND_LIST="This item is not currently in your autosend list.  Please use |cff00ffaa/bulkmail autosend add <destination> <item> [item2, ...]|r to add it.",
}
end
