local ADDON, Addon = ...
local Mod = Addon:NewModule('QuestFrame')
local Config

local dataProvder
local hoveredQuestID

local MAPID_BROKENISLES = 619
local MAPID_DALARAN = 627
local MAPID_AZSUNA = 630
local MAPID_STORMHEIM = 634
local MAPID_VALSHARAH = 641
local MAPID_HIGHMOUNTAIN = 650
local MAPID_SURAMAR = 680
local MAPID_EYEOFAZSHARA = 790
local MAPID_BROKENSHORE = 646
local MAPID_ARGUS = 905
local MAPID_ANTORANWASTES = 885
local MAPID_KROKUUN = 830
local MAPID_MACAREE = 882

local MAPID_ZONES_CONTINENTS = {
	[MAPID_DALARAN] = MAPID_BROKENISLES,
	[MAPID_AZSUNA] = MAPID_BROKENISLES,
	[MAPID_STORMHEIM] = MAPID_BROKENISLES,
	[MAPID_VALSHARAH] = MAPID_BROKENISLES,
	[MAPID_HIGHMOUNTAIN] = MAPID_BROKENISLES,
	[MAPID_SURAMAR] = MAPID_BROKENISLES,
	[MAPID_EYEOFAZSHARA] = MAPID_BROKENISLES,
	[MAPID_BROKENSHORE] = MAPID_BROKENISLES,
	[MAPID_ANTORANWASTES] = MAPID_ARGUS,
	[MAPID_KROKUUN] = MAPID_ARGUS,
	[MAPID_MACAREE] = MAPID_ARGUS,
}
local MAPID_CONTINENTS = { [MAPID_BROKENISLES] = true, [MAPID_ARGUS] = true }

local MAPID_ALL = { MAPID_SURAMAR, MAPID_AZSUNA, MAPID_VALSHARAH, MAPID_HIGHMOUNTAIN, MAPID_STORMHEIM, MAPID_DALARAN, MAPID_EYEOFAZSHARA, MAPID_BROKENSHORE, MAPID_ANTORANWASTES, MAPID_KROKUUN, MAPID_MACAREE }
local MAPID_ALL_BROKENISLES = { MAPID_SURAMAR, MAPID_AZSUNA, MAPID_VALSHARAH, MAPID_HIGHMOUNTAIN, MAPID_STORMHEIM, MAPID_DALARAN, MAPID_EYEOFAZSHARA, MAPID_BROKENSHORE }
local MAPID_ALL_ARGUS = { MAPID_ANTORANWASTES, MAPID_KROKUUN, MAPID_MACAREE }
local MAPID_ORDER = { [MAPID_SURAMAR] = 1, [MAPID_AZSUNA] = 2, [MAPID_VALSHARAH] = 3, [MAPID_HIGHMOUNTAIN] = 4, [MAPID_STORMHEIM] = 5, [MAPID_DALARAN] = 6, [MAPID_EYEOFAZSHARA] = 7, [MAPID_BROKENSHORE] = 8, [MAPID_ANTORANWASTES] = 9, [MAPID_KROKUUN] = 10, [MAPID_MACAREE] = 11 }

local TitleButton_RarityColorTable = { [LE_WORLD_QUEST_QUALITY_COMMON] = 110, [LE_WORLD_QUEST_QUALITY_RARE] = 113, [LE_WORLD_QUEST_QUALITY_EPIC] = 120 }

local FILTER_COUNT = 19
local FILTER_ICONS = { "achievement_reputation_01", "inv_7xp_inscription_talenttome01", "inv_misc_lockboxghostiron", "inv_orderhall_orderresources", "inv_misc_coin_01", "inv_box_01", "ability_bossmagistrix_timewarp2", "achievement_reputation_06", "pvpcurrency-honor-horde", "inv_misc_note_01", "tracking_wildpet", "", "inv_misc_map_01", "icon_treasuremap", "achievement_raregarrisonquests_x", "achievement_general_stayclassy", "inv_misc_summonable_boss_token", "inv_datacrystal01", "oshugun_crystalfragments" }
local FILTER_NAMES = { BOUNTY_BOARD_LOCKED_TITLE, ARTIFACT_POWER, BONUS_ROLL_REWARD_ITEM, "Order Resources", BONUS_ROLL_REWARD_MONEY, ITEMS, CLOSES_IN, FACTION, PVP, TRADE_SKILLS, SHOW_PET_BATTLES_ON_MAP_TEXT, RAID_FRAME_SORT_LABEL, TRACKING, ZONE, ITEM_QUALITY3_DESC, GROUP_FINDER, "Legionfall War Supplies", "Nethershard", "Veiled Argunite" }
local FILTER_EMISSARY = 1
local FILTER_ARTIFACT_POWER = 2
local FILTER_LOOT = 3
local FILTER_ORDER_RESOURCES = 4
local FILTER_GOLD = 5
local FILTER_ITEMS = 6
local FILTER_TIME = 7
local FILTER_FACTION = 8
local FILTER_PVP = 9
local FILTER_PROFESSION = 10
local FILTER_PETBATTLE = 11
local FILTER_SORT = 12
local FILTER_TRACKED = 13
local FILTER_ZONE = 14
local FILTER_RARE = 15
local FILTER_DUNGEON = 16
local FILTER_WAR_SUPPLIES = 17
local FILTER_NETHERSHARD = 18
local FILTER_VEILED_ARGUNITE = 19
local FILTER_ORDER = { FILTER_EMISSARY, FILTER_TIME, FILTER_ZONE, FILTER_TRACKED, FILTER_FACTION, FILTER_ARTIFACT_POWER, FILTER_LOOT, FILTER_ORDER_RESOURCES, FILTER_WAR_SUPPLIES, FILTER_NETHERSHARD, FILTER_VEILED_ARGUNITE, FILTER_GOLD, FILTER_ITEMS, FILTER_PVP, FILTER_PROFESSION, FILTER_PETBATTLE, FILTER_RARE, FILTER_DUNGEON, FILTER_SORT }
Mod.FilterNames = FILTER_NAMES
Mod.FilterOrder = FILTER_ORDER
local FILTER_TIME_VALUES = { 1, 3, 6, 12, 24 }
Mod.FilterTimeValues = FILTER_TIME_VALUES

local SORT_NAME = 1
local SORT_TIME = 2
local SORT_ZONE = 3
local SORT_FACTION = 4
local SORT_REWARDS = 5
local SORT_ORDER = { SORT_NAME, SORT_TIME, SORT_ZONE, SORT_FACTION, SORT_REWARDS }
local REWARDS_ORDER = { [FILTER_ARTIFACT_POWER] = 1, [FILTER_LOOT] = 2, [FILTER_ORDER_RESOURCES] = 3, [FILTER_GOLD] = 4, [FILTER_ITEMS] = 5 }
Mod.SortOrder = SORT_ORDER

local FACTION_ORDER = { 1900, 1883, 1828, 1948, 1894, 1859, 1090, 2045, 2165, 2170 }

local FILTER_LOOT_ALL = 1
local FILTER_LOOT_UPGRADES = 2

local My_HideDropDownMenu, My_DropDownList1, My_UIDropDownMenu_AddButton, My_UIDropDownMenu_Initialize, My_ToggleDropDownMenu, My_UIDropDownMenuTemplate
function Mod:BeforeStartup()
	My_HideDropDownMenu = Lib_HideDropDownMenu or HideDropDownMenu
	My_DropDownList1 = Lib_DropDownList1 or DropDownList1
	My_UIDropDownMenu_AddButton = Lib_UIDropDownMenu_AddButton or UIDropDownMenu_AddButton
	My_UIDropDownMenu_Initialize = Lib_UIDropDownMenu_Initialize or UIDropDownMenu_Initialize
	My_ToggleDropDownMenu = Lib_ToggleDropDownMenu or ToggleDropDownMenu
	My_UIDropDownMenuTemplate = Lib_UIDropDownMenu_Initialize and "Lib_UIDropDownMenuTemplate" or "UIDropDownMenuTemplate"
end

-- ===================
--  Utility Functions
-- ===================



-- =================
--  Event Functions
-- =================

local function HeaderButton_OnClick(self, button)
	local questsCollapsed = Config.collapsed
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if ( button == "LeftButton" ) then
		questsCollapsed = not questsCollapsed
		Config:Set('collapsed', questsCollapsed)
		QuestMapFrame_UpdateAll()
	end
end

local function TitleButton_OnEnter(self)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
	local _, color = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )
	self.Text:SetTextColor( color.r, color.g, color.b )
	
	hoveredQuestID = self.questID

	if dataProvder then
		local pin = dataProvder.activePins[self.questID]
		if pin then
			pin:EnableDrawLayer("HIGHLIGHT")
		end
	end
	if Config.showComparisonRight then
		WorldMapTooltip.ItemTooltip.Tooltip.overrideComparisonAnchorSide = "right"
	end
	TaskPOI_OnEnter(self)
end

local function TitleButton_OnLeave(self)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
	local color = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )
	self.Text:SetTextColor( color.r, color.g, color.b )

	hoveredQuestID = nil

	if dataProvder then
		local pin = dataProvder.activePins[self.questID]
		if pin then
			pin:DisableDrawLayer("HIGHLIGHT")
		end
	end
	TaskPOI_OnLeave(self)
end

local function TitleButton_OnClick(self, button)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if ( not ChatEdit_TryInsertQuestLinkForQuestID(self.questID) ) then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
		
		if ( button == "RightButton" ) then
			if ( self.mapID ) then
				QuestMapFrame:GetParent():SetMapID(self.mapID)
			end
		elseif IsShiftKeyDown() then
			if IsWorldQuestHardWatched(self.questID) or (IsWorldQuestWatched(self.questID) and GetSuperTrackedQuestID() == self.questID) then
				BonusObjectiveTracker_UntrackWorldQuest(self.questID);
			else
				BonusObjectiveTracker_TrackWorldQuest(self.questID, true)
			end
		else
			if IsWorldQuestHardWatched(self.questID) then
				SetSuperTrackedQuestID(self.questID);
			else
				BonusObjectiveTracker_TrackWorldQuest(self.questID)
			end
		end
	end
end

local function FilterButton_OnEnter(self)
	local text = FILTER_NAMES[ self.index ]
	if self.index == FILTER_EMISSARY and Config.filterEmissary and not IsQuestComplete(Config.filterEmissary) then
		local title = GetQuestLogTitle(GetQuestLogIndexByID(Config.filterEmissary))
		if title then text = text..": "..title end
	end
	if self.index == FILTER_LOOT then
		if Config.filterLoot == FILTER_LOOT_UPGRADES or (Config.filterLoot == 0 and Config.lootFilterUpgrades) then
			text = string.format("%s (%s)", text, Addon.Locale.UPGRADES)
		end
	end
	if self.index == FILTER_FACTION and Config.filterFaction ~= 0 then
		local title = GetFactionInfoByID(Config.filterFaction)
		if title then text = text..": "..title end
	end
	if self.index == FILTER_SORT then
		local title = Addon.Locale["config_sortMethod_"..Config.sortMethod]
		if title then text = text..": "..title end
	end
	if self.index == FILTER_ZONE and Config.filterZone ~= 0 then
		local title = GetMapNameByID(Config.filterZone)
		if title then text = text..": "..title end
	end
	if self.index == FILTER_TIME then
		local hours = Config.filterTime ~= 0 and Config.filterTime or Config.timeFilterDuration
		text = string.format(BLACK_MARKET_HOT_ITEM_TIME_LEFT, string.format(FORMATED_HOURS, hours))
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(text)
	GameTooltip:Show()
end

local function FilterButton_OnLeave(self)
	GameTooltip:Hide()
end

local filterMenu
local function FilterMenu_OnClick(self, filterIndex)
	if filterIndex == FILTER_EMISSARY then
		Config:Set('filterEmissary', self.value, true)
	end
	if filterIndex == FILTER_LOOT then
		Config:Set('filterLoot', self.value, true)
	end
	if filterIndex == FILTER_FACTION then
		Config:Set('filterFaction', self.value, true)
	end
	if filterIndex == FILTER_ZONE then
		Config:Set('filterZone', self.value, true)
	end
	if filterIndex == FILTER_TIME then
		Config:Set('filterTime', self.value, true)
	end
	if filterIndex == FILTER_SORT then
		Config:Set('sortMethod', self.value)
	elseif IsShiftKeyDown() then
		Config:SetFilter(filterIndex, true)
	else
		Config:SetOnlyFilter(filterIndex)
	end
end

local function FilterMenu_Initialize(self, level)
	local info = { func = FilterMenu_OnClick, arg1 = self.index }
	if self.index == FILTER_EMISSARY then
		local value = Config.filterEmissary
		if GetQuestLogIndexByID(value) == 0 then value = 0 end

		info.text = ALL
		info.value = 0
		info.checked = info.value == value
		My_UIDropDownMenu_AddButton(info, level)

		local bounties = GetQuestBountyInfoForMapID(MAPID_BROKENISLES)
		for _, bounty in ipairs(bounties) do
			if not IsQuestComplete(bounty.questID) then
				info.text =  GetQuestLogTitle(GetQuestLogIndexByID(bounty.questID))
				info.icon = bounty.icon
				info.value = bounty.questID
				info.checked = info.value == value
				My_UIDropDownMenu_AddButton(info, level)
			end
		end
	elseif self.index == FILTER_LOOT then
		local value = Config.filterLoot
		if value == 0 then value = Config.lootFilterUpgrades and FILTER_LOOT_UPGRADES or FILTER_LOOT_ALL end

		info.text = ALL
		info.value = FILTER_LOOT_ALL
		info.checked = info.value == value
		My_UIDropDownMenu_AddButton(info, level)

		info.text = Addon.Locale.UPGRADES
		info.value = FILTER_LOOT_UPGRADES
		info.checked = info.value == value
		My_UIDropDownMenu_AddButton(info, level)
	elseif self.index == FILTER_ZONE then
		local value = Config.filterZone

		info.text = Addon.Locale.CURRENT_ZONE
		info.value = 0
		info.checked = info.value == value
		My_UIDropDownMenu_AddButton(info, level)

		for _,mapID in ipairs(MAPID_ALL) do
			info.text = GetMapNameByID(mapID)
			info.value = mapID
			info.checked = info.value == value
			My_UIDropDownMenu_AddButton(info, level)
		end
	elseif self.index == FILTER_FACTION then
		local value = Config.filterFaction

		for _, factionID in ipairs(FACTION_ORDER) do
			info.text =  GetFactionInfoByID(factionID)
			info.value = factionID
			info.checked = info.value == value
			My_UIDropDownMenu_AddButton(info, level)
		end
	elseif self.index == FILTER_TIME then
		local value = Config.filterTime ~= 0 and Config.filterTime or Config.timeFilterDuration

		for _, hours in ipairs(FILTER_TIME_VALUES) do
			info.text = string.format(FORMATED_HOURS, hours)
			info.value = hours
			info.checked = info.value == value
			My_UIDropDownMenu_AddButton(info, level)
		end
	elseif self.index == FILTER_SORT then
		local value = Config.sortMethod

		info.text = FILTER_NAMES[ self.index ]
		info.notCheckable = true
		info.isTitle = true
		My_UIDropDownMenu_AddButton(info, level)

		info.notCheckable = false
		info.isTitle = false
		info.disabled = false
		for _, sortIndex in ipairs(SORT_ORDER) do
			info.text =  Addon.Locale["config_sortMethod_"..sortIndex]
			info.value = sortIndex
			info.checked = info.value == value
			My_UIDropDownMenu_AddButton(info, level)
		end
	end
end

local function FilterButton_ShowMenu(self)
	if not filterMenu then
		filterMenu = CreateFrame("Button", "DropDownMenuAWQ", QuestMapFrame, My_UIDropDownMenuTemplate)
	end

	filterMenu.index = self.index
	My_UIDropDownMenu_Initialize(filterMenu, FilterMenu_Initialize, "MENU")
	My_ToggleDropDownMenu(1, nil, filterMenu, self, 0, 0)
end

local function FilterButton_OnClick(self, button)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if (button == 'RightButton' and (self.index == FILTER_EMISSARY or self.index == FILTER_LOOT or self.index == FILTER_FACTION or self.index == FILTER_ZONE  or self.index == FILTER_TIME))
			or (self.index == FILTER_SORT)
			or (self.index == FILTER_FACTION and not Config:GetFilter(FILTER_FACTION) and Config.filterFaction == 0) then
		local MY_UIDROPDOWNMENU_OPEN_MENU = Lib_UIDropDownMenu_Initialize and LIB_UIDROPDOWNMENU_OPEN_MENU or UIDROPDOWNMENU_OPEN_MENU
		if filterMenu and MY_UIDROPDOWNMENU_OPEN_MENU == filterMenu and My_DropDownList1:IsShown() and filterMenu.index == self.index then
			My_HideDropDownMenu(1)
		else
			My_HideDropDownMenu(1)
			FilterButton_ShowMenu(self)
		end
	else
		My_HideDropDownMenu(1)
		if IsShiftKeyDown() then
			if self.index == FILTER_EMISSARY then Config:Set('filterEmissary', 0, true) end
			if self.index == FILTER_LOOT then Config:Set('filterLoot', 0, true) end
			Config:ToggleFilter(self.index)
		else
			if Config:IsOnlyFilter(self.index) then
				Config:Set('filterEmissary', 0, true)
				Config:Set('filterLoot', 0, true)
				Config:Set('filterZone', 0, true)
				Config:Set('filterTime', 0, true)
				Config:SetNoFilter()
			else
				if self.index ~= FILTER_EMISSARY then Config:Set('filterEmissary', 0, true) end
				if self.index ~= FILTER_LOOT then Config:Set('filterLoot', 0, true) end
				if self.index ~= FILTER_ZONE then Config:Set('filterZone', 0, true) end
				if self.index ~= FILTER_TIME then Config:Set('filterTime', 0, true) end
				Config:SetOnlyFilter(self.index)
			end
		end
		FilterButton_OnEnter(self)
	end
end

local function GetMapIDsForDisplay(mapID)
	if (Config.showEverywhere and not tContains(MAPID_ALL, mapID)) or mapID == MAPID_BROKENISLES then
		return { MAPID_BROKENISLES, MAPID_ANTORANWASTES, MAPID_KROKUUN, MAPID_MACAREE }
	elseif not Config.onlyCurrentZone and tContains(MAPID_ALL, mapID) then
		return { MAPID_BROKENISLES, MAPID_ANTORANWASTES, MAPID_KROKUUN, MAPID_MACAREE }
	elseif mapID == MAPID_ARGUS then
		return MAPID_ALL_ARGUS
	else
		return { mapID }
	end
end

local filterButtons = {}
local function GetFilterButton(index)
	if ( not filterButtons[index] ) then
		local button = CreateFrame("Button", nil, QuestMapFrame.QuestsFrame.Contents)
		button.index = index

		button:SetScript("OnEnter", FilterButton_OnEnter)
		button:SetScript("OnLeave", FilterButton_OnLeave)
		button:RegisterForClicks("LeftButtonUp","RightButtonUp")
		button:SetScript("OnClick", FilterButton_OnClick)

		button:SetSize(24, 24)
			
		if index == FILTER_SORT then
			button:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
			button:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
			button:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
			button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		else
			button:SetNormalAtlas("worldquest-tracker-ring")
			button:SetHighlightAtlas("worldquest-tracker-ring")
			button:GetHighlightTexture():SetAlpha(0.4)

			local icon = button:CreateTexture(nil, "BACKGROUND", nil, -1)
			icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
			icon:SetSize(16, 16)
			icon:SetPoint("CENTER", 0, 1)
			icon:SetTexture("Interface\\Icons\\"..(FILTER_ICONS[index] or "inv_misc_questionmark"))
			button.Icon = icon
		end
		filterButtons[index] = button
	end
	return filterButtons[index]
end

local function TitleButton_Initiliaze(button)
	if not button.awq then
		button:SetScript("OnEnter", TitleButton_OnEnter)
		button:SetScript("OnLeave", TitleButton_OnLeave)
		button:SetScript("OnClick", TitleButton_OnClick)

		button.TagTexture:SetSize(24, 24)
		button.TagTexture:ClearAllPoints()
		button.TagTexture:SetPoint("TOP", button.Text, "CENTER", 0, 8)
		button.TagTexture:SetPoint("RIGHT", 0, 0)
		button.TagTexture:Hide()

		button.TagText = button:CreateFontString(nil, nil, "GameFontNormalLeft")
		button.TagText:SetTextColor(1, 1, 1)
		button.TagText:Hide()

		button.TaskIcon:ClearAllPoints()
		button.TaskIcon:SetPoint("CENTER", button.Text, "LEFT", -15, 0)

		button.TimeIcon = button:CreateTexture(nil, "OVERLAY")
		button.TimeIcon:SetAtlas("worldquest-icon-clock")

		local filename, fontHeight = button.TagText:GetFont()
		button.TagTexture:SetSize(16, 16)
		button.TagText:ClearAllPoints()
		button.TagText:SetPoint("RIGHT", button.TagTexture , "LEFT", -3, 0)
		button.TagText:SetFont(filename, fontHeight, "")

		button.awq = true
	end
end

local titleFramePool
local headerButton
local spacerFrame

local function QuestFrame_AddQuestButton(questInfo, prevButton)
	local totalHeight = 8
	local button = titleFramePool:Acquire()
	TitleButton_Initiliaze(button)

	local questID = questInfo.questId
	local title, factionID, capped = C_TaskQuest.GetQuestInfoByQuestID(questID)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(questID)
	local tradeskillLineID = tradeskillLineIndex and select(7, GetProfessionInfo(tradeskillLineIndex))
	local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
	C_TaskQuest.RequestPreloadRewardData(questID)

	local totalHeight = 8
	button.worldQuest = true
	button.questID = questID
	button.mapID = questInfo.mapID
	button.factionID = factionID
	button.timeLeftMinutes = timeLeftMinutes
	button.numObjectives = questInfo.numObjectives
	button.infoX = questInfo.x
	button.infoY = questInfo.y
	local difficultyColor = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )

	button.Text:SetText(title)
	button.Text:SetTextColor( difficultyColor.r, difficultyColor.g, difficultyColor.b )

	totalHeight = totalHeight + button.Text:GetHeight()

	if ( IsWorldQuestHardWatched(questID) or GetSuperTrackedQuestID() == questID ) then
		button.Check:Show()
		button.Check:SetPoint("LEFT", button.Text, button.Text:GetWrappedWidth() + 2, 0)
	else
		button.Check:Hide()
	end

	local hasIcon = true
	button.TaskIcon:Show()
	button.TaskIcon:SetTexCoord(0, 1, 0, 1)
	if questInfo.inProgress then
		button.TaskIcon:SetAtlas("worldquest-questmarker-questionmark")
		button.TaskIcon:SetSize(10, 15)
	elseif worldQuestType == LE_QUEST_TAG_TYPE_PVP then
		button.TaskIcon:SetAtlas("worldquest-icon-pvp-ffa", true)
	elseif worldQuestType == LE_QUEST_TAG_TYPE_PET_BATTLE then
		button.TaskIcon:SetAtlas("worldquest-icon-petbattle", true)
	elseif worldQuestType == LE_QUEST_TAG_TYPE_DUNGEON then
		button.TaskIcon:SetAtlas("worldquest-icon-dungeon", true)
	elseif worldQuestType == LE_QUEST_TAG_TYPE_RAID then
		button.TaskIcon:SetAtlas("worldquest-icon-raid", true)
	elseif ( worldQuestType == LE_QUEST_TAG_TYPE_PROFESSION and WORLD_QUEST_ICONS_BY_PROFESSION[tradeskillLineID] ) then
		button.TaskIcon:SetAtlas(WORLD_QUEST_ICONS_BY_PROFESSION[tradeskillLineID], true)
	elseif isElite then
		--local tagCoords = QUEST_TAG_TCOORDS[QUEST_TAG_HEROIC]
		--button.TaskIcon:SetSize(16, 16)
		--button.TaskIcon:SetTexture("Interface\\QuestFrame\\QuestTypeIcons")
		--button.TaskIcon:SetTexCoord( unpack(tagCoords) )
	else
		hasIcon = false
		button.TaskIcon:Hide()
	end

	if ( timeLeftMinutes and timeLeftMinutes > 0 and timeLeftMinutes <= WORLD_QUESTS_TIME_LOW_MINUTES ) then
		button.TimeIcon:Show()
		if hasIcon then
			button.TimeIcon:SetSize(14, 14)
			button.TimeIcon:SetPoint("CENTER", button.TaskIcon, "BOTTOMLEFT", 0, 0)
		else
			button.TimeIcon:SetSize(16, 16)
			button.TimeIcon:SetPoint("CENTER", button.Text, "LEFT", -15, 0)
		end
	else
		button.TimeIcon:Hide()
	end

	local tagText, tagTexture, tagTexCoords, tagColor
	tagColor = {r=1, g=1, b=1}

	local money = GetQuestLogRewardMoney(questID)
	if ( money > 0 ) then
		local gold = floor(money / (COPPER_PER_GOLD))
		tagTexture = "Interface\\MoneyFrame\\UI-MoneyIcons"
		tagTexCoords = { 0, 0.25, 0, 1 }
		tagText = BreakUpLargeNumbers(gold)
		button.rewardCategory = FILTER_GOLD
		button.rewardValue = gold
	end	

	local numQuestCurrencies = GetNumQuestLogRewardCurrencies(questID)
	if numQuestCurrencies > 0 then
		for currencyNum = 1, numQuestCurrencies do 
			local name, texture, numItems = GetQuestLogRewardCurrencyInfo(currencyNum, questID)
			if name ~= FILTER_NAMES[FILTER_WAR_SUPPLIES] and name ~= FILTER_NAMES[FILTER_NETHERSHARD] then
				tagText = numItems
				tagTexture = texture
				tagTexCoords = nil
				if name == FILTER_NAMES[FILTER_WAR_SUPPLIES] then
					button.rewardCategory = FILTER_WAR_SUPPLIES
				else
					button.rewardCategory = FILTER_ORDER_RESOURCES
				end
				button.rewardValue = numItems
			end
		end
	end

	local numQuestRewards = GetNumQuestLogRewards(questID)
	if numQuestRewards > 0 then
		local itemName, itemTexture, quantity, quality, isUsable, itemID = GetQuestLogRewardInfo(1, questID)
		if itemName and itemTexture then
			local artifactPower = nil--Addon.Data:ItemArtifactPower(itemID)
			local iLevel = Addon.Data:RewardItemLevel(itemID, questID)
			if artifactPower then
				tagTexture = "Interface\\Icons\\inv_7xp_inscription_talenttome01"
				tagTexCoords = nil
				tagText = ArtifactPowerTruncate(artifactPower)
				tagColor = BAG_ITEM_QUALITY_COLORS[LE_ITEM_QUALITY_ARTIFACT]
				button.rewardCategory = FILTER_ARTIFACT_POWER
				button.rewardValue = artifactPower
			else
				tagTexture = itemTexture
				tagTexCoords = nil
				if iLevel then
					tagText = iLevel
					tagColor = BAG_ITEM_QUALITY_COLORS[quality]
					button.rewardCategory = FILTER_LOOT
					button.rewardValue = iLevel
				else
					tagText = quantity > 1 and quantity
					button.rewardCategory = FILTER_ITEMS
					button.rewardValue = quantity
				end
			end
		end
	end

	if tagTexture and tagText then
		button.TagText:Show()
		button.TagText:SetText(tagText)
		button.TagText:SetTextColor(tagColor.r, tagColor.g, tagColor.b )
		button.TagTexture:Show()
		button.TagTexture:SetTexture(tagTexture)
	elseif tagTexture then
		button.TagText:Hide()
		button.TagText:SetText("")
		button.TagTexture:Show()
		button.TagTexture:SetTexture(tagTexture)
	end
	if tagTexture then
		if tagTexCoords then
			button.TagTexture:SetTexCoord( unpack(tagTexCoords) )
		else
			button.TagTexture:SetTexCoord( 0, 1, 0, 1 )
		end
	end

	button:SetHeight(totalHeight)
	-- button:ClearAllPoints()
	-- if prevButton then
	-- 	button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
	-- else
	-- 	button:SetPoint("TOPLEFT", 1, -6)
	-- end
	-- button.layoutIndex = QuestMapFrame:GetManagedLayoutIndex("AWQ")
	button:Show()

	return button
end

local function TaskPOI_IsFilteredReward(selectedFilters, questID)
	local positiveMatch = false

	local money = GetQuestLogRewardMoney(questID)
	if money > 0 and selectedFilters[FILTER_GOLD] then
		positiveMatch = true
	end	

	local numQuestCurrencies = GetNumQuestLogRewardCurrencies(questID)
	for i = 1, numQuestCurrencies do
		local name, texture, numItems = GetQuestLogRewardCurrencyInfo(i, questID)
		if name == FILTER_NAMES[FILTER_ORDER_RESOURCES] and selectedFilters[FILTER_ORDER_RESOURCES] then
			positiveMatch = true
		end
		if name == FILTER_NAMES[FILTER_WAR_SUPPLIES] and selectedFilters[FILTER_WAR_SUPPLIES] then
			positiveMatch = true
		end
		if name == FILTER_NAMES[FILTER_VEILED_ARGUNITE] and selectedFilters[FILTER_VEILED_ARGUNITE] then
			positiveMatch = true
		end
		if name == FILTER_NAMES[FILTER_NETHERSHARD] and selectedFilters[FILTER_NETHERSHARD] then
			positiveMatch = true
		end
	end

	local numQuestRewards = GetNumQuestLogRewards(questID)
	if numQuestRewards > 0 then
		local itemName, itemTexture, quantity, quality, isUsable, itemID = GetQuestLogRewardInfo(1, questID)
		if itemName and itemTexture then
			local artifactPower = nil--Addon.Data:ItemArtifactPower(itemID)
			local iLevel = Addon.Data:RewardItemLevel(itemID, questID)
			if artifactPower then
				if selectedFilters[FILTER_ARTIFACT_POWER] then
					positiveMatch = true
				end
			else
				if iLevel then
					local upgradesOnly = Config.filterLoot == FILTER_LOOT_UPGRADES or (Config.filterLoot == 0 and Config.lootFilterUpgrades)
					if selectedFilters[FILTER_LOOT] and (not upgradesOnly or Addon.Data:RewardIsUpgrade(itemID, questID)) then
						positiveMatch = true
					end
				else
					if selectedFilters[FILTER_ITEMS] then
						positiveMatch = true
					end
				end
			end
		end
	end

	if positiveMatch then
		return false
	elseif selectedFilters[FILTER_ORDER_RESOURCES] or selectedFilters[FILTER_WAR_SUPPLIES] or selectedFilters[FILTER_VEILED_ARGUNITE] or selectedFilters[FILTER_NETHERSHARD] or selectedFilters[FILTER_ARTIFACT_POWER] or selectedFilters[FILTER_LOOT] or selectedFilters[FILTER_ITEMS] then
		return true
	end
end

local function TaskPOI_IsFiltered(info)
	local hasFilters = Config:HasFilters()
	local selectedFilters = Config:GetFilterTable(FILTER_COUNT)

	local title, factionID, capped = C_TaskQuest.GetQuestInfoByQuestID(info.questId)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(info.questId)
	local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(info.questId)
	C_TaskQuest.RequestPreloadRewardData(info.questId)

	local isFiltered = hasFilters

	if hasFilters then
		local lootFiltered = TaskPOI_IsFilteredReward(selectedFilters, info.questId)
		if lootFiltered ~= nil then
			isFiltered = lootFiltered
		end
		
		if selectedFilters[FILTER_FACTION] then
			if (factionID == Config.filterFaction or Addon.Data:QuestHasFaction(info.questId, Config.filterFaction)) then
				isFiltered = false
			end
		end

		if selectedFilters[FILTER_TIME] then
			local hours = Config.filterTime ~= 0 and Config.filterTime or Config.timeFilterDuration
			if timeLeftMinutes and (timeLeftMinutes - WORLD_QUESTS_TIME_CRITICAL_MINUTES) <= (hours * 60) then
				isFiltered = false
			end
		end

		if selectedFilters[FILTER_PVP] then
			if worldQuestType == LE_QUEST_TAG_TYPE_PVP then
				isFiltered = false
			end
		end

		if selectedFilters[FILTER_PETBATTLE] then
			if worldQuestType == LE_QUEST_TAG_TYPE_PET_BATTLE then
				isFiltered = false
			end
		end

		if selectedFilters[FILTER_PROFESSION] then
			if tradeskillLineIndex then
				isFiltered = false
			end
		end

		if selectedFilters[FILTER_TRACKED] then
			if IsWorldQuestHardWatched(info.questId) or GetSuperTrackedQuestID() == info.questId then
				isFiltered = false
			end
		end

		if selectedFilters[FILTER_RARE] then
			if rarity ~= LE_WORLD_QUEST_QUALITY_COMMON then
				isFiltered = false
			end
		end

		if selectedFilters[FILTER_DUNGEON] then
			if worldQuestType == LE_QUEST_TAG_TYPE_DUNGEON or worldQuestType == LE_QUEST_TAG_TYPE_RAID then
				isFiltered = false
			end
		end

		if selectedFilters[FILTER_ZONE] then
			local currentMapID = GetMapAreaIDs()
			local filterMapID = Config.filterZone

			if filterMapID ~= 0 then
				if (info.mapID and info.mapID == filterMapID) or (not info.mapID and currentMapID == filterMapID) then
					isFiltered = false
				end
			else
				if (info.mapID and info.mapID == currentMapID) or not info.mapID or currentMapID == MAPID_BROKENISLES then
					isFiltered = false
				end
			end
		end

		if selectedFilters[FILTER_EMISSARY] then
			local bounties = GetQuestBountyInfoForMapID(MAPID_BROKENISLES)
			local bountyFilter = Config.filterEmissary
			if GetQuestLogIndexByID(bountyFilter) == 0 or IsQuestComplete(bountyFilter) then bountyFilter = 0 end
			for _, bounty in ipairs(bounties) do
				if bounty and not IsQuestComplete(bounty.questID) and IsQuestCriteriaForBounty(info.questId, bounty.questID) and (bountyFilter == 0 or bountyFilter == bounty.questID) then
					isFiltered = false
				end
			end
		end

	end

	return isFiltered
end

local function TaskPOI_Sorter(a, b)
	if Config.sortMethod == SORT_FACTION then
		if (a.factionID or 0) ~= (b.factionID or 0) then
			return (a.factionID or 0) < (b.factionID or 0)
		end
	elseif Config.sortMethod == SORT_TIME then
		if math.abs( (a.timeLeftMinutes or 0) - (b.timeLeftMinutes or 0) ) > 2 then
			return (a.timeLeftMinutes or 0) < (b.timeLeftMinutes or 0)
		end
	elseif Config.sortMethod == SORT_ZONE then
		if MAPID_ORDER[a.mapID] ~= MAPID_ORDER[b.mapID] then
			return MAPID_ORDER[a.mapID] < MAPID_ORDER[b.mapID]
		end
	elseif Config.sortMethod == SORT_REWARDS then
		local default_cat = FILTER_COUNT + 1
		local acat = (a.rewardCategory and REWARDS_ORDER[a.rewardCategory]) or default_cat
		local bcat = (b.rewardCategory and REWARDS_ORDER[b.rewardCategory]) or default_cat
		if acat ~= bcat then
			return acat < bcat
		elseif acat ~= default_cat and (a.rewardValue or 0) ~= (b.rewardValue or 0) then
			return (a.rewardValue or 0) > (b.rewardValue or 0)
		end
	end

	return a.Text:GetText() < b.Text:GetText()
end

local function QuestFrame_Update()
	titleFramePool:ReleaseAll()

	local mapID = QuestMapFrame:GetParent():GetMapID()

	local bounties, displayLocation, lockedQuestID = GetQuestBountyInfoForMapID(mapID)
	if (not Config.showEverywhere) and (not displayLocation or lockedQuestID) then
		for i = 1, #filterButtons do filterButtons[i]:Hide() end
		if spaceFrame then spacerFrame:Hide() end
		if headerButton then headerButton:Hide() end
		QuestScrollFrame.Contents:Layout()
		return
	end

	local questsCollapsed = Config.collapsed

	local button, firstButton, storyButton, prevButton

	local storyAchievementID, storyMapID = C_QuestLog.GetZoneStoryInfo(mapID)
	if storyAchievementID then
		storyButton = QuestScrollFrame.Contents.StoryHeader
	end

	for header in QuestScrollFrame.headerFramePool:EnumerateActive() do
		if header.questLogIndex == 1 then
			firstButton = header
		end
	end
	QuestScrollFrame.Background:SetAtlas("QuestLogBackground", true) -- Always show quest background

	if not headerButton then
		headerButton = CreateFrame("BUTTON", nil, QuestMapFrame.QuestsFrame.Contents, "QuestLogHeaderTemplate")
		headerButton:SetScript("OnClick", HeaderButton_OnClick)
		headerButton:SetText(TRACKER_HEADER_WORLD_QUESTS)
		headerButton:SetHitRectInsets(0, -headerButton.ButtonText:GetWidth(), 0, 0)
		headerButton:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
	end
	if (questsCollapsed) then
		headerButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
	else
		headerButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
	end
	headerButton:ClearAllPoints()
	if storyButton then
		headerButton:SetPoint("TOPLEFT", storyButton, "BOTTOMLEFT", 0, 0)
	else
		headerButton:SetPoint("TOPLEFT", 1, -6)
	end
	headerButton.layoutIndex = QuestMapFrame:GetManagedLayoutIndex("AWQ")
	headerButton:Show()
	prevButton = headerButton

	local displayedQuestIDs = {}
	local usedButtons = {}
	local filtersOwnRow = false

	if questsCollapsed then
		for i = 1, #filterButtons do filterButtons[i]:Hide() end
	else
		local hasFilters = Config:HasFilters()
		local selectedFilters = Config:GetFilterTable(FILTER_COUNT)

		local enabledCount = 0
		for i=#FILTER_ORDER, 1, -1 do
			if not Config:GetFilterDisabled(FILTER_ORDER[i]) then enabledCount = enabledCount + 1 end
		end

		local prevFilter

		for j=1, #FILTER_ORDER, 1 do
			local i = j
			if not filtersOwnRow then i = #FILTER_ORDER - i + 1 end
			local filterButton = GetFilterButton(FILTER_ORDER[i])
			filterButton:SetFrameLevel(50 + i)
			if Config:GetFilterDisabled(FILTER_ORDER[i]) then
				filterButton:Hide()
			else
				filterButton:Show()

				filterButton:ClearAllPoints()
				if prevFilter then
					filterButton:SetPoint("RIGHT", prevFilter, "LEFT", 5, 0)
					filterButton:SetPoint("TOP", prevButton, "TOP", 0, 3)
				else
					filterButton:SetPoint("RIGHT", 1, 0)
					filterButton:SetPoint("TOP", prevButton, "TOP", 0, 3)
				end

				if FILTER_ORDER[i] ~= FILTER_SORT then
					if selectedFilters[FILTER_ORDER[i]] then
						filterButton:SetNormalAtlas("worldquest-tracker-ring-selected")
					else
						filterButton:SetNormalAtlas("worldquest-tracker-ring")
					end
				end
				prevFilter = filterButton
			end
		end

		local displayMapIDs = GetMapIDsForDisplay(mapID)
		for _, mapID in ipairs(displayMapIDs) do
			local taskInfo = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)

			if taskInfo then
				for i, info in ipairs(taskInfo) do
					if HaveQuestData(info.questId) and QuestUtils_IsQuestWorldQuest(info.questId) then
						if WorldMap_DoesWorldQuestInfoPassFilters(info) and (info.mapID == mapID or MAPID_CONTINENTS[mapID]) then
							local isFiltered = TaskPOI_IsFiltered(info)
							if not isFiltered then
								local button = QuestFrame_AddQuestButton(info)
								table.insert(usedButtons, button)
							end
						end
					end
				end
			end
		end

		table.sort(usedButtons, TaskPOI_Sorter)
		for i, button in ipairs(usedButtons) do
			button.layoutIndex = QuestMapFrame:GetManagedLayoutIndex("AWQ")
			button:Show()
			prevButton = button
			
			if hoveredQuestID == button.questID then
				TitleButton_OnEnter(button)
			end
		end
	end

	if not spacerFrame then
		spacerFrame = CreateFrame("FRAME", nil, QuestMapFrame.QuestsFrame.Contents)
		spacerFrame:SetHeight(6)
	end
	if #usedButtons > 0 then
		spacerFrame:Show()
		spacerFrame.layoutIndex = QuestMapFrame:GetManagedLayoutIndex("AWQ")
	else
		spacerFrame:Hide()
	end

	QuestScrollFrame.Contents:Layout()
end

local function WorldMap_WorldQuestDataProviderMixin_ShouldShowQuest(self, info)
	if self.focusedQuestID or self:IsQuestSuppressed(info.questId) then
		return false
	end
	local mapID = self:GetMap():GetMapID()

	if Config.showHoveredPOI and hoveredQuestID == info.questId then
		return true
	end

	if Config.hideFilteredPOI then
		if TaskPOI_IsFiltered(info) then
			return false
		end
	end
	if Config.hideUntrackedPOI then
		if not (IsWorldQuestHardWatched(info.questId) or GetSuperTrackedQuestID() == info.questId) then
			return false
		end
	end

	if Config.showContinentPOI and MAPID_CONTINENTS[mapID] then
		return MAPID_ZONES_CONTINENTS[info.mapID] and MAPID_ZONES_CONTINENTS[info.mapID] == mapID
	else
		return mapID == info.mapID
	end
end

function Mod:Blizzard_WorldMap()
	for dp,_ in pairs(WorldMapFrame.dataProviders) do
		if dp.AddWorldQuest then
			dataProvder = dp

			dataProvder.ShouldShowQuest = WorldMap_WorldQuestDataProviderMixin_ShouldShowQuest
		end
	end
end

local function OverrideLayoutManager()
	if Config.showAtTop then
		QuestMapFrame.layoutIndexManager:AddManagedLayoutIndex("AWQ", QUEST_LOG_STORY_LAYOUT_INDEX + 1)
		QuestMapFrame.layoutIndexManager.startingLayoutIndexes["Other"] = QUEST_LOG_STORY_LAYOUT_INDEX + 500 + 1
	else
		QuestMapFrame.layoutIndexManager:AddManagedLayoutIndex("Other", QUEST_LOG_STORY_LAYOUT_INDEX + 1)
		QuestMapFrame.layoutIndexManager.startingLayoutIndexes["AWQ"] = QUEST_LOG_STORY_LAYOUT_INDEX + 500 + 1
	end
end

function Mod:Startup()
	Config = Addon.Config

	self:RegisterAddOnLoaded("Blizzard_WorldMap")

	titleFramePool = CreateFramePool("BUTTON", QuestMapFrame.QuestsFrame.Contents, "QuestLogTitleTemplate")
	OverrideLayoutManager()

	hooksecurefunc("QuestLogQuests_Update", QuestFrame_Update)

	Config:RegisterCallback('showAtTop', function()
		OverrideLayoutManager()
		QuestMapFrame_UpdateAll()
	end)

	Config:RegisterCallback({'showEverywhere', 'hideUntrackedPOI', 'hideFilteredPOI', 'showContinentPOI', 'onlyCurrentZone', 'sortMethod', 'selectedFilters', 'disabledFilters', 'filterEmissary', 'filterLoot', 'filterFaction', 'filterZone', 'filterTime', 'lootFilterUpgrades', 'lootUpgradesLevel', 'timeFilterDuration'}, function() 
		QuestMapFrame_UpdateAll()
		dataProvder:RefreshAllData()
	end)
end