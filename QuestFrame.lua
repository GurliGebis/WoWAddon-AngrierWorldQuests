local ADDON, Addon = ...
local QF = Addon:NewModule('QuestFrame')

local MAPID_BROKENISLES = 1007
local MAPID_DALARAN = 1014
local MAPID_AZSUNA = 1015
local MAPID_STORMHEIM = 1017
local MAPID_VALSHARAH = 1018
local MAPID_HIGHMOUNTAIN = 1024
local MAPID_SURAMAR = 1033
local MAPID_ALL = { MAPID_DALARAN, MAPID_AZSUNA, MAPID_STORMHEIM, MAPID_VALSHARAH, MAPID_HIGHMOUNTAIN, MAPID_SURAMAR }

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

local myTaskPOI

local TitleButton_RarityColorTable = { [LE_WORLD_QUEST_QUALITY_COMMON] = 110, [LE_WORLD_QUEST_QUALITY_RARE] = 113, [LE_WORLD_QUEST_QUALITY_EPIC] = 120 }

local function HeaderButton_OnClick(self, button)
	local questsCollapsed = Addon.Config.collapsed
	PlaySound("igMainMenuOptionCheckBoxOn")
	if ( button == "LeftButton" ) then
		questsCollapsed = not questsCollapsed
		Addon.Config:Set('collapsed', questsCollapsed)
		QuestMapFrame_UpdateAll()
	end
end

local function DisplayMyTaskPOI(self)
	if GetCurrentMapAreaID() == MAPID_BROKENISLES and Addon.Config.showContinentPOI then
		local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
		local selected = self.questID == GetSuperTrackedQuestID()
		local isCriteria = WorldMapFrame.UIElementsFrame.BountyBoard:IsWorldQuestCriteriaForSelectedBounty(self.questID)
		local isSpellTarget = SpellCanTargetQuest() and IsQuestIDValidSpellTarget(self.questID)
		myTaskPOI.worldQuest = true
		myTaskPOI.Texture:SetDrawLayer("OVERLAY")
		WorldMap_SetupWorldQuestButton(myTaskPOI, worldQuestType, rarity, isElite, tradeskillLineIndex, self.inProgress, selected, isCriteria, isSpellTarget)
		WorldMapPOIFrame_AnchorPOI(myTaskPOI, self.infoX, self.infoY, WORLD_MAP_POI_FRAME_LEVEL_OFFSETS.WORLD_QUEST);
		myTaskPOI.questID = self.questID;
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
		if mapButton and mapButton.questID == self.questID then
			if Addon.Config.hidePOI then
				mapButton:Show()
			end
			mapButton:LockHighlight()
		end
	end

	DisplayMyTaskPOI(self)
	
	TaskPOI_OnEnter(self, button)
end

local function TitleButton_OnLeave(self)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
	local color = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )
	self.Text:SetTextColor( color.r, color.g, color.b )

	for i = 1, NUM_WORLDMAP_TASK_POIS do
		local mapButton = _G["WorldMapFrameTaskPOI"..i]
		if mapButton and mapButton.questID == self.questID then
			mapButton:UnlockHighlight()
			if Addon.Config.hidePOI then
				mapButton:SetShown( IsWorldQuestHardWatched(self.questID) or GetSuperTrackedQuestID() == self.questID )
			end
		end
	end

	myTaskPOI:Hide()

	TaskPOI_OnLeave(self, button)
end

local function TitleButton_OnClick(self, button)
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
				SetSuperTrackedQuestID(self.questID);
			else
				BonusObjectiveTracker_TrackWorldQuest(self.questID)
			end
		end
		DisplayMyTaskPOI(self)
	end
end

local function FilterButton_OnEnter(self)
	local text = FILTER_NAMES[ self.index ]
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(text)
	GameTooltip:Show()
end

local function FilterButton_OnLeave(self)
	GameTooltip:Hide()
end

local function FilterButton_OnClick(self, button)
	if button == 'RightButton' then
		Addon.Config:ToggleFilter(self.index)
	else
		if Addon.Config:IsOnlyFilter(self.index) then
			Addon.Config:SetNoFilter()
		else
			Addon.Config:SetOnlyFilter(self.index)
		end
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
	return mapID, conts[contIndex*2 - 1]
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

	local questsCollapsed = Addon.Config.collapsed

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

	local headerIndex = 0
	local titleIndex = 0
	local filterIndex = 0

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
	if ( prevButton and not Addon.Config.showAtTop ) then
		button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
	elseif storyButton then
		button:SetPoint("TOPLEFT", storyButton, "BOTTOMLEFT", 0, 0)
	else
		button:SetPoint("TOPLEFT", 1, -6)
	end
	button:Show()
	prevButton = button

	if (not questsCollapsed) then
		local hasFilters = Addon.Config:HasFilters()
		if Addon.Config.selectedFilters == FILTER_EMISSARY then hasFilters = false end
		local selectedFilters = Addon.Config:GetFilterTable(FILTER_COUNT)
		for i=#FILTER_ORDER, 1, -1 do
			local filterButton = GetFilterButton(FILTER_ORDER[i])
			filterButton:Show()

			filterButton:ClearAllPoints()
			if i == #FILTER_ORDER then
				filterButton:SetPoint("RIGHT", 1, 0)
				filterButton:SetPoint("TOP", prevButton, "TOP", 0, 3)
			else
				filterButton:SetPoint("RIGHT", GetFilterButton( FILTER_ORDER[i+1] ), "LEFT", 5, 0)
				filterButton:SetPoint("TOP", prevButton, "TOP", 0, 3)
			end

			if selectedFilters[FILTER_ORDER[i]] then
				filterButton:SetNormalAtlas("worldquest-tracker-ring-selected")
			else
				filterButton:SetNormalAtlas("worldquest-tracker-ring")
			end
		end
		filterIndex = FILTER_COUNT

		local questMapIDs = { currentMapID }
		if currentMapID == MAPID_BROKENISLES or (not Addon.Config.onlyCurrentZone and continentMapID == MAPID_BROKENISLES) then
			questMapIDs = MAPID_ALL
		end

		for _, mapID in ipairs(questMapIDs) do

			local questsList = C_TaskQuest.GetQuestsForPlayerByMapID(mapID, continentMapID)
			if (questsList and #questsList > 0) then
				for i, questInfo in ipairs(questsList) do
					local questID = questInfo.questId
					if (HaveQuestData (questID)) then

						local isWorldQuest = QuestMapFrame_IsQuestWorldQuest(questID)
						local passFilters = WorldMap_DoesWorldQuestInfoPassFilters(questInfo)

						if isWorldQuest and passFilters then
							local isSuppressed = WorldMap_IsWorldQuestSuppressed(questID)

							if (not isSuppressed) then
								local title, factionID, capped = C_TaskQuest.GetQuestInfoByQuestID(questID)
								local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(questID)
								local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
								C_TaskQuest.RequestPreloadRewardData(questID)
								
								local isFiltered = hasFilters

								local totalHeight = 8
								titleIndex = titleIndex + 1
								local button = GetTitleButton(titleIndex)
								button.worldQuest = true
								button.questID = questID
								button.mapID = mapID
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
								if worldQuestType == LE_QUEST_TAG_TYPE_PVP then
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
									isFiltered = hasFilters and not selectedFilters[FILTER_GOLD]
									local gold = floor(money / (COPPER_PER_SILVER * SILVER_PER_GOLD) + 0.5)
									tagTexture = "Interface\\MoneyFrame\\UI-MoneyIcons"
									tagTexCoords = { 0, 0.25, 0, 1 }
									tagText = BreakUpLargeNumbers(gold)
								end	

								local numQuestCurrencies = GetNumQuestLogRewardCurrencies(questID)
								for i = 1, numQuestCurrencies do
									local name, texture, numItems = GetQuestLogRewardCurrencyInfo(i, questID)
									if name == FILTER_NAMES[FILTER_ORDER_RESOURCES] then
										isFiltered = hasFilters and not selectedFilters[FILTER_ORDER_RESOURCES]
									end
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
											isFiltered = hasFilters and not selectedFilters[FILTER_ARTIFACT_POWER]
											tagTexture = "Interface\\Icons\\inv_7xp_inscription_talenttome01"
											tagText = artifactPower
											tagColor = BAG_ITEM_QUALITY_COLORS[LE_ITEM_QUALITY_ARTIFACT]
										else
											tagTexture = itemTexture
											if iLevel then
												isFiltered = hasFilters and not selectedFilters[FILTER_LOOT]
												tagText = iLevel
												tagColor = BAG_ITEM_QUALITY_COLORS[quality]
											else
												isFiltered = hasFilters and not selectedFilters[FILTER_ITEMS]
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

								if selectedFilters[FILTER_TIME] then
									if timeLeftMinutes and timeLeftMinutes <= (Addon.Config.timeFilterDuration * 60) then
										isFiltered = false
									end
								end

								if selectedFilters[FILTER_EMISSARY] and not isFiltered then
									local isBounty = false
									for _, bounty in ipairs(bounties) do
										if bounty and IsQuestCriteriaForBounty(questID, bounty.questID) then
											isBounty = true
										end
									end
									if not isBounty then isFiltered = true end
								end

								button:SetHeight(totalHeight)
								button:ClearAllPoints()
								if ( prevButton ) then
									button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
								else
									button:SetPoint("TOPLEFT", 1, -6)
								end
								if isFiltered then
									button:Hide()
									titleIndex = titleIndex - 1
								else
									button:Show()
									prevButton = button
								end
							end
						end

					end
				end
			end

		end
	end

	if Addon.Config.showAtTop and firstButton then
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
	for i = filterIndex + 1, #filterButtons do
		filterButtons[i]:Hide()
	end
	
end

local function MapFrame_Update()
	if Addon.Config.hidePOI then
		for i = 1, NUM_WORLDMAP_TASK_POIS do
			local taskPOI = _G["WorldMapFrameTaskPOI"..i]
			if taskPOI.worldQuest and not (IsWorldQuestHardWatched(taskPOI.questID) or GetSuperTrackedQuestID() == taskPOI.questID) then
				taskPOI:Hide()
			end
		end
	end
end

function UpdateTimeRemainingName()
	FILTER_NAMES[FILTER_TIME] = string.format(BLACK_MARKET_HOT_ITEM_TIME_LEFT, string.format(FORMATED_HOURS, Addon.Config.timeFilterDuration))
end

function QF:QUEST_WATCH_LIST_CHANGED()
	QuestFrame_Update()
	MapFrame_Update()
end

function QF:SUPER_TRACKED_QUEST_CHANGED()
	QuestFrame_Update()
	MapFrame_Update()
end

function QF:Startup()
	FILTER_NAMES[FILTER_ORDER_RESOURCES] = select(1, GetCurrencyInfo(1220)) -- Add in localized name of Order Resources
	UpdateTimeRemainingName()

	self:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
	self:RegisterEvent("SUPER_TRACKED_QUEST_CHANGED")

	Addon.Config:RegisterCallback('showAtTop', function() QuestMapFrame_UpdateAll(); QuestFrame_Update() end)
	Addon.Config:RegisterCallback('hidePOI', function() WorldMap_UpdateQuestBonusObjectives(); MapFrame_Update() end)
	Addon.Config:RegisterCallback('onlyCurrentZone', QuestFrame_Update)
	Addon.Config:RegisterCallback('selectedFilters', QuestFrame_Update)
	Addon.Config:RegisterCallback('timeFilterDuration', function() UpdateTimeRemainingName(); QuestFrame_Update() end)

	hooksecurefunc("QuestMapFrame_UpdateAll", QuestFrame_Update)
	hooksecurefunc("WorldMapTrackingOptionsDropDown_OnClick", QuestFrame_Update)
	hooksecurefunc("WorldMap_UpdateQuestBonusObjectives", MapFrame_Update)

	myTaskPOI = WorldMap_GetOrCreateTaskPOI("AWQ")
	myTaskPOI:Hide()
end
