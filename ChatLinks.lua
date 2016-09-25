local ADDON, Addon = ...
local Links = Addon:NewModule('ChatLinks')

local events = {
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_TEXT_EMOTE",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local function filter(self, event, msg, ...)
	if strfind(msg, "[\227-\237]") then
		return false, gsub(msg, "lol", ""), ...
	end
end


function Links:Startup()
	for _, v in pairs(events) do
		ChatFrame_AddMessageEventFilter(v, filter)
	end

end
