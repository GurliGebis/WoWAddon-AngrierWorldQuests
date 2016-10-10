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
	config_timeFilterDuration = "Time Remaining filter duration",
	config_enabledFilters = "Enabled Filters",
	config_sortMethod = "Sort World Quests by",
	config_sortMethod_1 = NAME,
	config_sortMethod_2 = CLOSES_IN,
	config_sortMethod_3 = ZONE,
	config_sortMethod_4 = FACTION,
	config_sortMethod_5 = REWARDS,
	config_characterConfig = "Per-character configuration",
	config_saveFilters = "Save active filters between logins",
	config_lootUpgradesLevel = "Loot filter shows upgrades",
	config_lootUpgradesLevelValue1 = "Higher ilvl only",
	config_lootUpgradesLevelValue2 = "Up to same ilvl",
	config_lootUpgradesLevelValue = "Up to %d ilvls less",
	config_flightMapTracked = "Show tracked World Quest POI icons on the flight map",
	config_flightMapAll = "Show all World Quest POI icons on the flight map",
	CURRENT_ZONE = "Current Zone",
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
	config_characterConfig = "Configuración por personaje",
	config_saveFilters = "Guardar filtros activos entre sesiones",
	config_lootUpgradesLevel = "El filtro de Botín muestra mejoras:",
	config_lootUpgradesLevelValue1 = "De mayor ilvl",
	config_lootUpgradesLevelValue2 = "Del mismo ilvl",
	config_lootUpgradesLevelValue = "Hasta %d ilvl menos",
	config_flightMapTracked = "Mostrar Misiones del Mundo en seguimiento en el mapa de vuelo",
	config_flightMapAll = "Mostrar todas las Misiones del Mundo en el mapa de vuelo",
	CURRENT_ZONE = "Zona actual",
}
langs.esMX = langs.esES

langs.koKR = {
	UPGRADES = "업그레이드",
	config_showAtTop = "퀘스트 목록창의 상단에 표시합니다",
	config_onlyCurrentZone = "퀘스트 목록창에 현재 지역에 있는 전역 퀘스트만 표시합니다",
	config_showEverywhere = "퀘스트 목록창에 부서진 섬의 전역 퀘스트를 모두 표시합니다",
	config_hideFilteredPOI = "세계지도에 필터링한 전역퀘스트 아이콘을 표시합니다",
	config_hideUntrackedPOI = "세계지도에 추적중인 전역퀘스트 아이콘을 표시합니다",
	config_showHoveredPOI = "퀘스트 목록창에 있는 전역 퀘스트들의 아이콘을 항상 표시합니다",
	config_showContinentPOI = "부서진 섬 지도에 전역퀘스트 아이콘을 표시합니다",
	config_lootFilterUpgrades = "전리품 필터를 통해 나온 결과물 중에, 현재 장비보다 좋은 항목만을 표시합니다",
	config_timeFilterDuration = "마감 시한 필터의 기준 시간",
	config_enabledFilters = "사용할 필터 선택",
	config_sortMethod = "전역 퀘스트 정렬 기준",
	config_sortMethod_1 = "이름",
	config_sortMethod_2 = "마감 시한",
	config_sortMethod_3 = "지역",
	config_sortMethod_4 = "사절 및 세력",
	config_characterConfig = "캐릭터 개별 설정",
	config_saveFilters = "활성화된 필터목록을 저장하여 다음 접속까지 유지",
	config_lootUpgradesLevel = "전리품 업그레이드 필터",
	config_lootUpgradesLevelValue1 = "높은 등급 전리품",
	config_lootUpgradesLevelValue2 = "동일한 등급 전리품",
	config_lootUpgradesLevelValue = "%d등급 낮은 전리품",
	config_flightMapTracked = "비행 지도에 추적중인 전역퀘스트 아이콘을 표시합니다",
	config_flightMapAll = "비행 지도에 모든 전역퀘스트 아이콘을 표시합니다",
	CURRENT_ZONE = "현재 지역",
}

langs.zhCN = {
	UPGRADES = "可升级",
	config_showAtTop = "将任务列表置于任务日志顶部",
	config_onlyCurrentZone = "仅显示当前区域的任务列表",
	config_showEverywhere = "在所有的地图显示任务列表",
	config_hideFilteredPOI = "在世界地图上隐藏被过滤的任务",
	config_hideUntrackedPOI = "在世界地图上隐藏未被追踪的任务",
	config_showHoveredPOI = "总是显示鼠标悬停的世界任务",
	config_showContinentPOI = "在破碎群岛的地图上显示世界任务图标",
	config_lootFilterUpgrades = "在物品过滤里仅显示更高装等的物品任务",
	config_timeFilterDuration = "剩余时间过滤时长",
	config_enabledFilters = "启用过滤",
	config_sortMethod = "任务列表排序",
	config_sortMethod_1 = "名字",
	config_sortMethod_2 = "剩余时间",
	config_sortMethod_3 = "区域",
	config_sortMethod_4 = "声望",
	config_characterConfig = "为角色进行独立的配置",
	config_saveFilters = "自动保存最后选择的过滤",
	config_lootUpgradesLevel = "可升级物品装等过滤",
	config_lootUpgradesLevelValue1 = "仅显示更高装等",
	config_lootUpgradesLevelValue2 = "显示最高同等级",
	config_lootUpgradesLevelValue = "最多相差%d装等",
	config_flightMapTracked = "在飞行地图点上显示当前追踪的世界任务",
	config_flightMapAll = "在飞行地图点上显示所有的世界任务",
	CURRENT_ZONE = "当前区域",
}

langs.zhTW = {
	UPGRADES = "可升級",
	config_showAtTop = "將任務列表置於任務日誌頂部",
	config_onlyCurrentZone = "僅顯示當前區域的任務列表",
	config_showEverywhere = "在所有的地圖顯示任務列表",
	config_hideFilteredPOI = "在世界地圖上隱藏被過濾的任務",
	config_hideUntrackedPOI = "在世界地圖上隱藏未被追蹤的任務",
	config_showHoveredPOI = "總是顯示鼠標懸停的世界任務",
	config_showContinentPOI = "在破碎群島的地圖上顯示世界任務圖標",
	config_lootFilterUpgrades = "在物品過濾裏僅顯示更高裝等的物品任務",
	config_timeFilterDuration = "剩餘時間過濾時長",
	config_enabledFilters = "啟用過濾",
	config_sortMethod = "任務列表排序",
	config_sortMethod_1 = "名字",
	config_sortMethod_2 = "剩餘時間",
	config_sortMethod_3 = "區域",
	config_sortMethod_4 = "聲望",
	config_characterConfig = "為角色進行獨立的配置",
	config_saveFilters = "自動保存最後選擇的過濾",
	config_lootUpgradesLevel = "可升級物品裝等過濾",
	config_lootUpgradesLevelValue1 = "僅顯示更高裝等物品",
	config_lootUpgradesLevelValue2 = "顯示最高同裝等物品",
	config_lootUpgradesLevelValue = "最多相差%d裝等",
	config_flightMapTracked = "在飛行地圖點上顯示當前追蹤的世界任務",
	config_flightMapAll = "在飛行地圖點上顯示所有的世界任務",
	CURRENT_ZONE = "當前區域",
}

langs.ruRU = {
	UPGRADES = "Обновление",
	config_showAtTop = "Показать вверху списка квестов",
	config_onlyCurrentZone = "Показывать Локальные Задания только для текущей зоны",
	config_showEverywhere = "Показать Локальные задания на отдельной карте",
	config_hideFilteredPOI = "Скрыть отфильтрованные World Quest иконки на карте мира",
	config_hideUntrackedPOI = "Скрыть неотслеживаемые World Quest иконки на карте мира",
	config_showHoveredPOI = "Всегда показывать значок World Quest",
	config_showContinentPOI = "Показать World Quest иконки на полной карте материка",
	config_lootFilterUpgrades = "Показать обновления только для Loot фильтра",
	config_timeFilterDuration = "Оставшееся время(Продолжительность)",
	config_enabledFilters = "Включенные фильтры",
	config_sortMethod = "Сортировать Задания",
	config_sortMethod_1 = "Имя",
	config_sortMethod_2 = "Оставшееся время",
	config_sortMethod_3 = "Зона",
	config_sortMethod_4 = "Фракция",
}

function Locale:Get(key)
	if langs[current_locale][key] ~= nil then
		return langs[current_locale][key]
	else
		return langs[default_locale][key]
	end
end

function Locale:Exists(key)
	return langs[default_locale][key] ~= nil
end

setmetatable(Locale, {__index = Locale.Get})

function Locale:Startup()
	current_locale = GetLocale()
	if langs[current_locale] == nil then
		current_locale = default_locale
	end
end
