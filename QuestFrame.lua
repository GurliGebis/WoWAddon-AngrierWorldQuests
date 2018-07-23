local ADDON, Addon = ...
local Mod = Addon:NewModule('QuestFrame')
local Config

local MAPID_CONTINENTS = { 619 }

local TitleButton_RarityColorTable = { [LE_WORLD_QUEST_QUALITY_COMMON] = 110, [LE_WORLD_QUEST_QUALITY_RARE] = 113, [LE_WORLD_QUEST_QUALITY_EPIC] = 120 }

local FILTER_NAMES = { BOUNTY_BOARD_LOCKED_TITLE, ARTIFACT_POWER, BONUS_ROLL_REWARD_ITEM, "Order Resources", BONUS_ROLL_REWARD_MONEY, ITEMS, CLOSES_IN, FACTION, PVP, TRADE_SKILLS, SHOW_PET_BATTLES_ON_MAP_TEXT, RAID_FRAME_SORT_LABEL, TRACKING, ZONE, ITEM_QUALITY3_DESC, GROUP_FINDER, "Legionfall War Supplies", "Nethershard", "Veiled Argunite" }

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
	
	if Config.showComparisonRight then
		WorldMapTooltip.ItemTooltip.Tooltip.overrideComparisonAnchorSide = "right"
	end
	TaskPOI_OnEnter(self)
end

local function TitleButton_OnLeave(self)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questID)
	local color = GetQuestDifficultyColor( TitleButton_RarityColorTable[rarity] )
	self.Text:SetTextColor( color.r, color.g, color.b )

	TaskPOI_OnLeave(self)
end

local function TitleButton_OnClick(self, button)
	if false and SpellCanTargetQuest() then
		if IsQuestIDValidSpellTarget(self.questID) then
			UseWorldMapActionButtonSpellOnQuest(self.questID)
			-- Assume success for responsiveness
			WorldMap_OnWorldQuestCompletedBySpell(self.questID)
		else
			UIErrorsFrame:AddMessage(WORLD_QUEST_CANT_COMPLETE_BY_SPELL, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
		end
	else
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		if ChatEdit_TryInsertQuestLinkForQuestID(self.questID) then
			
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
		end
	end
end

local function GetQuestsTaskInfo(mapID)
	return mapID and C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
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
	button.mapID = mapID
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
	button:ClearAllPoints()
	if prevButton then
		button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
	else
		button:SetPoint("TOPLEFT", 1, -6)
	end
	button.layoutIndex = QuestMapFrame:GetManagedLayoutIndex("AWQ")
	button:Show()

	return button
end

local function QuestFrame_Update()
	titleFramePool:ReleaseAll()

	local mapID = QuestMapFrame:GetParent():GetMapID()

	local bounties, displayLocation, lockedQuestID = GetQuestBountyInfoForMapID(mapID)
	if not displayLocation or lockedQuestID then
		headerButton:Hide()
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
	headerButton.layoutIndex = QuestMapFrame:GetManagedLayoutIndex("AWQ");
	headerButton:Show()
	prevButton = headerButton

	if (not questsCollapsed) then
		local taskInfo = GetQuestsTaskInfo(mapID)

		if taskInfo then
			for i, info in ipairs(taskInfo) do
				if HaveQuestData(info.questId) and QuestUtils_IsQuestWorldQuest(info.questId) then
					if WorldMap_DoesWorldQuestInfoPassFilters(info) and (info.mapID == mapID or tContains(MAPID_CONTINENTS, mapID)) then

						
						prevButton = QuestFrame_AddQuestButton(info, prevButton)
					end
				end
			end
		end
	end

	if firstButton then
		firstButton:ClearAllPoints()
		firstButton:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
	end

	QuestScrollFrame.Contents:Layout()
end

function Mod:Startup()
	Config = Addon.Config

	titleFramePool = CreateFramePool("BUTTON", QuestMapFrame.QuestsFrame.Contents, "QuestLogTitleTemplate")

	QuestMapFrame.layoutIndexManager:AddManagedLayoutIndex("AWQ", QUEST_LOG_STORY_LAYOUT_INDEX + 1);
	QuestMapFrame.layoutIndexManager.startingLayoutIndexes["Other"] = QUEST_LOG_STORY_LAYOUT_INDEX + 100 + 1
	hooksecurefunc("QuestLogQuests_Update", QuestFrame_Update)
end