local ADDON, Addon = ...
local QF = Addon:NewModule('QuestFrame')

local MAPID_BROKENISLES = 1007
local MAPID_DALARAN = 1014
local MAPID_AZSUNA = 1015
local MAPID_VALSHARAH = 1018
local MAPID_STORMHEIM = 1017
local MAPID_SURAMAR = 1033
local MAPID_HIGHMOUNTAIN = 1024
local MAPID_ALL = { [MAPID_AZSUNA]=MAPID_AZSUNA, [MAPID_VALSHARAH]=MAPID_VALSHARAH, [MAPID_STORMHEIM]=MAPID_STORMHEIM, [MAPID_SURAMAR]=MAPID_SURAMAR, [MAPID_HIGHMOUNTAIN]=MAPID_HIGHMOUNTAIN, [MAPID_DALARAN]=MAPID_DALARAN }

local QUESTTYPE_GOLD = 0x1
local QUESTTYPE_RESOURCE = 0x2
local QUESTTYPE_ITEM = 0x4
local QUESTTYPE_ARTIFACTPOWER = 0x8

local config = {
	showAtTop = true
}

local questsCollapsed = false

local TitleButton_RarityColorTable = { [LE_WORLD_QUEST_QUALITY_COMMON] = 110, [LE_WORLD_QUEST_QUALITY_RARE] = 113, [LE_WORLD_QUEST_QUALITY_EPIC] = 120 }

local function HeaderButton_OnClick(self, button)
	PlaySound("igMainMenuOptionCheckBoxOn")
	if ( button == "LeftButton" ) then
		questsCollapsed = not questsCollapsed
		QuestMapFrame_UpdateAll()
	end
end

local function TitleButton_OnEnter(self, button)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
	local _, color = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )
	self.Text:SetTextColor( color.r, color.g, color.b )
	
	TaskPOI_OnEnter(self, button)
end

local function TitleButton_OnLeave(self, button)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
	local color = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )
	self.Text:SetTextColor( color.r, color.g, color.b )

	TaskPOI_OnLeave(self, button)
end

local function TitleButton_OnClick(self, button)
	PlaySound("igMainMenuOptionCheckBoxOn");
	if ( IsShiftKeyDown() ) then
		if IsWorldQuestHardWatched(self.questID) or (IsWorldQuestWatched(self.questID) and GetSuperTrackedQuestID() == self.questID) then
			BonusObjectiveTracker_UntrackWorldQuest(self.questID);
		else
			BonusObjectiveTracker_TrackWorldQuest(self.questID, true);
		end
	else
		if ( button == "RightButton" ) then
			if ( self.mapID ) then
				SetMapByID(self.mapID)
			end
		else
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
		title.TaskIcon:SetPoint("RIGHT", title.Text, "LEFT", -7, 0)

		titleButtons[index] = title
	end
	return titleButtons[index]
end

local filterButtons = {}
local function GetFilterButton(index, parent)
	if ( not titleButtons[index] ) then
		local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		button:SetScript("OnClick", FilterButton_OnClick)
		button:SetHeight(16)
		button:SetWidth(80)

		filterButtons[index] = button
	end
	return filterButtons[index]
end

local function QuestFrame_Update()
	local currentMapID = GetCurrentMapAreaID()
	local bounties, displayLocation, lockedQuestID = GetQuestBountyInfoForMapID(currentMapID)
	if not displayLocation or lockedQuestID then
		for i = 1, #headerButtons do headerButtons[i]:Hide() end
		for i = 1, #titleButtons do titleButtons[i]:Hide() end
		return
	end

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
	if ( prevButton and not config.showAtTop ) then
		button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
	elseif storyButton then
		button:SetPoint("TOPLEFT", storyButton, "BOTTOMLEFT", 0, 0)
	else
		button:SetPoint("TOPLEFT", 1, -6)
	end
	button:Show()
	prevButton = button

	-- if not filterFrame then
	-- 	local frame = CreateFrame("FRAME", nil, QuestMapFrame.QuestsFrame.Contents)
	-- 	frame:SetSize(255, 16)
	-- 	frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
	-- 	frame:SetBackdropColor( 0.616, 0.149, 0.114, 0.9)
	-- 	filterFrame = frame

	-- 	local filter1Button = GetFilterButton(1, frame)
	-- 	filter1Button:SetText("Emissary")
	-- 	filter1Button:ClearAllPoints()
	-- 	filter1Button:SetPoint("LEFT", 0, 0)
	-- end
	-- filterFrame:ClearAllPoints()
	-- filterFrame:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)

	-- prevButton = filterFrame

	if (not questsCollapsed) then
		local questMapIDs = { [currentMapID] = currentMapID }
		if currentMapID == MAPID_BROKENISLES then
			questMapIDs = MAPID_ALL
		end

		for _, mapID in pairs(questMapIDs) do

			local questsList = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
			if (questsList and #questsList > 0) then
				for i, questInfo in ipairs(questsList) do
					local questID = questInfo.questId
					if (HaveQuestData (questID)) then

						local isWorldQuest = QuestMapFrame_IsQuestWorldQuest(questID)
						local passFilters = WorldMap_DoesWorldQuestInfoPassFilters(questInfo)

						if isWorldQuest and passFilters then
							local isSuppressed = WorldMap_IsWorldQuestSuppressed (questID)
							local isFiltered = false

							if (not isSuppressed and not isFiltered) then
								local title, factionID, capped = C_TaskQuest.GetQuestInfoByQuestID(questID)
								local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(questID)
								local isCriteria = WorldMapFrame.UIElementsFrame.BountyBoard:IsWorldQuestCriteriaForSelectedBounty(questID)
								local selected = questIDd == GetSuperTrackedQuestID()
								C_TaskQuest.RequestPreloadRewardData(questID)

								local totalHeight = 8
								titleIndex = titleIndex + 1
								local button = GetTitleButton(titleIndex)
								button.worldQuest = true
								button.questID = questID
								button.mapID = mapID
								button.numObjectives = questInfo.numObjectives

								local color = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )
								button.Text:SetTextColor( color.r, color.g, color.b )

								button.Text:SetText(title)
								totalHeight = totalHeight + button.Text:GetHeight()

								if ( IsWorldQuestHardWatched(questID) ) then -- TODO: Add support if world quest is tracked
									button.Check:Show();
									button.Check:SetPoint("LEFT", button.Text, button.Text:GetWrappedWidth() + 2, 0);
								else
									button.Check:Hide();
								end

								button.TaskIcon:Show()
								if worldQuestType == LE_QUEST_TAG_TYPE_PVP then
									button.TaskIcon:SetAtlas("worldquest-icon-pvp-ffa", true)
								elseif worldQuestType == LE_QUEST_TAG_TYPE_PET_BATTLE then
									button.TaskIcon:SetAtlas("worldquest-icon-petbattle", true)
								elseif worldQuestType == LE_QUEST_TAG_TYPE_DUNGEON then
									button.TaskIcon:SetAtlas("worldquest-icon-dungeon", true)
								elseif ( worldQuestType == LE_QUEST_TAG_TYPE_PROFESSION and WORLD_QUEST_ICONS_BY_PROFESSION[tradeskillLineID] ) then
									button.TaskIcon:SetAtlas(WORLD_QUEST_ICONS_BY_PROFESSION[tradeskillLineID], true)
								else
									button.TaskIcon:Hide()
								end

								local tagText, tagTexture, tagTexCoords, tagColor
								tagColor = {r=1, g=1, b=1}

								local money = GetQuestLogRewardMoney(questID)
								if ( money > 0 ) then
									local gold = floor(money / (COPPER_PER_SILVER * SILVER_PER_GOLD))
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
										local artifactPower = Addon.Modules.Data:ItemArtifactPower(itemID)
										local iLevel = Addon.Modules.Data:RewardItemLevel(questID)
										if artifactPower then
											tagTexture = "Interface\\Icons\\inv_7xp_inscription_talenttome01"
											tagText = artifactPower
											tagColor = BAG_ITEM_QUALITY_COLORS[LE_ITEM_QUALITY_ARTIFACT]
										else
											tagTexture = itemTexture
											if quantity > 1 then
												tagText = quantity
											elseif iLevel then
												tagText = iLevel
												tagColor = BAG_ITEM_QUALITY_COLORS[quality]
											else
												tagText = nil
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

								button:SetHeight(totalHeight)
								button:ClearAllPoints()
								if ( prevButton ) then
									button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
								else
									button:SetPoint("TOPLEFT", 1, -6)
								end
								button:Show()
								prevButton = button

							end
						end

					end
				end
			end

		end
	end

	if config.showAtTop and firstButton then
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

function QF:Startup()
	hooksecurefunc("QuestMapFrame_UpdateAll", QuestFrame_Update)
	hooksecurefunc("WorldMapTrackingOptionsDropDown_OnClick", QuestFrame_Update)
end
