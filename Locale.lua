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
langs.esMX = langs.esES

langs.koKR = {
	UPGRADES = "업그레이드",
	config_showAtTop = "퀘스트 목록 창의 상단 혹은 하단에 표시합니다", 
	config_onlyCurrentZone = "현재 지역에 있는 전역 퀘스트만 표시합니다", 
	config_showEverywhere = "전 지역에 있는 전역 퀘스트를 모두 표시합니다",
	config_hideFilteredPOI = "필터를 통해 걸러진 퀘스트들의 전역 퀘스트 아이콘을 숨깁니다", 
	config_hideUntrackedPOI = "추적중인 퀘스트들의 전역 퀘스트 아이콘을 숨깁니다", 
	config_showHoveredPOI = "전역 퀘스트 아이콘을 항상 표시합니다",
	config_showContinentPOI = "부서진 섬 지도에서 전역 퀘스트 아이콘을 표시합니다",
	config_lootFilterUpgrades = "전리품 필터를 통해 나온 결과물 중에, 현재 장비보다 좋은 항목만을 표시합니다",
	config_timeFilterDuration = "마감 시한 필터의 기준 시간",
	config_enabledFilters = "사용할 필터 선택",
	config_sortMethod = "전역 퀘스트 정렬 기준",
	config_sortMethod_1 = "이름",
	config_sortMethod_2 = "마감 시한",
	config_sortMethod_3 = "지역",
	config_sortMethod_4 = "사절 및 세력",
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
