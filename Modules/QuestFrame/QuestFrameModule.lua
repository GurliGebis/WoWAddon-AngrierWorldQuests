--[[
    Copyright (C) 2024-2026 GurliGebis

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    1: Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.

    2: Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.

    3: Neither the name of the copyright holder nor the names of its contributors
       may be used to endorse or promote products derived from this software
       without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
    IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
    USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
    NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
    ADVISED OF THE POSSIBILITY OF SUCH DAMAGE
]]

local addonName, _ = ...
local AngrierWorldQuests = LibStub("AceAddon-3.0"):GetAddon(addonName)
local QuestFrameModule = AngrierWorldQuests:NewModule("QuestFrameModule", "AceConsole-3.0")
local ConfigModule = AngrierWorldQuests:GetModule("ConfigModule")
local DataModule = AngrierWorldQuests:GetModule("DataModule")

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

-- ============================================================
-- TAINT AVOIDANCE (issue #161)
-- ============================================================
-- securecallfunction / securecall protect a SECURE caller from
-- being tainted by a tainted callee — the opposite of what was
-- mistakenly applied in earlier attempts.  Calling secure Blizzard
-- frame methods via securecallfunction() from tainted addon code
-- provides NO protection; the frame operations still run tainted.
--
-- The only correct fix for taint-sensitive frame Show/Hide
-- operations is to ensure they run from a clean Lua coroutine.
-- C_Timer.After(0, ...) callbacks fire from WoW's main game loop
-- in a fresh untainted coroutine.
--
-- PostProcessWorldQuestPins is therefore deferred via
-- C_Timer.After(0) rather than called directly from the
-- hooksecurefunc hook (which always runs tainted).
-- ============================================================

--region Variables

local dataProvider
local hoveredQuestID
local titleFramePool
local listRefreshPending = false
local fullRefreshPending = false
local fullRefreshDirty = false
local fullRefreshRetryCount = 0
local fullRefreshReason
local addonAddedPins = {}

local function DebugLog(message)
    if not ConfigModule:Get("enableDebugging") then
        return
    end

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff7f00AWQ|r %s", message))
    end
end

local function CanApplyFullRefresh()
    if not QuestMapFrame or not QuestMapFrame:IsShown() then
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        return false
    end

    return true
end

--endregion

--region QuestLog
do
    local REWARDS_ORDER = {
        ARTIFACT_POWER = 1,
        LOOT = 2,
        CURRENCY = 3,
        GOLD = 4,
        ITEMS = 5
    }

    local awqContainer
    local headerButton
    local filterButtons = {}

    local QuestButton_RarityColorTable = { [Enum.WorldQuestQuality.Common] = 0, [Enum.WorldQuestQuality.Rare] = 3, [Enum.WorldQuestQuality.Epic] = 10 }

    local MAPID_ARGUS = 905
    local ANIMA_ITEM_COLOR = { r=.6, g=.8, b=1 }
    local ANIMA_SPELLID = {[347555] = 3, [345706] = 5, [336327] = 35, [336456] = 250}

    local QUEST_BONUS_COLOR = {
        r = math.min(QUEST_REWARD_CONTEXT_FONT_COLOR.r + 0.15, 1),
        g = math.min(QUEST_REWARD_CONTEXT_FONT_COLOR.g + 0.15, 1),
        b = math.min(QUEST_REWARD_CONTEXT_FONT_COLOR.b + 0.15, 1)
    }

    local function FilterMenu_ApplySelection(filterKey, value)
        if filterKey == "EMISSARY" then
            ConfigModule:Set("filterEmissary", value, true)
        elseif filterKey == "LOOT" then
            ConfigModule:Set("filterLoot", value, true)
        elseif filterKey == "FACTION" then
            ConfigModule:Set("filterFaction", value, true)
        elseif filterKey == "ZONE" then
            ConfigModule:Set("filterZone", value, true)
        elseif filterKey == "TIME" then
            ConfigModule:Set("filterTime", value, true)
        end

        if filterKey == "SORT" then
            ConfigModule:Set("sortMethod", value)
        elseif IsShiftKeyDown() then
            ConfigModule:SetFilter(filterKey, true)
        else
            ConfigModule:SetOnlyFilter(filterKey)
        end
    end

    local function FilterMenu_Generator(owner, rootDescription)
        local filterKey = owner.filter

        if filterKey == "EMISSARY" then
            local currentValue = ConfigModule:Get("filterEmissary")
            if not C_QuestLog.IsOnQuest(currentValue) then currentValue = 0 end

            local function IsSelected(value) return value == currentValue end
            local function SetSelected(value) FilterMenu_ApplySelection(filterKey, value) end

            rootDescription:CreateRadio(ALL, IsSelected, SetSelected, 0)

            local mapID = QuestMapFrame:GetParent():GetMapID()
            if mapID == _AngrierWorldQuests.Constants.MAP_IDS.BROKENISLES then mapID = _AngrierWorldQuests.Constants.MAP_IDS.DALARAN end
            local bounties = C_QuestLog.GetBountiesForMapID(mapID)
            if bounties then
                for _, bounty in ipairs(bounties) do
                    if not C_QuestLog.IsComplete(bounty.questID) then
                        local radio = rootDescription:CreateRadio(
                            C_QuestLog.GetTitleForQuestID(bounty.questID),
                            IsSelected, SetSelected, bounty.questID
                        )
                        radio:AddInitializer(function(button)
                            local tex = button:AttachTexture()
                            tex:SetTexture(bounty.icon)
                            tex:SetSize(16, 16)
                            tex:SetPoint("RIGHT")
                        end)
                    end
                end
            end

        elseif filterKey == "LOOT" then
            local currentValue = ConfigModule:Get("filterLoot")
            if currentValue == 0 then currentValue = ConfigModule:Get("lootFilterUpgrades") and _AngrierWorldQuests.Constants.FILTERS.LOOT_UPGRADES or _AngrierWorldQuests.Constants.FILTERS.LOOT_ALL end

            local function IsSelected(value) return value == currentValue end
            local function SetSelected(value) FilterMenu_ApplySelection(filterKey, value) end

            rootDescription:CreateRadio(ALL, IsSelected, SetSelected, _AngrierWorldQuests.Constants.FILTERS.LOOT_ALL)
            rootDescription:CreateRadio(L["UPGRADES"], IsSelected, SetSelected, _AngrierWorldQuests.Constants.FILTERS.LOOT_UPGRADES)

        elseif filterKey == "ZONE" then
            local currentValue = ConfigModule:Get("filterZone")

            local function IsSelected(value) return value == currentValue end
            local function SetSelected(value) FilterMenu_ApplySelection(filterKey, value) end

            rootDescription:CreateRadio(L["CURRENT_ZONE"], IsSelected, SetSelected, 0)

        elseif filterKey == "FACTION" then
            local currentValue = ConfigModule:Get("filterFaction")

            local function IsSelected(value) return value == currentValue end
            local function SetSelected(value) FilterMenu_ApplySelection(filterKey, value) end

            local mapID = QuestMapFrame:GetParent():GetMapID()
            local factions = DataModule:GetFactionsByMapID(mapID)

            for _, factionID in ipairs(factions) do
                local factionData = C_Reputation.GetFactionDataByID(factionID)
                rootDescription:CreateRadio(factionData.name, IsSelected, SetSelected, factionID)
            end

        elseif filterKey == "TIME" then
            local filterTime = ConfigModule:Get("filterTime")
            local timeFilterDuration = ConfigModule:Get("timeFilterDuration")
            local currentValue = filterTime ~= 0 and filterTime or timeFilterDuration

            local function IsSelected(value) return value == currentValue end
            local function SetSelected(value) FilterMenu_ApplySelection(filterKey, value) end

            for _, hours in ipairs(ConfigModule.Filters.TIME.values) do
                rootDescription:CreateRadio(string.format(FORMATED_HOURS, hours), IsSelected, SetSelected, hours)
            end

        elseif filterKey == "SORT" then
            local currentValue = ConfigModule:Get("sortMethod")

            local function IsSelected(value) return value == currentValue end
            local function SetSelected(value) FilterMenu_ApplySelection(filterKey, value) end

            rootDescription:CreateTitle(ConfigModule.Filters[filterKey].name)

            for _, sortIndex in ipairs(ConfigModule.SortOrder) do
                rootDescription:CreateRadio(L["config_sortMethod_"..sortIndex], IsSelected, SetSelected, sortIndex)
            end
        end
    end

    local function FilterButton_OnEnter(self)
        local text = ConfigModule.Filters[ self.filter ].name

        local filterEmissary = ConfigModule:Get("filterEmissary")
        if self.filter == "EMISSARY" and filterEmissary and not C_QuestLog.IsComplete(filterEmissary) then
            local title = C_QuestLog.GetTitleForQuestID(filterEmissary)
            if title then text = text..": "..title end
        end

        local filterLoot = ConfigModule:Get("filterLoot")
        local lootFilterUpgrades = ConfigModule:Get("lootFilterUpgrades")
        if self.filter == "LOOT" then
            if filterLoot == _AngrierWorldQuests.Constants.FILTERS.LOOT_UPGRADES or (filterLoot == 0 and lootFilterUpgrades) then
                text = string.format("%s (%s)", text, L["UPGRADES"])
            end
        end

        local filterFaction = ConfigModule:Get("filterFaction")
        if self.filter == "FACTION" and filterFaction ~= 0 then
            local factionData = C_Reputation.GetFactionDataByID(filterFaction)
            local title = factionData and factionData.name
            if title then text = text..": "..title end
        end

        local sortMethod = ConfigModule:Get("sortMethod")
        if self.filter == "SORT" then
            local title = L["config_sortMethod_"..sortMethod]
            if title then text = text..": "..title end
        end

        local filterZone = ConfigModule:Get("filterZone")
        if self.filter == "ZONE" and filterZone ~= 0 then
            local mapInfo = C_Map.GetMapInfo(filterZone)
            local title = mapInfo and mapInfo.name
            if title then text = text..": "..title end
        end

        local filterTime = ConfigModule:Get("filterTime")
        local timeFilterDuration = ConfigModule:Get("timeFilterDuration")
        if self.filter == "TIME" then
            local hours = filterTime ~= 0 and filterTime or timeFilterDuration
            text = string.format(BLACK_MARKET_HOT_ITEM_TIME_LEFT, string.format(FORMATED_HOURS, hours))
        end

        QuestFrameModule.Tooltip_ShowSimple(self, text, HIGHLIGHT_FONT_COLOR)
    end

    local function FilterButton_OnLeave(self)
        QuestFrameModule.Tooltip_Hide(self)
    end

    local function FilterButton_ShowMenu(self)
        MenuUtil.CreateContextMenu(self, FilterMenu_Generator)
    end

    local function FilterButton_OnClick(self, button)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if (button == "RightButton" and (self.filter == "EMISSARY" or self.filter == "LOOT" or self.filter == "FACTION" or self.filter == "TIME"))
                or (self.filter == "SORT")
                or (self.filter == "FACTION" and not ConfigModule:GetFilter("FACTION")) then
            FilterButton_ShowMenu(self)
        else
            if IsShiftKeyDown() then
                if self.filter == "EMISSARY" then ConfigModule:Set("filterEmissary", 0, true) end
                if self.filter == "LOOT" then ConfigModule:Set("filterLoot", 0, true) end
                ConfigModule:ToggleFilter(self.filter)
            else
                if ConfigModule:IsOnlyFilter(self.filter) then
                    ConfigModule:Set("filterFaction", 0, true)
                    ConfigModule:Set("filterEmissary", 0, true)
                    ConfigModule:Set("filterLoot", 0, true)
                    ConfigModule:Set("filterZone", 0, true)
                    ConfigModule:Set("filterTime", 0, true)
                    ConfigModule:SetNoFilter()
                else
                    if self.filter ~= "FACTION" then ConfigModule:Set("filterFaction", 0, true) end
                    if self.filter ~= "EMISSARY" then ConfigModule:Set("filterEmissary", 0, true) end
                    if self.filter ~= "LOOT" then ConfigModule:Set("filterLoot", 0, true) end
                    if self.filter ~= "ZONE" then ConfigModule:Set("filterZone", 0, true) end
                    if self.filter ~= "TIME" then ConfigModule:Set("filterTime", 0, true) end
                    ConfigModule:SetOnlyFilter(self.filter)
                end
            end

            FilterButton_OnEnter(self)
        end
    end

    local function GetFilterButton(key)
        local index = ConfigModule.Filters[key].index
        if ( not filterButtons[index] ) then
            local button = CreateFrame("Button", nil, awqContainer)
            button.filter = key

            button:SetScript("OnEnter", FilterButton_OnEnter)
            button:SetScript("OnLeave", FilterButton_OnLeave)
            button:RegisterForClicks("LeftButtonUp","RightButtonUp")
            button:SetScript("OnClick", FilterButton_OnClick)

            button:SetSize(24, 24)

            if key == "SORT" then
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
                icon:SetTexture(ConfigModule.Filters[key].icon or "inv_misc_questionmark")
                button.Icon = icon
            end
            filterButtons[index] = button
        end
        return filterButtons[index]
    end

    local function HeaderButton_OnClick(_, button)
        local questsCollapsed = ConfigModule:Get("collapsed")
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

        if ( button == "LeftButton" ) then
            questsCollapsed = not questsCollapsed
            ConfigModule:Set("collapsed", questsCollapsed)
            QuestFrameModule:RequestQuestLogUpdate()
        end
    end

    local function ShouldQuestBeBonusColored(questID)
        if not ConfigModule:Get("colorWarbandBonus") then
            return false
        end

        return C_QuestLog.QuestContainsFirstTimeRepBonusForPlayer(questID)
    end

    local function QuestButton_OnEnter(self)
        local questTagInfo = DataModule.GetCachedQuestTagInfo(self.questID)
        local color
        if ShouldQuestBeBonusColored(self.questID) then
            color = QUEST_BONUS_COLOR
        else
            _, color = GetQuestDifficultyColor(UnitLevel("player") + QuestButton_RarityColorTable[questTagInfo.quality])
        end
        self.Text:SetTextColor(color.r, color.g, color.b)
        hoveredQuestID = self.questID
        self.HighlightTexture:SetShown(true)
        QuestFrameModule.Tooltip_BuildSafe(self)
    end

    local function QuestButton_OnLeave(self)
        local questTagInfo = DataModule.GetCachedQuestTagInfo(self.questID)
        local color
        if ShouldQuestBeBonusColored(self.questID) then
            color = QUEST_REWARD_CONTEXT_FONT_COLOR
        else
            color = GetQuestDifficultyColor(UnitLevel("player") + QuestButton_RarityColorTable[questTagInfo.quality])
        end
        self.Text:SetTextColor(color.r, color.g, color.b)
        hoveredQuestID = nil
        self.HighlightTexture:SetShown(false)
        QuestFrameModule.Tooltip_Hide(self)
    end

    local function QuestButton_OnClick(self, button)
        if ( not ChatEdit_TryInsertQuestLinkForQuestID(self.questID) ) then
            local watchType = C_QuestLog.GetQuestWatchType(self.questID);
            local isSuperTracked = C_SuperTrack.GetSuperTrackedQuestID() == self.questID;

            if ( button == "RightButton" ) then
                if ( self.mapID ) then
                    QuestMapFrame:GetParent():SetMapID(self.mapID)
                end
            elseif IsShiftKeyDown() then
                if watchType == Enum.QuestWatchType.Manual or (watchType == Enum.QuestWatchType.Automatic and isSuperTracked) then
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF);
                    C_Timer.After(0, function() QuestUtil.UntrackWorldQuest(self.questID) end)
                else
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
                    C_Timer.After(0, function() QuestUtil.TrackWorldQuest(self.questID, Enum.QuestWatchType.Manual) end)
                end
            else
                if isSuperTracked then
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF);
                    C_Timer.After(0, function() C_SuperTrack.SetSuperTrackedQuestID(0) end)
                else
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
                    C_Timer.After(0, function()
                        if watchType ~= Enum.QuestWatchType.Manual then
                            QuestUtil.TrackWorldQuest(self.questID, Enum.QuestWatchType.Automatic);
                        end

                        C_SuperTrack.SetSuperTrackedQuestID(self.questID);
                    end)
                end
            end
        end
    end

    local function QuestButton_ToggleTracking(self)
        local watchType = C_QuestLog.GetQuestWatchType(self.questID)

        if watchType == Enum.QuestWatchType.Manual or (watchType == Enum.QuestWatchType.Automatic and C_SuperTrack.GetSuperTrackedQuestID() == self.questID) then
            C_Timer.After(0, function() QuestUtil.UntrackWorldQuest(self.questID) end)
        else
            C_Timer.After(0, function() QuestUtil.TrackWorldQuest(self.questID, Enum.QuestWatchType.Manual) end)
        end
    end

    local function QuestButton_Initialize(button)
        if button.awq then
            return
        end

        button:SetParent(awqContainer)

        button.questRewardTooltipStyle = TOOLTIP_QUEST_REWARDS_STYLE_WORLD_QUEST
        button.OnLegendPinMouseEnter = function() end
        button.OnLegendPinMouseLeave = function() end

        button:SetScript("OnEnter", QuestButton_OnEnter)
        button:SetScript("OnLeave", QuestButton_OnLeave)
        button:SetScript("OnClick", QuestButton_OnClick)

        button.TagTexture:Hide()
        button.StorylineTexture:Hide()

        button.TagText = button:CreateFontString(nil, nil, "GameFontNormalLeft")
        button.TagText:SetJustifyH("RIGHT")
        button.TagText:SetTextColor(1, 1, 1)
        button.TagText:SetPoint("RIGHT", button.TagTexture, "LEFT", -2, 0)
        button.TagText:Hide()

        button.TimeIcon = button:CreateTexture(nil, "OVERLAY")
        button.TimeIcon:SetAtlas("worldquest-icon-clock")
        button.TimeIcon:SetPoint("RIGHT", button.Text, "LEFT", -5, 0)

        button.ToggleTracking = QuestButton_ToggleTracking

        button.awq = true
    end

    local function GetAnimaValue(itemID)
        local _, spellID = C_Item.GetItemSpell(itemID)
        return ANIMA_SPELLID[spellID] or 1
    end

    local function QuestSorter(a, b)
        local sortMethod = ConfigModule:Get("sortMethod")
        local sortMethods = _AngrierWorldQuests.Enums.SortOrder

        if sortMethod == sortMethods.SORT_FACTION then
            if (a.factionID or 0) ~= (b.factionID or 0) then
                return (a.factionID or 0) < (b.factionID or 0)
            end
        elseif sortMethod == sortMethods.SORT_TIME then
            if math.abs((a.timeLeftMinutes or 0) - (b.timeLeftMinutes or 0)) > 2 then
                return (a.timeLeftMinutes or 0) < (b.timeLeftMinutes or 0)
            end
        elseif sortMethod == sortMethods.SORT_ZONE then
            if a.mapID ~= b.mapID then
                return (a.mapID or 0) < (b.mapID or 0)
            end
        elseif sortMethod == sortMethods.SORT_REWARDS then
            local default_cat = #ConfigModule.Filters + 1
            local acat = (a.rewardCategory and REWARDS_ORDER[a.rewardCategory]) or default_cat
            local bcat = (b.rewardCategory and REWARDS_ORDER[b.rewardCategory]) or default_cat
            if acat ~= bcat then
                return acat < bcat
            elseif acat ~= default_cat then
                if (a.rewardValue or 0) ~= (b.rewardValue or 0) then
                    return (a.rewardValue or 0) > (b.rewardValue or 0)
                elseif (a.rewardValue2 or 0) ~= (b.rewardValue2 or 0) then
                    return (a.rewardValue2 or 0) > (b.rewardValue2 or 0)
                end
            end
        end

        return a.Text:GetText() < b.Text:GetText()
    end

    function QuestFrameModule:QuestLogClosed()
        DataModule:ClearQuestTagInfoCache()
    end

    function QuestFrameModule:HideWorldQuestsHeader()
        for i = 1, #filterButtons do
            filterButtons[i]:Hide()
        end

        if awqContainer then
            awqContainer:Hide()
        end

        QuestScrollFrame.Contents:Layout()
    end

    function QuestFrameModule:QuestLog_Update()
        if not QuestMapFrame or not QuestMapFrame:IsShown() then
            return
        end

        if QuestFrameModule:IsLockedDown() then
            return
        end

        titleFramePool:ReleaseAll()

        local mapID = QuestMapFrame:GetParent():GetMapID()

        local displayLocation, lockedQuestID = C_QuestLog.GetBountySetInfoForMapID(mapID);

        local tasksOnMap = C_TaskQuest.GetQuestsOnMap(mapID)
        if (ConfigModule:Get("onlyCurrentZone")) and (not displayLocation or lockedQuestID) and not (tasksOnMap and #tasksOnMap > 0) and (mapID ~= MAPID_ARGUS) then
            QuestFrameModule:HideWorldQuestsHeader()
            return
        end

        if (ConfigModule:Get("hideQuestList")) then
            QuestFrameModule:HideWorldQuestsHeader()
            return
        end

        local questsCollapsed = ConfigModule:Get("collapsed")
        local showAtTop = ConfigModule:Get("showAtTop")

        if not showAtTop then
            awqContainer.layoutIndex = 9999.5
        end
        awqContainer:Show()

        local needsReposition = showAtTop and not awqContainer.layoutIndex

        headerButton:Show()
        local prevButton = headerButton

        local usedButtons = {}
        local filtersOwnRow = false

        local addedQuests = {}
        local questCount = 0
        local displayMapIDs = DataModule:GetMapIDsToGetQuestsFrom(mapID)
        local searchBoxText = QuestScrollFrame.SearchBox:GetText():lower()

        for mID in pairs(displayMapIDs) do
            local taskInfo = C_TaskQuest.GetQuestsOnMap(mID)

            if taskInfo then
                for _, info in ipairs(taskInfo) do
                    if HaveQuestData(info.questID) and QuestUtils_IsQuestWorldQuest(info.questID) then
                        if WorldMap_DoesWorldQuestInfoPassFilters(info) then
                            local isFiltered = DataModule:IsQuestFiltered(info, mapID)
                            if not isFiltered then
                                if addedQuests[info.questID] == nil then
                                    addedQuests[info.questID] = true
                                    questCount = questCount + 1
                                    if not questsCollapsed then
                                        local button = QuestFrameModule:QuestLog_AddQuestButton(info, searchBoxText)
                                        if button ~= nil then
                                            table.insert(usedButtons, button)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        if questCount == 0 and ConfigModule:HasFilters() == false then
            QuestFrameModule:HideWorldQuestsHeader()
            return
        end

        if questsCollapsed then
            for i = 1, #filterButtons do
                filterButtons[i]:Hide()
            end
        else
            local selectedFilters = ConfigModule:GetFilterTable()
            local prevFilter

            for j = 1, #ConfigModule.FiltersOrder, 1 do
                local i = j

                if not filtersOwnRow then
                    i = #ConfigModule.FiltersOrder - i + 1
                end

                local optionKey = ConfigModule.FiltersOrder[i]
                local filterButton = GetFilterButton(optionKey)
                filterButton:SetFrameLevel(50 + i)
                local rightMap = DataModule:IsFilterOnCorrectMap(optionKey, mapID)

                if ConfigModule:GetFilterDisabled(optionKey) or (not rightMap) then
                    filterButton:Hide()
                else
                    filterButton:Show()
                    filterButton:ClearAllPoints()

                    if prevFilter then
                        filterButton:SetPoint("RIGHT", prevFilter, "LEFT", 5, 0)
                        filterButton:SetPoint("TOP", prevButton, "TOP", 0, 2)
                    else
                        filterButton:SetPoint("LEFT", prevButton.CollapseButton, "LEFT", -22, 0)
                        filterButton:SetPoint("TOP", prevButton, "TOP", 0, 2)
                    end

                    if optionKey ~= "SORT" then
                        if selectedFilters[optionKey] then
                            filterButton:SetNormalAtlas("worldquest-tracker-ring-selected")
                        else
                            filterButton:SetNormalAtlas("worldquest-tracker-ring")
                        end
                    end
                    prevFilter = filterButton
                end
            end

            if #usedButtons > 0 then
                QuestScrollFrame.EmptyText:Hide()
                QuestScrollFrame.NoSearchResultsText:Hide()
            end

            table.sort(usedButtons, QuestSorter)

            for i, button in ipairs(usedButtons) do
                button.layoutIndex = i + 1
                button:Show()

                if hoveredQuestID == button.questID then
                    QuestButton_OnEnter(button)
                end
            end
        end

        headerButton.CollapseButton:UpdateCollapsedState(ConfigModule:Get("collapsed"))
        headerButton.CollapseButton:Show()

        if needsReposition then
            awqContainer.layoutIndex = nil
            QuestLogQuests_Update()

            if not awqContainer.layoutIndex then
                awqContainer.layoutIndex = 0.5
            end
        else
            QuestScrollFrame.Contents:Layout()
        end
    end

    function QuestFrameModule:QuestLog_AddQuestButton(questInfo, searchBoxText)
        local questID = questInfo.questID
        local title, factionID, _ = C_TaskQuest.GetQuestInfoByQuestID(questID)
        local questTagInfo = DataModule.GetCachedQuestTagInfo(questID)
        local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
        DataModule:RequestRewardPreload(questID)

        if (questTagInfo == nil) then
            return nil
        end

        if searchBoxText ~= "" and not title:lower():find(searchBoxText, 1, true) then
            return nil
        end

        local button = titleFramePool:Acquire()
        QuestButton_Initialize(button)

        local totalHeight = 8
        button.worldQuest = true
        button.questLogIndex = nil
        button.info = nil
        button.isHeader = nil
        button.isCollapsed = nil
        button.isInternalOnly = nil
        button.questID = questID
        button.mapID = questInfo.mapID
        button.factionID = factionID
        button.timeLeftMinutes = timeLeftMinutes
        button.numObjectives = questInfo.numObjectives
        button.infoX = questInfo.x
        button.infoY = questInfo.y
        -- Store title as awqTitle so Tooltip_BuildSafe can read it without
        -- calling GetText() on a FontString (issue #161).
        button.awqTitle = title
        button.Text:SetText(title)

        local color

        if ShouldQuestBeBonusColored(button.questID) then
            color = QUEST_REWARD_CONTEXT_FONT_COLOR
        else
            color = GetQuestDifficultyColor( UnitLevel("player") + QuestButton_RarityColorTable[questTagInfo.quality] )
        end

        button.Text:SetTextColor(color.r, color.g, color.b)

        -- Hard-coded line height: avoids GetFont/GetHeight/GetStringHeight which
        -- return SECRET in WoW 11.x when called from a tainted coroutine (issue #161).
        totalHeight = totalHeight + 14  -- 12pt rendered line height ≈ 14px

        if (WorldMap_IsWorldQuestEffectivelyTracked(questID)) then
            button.Checkbox.CheckMark:Show()
        else
            button.Checkbox.CheckMark:Hide()
        end

        local hasIcon = true
        button.TaskIcon:Show()
        button.TaskIcon:SetTexCoord(.08, .92, .08, .92)

        if questInfo.inProgress then
            button.TaskIcon:SetAtlas("worldquest-questmarker-questionmark")
            button.TaskIcon:SetSize(10, 15)
        else
            local atlas, width, height = QuestUtil.GetWorldQuestAtlasInfo(questID, questTagInfo, false)
            if atlas and atlas ~= "Worldquest-icon" then
                button.TaskIcon:SetAtlas(atlas)
                local w, h = math.min(width or 16, 16), math.min(height or 16, 16)
                button.TaskIcon:SetSize(w, h)
            elseif questTagInfo.isElite then
                button.TaskIcon:SetAtlas("questlog-questtypeicon-heroic")
                button.TaskIcon:SetSize(16, 16)
            else
                hasIcon = false
                button.TaskIcon:Hide()
            end
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

        button.HighlightTexture:SetShown(false)

        local tagText, tagTexture, tagTexCoords, tagColor
        tagColor = {r=1, g=1, b=1}

        local money = GetQuestLogRewardMoney(questID)

        if ( money > 0 ) then
            local gold = floor(money / (_AngrierWorldQuests.Constants.MONEY.COPPER_PER_GOLD))
            tagTexture = "Interface\\MoneyFrame\\UI-MoneyIcons"
            tagTexCoords = { 0, 0.25, 0, 1 }
            tagText = BreakUpLargeNumbers(gold)
            button.rewardCategory = "GOLD"
            button.rewardValue = gold
            button.rewardValue2 = 0
        end

        for _, currencyInfo in ipairs(C_QuestLog.GetQuestRewardCurrencies(questID)) do
            local texture, numItems, currencyID = currencyInfo.texture, currencyInfo.totalRewardAmount, currencyInfo.currencyID

            if currencyID ~= _AngrierWorldQuests.Constants.CURRENCY_IDS.WAR_SUPPLIES and currencyID ~= _AngrierWorldQuests.Constants.CURRENCY_IDS.NETHERSHARD then
                tagText = numItems
                tagTexture = texture
                tagTexCoords = nil

                if currencyID == _AngrierWorldQuests.Constants.CURRENCY_IDS.AZERITE then
                    tagColor = BAG_ITEM_QUALITY_COLORS[Enum.ItemQuality.Artifact]
                end

                button.rewardCategory = "CURRENCY"
                button.rewardValue = currencyID
                button.rewardValue2 = numItems
            end
        end

        local numQuestRewards = GetNumQuestLogRewards(questID)
        if numQuestRewards > 0 then
            local itemName, itemTexture, quantity, quality, _, itemID = GetQuestLogRewardInfo(1, questID)

            if itemName and itemTexture then
                local iLevel = DataModule:RewardItemLevel(itemID, questID)
                tagTexture = itemTexture
                tagTexCoords = nil

                if iLevel then
                    tagText = iLevel
                    tagColor = BAG_ITEM_QUALITY_COLORS[quality]
                    button.rewardCategory = "LOOT"
                    button.rewardValue = iLevel
                    button.rewardValue2 = 0
                else
                    tagText = quantity > 1 and quantity
                    button.rewardCategory = "ITEMS"
                    button.rewardValue = quantity
                    button.rewardValue2 = 0
                end

                if C_Item.IsAnimaItemByID(itemID) then
                    tagTexture = 3528288 -- Interface/Icons/Spell_AnimaBastion_Orb
                    tagColor = ANIMA_ITEM_COLOR
                    tagText = quantity * GetAnimaValue(itemID)
                end
            end
        end

        if tagTexture and tagText then
            button.TagText:Show()
            button.TagText:SetText(tagText)
            button.TagText:SetTextColor(tagColor.r, tagColor.g, tagColor.b)
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

        if tagTexture then
            if tagTexCoords then
                button.TagTexture:SetTexCoord( unpack(tagTexCoords) )
            else
                button.TagTexture:SetTexCoord(.08, .92, .08, .92)
            end
        end

        -- fixedHeight lets VerticalLayoutFrame read height without calling
        -- GetHeight() (which returns SECRET from a tainted coroutine — issue #161).
        button.fixedHeight = totalHeight
        button:SetHeight(totalHeight)
        button:Show()

        return button
    end

    function QuestFrameModule:InitQuestLogFrames()
        awqContainer = CreateFrame("Frame", "AngrierWorldQuestsContainer", QuestScrollFrame.Contents, "VerticalLayoutFrame")
        awqContainer.fixedWidth = 304
        awqContainer.bottomPadding = 2
        awqContainer:Hide()

        headerButton = CreateFrame("BUTTON", "AngrierWorldQuestsHeader", awqContainer, "QuestLogHeaderTemplate")
        headerButton:SetScript("OnClick", HeaderButton_OnClick)
        headerButton:SetText(TRACKER_HEADER_WORLD_QUESTS)
        headerButton.topPadding = 6
        headerButton.titleFramePool = titleFramePool
        headerButton.layoutIndex = 1

        local function ApplyLayoutIndex(_, frame)
            if awqContainer:IsShown()
                    and ConfigModule:Get("showAtTop")
                    and frame == QuestScrollFrame.Contents.Separator then
                awqContainer.layoutIndex = frame.layoutIndex + 0.5
            end
        end

        hooksecurefunc(QuestMapFrame, "SetFrameLayoutIndex", function(mapFrame, frame)
            ApplyLayoutIndex(mapFrame, frame)
        end)
    end

    function QuestFrameModule:IsLockedDown()
        if InCombatLockdown and InCombatLockdown() then
            return true
        end

        local inInstance, instanceType = IsInInstance()

        return inInstance and (instanceType == "pvp" or instanceType == "arena")
    end
end
--endregion

--region Initialization
do
    local function AddFilter(key, name, icon, default)
        local filter = {
            key = key,
            name = name,
            icon = "Interface\\Icons\\" .. icon,
            default = default,
            index = #ConfigModule.FiltersOrder + 1,
        }

        ConfigModule.Filters[key] = filter
        table.insert(ConfigModule.FiltersOrder, key)

        return filter
    end

    local function AddCurrencyFilter(key, currencyID, default)
        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        local name = currencyInfo.name
        local icon = currencyInfo.iconFileID

        local filter = {
            key = key,
            name = name,
            icon = icon,
            default = default,
            index = #ConfigModule.FiltersOrder + 1,
            preset = _AngrierWorldQuests.Constants.FILTERS.CURRENCY,
            currencyID = currencyID,
        }

        ConfigModule.Filters[key] = filter
        table.insert(ConfigModule.FiltersOrder, key)

        return filter
    end

    local function InitializeFilterLists()
        AddFilter("EMISSARY", BOUNTY_BOARD_LOCKED_TITLE, "achievement_reputation_01")
        AddFilter("TIME", CLOSES_IN, "ability_bossmagistrix_timewarp2")
        AddFilter("TRACKED", TRACKING, "icon_treasuremap")
        AddFilter("FACTION", FACTION, "achievement_reputation_06", true)
        AddFilter("LOOT", BONUS_ROLL_REWARD_ITEM, "inv_misc_lockboxghostiron", true)
        AddFilter("CONDUIT", L["CONDUIT_ITEMS"], "Spell_Shadow_SoulGem", true)
        AddFilter("ANIMA", POWER_TYPE_ANIMA, "Spell_AnimaBastion_Orb", true)

        AddCurrencyFilter("ORDER_RESOURCES", _AngrierWorldQuests.Constants.CURRENCY_IDS.RESOURCES, true)
        AddCurrencyFilter("WAKENING_ESSENCE", _AngrierWorldQuests.Constants.CURRENCY_IDS.WAKENING_ESSENCE)

        AddCurrencyFilter("AZERITE", _AngrierWorldQuests.Constants.CURRENCY_IDS.AZERITE)
        AddCurrencyFilter("WAR_RESOURCES", _AngrierWorldQuests.Constants.CURRENCY_IDS.WAR_RESOURCES)

        AddFilter("GOLD", BONUS_ROLL_REWARD_MONEY, "inv_misc_coin_01")
        AddFilter("ITEMS", ITEMS, "inv_box_01")
        AddFilter("PROFESSION", TRADE_SKILLS, "inv_misc_note_01", true)
        AddFilter("PETBATTLE", SHOW_PET_BATTLES_ON_MAP_TEXT, "tracking_wildpet", true)
        AddFilter("RARE", ITEM_QUALITY3_DESC, "achievement_general_stayclassy")
        AddFilter("DUNGEON", GROUP_FINDER, "inv_misc_summonable_boss_token")
        AddFilter("SORT", RAID_FRAME_SORT_LABEL, "inv_misc_map_01")

        ConfigModule.Filters.TIME.values = { 1, 3, 6, 12, 24 }
    end

    local function GetDataProvider()
        for dp, _ in pairs(WorldMapFrame.dataProviders) do
            if dp.AddWorldQuest and dp.AddWorldQuest == WorldMap_WorldQuestDataProviderMixin.AddWorldQuest then
                return dp
            end
        end

        return nil
    end

    local printedLockdownMessage = false

    local function PostProcessWorldQuestPins(dp)
        local map = dp:GetMap()

        if not map then
            return
        end

        if QuestFrameModule:IsLockedDown() then
            if not printedLockdownMessage then
                QuestFrameModule:Print(L["Skipping world quest pin update because player is in combat."])
                printedLockdownMessage = true
            end

            return
        else
            printedLockdownMessage = false
        end

        local mapID = map:GetMapID()
        local hideFilteredPOI = ConfigModule:Get("hideFilteredPOI")
        local hideUntrackedPOI = ConfigModule:Get("hideUntrackedPOI")
        local showHoveredPOI = ConfigModule:Get("showHoveredPOI")
        local showContinentPOI = ConfigModule:Get("showContinentPOI")

        local function ShouldFilterQuest(info)
            if showHoveredPOI and hoveredQuestID == info.questID then
                return false
            end

            if hideFilteredPOI and DataModule:IsQuestFiltered(info, mapID) then
                return true
            end

            if hideUntrackedPOI and not WorldMap_IsWorldQuestEffectivelyTracked(info.questID) then
                return true
            end

            return false
        end

        local function AddTrackedWorldQuestPin(info)
            local pin = dp:AddWorldQuest(info)

            if pin then
                local x, y = C_TaskQuest.GetQuestLocation(info.questID, info.mapID)
                local continentID, worldPosition = C_Map.GetWorldPosFromMapPos(info.mapID, { x = x, y = y })
                local translatedPos = select(2, C_Map.GetMapPosFromWorldPos(continentID, worldPosition, mapID))

                if translatedPos then
                    pin:SetPosition(translatedPos:GetXY())
                end

                table.insert(addonAddedPins, pin)
            end

            return pin
        end

        local function GetChildMapQuests()
            local quests = {}
            local childMapIDs = DataModule:GetMapIDsToGetQuestsFrom(mapID)

            for mID in pairs(childMapIDs) do
                if mID ~= mapID then
                    local taskInfo = C_TaskQuest.GetQuestsOnMap(mID)
                    if taskInfo then
                        for _, info in ipairs(taskInfo) do
                            table.insert(quests, info)
                        end
                    end
                end
            end

            return quests
        end

        local mapInfo = C_Map.GetMapInfo(mapID)
        local pinTemplate = dp.GetPinTemplate and dp:GetPinTemplate() or dp.pinTemplate

        if not pinTemplate or not map.pinPools or not map.pinPools[pinTemplate] then
            return
        end

        -- TAINT-SAFE FILTERING (issue #161)
        --
        -- pin:Hide() fires synchronous OnLeave/OnEnter mouse events.  If called
        -- from our tainted C_Timer callback while the cursor is near an Area POI
        -- pin, the Area POI's OnMouseEnter runs tainted.  Inside that chain,
        -- Blizzard calls self.Text:SetText() (tainted) on a UIWidget FontString.
        -- Once tainted, self.Text:GetStringHeight() permanently returns SECRET,
        -- causing arithmetic errors every time that widget is rendered or its
        -- timer fires — even from fully untainted Blizzard code.
        --
        -- The fix: NEVER call Hide() on pins.  Instead use:
        --   pin:SetAlpha(0)       — makes pin invisible (pure render, no events)
        --   pin:EnableMouse(false) — removes it from mouse hit-testing (no events)
        --
        -- Neither API fires OnEnter/OnLeave synchronously, so Area POI
        -- OnMouseEnter can never run in our tainted context.
        --
        -- Pass 1: restore alpha on any pins we previously hidden.
        -- SetAlpha(1) is purely visual and fires NO mouse events, so this is
        -- always safe regardless of cursor position.
        for pin in map.pinPools[pinTemplate]:EnumerateActive() do
            if pin.awqAlphaHidden then
                pin:SetAlpha(1)
                pin.awqAlphaHidden = nil
            end
        end

        -- Clean up stale addon-pin references (pins released by Blizzard's
        -- pool:ReleaseAll on the previous RefreshAllData are no longer active).
        -- We do NOT call map:RemovePin — that calls pin:Hide() internally.
        -- Blizzard's own pool management will release them on the next refresh.
        local activeSet = {}
        for pin in map.pinPools[pinTemplate]:EnumerateActive() do
            activeSet[pin] = true
        end
        local remainingAddonPins = {}
        for _, pin in ipairs(addonAddedPins) do
            if activeSet[pin] then
                table.insert(remainingAddonPins, pin)
            end
        end
        addonAddedPins = remainingAddonPins

        -- Pass 2: alpha-hide filtered pins.
        --
        -- ONLY SetAlpha(0) is used — no Hide(), EnableMouse(false), or
        -- SetHitRectInsets().  Every other API that affects mouse hit-testing
        -- (Hide, EnableMouse, SetHitRectInsets) fires a synchronous mouse-focus
        -- recalculation.  If the cursor is over the affected pin, that
        -- recalculation fires OnEnter on the Area POI beneath in our tainted
        -- C_Timer context, permanently tainting UIWidget FontString geometry
        -- values (issue #161).
        --
        -- SetAlpha(0) is purely visual: it makes the pin invisible but leaves
        -- it in the hit-test system.  No synchronous mouse events fire.
        -- Trade-off: invisible pins still intercept mouse input at their exact
        -- pixel positions, so Area POI tooltips may not appear directly under a
        -- filtered quest pin.  This is acceptable vs. permanent SECRET errors.
        for pin in map.pinPools[pinTemplate]:EnumerateActive() do
            if pin.questID and C_QuestLog.IsWorldQuest(pin.questID) then
                if ShouldFilterQuest({ questID = pin.questID, mapID = pin.mapID or mapID }) then
                    pin:SetAlpha(0)
                    pin.awqAlphaHidden = true
                end
            end
        end

        local unsafe = map:IsMouseOver() or GameTooltip:IsShown()
        if mapInfo and mapInfo.mapType == Enum.UIMapType.Continent and not unsafe then
            local childQuests = GetChildMapQuests()

            if showContinentPOI then
                local shownQuests = {}
                for pin in map.pinPools[pinTemplate]:EnumerateActive() do
                    if pin.questID then
                        shownQuests[pin.questID] = true
                    end
                end

                for _, info in ipairs(childQuests) do
                    if not shownQuests[info.questID]
                        and HaveQuestData(info.questID)
                        and QuestUtils_IsQuestWorldQuest(info.questID)
                        and WorldMap_DoesWorldQuestInfoPassFilters(info)
                        and DataModule:GetContentMapIDFromMapID(info.mapID) == mapID
                        and not ShouldFilterQuest(info) then

                        AddTrackedWorldQuestPin(info)
                        shownQuests[info.questID] = true
                    end
                end
            end

            local superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
            if superTrackedQuestID and superTrackedQuestID > 0 then
                local hasPin = false
                for pin in map.pinPools[pinTemplate]:EnumerateActive() do
                    if pin.questID == superTrackedQuestID then
                        hasPin = true
                        break
                    end
                end

                if not hasPin and QuestUtils_IsQuestWorldQuest(superTrackedQuestID) then
                    for _, info in ipairs(childQuests) do
                        if info.questID == superTrackedQuestID then
                            AddTrackedWorldQuestPin(info)
                            break
                        end
                    end
                end
            end
        end
    end

    function QuestFrameModule:InitializeProvider()
        local dp = GetDataProvider()

        if dp ~= nil then
            dataProvider = dp

            -- Defer PostProcessWorldQuestPins via C_Timer.After(0) so it runs from
            -- WoW's game-loop in a fresh untainted coroutine.
            --
            -- hooksecurefunc hooks always run in a tainted coroutine.  Any frame
            -- Show/Hide called from a tainted coroutine can synchronously fire
            -- OnMouseEnter on a newly-exposed AreaPOI pin in that same tainted
            -- coroutine, causing UIWidget C APIs to return SECRET values and
            -- arithmetic on them to error (issue #161).
            --
            -- Note: securecallfunction protects a SECURE caller from being tainted
            -- by a tainted callee — it cannot make tainted code run securely.
            -- C_Timer.After(0) is the correct solution here.
            local postProcessPending = false
            hooksecurefunc(dataProvider, "RefreshAllData", function(dpArg)
                if postProcessPending then return end
                postProcessPending = true
                C_Timer.After(0, function()
                    postProcessPending = false
                    PostProcessWorldQuestPins(dpArg)
                end)
            end)
        end
    end

    function QuestFrameModule:ApplyWorkarounds()
        do
            local lastTrackedQuestID = nil

            function QuestUtil.TrackWorldQuest(questID, watchType)
                if C_QuestLog.AddWorldQuestWatch(questID, watchType) then
                    if lastTrackedQuestID and lastTrackedQuestID ~= questID then
                        if C_QuestLog.GetQuestWatchType(lastTrackedQuestID) ~= Enum.QuestWatchType.Manual and watchType == Enum.QuestWatchType.Manual then
                            C_QuestLog.AddWorldQuestWatch(lastTrackedQuestID, Enum.QuestWatchType.Manual);
                        end
                    end
                    lastTrackedQuestID = questID;
                end

                if watchType == Enum.QuestWatchType.Automatic then
                    local forceAllowTasks = true;
                    QuestUtil.CheckAutoSuperTrackQuest(questID, forceAllowTasks);
                end
            end

            function QuestUtil.UntrackWorldQuest(questID)
                if C_QuestLog.RemoveWorldQuestWatch(questID) then
                    if lastTrackedQuestID == questID then
                        lastTrackedQuestID = nil;
                    end
                end
            end
        end
    end

    function QuestFrameModule:ExtendMapMenu()
        Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, rootDescription, _)
            rootDescription:AddMenuResponseCallback(function()
                QuestFrameModule:RequestFullRefresh("MENU_WORLD_MAP_TRACKING")
            end)

            rootDescription:CreateDivider()
            local awqMenu = rootDescription:CreateButton(AngrierWorldQuests.Name)

            local mapID = QuestMapFrame and QuestMapFrame:GetParent():GetMapID()

            awqMenu:CreateTitle(TRACKER_FILTER_QUESTS or FILTERS)

            for _, optionKey in ipairs(ConfigModule.FiltersOrder) do
                if optionKey ~= "SORT" then
                    local filter = ConfigModule.Filters[optionKey]

                    if not ConfigModule:GetFilterDisabled(optionKey) and (not mapID or DataModule:IsFilterOnCorrectMap(optionKey, mapID)) then
                        local filterButton = awqMenu:CreateCheckbox(
                            filter.name,
                            function() return ConfigModule:GetFilter(optionKey) end,
                            function()
                                if IsShiftKeyDown() then
                                    ConfigModule:ToggleFilter(optionKey)
                                else
                                    if ConfigModule:IsOnlyFilter(optionKey) then
                                        ConfigModule:SetNoFilter()
                                    else
                                        ConfigModule:SetOnlyFilter(optionKey)
                                    end
                                end
                            end
                        )

                        if filter.icon then
                            filterButton:AddInitializer(function(button)
                                local tex = button:AttachTexture()
                                tex:SetTexture(filter.icon)
                                tex:SetSize(16, 16)
                                tex:SetPoint("RIGHT")
                            end)
                        end
                    end
                end
            end

            awqMenu:CreateDivider()
            awqMenu:CreateTitle(RAID_FRAME_SORT_LABEL)

            for _, sortIndex in ipairs(ConfigModule.SortOrder) do
                awqMenu:CreateRadio(
                    L["config_sortMethod_" .. sortIndex],
                    function() return ConfigModule:Get("sortMethod") == sortIndex end,
                    function()
                        ConfigModule:Set("sortMethod", sortIndex)
                    end
                )
            end

            awqMenu:CreateDivider()
            awqMenu:CreateTitle(DISPLAY_OPTIONS or OPTIONS)

            awqMenu:CreateCheckbox(
                L["config_hideFilteredPOI"] or "Hide Filtered POI",
                function() return ConfigModule:Get("hideFilteredPOI") end,
                function() ConfigModule:Set("hideFilteredPOI", tostring(not ConfigModule:Get("hideFilteredPOI"))) end
            )

            awqMenu:CreateCheckbox(
                L["config_hideUntrackedPOI"] or "Hide Untracked POI",
                function() return ConfigModule:Get("hideUntrackedPOI") end,
                function() ConfigModule:Set("hideUntrackedPOI", tostring(not ConfigModule:Get("hideUntrackedPOI"))) end
            )

            awqMenu:CreateCheckbox(
                L["config_showContinentPOI"] or "Show Continent POI",
                function() return ConfigModule:Get("showContinentPOI") end,
                function() ConfigModule:Set("showContinentPOI", tostring(not ConfigModule:Get("showContinentPOI"))) end
            )

            awqMenu:CreateCheckbox(
                L["config_onlyCurrentZone"] or "Only Current Zone",
                function() return ConfigModule:Get("onlyCurrentZone") end,
                function() ConfigModule:Set("onlyCurrentZone", tostring(not ConfigModule:Get("onlyCurrentZone"))) end
            )
        end)
    end

    function QuestFrameModule:RegisterCallbacks()
        ConfigModule:RegisterCallback("showAtTop", function()
            QuestFrameModule:RequestQuestLogUpdate()
        end)

        ConfigModule:RegisterCallback({ "hideUntrackedPOI", "hideFilteredPOI", "showContinentPOI", "onlyCurrentZone", "sortMethod", "selectedFilters","disabledFilters", "filterEmissary", "filterLoot", "filterFaction", "filterZone", "filterTime", "lootFilterUpgrades", "lootUpgradesLevel", "timeFilterDuration" }, function(key)
            self:RequestFullRefresh(key)
        end)
    end

    function QuestFrameModule:OnInitialize()
        InitializeFilterLists()
    end

    function QuestFrameModule:OnEnable()
        self:InitializeProvider()
        self:ApplyWorkarounds()
        self:ExtendMapMenu()

        titleFramePool = CreateFramePool("BUTTON", QuestScrollFrame.Contents, "QuestLogTitleTemplate")

        self:InitQuestLogFrames()

        hooksecurefunc("QuestLogQuests_Update", function()
            self:RequestQuestLogUpdate()
        end)

        hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
            self:RequestQuestLogUpdate()
        end)

        self:RegisterCallbacks()
    end
end
--endregion

function QuestFrameModule:RequestQuestLogUpdate()
    if listRefreshPending then
        return
    end

    listRefreshPending = true
    C_Timer.After(0.05, function()
        listRefreshPending = false
        -- Skip when any tooltip is shown.  QuestLog_Update hides/shows quest
        -- log buttons (children of WorldMapFrame) from tainted code; this can
        -- trigger a canvas mouse-focus recalculation and fire Area POI OnEnter
        -- in our tainted context, causing UIWidget SECRET errors (issue #161).
        -- The next QuestLogQuests_Update event reschedules naturally.
        if QuestMapFrame and QuestMapFrame:IsShown() and not GameTooltip:IsShown() then
            QuestFrameModule:QuestLog_Update()
        end
    end)
end

function QuestFrameModule:RequestFullRefresh(reason)
    fullRefreshDirty = true
    fullRefreshReason = reason or fullRefreshReason or "unknown"

    if fullRefreshPending then
        return
    end

    fullRefreshPending = true
    C_Timer.After(0.1, function()
        fullRefreshPending = false

        if not fullRefreshDirty then
            return
        end

        -- Also defer if any tooltip is currently shown.  QuestLogQuests_Update
        -- hides/shows WorldMapFrame children from tainted code; if the user is
        -- hovering over an Area POI at that instant the mouse-focus
        -- recalculation fires Area POI OnEnter tainted, permanently tainting
        -- UIWidget FontString values (issue #161).
        if not CanApplyFullRefresh() or GameTooltip:IsShown() then
            fullRefreshRetryCount = fullRefreshRetryCount + 1

            if fullRefreshRetryCount <= 20 then
                QuestFrameModule:RequestFullRefresh(fullRefreshReason or "retry")
            else
                DebugLog(string.format("Skipped map refresh after %d retries (%s)", fullRefreshRetryCount, fullRefreshReason or "unknown"))
                fullRefreshDirty = false
                fullRefreshRetryCount = 0
                fullRefreshReason = nil
            end

            return
        end

        local reasonText = fullRefreshReason or "unknown"
        fullRefreshDirty = false
        fullRefreshRetryCount = 0
        fullRefreshReason = nil

        DebugLog(string.format("Applying full refresh (%s)", reasonText))
        QuestLogQuests_Update()

        -- Do NOT call dataProvider:RefreshAllData() directly from addon code.
        -- Addon code is tainted; calling RefreshAllData() from here taints the
        -- entire synchronous call-chain including any OnMouseEnter handlers for
        -- Area POI pins that may fire while pins are being recreated.  This causes
        -- UIWidget C APIs (e.g. GetWidth) to return SECRET values and triggers the
        -- "attempt to perform arithmetic on a secret number value" error (#161).
        --
        -- Instead we rely on Blizzard's own event-driven refresh cycle.
        -- When QuestLogQuests_Update() runs it fires QUEST_LOG_UPDATE and similar
        -- events that cause the WorldQuestDataProvider to call RefreshAllData()
        -- from its own (untainted) Lua context.  Our hooksecurefunc post-hook on
        -- RefreshAllData then defers PostProcessWorldQuestPins via C_Timer.After(0)
        -- as normal.
    end)
end