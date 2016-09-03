local ADDON, Addon = ...
local QF = Addon:NewModule('QuestFrame')
local Config

local MAPID_BROKENISLES = 1007
local MAPID_DALARAN = 1014
local MAPID_AZSUNA = 1015
local MAPID_STORMHEIM = 1017
local MAPID_VALSHARAH = 1018
local MAPID_HIGHMOUNTAIN = 1024
local MAPID_SURAMAR = 1033
local MAPID_ALL = { MAPID_SURAMAR, MAPID_AZSUNA, MAPID_VALSHARAH, MAPID_HIGHMOUNTAIN, MAPID_STORMHEIM, MAPID_DALARAN }
local MAPID_ORDER = { [MAPID_SURAMAR] = 1, [MAPID_AZSUNA] = 2, [MAPID_VALSHARAH] = 3, [MAPID_HIGHMOUNTAIN] = 4, [MAPID_STORMHEIM] = 5, [MAPID_DALARAN] = 6 }

local FILTER_COUNT = 7
local FILTER_ICONS = { "achievement_reputation_01", "inv_7xp_inscription_talenttome01", "inv_misc_lockboxghostiron", "inv_orderhall_orderresources", "inv_misc_coin_01", "inv_box_01", "ability_bossmagistrix_timewarp2" }
local FILTER_NAMES = { BOUNTY_BOARD_LOCKED_TITLE, ARTIFACT_POWER, BONUS_ROLL_REWARD_ITEM, "Order Resources", BONUS_ROLL_REWARD_MONEY, ITEMS, CLOSES_IN }
local FILTER_EMISSARY = 1
local FILTER_ARTIFACT_POWER = 2
local FILTER_LOOT = 3
local FILTER_ORDER_RESOURCES = 4
local FILTER_GOLD = 5
local FILTER_ITEMS = 6
local FILTER_TIME = 7
local FILTER_ORDER = { FILTER_EMISSARY, FILTER_TIME, FILTER_ARTIFACT_POWER, FILTER_LOOT, FILTER_ORDER_RESOURCES, FILTER_GOLD, FILTER_ITEMS }
QF.FilterNames = FILTER_NAMES
QF.FilterOrder = FILTER_ORDER

local SORT_NAME = 1
local SORT_TIME = 2
local SORT_ZONE = 3
local SORT_FACTION = 4
local SORT_ORDER = { SORT_NAME, SORT_TIME, SORT_ZONE, SORT_FACTION }
QF.SortOrder = SORT_ORDER

local FILTER_LOOT_ALL = 1
local FILTER_LOOT_UPGRADES = 2

local AWQ_POI_COUNT = 0
local myTaskPOI

local TitleButton_RarityColorTable = { [LE_WORLD_QUEST_QUALITY_COMMON] = 110, [LE_WORLD_QUEST_QUALITY_RARE] = 113, [LE_WORLD_QUEST_QUALITY_EPIC] = 120 }

-- ===================
--  Utility Functions
-- ===================

local function GetMapAreaIDs()
	local mapID = GetCurrentMapAreaID()
	local contIndex = 0
	local mapHeirarchy = GetMapHierarchy()
	for _, mapInfo in ipairs(mapHeirarchy) do
		if mapInfo['isContinent'] then
			contIndex = mapInfo['id']
		else
			mapID = mapInfo['id']
		end
	end
	local conts = { GetMapContinents() }
	local contID = conts[contIndex*2 - 1]
	if #mapHeirarchy == 0 then contID = mapID end
	if Config.showEverywhere and contID ~= MAPID_BROKENISLES then
		return MAPID_BROKENISLES, MAPID_BROKENISLES
	else
		return mapID, contID
	end
end

local function ArtifactPowerTruncate(power)
	if power >= 10000 then
		return floor(power / 1000) .. "k"
	elseif power >= 1000 then
		return (floor(power / 100) / 10) .. "k"
	else
		return power
	end
end

-- =================
--  Event Functions
-- =================

local function HeaderButton_OnClick(self, button)
	local questsCollapsed = Config.collapsed
	PlaySound("igMainMenuOptionCheckBoxOn")
	if ( button == "LeftButton" ) then
		questsCollapsed = not questsCollapsed
		Config:Set('collapsed', questsCollapsed)
		QuestMapFrame_UpdateAll()
	end
end

local function DisplayMyTaskPOI(self)
	if GetCurrentMapAreaID() == MAPID_BROKENISLES and Config.showHoveredPOI and not Config.showContinentPOI then
		local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
		local selected = self.questID == GetSuperTrackedQuestID()
		local isCriteria = WorldMapFrame.UIElementsFrame.BountyBoard:IsWorldQuestCriteriaForSelectedBounty(self.questID)
		local isSpellTarget = SpellCanTargetQuest() and IsQuestIDValidSpellTarget(self.questID)
		myTaskPOI.worldQuest = true
		myTaskPOI.Texture:SetDrawLayer("OVERLAY")
		WorldMap_SetupWorldQuestButton(myTaskPOI, worldQuestType, rarity, isElite, tradeskillLineIndex, self.inProgress, selected, isCriteria, isSpellTarget)
		WorldMapPOIFrame_AnchorPOI(myTaskPOI, self.infoX, self.infoY, WORLD_MAP_POI_FRAME_LEVEL_OFFSETS.WORLD_QUEST)
		myTaskPOI.questID = self.questID
		myTaskPOI.numObjectives = self.numObjectives
		myTaskPOI:Show()
	else
		myTaskPOI:Hide()
	end
end

local function TitleButton_OnEnter(self)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
	local _, color = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )
	self.Text:SetTextColor( color.r, color.g, color.b )

	for i = 1, NUM_WORLDMAP_TASK_POIS do
		local mapButton = _G["WorldMapFrameTaskPOI"..i]
		if mapButton and mapButton.wasShown and mapButton.worldQuest and mapButton.questID == self.questID then
			if Config.hideUntrackedPOI then
				if Config.showHoveredPOI and not (IsWorldQuestHardWatched(self.questID) or GetSuperTrackedQuestID() == self.questID) then
					mapButton:Show()
				else
					mapButton:LockHighlight()
				end
			else
				mapButton:LockHighlight()
			end
		end
	end
	for i = 1, AWQ_POI_COUNT do
		local mapButton = _G["WorldMapFrameTaskPOIAWQ"..i]
		if mapButton and mapButton.wasShown and mapButton.worldQuest and mapButton.questID == self.questID then
			if Config.hideUntrackedPOI then
				if Config.showHoveredPOI and not (IsWorldQuestHardWatched(self.questID) or GetSuperTrackedQuestID() == self.questID) then
					mapButton:Show()
				else
					mapButton:LockHighlight()
				end
			else
				mapButton:LockHighlight()
			end
		end
	end

	DisplayMyTaskPOI(self)
	
	if Config.showComparisonRight then
		WorldMapTooltip.ItemTooltip.Tooltip.overrideComparisonAnchorSide = "right"
	end
	TaskPOI_OnEnter(self)
end

local function TitleButton_OnLeave(self)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
	local color = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )
	self.Text:SetTextColor( color.r, color.g, color.b )

	for i = 1, NUM_WORLDMAP_TASK_POIS do
		local mapButton = _G["WorldMapFrameTaskPOI"..i]
		if mapButton and mapButton.wasShown and mapButton.worldQuest and mapButton.questID == self.questID then
			mapButton:UnlockHighlight()
			if Config.hideUntrackedPOI then
				mapButton:SetShown( IsWorldQuestHardWatched(self.questID) or GetSuperTrackedQuestID() == self.questID )
			end
		end
	end
	for i = 1, AWQ_POI_COUNT do
		local mapButton = _G["WorldMapFrameTaskPOIAWQ"..i]
		if mapButton and mapButton.wasShown and mapButton.worldQuest and mapButton.questID == self.questID then
			mapButton:UnlockHighlight()
			if Config.hideUntrackedPOI then
				mapButton:SetShown( IsWorldQuestHardWatched(self.questID) or GetSuperTrackedQuestID() == self.questID )
			end
		end
	end

	myTaskPOI:Hide()

	TaskPOI_OnLeave(self)
end

local function TitleButton_OnClick(self, button)
	if SpellCanTargetQuest() then
		if IsQuestIDValidSpellTarget(self.questID) then
			UseWorldMapActionButtonSpellOnQuest(self.questID)
			-- Assume success for responsiveness
			WorldMap_OnWorldQuestCompletedBySpell(self.questID)
		else
			UIErrorsFrame:AddMessage(WORLD_QUEST_CANT_COMPLETE_BY_SPELL, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
		end
	else
		PlaySound("igMainMenuOptionCheckBoxOn")
		if IsModifiedClick("CHATLINK") and ChatEdit_GetActiveWindow() then
			local title, factionID, capped = C_TaskQuest.GetQuestInfoByQuestID(self.questID)
			-- ChatEdit_InsertLink( string.format("|cffffff00|Hquest:%d:110|h[%s]|h|r", self.questID, title) )
			ChatEdit_InsertLink( string.format("[%s]", title) )
		elseif ( button == "RightButton" ) then
			if ( self.mapID ) then
				SetMapByID(self.mapID)
			end
		else
			if IsShiftKeyDown() then
				if IsWorldQuestHardWatched(self.questID) or (IsWorldQuestWatched(self.questID) and GetSuperTrackedQuestID() == self.questID) then
					BonusObjectiveTracker_UntrackWorldQuest(self.questID)
				else
					BonusObjectiveTracker_TrackWorldQuest(self.questID, true)
				end
			else
				if IsWorldQuestHardWatched(self.questID) then
					SetSuperTrackedQuestID(self.questID)
				else
					BonusObjectiveTracker_TrackWorldQuest(self.questID)
				end
			end
			DisplayMyTaskPOI(self)
		end
	end
end

local function FilterButton_OnEnter(self)
	local text = FILTER_NAMES[ self.index ]
	if self.index == FILTER_EMISSARY and Config.filterEmissary then
		local title = GetQuestLogTitle(GetQuestLogIndexByID(Config.filterEmissary))
		if title then text = text..": "..title end
	end
	if self.index == FILTER_LOOT then
		if Config.filterLoot == FILTER_LOOT_UPGRADES or (Config.filterLoot == 0 and Config.lootFilterUpgrades) then
			text = string.format("%s (%s)", text, Addon.Locale.UPGRADES)
		end
	end
	if self.index == FILTER_TIME then
		text = string.format(BLACK_MARKET_HOT_ITEM_TIME_LEFT, string.format(FORMATED_HOURS, Config.timeFilterDuration))
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
	if IsShiftKeyDown() then
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
		UIDropDownMenu_AddButton(info, level)

		local currentMapID, continentMapID = GetMapAreaIDs()
		local bounties = GetQuestBountyInfoForMapID(currentMapID)
		for _, bounty in ipairs(bounties) do
			info.text =  GetQuestLogTitle(GetQuestLogIndexByID(bounty.questID))
			info.icon = bounty.icon
			info.value = bounty.questID
			info.checked = info.value == value
			UIDropDownMenu_AddButton(info, level)
		end
	elseif self.index == FILTER_LOOT then
		local value = Config.filterLoot
		if value == 0 then value = Config.lootFilterUpgrades and FILTER_LOOT_UPGRADES or FILTER_LOOT_ALL end

		info.text = ALL
		info.value = FILTER_LOOT_ALL
		info.checked = info.value == value
		UIDropDownMenu_AddButton(info, level)

		info.text = Addon.Locale.UPGRADES
		info.value = FILTER_LOOT_UPGRADES
		info.checked = info.value == value
		UIDropDownMenu_AddButton(info, level)
	end
end

local function FilterButton_ShowMenu(self)
	if not filterMenu then
		filterMenu = CreateFrame("Button", "DropDownMenuTest", QuestMapFrame, "UIDropDownMenuTemplate")
	end

	filterMenu.index = self.index
	UIDropDownMenu_Initialize(filterMenu, FilterMenu_Initialize, "MENU")
	ToggleDropDownMenu(1, nil, filterMenu, self, 0, 0)
end

local function FilterButton_OnClick(self, button)
	HideDropDownMenu(1)
	PlaySound("igMainMenuOptionCheckBoxOn")
	if button == 'RightButton' and (self.index == FILTER_EMISSARY or self.index == FILTER_LOOT) then
		FilterButton_ShowMenu(self)
	else
		if IsShiftKeyDown() then
			if self.index == FILTER_EMISSARY then Config:Set('filterEmissary', 0, true) end
			if self.index == FILTER_LOOT then Config:Set('filterLoot', 0, true) end
			Config:ToggleFilter(self.index)
		else
			Config:Set('filterEmissary', 0, true)
			Config:Set('filterLoot', 0, true)
			if Config:IsOnlyFilter(self.index) then
				Config:SetNoFilter()
			else
				Config:SetOnlyFilter(self.index)
			end
		end
		FilterButton_OnEnter(self)
	end
end

local headerButtons = {}
local function GetHeaderButton(index)
	if ( not headerButtons[index] ) then
		local header = CreateFrame("BUTTON", nil, QuestMapFrame.QuestsFrame.Contents, "QuestLogHeaderTemplate")
		header:SetScript("OnClick", HeaderButton_OnClick)
		headerButtons[index] = header
	end
	return headerButtons[index]
end

local titleButtons = {}
local function GetTitleButton(index)
	if ( not titleButtons[index] ) then
		local title = CreateFrame("BUTTON", nil, QuestMapFrame.QuestsFrame.Contents, "QuestLogTitleTemplate")
		title:SetScript("OnEnter", TitleButton_OnEnter)
		title:SetScript("OnLeave", TitleButton_OnLeave)
		title:SetScript("OnClick", TitleButton_OnClick)

		title.TagTexture:SetSize(16, 16)
		title.TagTexture:ClearAllPoints()
		title.TagTexture:SetPoint("TOP", title.Text, "CENTER", 0, 8)
		title.TagTexture:SetPoint("RIGHT", 0, 0)

		title.TagText = title:CreateFontString(nil, nil, "GameFontNormalLeft")
		title.TagText:SetTextColor(1, 1, 1)
		title.TagText:SetPoint("RIGHT", title.TagTexture , "LEFT", -3, 0)
		title.TagText:Hide()

		title.TaskIcon:ClearAllPoints()
		title.TaskIcon:SetPoint("CENTER", title.Text, "LEFT", -15, 0)

		title.TimeIcon = title:CreateTexture(nil, "OVERLAY")
		title.TimeIcon:SetAtlas("worldquest-icon-clock")

		title.UpdateTooltip = TaskPOI_OnEnter

		titleButtons[index] = title
	end
	return titleButtons[index]
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
		button:SetNormalAtlas("worldquest-tracker-ring")
		button:SetHighlightAtlas("worldquest-tracker-ring")
		button:GetHighlightTexture():SetAlpha(0.4)

		local icon = button:CreateTexture(nil, "BACKGROUND", nil, -1)
		icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		icon:SetSize(16, 16)
		icon:SetPoint("CENTER", 0, 1)
		icon:SetTexture("Interface\\Icons\\"..(FILTER_ICONS[index] or "inv_misc_questionmark"))
		button.Icon = icon

		filterButtons[index] = button
	end
	return filterButtons[index]
end

local function TaskPOI_IsFiltered(self, bounties, hasFilters, selectedFilters)
	if bounties == nil then
		local currentMapID, continentMapID = GetMapAreaIDs()
		bounties = GetQuestBountyInfoForMapID(currentMapID)
	end
	if hasFilters == nil then
		hasFilters = Config:HasFilters()
		if Config.selectedFilters == FILTER_EMISSARY then hasFilters = false end
	end
	if selectedFilters == nil then
		selectedFilters = Config:GetFilterTable(FILTER_COUNT)
	end

	local title, factionID, capped = C_TaskQuest.GetQuestInfoByQuestID(self.questID)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
	local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(self.questID)
	C_TaskQuest.RequestPreloadRewardData(self.questID)

	local isFiltered = hasFilters

	if hasFilters then
		local money = GetQuestLogRewardMoney(self.questID)
		if ( money > 0 ) then
			isFiltered = not selectedFilters[FILTER_GOLD]
		end	

		local numQuestCurrencies = GetNumQuestLogRewardCurrencies(self.questID)
		for i = 1, numQuestCurrencies do
			local name, texture, numItems = GetQuestLogRewardCurrencyInfo(i, self.questID)
			if name == FILTER_NAMES[FILTER_ORDER_RESOURCES] then
				isFiltered = not selectedFilters[FILTER_ORDER_RESOURCES]
			end
		end

		local numQuestRewards = GetNumQuestLogRewards(self.questID)
		if numQuestRewards > 0 then
			local itemName, itemTexture, quantity, quality, isUsable, itemID = GetQuestLogRewardInfo(1, self.questID)
			if itemName and itemTexture then
				local artifactPower = Addon.Data:ItemArtifactPower(itemID)
				local iLevel = Addon.Data:RewardItemLevel(self.questID)
				if artifactPower then
					isFiltered = hasFilters and not selectedFilters[FILTER_ARTIFACT_POWER]
				else
					if iLevel then
						local upgradesOnly = Config.filterLoot == FILTER_LOOT_UPGRADES or (Config.filterLoot == 0 and Config.lootFilterUpgrades)
						isFiltered = not selectedFilters[FILTER_LOOT] or (upgradesOnly and not Addon.Data:RewardIsUpgrade(self.questID))
					else
						isFiltered = not selectedFilters[FILTER_ITEMS]
					end
				end
			end
		end

		if selectedFilters[FILTER_TIME] then
			if timeLeftMinutes and timeLeftMinutes <= (Config.timeFilterDuration * 60) then
				isFiltered = false
			end
		end
	end

	if selectedFilters[FILTER_EMISSARY] and not isFiltered then
		local isBounty = false
		local bountyFilter = Config.filterEmissary
		if GetQuestLogIndexByID(bountyFilter) == 0 then bountyFilter = 0 end
		for _, bounty in ipairs(bounties) do
			if bounty and IsQuestCriteriaForBounty(self.questID, bounty.questID) and (bountyFilter == 0 or bountyFilter == bounty.questID) then
				isBounty = true
			end
		end
		if not isBounty then isFiltered = true end
	end

	return isFiltered
end

local function TaskPOI_Sorter(a, b)
	if Config.sortMethod == SORT_FACTION then
		if (a.factionID or 0) ~= (b.factionID or 0) then
			return (a.factionID or 0) < (b.factionID or 0)
		end
	elseif Config.sortMethod == SORT_TIME then
		if a.timeLeftMinutes ~= b.timeLeftMinutes then
			return a.timeLeftMinutes < b.timeLeftMinutes
		end
	elseif Config.sortMethod == SORT_ZONE then
		if MAPID_ORDER[a.mapID] ~= MAPID_ORDER[b.mapID] then
			return MAPID_ORDER[a.mapID] < MAPID_ORDER[b.mapID]
		end
	end

	return a.Text:GetText() < b.Text:GetText()
end

local function QuestFrame_Update()
	if not WorldMapFrame:IsShown() then return end

	myTaskPOI:Hide()
	local currentMapID, continentMapID = GetMapAreaIDs()
	local bounties, displayLocation, lockedQuestID = GetQuestBountyInfoForMapID(currentMapID)
	if not displayLocation or lockedQuestID then
		for i = 1, #headerButtons do headerButtons[i]:Hide() end
		for i = 1, #titleButtons do titleButtons[i]:Hide() end
		for i = 1, #filterButtons do filterButtons[i]:Hide() end
		return
	end

	local hoveredQuest
	for _, titleButton in ipairs(titleButtons) do
		if titleButton:IsMouseOver() and titleButton:IsShown() then
			hoveredQuest = titleButton.questID
		end
	end

	local questsCollapsed = Config.collapsed

	local numEntries, numQuests = GetNumQuestLogEntries()

	local headerIndex, titleIndex = 0, 0
	local i, firstButton, prevButton, storyButton, headerShown, headerCollapsed
	local storyID, storyMapID = GetZoneStoryID()
	if ( storyID ) then
		storyButton = QuestScrollFrame.Contents.StoryHeader
		prevButton = storyButton
	end
	for i = 1, numEntries do
		local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isBounty, isStory = GetQuestLogTitle(i)
		if isHeader then
			headerShown = false
			headerCollapsed = isCollapsed
		elseif ( not isTask and (not isBounty or IsQuestComplete(questID))) then
			if ( not headerShown ) then
				headerShown = true
				headerIndex = headerIndex + 1
				prevButton = QuestLogQuests_GetHeaderButton(headerIndex)
				if not firstButton then firstButton = prevButton end
			end
			if (not headerCollapsed) then
				titleIndex = titleIndex + 1
				prevButton = QuestLogQuests_GetTitleButton(titleIndex)
			end
		end
	end

	QuestScrollFrame.Background:SetAtlas("QuestLogBackground", true) -- Always show quest background

	local headerIndex = 0
	local titleIndex = 0

	headerIndex = headerIndex + 1
	local button = GetHeaderButton(headerIndex)
	button:SetText(TRACKER_HEADER_WORLD_QUESTS)
	button:SetHitRectInsets(0, -button.ButtonText:GetWidth(), 0, 0)
	if (questsCollapsed) then
		button:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
	else
		button:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
	end
	button:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
	button:ClearAllPoints()
	if ( prevButton and not Config.showAtTop ) then
		button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
	elseif storyButton then
		button:SetPoint("TOPLEFT", storyButton, "BOTTOMLEFT", 0, 0)
	else
		button:SetPoint("TOPLEFT", 1, -6)
	end
	button:Show()
	prevButton = button

	if (not questsCollapsed) then
		local hasFilters = Config:HasFilters()
		if Config.selectedFilters == FILTER_EMISSARY then hasFilters = false end
		local selectedFilters = Config:GetFilterTable(FILTER_COUNT)

		local prevFilter
		for i=#FILTER_ORDER, 1, -1 do
			local filterButton = GetFilterButton(FILTER_ORDER[i])
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

				if selectedFilters[FILTER_ORDER[i]] then
					filterButton:SetNormalAtlas("worldquest-tracker-ring-selected")
				else
					filterButton:SetNormalAtlas("worldquest-tracker-ring")
				end
				prevFilter = filterButton
			end
		end

		local questMapIDs = { currentMapID }
		if currentMapID == MAPID_BROKENISLES or (not Config.onlyCurrentZone and continentMapID == MAPID_BROKENISLES) then
			questMapIDs = MAPID_ALL
		end

		local usedButtons = {}

		for _, mapID in ipairs(questMapIDs) do

			local questsList = C_TaskQuest.GetQuestsForPlayerByMapID(mapID, continentMapID)
			if (questsList and #questsList > 0) then
				for i, questInfo in ipairs(questsList) do
					local questID = questInfo.questId
					if (HaveQuestData (questID)) then

						local isWorldQuest = QuestMapFrame_IsQuestWorldQuest(questID)
						local passFilters = WorldMap_DoesWorldQuestInfoPassFilters(questInfo)
						local isSuppressed = WorldMap_IsWorldQuestSuppressed(questID)

						if isWorldQuest and passFilters and not isSuppressed then

							local title, factionID, capped = C_TaskQuest.GetQuestInfoByQuestID(questID)
							local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(questID)
							local tradeskillLineID = tradeskillLineIndex and select(7, GetProfessionInfo(tradeskillLineIndex))
							local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
							C_TaskQuest.RequestPreloadRewardData(questID)

							local totalHeight = 8
							titleIndex = titleIndex + 1
							local button = GetTitleButton(titleIndex)
							button.worldQuest = true
							button.questID = questID
							button.mapID = mapID
							button.factionID = factionID
							button.timeLeftMinutes = timeLeftMinutes
							button.numObjectives = questInfo.numObjectives
							button.infoX = questInfo.x
							button.infoY = questInfo.y

							local color = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )
							button.Text:SetTextColor( color.r, color.g, color.b )

							button.Text:SetText(title)
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
							elseif ( worldQuestType == LE_QUEST_TAG_TYPE_PROFESSION and WORLD_QUEST_ICONS_BY_PROFESSION[tradeskillLineID] ) then
								button.TaskIcon:SetAtlas(WORLD_QUEST_ICONS_BY_PROFESSION[tradeskillLineID], true)
							elseif isElite then
								local tagCoords = QUEST_TAG_TCOORDS[QUEST_TAG_HEROIC]
								button.TaskIcon:SetSize(16, 16)
								button.TaskIcon:SetTexture("Interface\\QuestFrame\\QuestTypeIcons")
								button.TaskIcon:SetTexCoord( unpack(tagCoords) )
							else
								hasIcon = false
								button.TaskIcon:Hide()
							end


							if ( timeLeftMinutes and timeLeftMinutes <= WORLD_QUESTS_TIME_LOW_MINUTES ) then
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
							end	

							local numQuestCurrencies = GetNumQuestLogRewardCurrencies(questID)
							for i = 1, numQuestCurrencies do
								local name, texture, numItems = GetQuestLogRewardCurrencyInfo(i, questID)
								tagText = numItems
								tagTexture = texture
							end

							local numQuestRewards = GetNumQuestLogRewards(questID);
							if numQuestRewards > 0 then
								local itemName, itemTexture, quantity, quality, isUsable, itemID = GetQuestLogRewardInfo(1, questID)
								if itemName and itemTexture then
									local artifactPower = Addon.Data:ItemArtifactPower(itemID)
									local iLevel = Addon.Data:RewardItemLevel(questID)
									if artifactPower then
										tagTexture = "Interface\\Icons\\inv_7xp_inscription_talenttome01"
										tagText = ArtifactPowerTruncate(artifactPower)
										tagColor = BAG_ITEM_QUALITY_COLORS[LE_ITEM_QUALITY_ARTIFACT]
									else
										tagTexture = itemTexture
										if iLevel then
											tagText = iLevel
											tagColor = BAG_ITEM_QUALITY_COLORS[quality]
										else
											tagText = quantity > 1 and quantity
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
							else
								button.TagText:Hide()
								button.TagTexture:Hide()
							end
							if tagTexCoords then
								button.TagTexture:SetTexCoord( unpack(tagTexCoords) )
							else
								button.TagTexture:SetTexCoord( 0, 1, 0, 1 )
							end

							local isFiltered = TaskPOI_IsFiltered(button, bounties, hasFilters, selectedFilters)

							if not isFiltered then
								button:SetHeight(totalHeight)
								button:ClearAllPoints()

								table.insert(usedButtons, button)

								if hoveredQuest == button.questID then
									DisplayMyTaskPOI(button)
								end
							else
								titleIndex = titleIndex - 1
							end

						end

					end
				end
			end

		end

		table.sort(usedButtons, TaskPOI_Sorter)

		for _, button in ipairs(usedButtons) do
			button:Show()
			if ( prevButton ) then
				button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
			else
				button:SetPoint("TOPLEFT", 1, -6)
			end
			prevButton = button
		end

	else
		for i = 1, #filterButtons do filterButtons[i]:Hide() end
	end

	if Config.showAtTop and firstButton then
		firstButton:ClearAllPoints()
		if titleIndex > 0 then
			firstButton:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, -6)
		else
			firstButton:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
		end
	end

	for i = headerIndex + 1, #headerButtons do
		headerButtons[i]:Hide()
	end
	for i = titleIndex + 1, #titleButtons do
		titleButtons[i]:Hide()
	end
	
end

local function MapFrame_Update()
	if not WorldMapFrame:IsVisible() then return end

	local hoveredQuest
	for _, titleButton in ipairs(titleButtons) do
		if titleButton:IsMouseOver() and titleButton:IsShown() then
			hoveredQuest = titleButton.questID
		end
	end

	local mapAreaID = GetCurrentMapAreaID()

	if mapAreaID == MAPID_BROKENISLES and Config.showContinentPOI then
		local taskIconIndex  = 1
		for _, mapID in ipairs(MAPID_ALL) do
			local questsList = C_TaskQuest.GetQuestsForPlayerByMapID(mapID, continentMapID)
			if (questsList and #questsList > 0) then
				for i, info in ipairs(questsList) do
					if ( HaveQuestData(info.questId) ) then
						local isWorldQuest = QuestMapFrame_IsQuestWorldQuest(info.questId);
						if isWorldQuest then
							local taskPOI = WorldMap_TryCreatingWorldQuestPOI(info, "AWQ"..taskIconIndex)

							if ( taskPOI ) then
								WorldMapPOIFrame_AnchorPOI(taskPOI, info.x, info.y, WORLD_MAP_POI_FRAME_LEVEL_OFFSETS.WORLD_QUEST)
								taskPOI.questID = info.questId
								taskPOI.wasShown = true
								taskPOI.numObjectives = info.numObjectives
								taskPOI:Show()
								taskIconIndex = taskIconIndex + 1
							end

						end
					end
				end
			end
		end

		for i = taskIconIndex, AWQ_POI_COUNT do
			_G["WorldMapFrameTaskPOIAWQ"..i]:Hide()
			_G["WorldMapFrameTaskPOIAWQ"..i].wasShown = false
		end
		if taskIconIndex-1 > AWQ_POI_COUNT then
			AWQ_POI_COUNT = taskIconIndex - 1
		end
	else
		for i = 1, AWQ_POI_COUNT do
			_G["WorldMapFrameTaskPOIAWQ"..i]:Hide()
			_G["WorldMapFrameTaskPOIAWQ"..i].wasShown = false
		end
	end

	for i = 1, NUM_WORLDMAP_TASK_POIS do
		local taskPOI = _G["WorldMapFrameTaskPOI"..i]
		taskPOI:SetShown( taskPOI.wasShown )
	end

	if Config.hideUntrackedPOI then
		for i = 1, NUM_WORLDMAP_TASK_POIS do
			local taskPOI = _G["WorldMapFrameTaskPOI"..i]
			if taskPOI.worldQuest and taskPOI:IsShown() and not (IsWorldQuestHardWatched(taskPOI.questID) or GetSuperTrackedQuestID() == taskPOI.questID) then
				taskPOI:Hide()
			end
		end
		for i = 1, AWQ_POI_COUNT do
			local taskPOI = _G["WorldMapFrameTaskPOIAWQ"..i]
			if taskPOI.worldQuest and taskPOI:IsShown() and not (IsWorldQuestHardWatched(taskPOI.questID) or GetSuperTrackedQuestID() == taskPOI.questID) then
				taskPOI:Hide()
			end
		end
	end
	if Config.hideFilteredPOI then
		local bounties = GetQuestBountyInfoForMapID(GetCurrentMapAreaID())
		local hasFilters = Config:HasFilters()
		if Config.selectedFilters == FILTER_EMISSARY then hasFilters = false end
		local selectedFilters = Config:GetFilterTable(FILTER_COUNT)

		for i = 1, NUM_WORLDMAP_TASK_POIS do
			local taskPOI = _G["WorldMapFrameTaskPOI"..i]
			if taskPOI.worldQuest and taskPOI:IsShown() and TaskPOI_IsFiltered(taskPOI, bounties, hasFilters, selectedFilters) then
				taskPOI:Hide()
			end
		end
		for i = 1, AWQ_POI_COUNT do
			local taskPOI = _G["WorldMapFrameTaskPOIAWQ"..i]
			if taskPOI.worldQuest and taskPOI:IsShown() and TaskPOI_IsFiltered(taskPOI, bounties, hasFilters, selectedFilters) then
				taskPOI:Hide()
			end
		end
	end

	if Config.showHoveredPOI then
		for i = 1, AWQ_POI_COUNT do
			local taskPOI = _G["WorldMapFrameTaskPOIAWQ"..i]
			if taskPOI.wasShown and taskPOI.questID == hoveredQuest then
				taskPOI:Show()
			end
		end
	end

end

local function UpdateQuestBonusObjectives()
	for i = 1, NUM_WORLDMAP_TASK_POIS do
		local taskPOI = _G["WorldMapFrameTaskPOI"..i]
		taskPOI.wasShown = taskPOI:IsShown()
	end
	MapFrame_Update()
end

function QF:UNIT_INVENTORY_CHANGED(unit)
	if (Config.filterLoot == FILTER_LOOT_UPGRADES or (Config.filterLoot == 0 and Config.lootFilterUpgrades)) and unit == "player" then
		QuestFrame_Update() 
		if Config.hideFilteredPOI and WorldMapFrame:IsVisible() then
			WorldMap_UpdateQuestBonusObjectives()
			MapFrame_Update()
		end
	end
end

function QF:FrameUpdate()
	QuestFrame_Update()
	MapFrame_Update()
end

function QF:Startup()
	Config = Addon.Config

	FILTER_NAMES[FILTER_ORDER_RESOURCES] = select(1, GetCurrencyInfo(1220)) -- Add in localized name of Order Resources

	self:RegisterEvent("QUEST_WATCH_LIST_CHANGED", "FrameUpdate")
	self:RegisterEvent("SUPER_TRACKED_QUEST_CHANGED", "FrameUpdate")
	self:RegisterEvent("UNIT_INVENTORY_CHANGED")

	Config:RegisterCallback({'showAtTop', 'showEverywhere'}, function() QuestMapFrame_UpdateAll(); QuestFrame_Update() end)
	Config:RegisterCallback({'hideUntrackedPOI', 'hideFilteredPOI', 'showContinentPOI'}, function() WorldMap_UpdateQuestBonusObjectives(); MapFrame_Update() end)
	Config:RegisterCallback({'onlyCurrentZone', 'sortMethod'}, QuestFrame_Update)
	Config:RegisterCallback({'selectedFilters', 'disabledFilters', 'filterEmissary', 'filterLoot', 'lootFilterUpgrades', 'timeFilterDuration'}, function() 
		QuestFrame_Update()
		if Config.hideFilteredPOI and WorldMapFrame:IsShown() then
			WorldMap_UpdateQuestBonusObjectives()
			MapFrame_Update()
		end
	end)

	hooksecurefunc("QuestLogQuests_Update", QuestFrame_Update)
	hooksecurefunc("WorldMapTrackingOptionsDropDown_OnClick", QuestFrame_Update)
	hooksecurefunc("WorldMap_UpdateQuestBonusObjectives", UpdateQuestBonusObjectives)

	myTaskPOI = WorldMap_GetOrCreateTaskPOI("AWQ0")
	myTaskPOI:Hide()
end
