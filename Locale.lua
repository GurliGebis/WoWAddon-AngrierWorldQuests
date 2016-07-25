local ADDON, Addon = ...
local Locale = Addon:NewModule('Locale')

local default_locale = "enUS"
local current_locale

local langs = {}
langs.enUS = {
	UPGRADES = "Upgrades",
}

function Locale:Get(key)
	if langs[current_locale][key] ~= nil then
		return langs[current_locale][key]
	else
		return langs[default_locale][key]
	end
end

setmetatable(Locale, {__index = Locale.Get})

function Locale:Startup()
	current_locale = GetLocale()
	if langs[current_locale] == nil then
		current_locale = default_locale
	end
end
