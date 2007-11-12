
local L = AceLibrary("AceLocale-2.2"):new("BulkMail")
L:RegisterTranslations("frFR", function() return {
	["Accept"] = "Accepter",
--	["Add an item rule by itemlink or PeriodicTable-3.0 set manually."] = "",
	["Add rule"] = "Ajouter une règle",
	["add"] = "Ajouter",
	["as"] = "comme",
	["AutoSend Options"] = "Options d'auto-envoi",
	["AutoSend Rules"] = "Règles d'auto-envoi",
	["AutoSend"] = "Auto-envoi",
	["Bag Items"] = "Objets de sac",
	["BulkMail - Confirm removal of destination"] = "BulkMail - Confirmez la suppression de la destination",
	["BulkMailInbox Options"] = "Options de BulkMailInbox",
	["BulkMail - New AutoSend Destination"] = "Nouvelle destination d'auto-envoi",
	["Cancel"] = "Annuler",
	["Cannot determine the item clicked."] = "Impossible de déterminer l'objet cliqué",
	["Clear all rules for this realm."] = "Effacer toutes les règles de ce royaume",
	["Clear"] = "Vider",
	--["Click Include/Exclude headers to modify a ruleset.  Alt-Click destinations and rules to delete them."] = true,
	["Close"] = "Fermer",
	--["dd"] = true,
	["Default destination"] = "Destination par défaut",
	--["[destination] <itemlink|Periodic.Table.Set> [itemlink2|P.T.S.2 itemlink3|P.T.S.3 ...]"] = true,
	--["<destination>"] = true,
	--["Disable AutoSend queue auto-filling for this character."] = true,
	["Drop items here for Sending"] = "Lâchez les objets à envoyer ici",
	--["Edit AutoSend definitions."] = true,
	["edit"] = "Modifier",
	--["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."] = true,
	["Exclude"] = "Exclure",
	["Global Exclude"] = "Exclusion globale",
	["Hint: Click to show the AutoSend Rules editor."] = "Astuce: Cliquez pour afficher l'éditeur de règles d'auto-envoi",
	["Inbox"] = "Boîte-aux-lettres",
	["Include"] = "Inclure",
	["Item cannot be mailed: %s."] = "L'objet ne peut être envoyé: %s.",
	--["ItemID(s)"] = true,
	--["Item ID"] = true,
	--["Items from Bags"] = true,
	["Items to be sent (Alt-Click to add/remove):"] = "Objets à envoyer (Alt-Clique pour ajouter/enlever) :",
	["Item Type"] = "Type d'objet",
	["Mailable items in your bags."] = "Objet pouvant être envoyer de vos sacs",
	["New Destination"] = "Nouvelle destination",
	["No default destination set."] = "Aucune destination par défaut définie.",
	["No items selected"] = "Aucun objets sélectionnés",
	["None"] = "Aucun",
	--["Periodic Table Set"] = true,
	["Please supply a destination for the item(s), or set a default destination with |cff00ffaa/bulkmail defaultdest|r."] = "Spécifiez une destination ou indiquez une destination par défaut avec |cff00ffaa/bulkmail defaultdest|r.",
	--["rmdest"] = true,
	--["rmd"] = true,
	--["rules, list, ls"] = true,
	["Send"] = "Envoyer",
	["Set the default recipient of your AutoSend rules"] = "Indiquer le destinataire par défaut de vos règles d'auto-envoi",
	--["Sink"] = true,
	--["+"] = true,
	--["Usage: <itemID> [itemID2, ...]"] = true,
	["WARNING: Cursor item detection is NOT well-defined when multiple items are 'locked'.   Alt-click is recommended for adding items when there is already an item in the Send Mail item frame."] = "ATTENTION: La détection d'objets par le curseur est mal définie lorsque plusieurs objets sont \"verrouillés\". Alt-Clique est recommandé pour ajouter des objets lorsqu'il y en a déjà un dans la fenêtre d'envoi.",
} end)
