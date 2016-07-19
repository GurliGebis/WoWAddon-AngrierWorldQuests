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

local questsCollapsed = true

local TitleButton_TextColor = { font="QuestDifficulty_Standard", r=1, g=0.82, b=0 }
local TitleButton_TextHightlightColor = { font="QuestDifficulty_Standard", r=1, g=1, b=0.1 }

local function HeaderButton_OnClick(self, button)
	PlaySound("igMainMenuOptionCheckBoxOn")
	if ( button == "LeftButton" ) then
		questsCollapsed = not questsCollapsed
		QuestMapFrame_UpdateAll()
	end
end

local function TitleButton_OnEnter(self, button)
	local color = TitleButton_TextHightlightColor
	self.Text:SetTextColor( color.r, color.g, color.b )
	
	TaskPOI_OnEnter(self, button)
end

local function TitleButton_OnLeave(self, button)
	local color = TitleButton_TextColor
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
		local header = CreateFrame("BUTTON", nil, QuestMapFrame.QuestsFrame.Contents, "QuestLogHeaderTemplate");
		header:SetScript("OnClick", HeaderButton_OnClick)
		headerButtons[index] = header;
	end
	return headerButtons[index];
end

local titleButtons = {}
local function GetTitleButton(index)
	if ( not titleButtons[index] ) then
		local title = CreateFrame("BUTTON", nil, QuestMapFrame.QuestsFrame.Contents, "QuestLogTitleTemplate");
		title:SetScript("OnEnter", TitleButton_OnEnter)
		title:SetScript("OnLeave", TitleButton_OnLeave)
		title:SetScript("OnClick", TitleButton_OnClick)
		titleButtons[index] = title;
	end
	return titleButtons[index];
end

local function draw()
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

	if (not questsCollapsed) then
		local currentMapID = GetCurrentMapAreaID()
		local questMapIDs = MAPID_ALL
		if questMapIDs[currentMapID] then
			questMapIDs = { [currentMapID] = currentMapID }
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

								local totalHeight = 8
								titleIndex = titleIndex + 1
								local button = GetTitleButton(titleIndex)
								button.worldQuest = true
								button.questID = questID
								button.mapID = mapID
								button.numObjectives = questInfo.numObjectives

								local color = TitleButton_TextColor
								button.Text:SetTextColor( color.r, color.g, color.b )

								button.Text:SetText(title)
								totalHeight = totalHeight + button.Text:GetHeight()

								if ( false ) then -- TODO: Add support if world quest is tracked
									button.Check:Show();
									button.Check:SetPoint("LEFT", button.Text, button.Text:GetWrappedWidth() + 2, 0);
								else
									button.Check:Hide();
								end

								button.TagTexture:Hide()

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

	if config.showAtTop then
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
	hooksecurefunc("QuestMapFrame_UpdateAll", draw)
end
