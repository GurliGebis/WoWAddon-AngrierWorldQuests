local ADDON, Addon = ...
local Locale = Addon:NewModule('Locale')

local default_locale = "enUS"
local current_locale

local langs = {}
langs.enUS = {
	UPGRADES = "Upgrades",
	config_showAtTop = "Display at the top of the Quest Log", 
	config_onlyCurrentZone = "Only show World Quests for the current zone", 
	config_showEverywhere = "Show World Quests on every map",
	config_hideFilteredPOI = "Hide filtered World Quest POI icons on the world map", 
	config_hideUntrackedPOI = "Hide untracked World Quest POI icons on the world map", 
	config_showHoveredPOI = "Always show hovered World Quest POI icon",
	config_showContinentPOI = "Show World Quest POI icons on the Broken Isles map",
	config_lootFilterUpgrades = "Show only upgrades for Loot filter",
	config_timeFilterDuration = "Time Remaining Filter Duration",
	config_enabledFilters = "Enabled Filters",
	config_sortMethod = "Sort World Quests by",
	config_sortMethod_1 = "Name",
	config_sortMethod_2 = "Time Left",
	config_sortMethod_3 = "Zone",
	config_sortMethod_4 = "Faction",
}

langs.esES = {
	UPGRADES = "Mejoras",
	config_showAtTop = "Mostrar arriba en el rastreador de misiones",
	config_onlyCurrentZone = "Mostrar Misiones del Mundo sólo para la zona actual",
	config_showEverywhere = "Mostrar Misiones del Mundo en cualquier mapa",
	config_hideFilteredPOI = "Ocultar Misiones del Mundo filtradas en el mapa del mundo",
	config_hideUntrackedPOI = "Ocultar Misiones del Mundo sin seguimiento en el mapa",
	config_showHoveredPOI = "Mostrar siempre la Misión del Mundo sobre la que se pose el ratón",
	config_showContinentPOI = "Mostrar Misiones del Mundo en el mapa de las Islas Abruptas",
	config_lootFilterUpgrades = "Mostrar sólo objetos mejores en el filtro \"Botín\"",
	config_timeFilterDuration = "Duración para el filtro \"Tiempo restante\":",
	config_enabledFilters = "Filtros activos",
	config_sortMethod = "Ordenar Misiones del Mundo por:",
	config_sortMethod_1 = "Nombre",
	config_sortMethod_2 = "Tiempo restante",
	config_sortMethod_3 = "Zona",
	config_sortMethod_4 = "Facción",
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
