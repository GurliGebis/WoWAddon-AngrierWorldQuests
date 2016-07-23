local ADDON, Addon = ...
local Locale = Addon:NewModule('Locale')

local default_locale = "enUS"
local current_locale

Locale.enUS = {
	UPGRADES = "Upgrades"
}

function Locale:Get(key)
	if self[current_locale][key] ~= nil then
		return self[current_locale][key]
	else
		return self[default_locale][key]
	end
end

setmetatable(Locale, {__index = Locale.Get})

function Locale:Startup()
	current_locale = GetLocale()
	if Locale[current_locale] == nil then
		current_locale = default_locale
	end
end
