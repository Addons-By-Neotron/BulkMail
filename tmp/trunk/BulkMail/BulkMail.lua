-- To use this template, simply replace all occurances of BulkMail and self.loc
-- with the name of your addon. Make sure to use case-sensitive replacement for
-- global search and replacement.

-- NOTE: The globals TRUE and FALSE, defined in Ace.lua, contain the values 1 and
-- nil respectively. Their use is not required. The reason they are used as a
-- standard in Ace is just for readability. It's easier at a glance to know that a
-- variable is intended to be a boolean if you see TRUE and FALSE rather than 1 and
-- nil. Why not use true and false? Primarily because of false. false is equivalent
-- to nil but unlike nil it is an actual value that will keep the variable in
-- memory. And all those 'false' strings take up space in the SaveVariables file.
-- This is generally just a minor resource savings, but enough grains of sand make
-- a desert and all that. Use whatever method is your preference.

local DEFAULT_OPTIONS = {
	opt1 = FALSE,
	opt2 = TRUE
}

-- This data map may be used to map database values to command arguments, primarily
-- for use in the report() method. This is often necessary for localization. Say a
-- command can be entered as /addon display text. Hopefully display and text are
-- localized, but in your database display might be stored non-localized. So in the
-- map below you might have 'text' mapped to a global self.loc.DISPLAY_TEXT. The
-- [0] index will be used by the report() method as the display value if there is
-- no value. Otherwise, report() will display a generic "no value" message.
local DATA_MAP = {
	opt1     = {
	    [0]  = BulkMailLocals.OPT1_DEFAULT,
		val1 = BulkMailLocals.OPT1_VAL1,
		val2 = BulkMailLocals.OPT1_VAL2
	}
}

--[[--------------------------------------------------------------------------------
  Class Setup
-----------------------------------------------------------------------------------]]

-- See the "Ace Usage Guide.txt" document in the development kit for explanations of
-- each of the following parameters.
BulkMail = AceAddon:new({
	name            = BulkMailLocals.NAME,
	description     = BulkMailLocals.DESCRIPTION,
	version         = "0.1.0",
	releaseDate     = "04-08-2006",
	aceCompatible   = "103",
	author          = "Mynithrosil of Feathermoon",
	email           = "hyperactiveChipmunk@gmail.com",
	website         = "http://hyperactiveChipmunk.wowinterface.com",
	category        = "inventory",
	db              = AceDatabase:new("BulkMailDB"),
	defaults        = DEFAULT_OPTIONS,
	cmd             = AceChatCmd:new(BulkMailLocals.COMMANDS, BulkMailLocals.CMD_OPTIONS),
    loc             = BulkMailLocals,
})

function BulkMail:Initialize()
	if not self.data then
    	self.data = {}
    end

end

--[[--------------------------------------------------------------------------------
  Addon Enabling/Disabling
-----------------------------------------------------------------------------------]]

function BulkMail:Enable()
	--self:RegisterEvent("SOME_EVENT", "ProcessSomeEvent")
	--self:Hook("SomeFunction", "ProcessSomeFunction")
	--self:Hook(SomeObject, "SomeMethod", "ProcessSomeObjectMethod")
	--self:HookScript(SomeFrame, "OnShow", "ProcessOnShow")
end

-- Disable() is not needed if all you are doing in Enable() is registering events
-- and hooking functions. Ace will automatically unregister and unhook these.
function BulkMail:Disable()
end


--[[--------------------------------------------------------------------------------
  Main Processing
-----------------------------------------------------------------------------------]]

function BulkMail:ProcessSomeEvent()
end

--[[--------------------------------------------------------------------------------
  Register the Addon
-----------------------------------------------------------------------------------]]

BulkMail:RegisterForLoad()
