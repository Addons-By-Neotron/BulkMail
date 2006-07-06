BulkMail:RegisterChatCommand({"/bulkmail", "/bm"}) {
	type = "group",
	args = {
		defaultdest = {
			name  = "Default destination", type = "text",
			desc  = "Set the default recipient of autosent items",
			get   = function() return self.db.realm.defaultDestination end,
			set   = function(dest) self.db.realm.defaultDestination = dest end,
			usage = "<destnation>",
		},
		
		autosend = {
			name = "AutoSend", type = "group", pass = true,
			desc = "AutoSend Options",
			get  = "ListAutoSendItems",
			args = {
				add = {
					name  = "add", type = "text",
					desc  = "Add items to the AutoSend list.",
					set   = "AddAutoSendItem",
					usage = "[destination] <item> [item2 item3 ...]",
				},
				rm = {
					name  = "rm", type = "text",
					desc  = "Remove items from the AutoSend list.",
					set   = "RemoveAutoSendItem",
					usage = "<item> [item2 item3 ...]",
				},
				rmdest = {
					name  = "rmdest", type = "text",
					desc  = "Remove all items corresponding to a particular destination from your AutoSend list.",
					set   = "RemoveAutoSendItem",
					usage = "<destination>",
				},
				clear = {
					name  = "clear", type = "text",
					desc  = "Clear AutoSend list completely.",
					set   = "ClearAutoSendItems",
					validate = function(confirm) if confirm == "CONFIRM" then return true end end,
					error = "You must type 'CONFIRM' to clear.",
					usage = "CONFIRM",
				},
			},				
		},
	},
}