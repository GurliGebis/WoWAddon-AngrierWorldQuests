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

--region Variables

local dataProvider
local hoveredQuestID
local titleFramePool
local rewardPreloadRequested = {}
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

local function SafeCall(func, ...)
    if securecallfunction then
        securecallfunction(func, ...)
    else
        func(...)
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
    local filterMenu
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

    local function FilterMenu_OnClick(self, key)
        if key == "EMISSARY" then
            ConfigModule:Set("filterEmissary", self.value, true)
        elseif key == "LOOT" then
            ConfigModule:Set("filterLoot", self.value, true)
        elseif key == "FACTION" then
            ConfigModule:Set("filterFaction", self.value, true)
        elseif key == "ZONE" then
            ConfigModule:Set("filterZone", self.value, true)
        elseif key == "TIME" then
            ConfigModule:Set("filterTime", self.value, true)
        end

        if key == "SORT" then
            ConfigModule:Set("sortMethod", self.value)
        elseif IsShiftKeyDown() then
            ConfigModule:SetFilter(key, true)
        else
            ConfigModule:SetOnlyFilter(key)
        end
    end

    local function FilterMenu_Initialize(self, level)
        local info = { func = FilterMenu_OnClick, arg1 = self.filter }
        if self.filter == "EMISSARY" then
            local value = ConfigModule:Get("filterEmissary")
            if not C_QuestLog.IsOnQuest(value) then value = 0 end -- specific bounty not found, show all

            info.text = ALL
            info.value = 0
            info.checked = info.value == value
            AWQ_UIDropDownMenu_AddButton(info, level)

            local mapID = QuestMapFrame:GetParent():GetMapID()
            if mapID == _AngrierWorldQuests.Constants.MAP_IDS.BROKENISLES then mapID = _AngrierWorldQuests.Constants.MAP_IDS.DALARAN end -- fix no emissary on broken isles continent map
            local bounties = C_QuestLog.GetBountiesForMapID(mapID)
            if bounties then
                for _, bounty in ipairs(bounties) do
                    if not C_QuestLog.IsComplete(bounty.questID) then
                        info.text =  C_QuestLog.GetTitleForQuestID(bounty.questID)
                        info.icon = bounty.icon
                        info.value = bounty.questID
                        info.checked = info.value == value
                        AWQ_UIDropDownMenu_AddButton(info, level)
                    end
                end
            end
        elseif self.filter == "LOOT" then
            local value = ConfigModule:Get("filterLoot")
            if value == 0 then value = ConfigModule:Get("lootFilterUpgrades") and _AngrierWorldQuests.Constants.FILTERS.LOOT_UPGRADES or _AngrierWorldQuests.Constants.FILTERS.LOOT_ALL end

            info.text = ALL
            info.value = _AngrierWorldQuests.Constants.FILTERS.LOOT_ALL
            info.checked = info.value == value
            AWQ_UIDropDownMenu_AddButton(info, level)

            info.text = L["UPGRADES"]
            info.value = _AngrierWorldQuests.Constants.FILTERS.LOOT_UPGRADES
            info.checked = info.value == value
            AWQ_UIDropDownMenu_AddButton(info, level)
        elseif self.filter == "ZONE" then
            local value = ConfigModule:Get("filterZone")

            info.text = L["CURRENT_ZONE"]
            info.value = 0
            info.checked = info.value == value
            AWQ_UIDropDownMenu_AddButton(info, level)
        elseif self.filter == "FACTION" then
            local value = ConfigModule:Get("filterFaction")

            local mapID = QuestMapFrame:GetParent():GetMapID()
            local factions = DataModule:GetFactionsByMapID(mapID)

            for _, factionID in ipairs(factions) do
                local factionData = C_Reputation.GetFactionDataByID(factionID)
                info.text = factionData.name
                info.value = factionID
                info.checked = info.value == value
                AWQ_UIDropDownMenu_AddButton(info, level)
            end
        elseif self.filter == "TIME" then
            local filterTime = ConfigModule:Get("filterTime")
            local timeFilterDuration = ConfigModule:Get("timeFilterDuration")
            local value = filterTime ~= 0 and filterTime or timeFilterDuration

            for _, hours in ipairs(ConfigModule.Filters.TIME.values) do
                info.text = string.format(FORMATED_HOURS, hours)
                info.value = hours
                info.checked = info.value == value
                AWQ_UIDropDownMenu_AddButton(info, level)
            end
        elseif self.filter == "SORT" then
            local value = ConfigModule:Get("sortMethod")

            info.text = ConfigModule.Filters[ self.filter ].name
            info.notCheckable = true
            info.isTitle = true
            AWQ_UIDropDownMenu_AddButton(info, level)

            info.notCheckable = false
            info.isTitle = false
            info.disabled = false
            for _, sortIndex in ipairs(ConfigModule.SortOrder) do
                info.text =  L["config_sortMethod_"..sortIndex]
                info.value = sortIndex
                info.checked = info.value == value
                AWQ_UIDropDownMenu_AddButton(info, level)
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

            if title then
                text = text..": "..title
            end
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
        if not filterMenu then
            filterMenu = CreateFrame("Button", "DropDownMenuAWQ", QuestMapFrame, AWQ_UIDropDownMenuTemplate)
        end

        filterMenu.filter = self.filter
        AWQ_UIDropDownMenu_Initialize(filterMenu, FilterMenu_Initialize, "MENU")
        AWQ_ToggleDropDownMenu(1, nil, filterMenu, self, 0, 0)
    end

    local function FilterButton_OnClick(self, button)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if (button == "RightButton" and (self.filter == "EMISSARY" or self.filter == "LOOT" or self.filter == "FACTION" or self.filter == "TIME"))
                or (self.filter == "SORT")
                or (self.filter == "FACTION" and not ConfigModule:GetFilter("FACTION")) then

            local MY_UIDROPDOWNMENU_OPEN_MENU = Lib_UIDropDownMenu_Initialize and LIB_UIDROPDOWNMENU_OPEN_MENU or UIDROPDOWNMENU_OPEN_MENU

            if filterMenu and MY_UIDROPDOWNMENU_OPEN_MENU == filterMenu and AWQ_DropDownList1:IsShown() and filterMenu.filter == self.filter then
                AWQ_HideDropDownMenu(1)
            else
                AWQ_HideDropDownMenu(1)
                FilterButton_ShowMenu(self)
            end
        else
            AWQ_HideDropDownMenu(1)
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

    local questTagInfoCache = {}
    function QuestFrameModule.GetCachedQuestTagInfo(questID)
        if not questTagInfoCache[questID] then
            questTagInfoCache[questID] = C_QuestLog.GetQuestTagInfo(questID)
        end

        return questTagInfoCache[questID]
    end

    local function QuestButton_OnEnter(self)
        local questTagInfo = QuestFrameModule.GetCachedQuestTagInfo(self.questID)

        local color

        if ShouldQuestBeBonusColored(self.questID) then
            color = QUEST_BONUS_COLOR
        else
            _, color = GetQuestDifficultyColor( UnitLevel("player") + QuestButton_RarityColorTable[questTagInfo.quality] )
        end

        self.Text:SetTextColor( color.r, color.g, color.b )

        hoveredQuestID = self.questID

        self.HighlightTexture:SetShown(true);
        QuestFrameModule.Tooltip_BuildSafe(self)
    end

    local function QuestButton_OnLeave(self)
        local questTagInfo = QuestFrameModule.GetCachedQuestTagInfo(self.questID)

        local color

        if ShouldQuestBeBonusColored(self.questID) then
            color = QUEST_REWARD_CONTEXT_FONT_COLOR
        else
            color = GetQuestDifficultyColor( UnitLevel("player") + QuestButton_RarityColorTable[questTagInfo.quality] )
        end

        self.Text:SetTextColor( color.r, color.g, color.b )

        hoveredQuestID = nil

        self.HighlightTexture:SetShown(false);

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

        button.TagTexture:SetSize(16, 16)
        button.TagTexture:Hide()

        button.StorylineTexture:Hide()

        button.TagText = button:CreateFontString(nil, nil, "GameFontNormalLeft")
        button.TagText:SetJustifyH("RIGHT")
        button.TagText:SetTextColor(1, 1, 1)
        button.TagText:SetPoint("RIGHT", button.TagTexture, "LEFT", -2, 0)
        button.TagText:SetWidth(32)
        button.TagText:Hide()

        button.Text:ClearPoint("RIGHT")
        button.Text:SetPoint("RIGHT", button.TagText, "LEFT", -4, 0)
        button.Text:SetWidth(196)

        button.TaskIcon:ClearAllPoints()
        button.TaskIcon:SetPoint("RIGHT", button.Text, "LEFT", -4, 0)

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
        wipe(questTagInfoCache)
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

            local addedQuests = {}
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
                                        local button = QuestFrameModule:QuestLog_AddQuestButton(info, searchBoxText)

                                        if button ~= nil then
                                            table.insert(usedButtons, button)
                                            addedQuests[info.questID] = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if #usedButtons > 0 then
                -- In the situation where the normal quest log is empty, but we have world quests.
                -- We shouldn't show the empty quest log text.
                QuestScrollFrame.EmptyText:Hide()

                -- We need to also make sure the "No search results" text is hidden.
                QuestScrollFrame.NoSearchResultsText:Hide()
            elseif ConfigModule:HasFilters() == false then
                -- We should only hide the header, if no filters are active.
                QuestFrameModule:HideWorldQuestsHeader()
                return
            end

            table.sort(usedButtons, QuestSorter)

            for i, button in ipairs(usedButtons) do
                -- layoutIndex starts at 2 (headerButton is 1); all addon-owned integers.
                button.layoutIndex = i + 1

                -- Add bottom padding only on the last button so there is a small
                -- gap between the world quests section and whatever follows it.
                button.bottomPadding = (i == #usedButtons) and 6 or nil
                button:Show()

                if hoveredQuestID == button.questID then
                    QuestButton_OnEnter(button)
                end
            end
        end

        headerButton.CollapseButton:UpdateCollapsedState(ConfigModule:Get("collapsed"))
        headerButton.CollapseButton:Show()

        if needsReposition then
            -- awqContainer wasn't shown when QuestLogQuests_Update ran, so the hook
            -- couldn't assign a real layoutIndex. Clear it, re-run QuestLogQuests_Update
            -- so the hook fires with awqContainer shown and assigns the correct
            -- separator + 1 index. If the hook still doesn't fire (no campaign quests /
            -- no separator), fall back to 0.5 so the container sorts to the very top.
            awqContainer.layoutIndex = nil
            SafeCall(QuestLogQuests_Update)

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
        local questTagInfo = QuestFrameModule.GetCachedQuestTagInfo(questID)
        local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
        QuestFrameModule:RequestRewardPreload(questID)

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
        button.Text:SetText(title)

        local color

        if ShouldQuestBeBonusColored(button.questID) then
            color = QUEST_REWARD_CONTEXT_FONT_COLOR
        else
            color = GetQuestDifficultyColor( UnitLevel("player") + QuestButton_RarityColorTable[questTagInfo.quality] )
        end

        button.Text:SetTextColor( color.r, color.g, color.b )

        totalHeight = totalHeight + button.Text:GetHeight()

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
            local atlas, width, height = QuestUtil.GetWorldQuestAtlasInfo(questID, questTagInfo, false);
            if atlas and atlas ~= "Worldquest-icon" then
                button.TaskIcon:SetAtlas(atlas);
                button.TaskIcon:SetSize(math.min(width, 16), math.min(height, 16));
            elseif questTagInfo.isElite then
                button.TaskIcon:SetAtlas("questlog-questtypeicon-heroic")
                button.TaskIcon:SetSize(16, 16);
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

        button.HighlightTexture:SetShown(false);

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

        if tagTexture then
            if tagTexCoords then
                button.TagTexture:SetTexCoord( unpack(tagTexCoords) )
            else
                button.TagTexture:SetTexCoord(.08, .92, .08, .92)
            end
        end

        button:SetHeight(totalHeight)
        button:Show()

        return button
    end

    function QuestFrameModule:InitQuestLogFrames()
        awqContainer = CreateFrame("Frame", "AngrierWorldQuestsContainer", QuestScrollFrame.Contents, "VerticalLayoutFrame")
        awqContainer.fixedWidth = QuestScrollFrame.Contents:GetWidth()
        awqContainer.bottomPadding = 2
        awqContainer:Hide()

        headerButton = CreateFrame("BUTTON", "AngrierWorldQuestsHeader", awqContainer, "QuestLogHeaderTemplate")
        headerButton:SetScript("OnClick", HeaderButton_OnClick)
        headerButton:SetText(TRACKER_HEADER_WORLD_QUESTS)
        headerButton.topPadding = 6
        headerButton.titleFramePool = titleFramePool
        headerButton.layoutIndex = 1

        hooksecurefunc(QuestMapFrame, "SetFrameLayoutIndex", function(mapFrame, frame)
            if awqContainer:IsShown()
                    and ConfigModule:Get("showAtTop")
                    and frame == QuestScrollFrame.Contents.Separator then
                mapFrame:SetFrameLayoutIndex(awqContainer)
            end
        end)
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

        if InCombatLockdown and InCombatLockdown() then
            if not printedLockdownMessage then
                QuestFrameModule:Print(L["Skipping world quest pin update because player is in combat."])
                printedLockdownMessage = true
            end

            return
        else
            printedLockdownMessage = false
        end

        local mapID = map:GetMapID()

        -- Cache configuration values
        local hideFilteredPOI = ConfigModule:Get("hideFilteredPOI")
        local hideUntrackedPOI = ConfigModule:Get("hideUntrackedPOI")
        local showHoveredPOI = ConfigModule:Get("showHoveredPOI")
        local showContinentPOI = ConfigModule:Get("showContinentPOI")

        -- Returns true if a quest should be hidden based on the current filter and
        -- tracking settings. This is shared between hiding existing pins (Phase 1)
        -- and deciding whether to add new child-zone pins (Phase 2).
        local function ShouldFilterQuest(info)
            if hideFilteredPOI then
                if DataModule:IsQuestFiltered(info, mapID) then
                    return true
                end
            end

            if hideUntrackedPOI then
                if not WorldMap_IsWorldQuestEffectivelyTracked(info.questID) then
                    return true
                end
            end

            return false
        end

        -- Adds a world quest pin via the data provider and records it so it can be
        -- cleaned up on the next refresh (Phase 0).
        local function AddTrackedWorldQuestPin(info)
            local pin = dp:AddWorldQuest(info)

            if pin then
                -- Translate pin position from child zone to continent coordinates
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

        -- Collects quest info tables from all child zones of the given continent
        -- map, excluding the continent map itself.  Returns a flat list.
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

        -- Phase 0: Remove any pins we previously added (from Phase 2 of a prior
        -- refresh or a different map). This ensures stale addon-added pins don't
        -- persist across map changes.
        for _, pin in ipairs(addonAddedPins) do
            map:RemovePin(pin)
        end
        wipe(addonAddedPins)

        -- Phase 1: Hide pins that our filter settings reject
        for pin in map.pinPools[pinTemplate]:EnumerateActive() do
            if pin.questID and C_QuestLog.IsWorldQuest(pin.questID) then
                local shouldHide = ShouldFilterQuest({ questID = pin.questID, mapID = pin.mapID or mapID })

                -- Always show the hovered quest even if it would be filtered
                if showHoveredPOI and hoveredQuestID == pin.questID then
                    shouldHide = false
                end

                if shouldHide then
                    pin:Hide()
                else
                    pin:Show()
                end
            end
        end

        -- Phase 2: Add world quest pins from child zones on continent maps
        if mapInfo and mapInfo.mapType == Enum.UIMapType.Continent then
            local childQuests = GetChildMapQuests()

            if showContinentPOI then
                -- Collect already-shown questIDs to avoid duplicates
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

            -- Ensure the supertracked quest is visible on continent maps
            -- even when showContinentPOI is disabled (matches original ShouldMapShowQuest behavior)
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

            -- Use hooksecurefunc to post-process pins after Blizzard's untainted RefreshAllData completes.
            -- This keeps the data provider instance clean so taint doesn't propagate to other data providers
            -- (AreaPOI, etc.) via secureexecuterange in RefreshAllDataProviders.
            hooksecurefunc(dataProvider, "RefreshAllData", function(self)
                PostProcessWorldQuestPins(self)
            end)
        end
    end

    function QuestFrameModule:ApplyWorkarounds()
        -- Override QuestUtil.TrackWorldQuest/UntrackWorldQuest to remove the
        -- ObjectiveTrackerManager:UpdateAll() call that Blizzard's code calls.
        -- When called from addon code the taint propagates into the objective tracker,
        -- blocking protected actions like UseQuestLogSpecialItem(). See issue #67.
        do
            local lastTrackedQuestID = nil

            function QuestUtil.TrackWorldQuest(questID, watchType)
                if C_QuestLog.AddWorldQuestWatch(questID, watchType) then
                    if lastTrackedQuestID and lastTrackedQuestID ~= questID then
                        if C_QuestLog.GetQuestWatchType(lastTrackedQuestID) ~= Enum.QuestWatchType.Manual and watchType == Enum.QuestWatchType.Manual then
                            C_QuestLog.AddWorldQuestWatch(lastTrackedQuestID, Enum.QuestWatchType.Manual); -- Promote to manual watch
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
                -- Don't call ObjectiveTrackerManager:UpdateAll() here, see issue #67.
                --ObjectiveTrackerManager:UpdateAll();
            end
        end
    end

    function QuestFrameModule:ExtendMapMenu()
        Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, rootDescription, _)
            rootDescription:AddMenuResponseCallback(function()
                QuestFrameModule:RequestFullRefresh("MENU_WORLD_MAP_TRACKING")
            end)

            -- Add our filters as a submenu below Blizzard's tracking options
            rootDescription:CreateDivider()
            local awqMenu = rootDescription:CreateButton(AngrierWorldQuests.Name)

            local mapID = QuestMapFrame and QuestMapFrame:GetParent():GetMapID()

            -- Reward/type filters
            awqMenu:CreateTitle(TRACKER_FILTER_QUESTS or FILTERS)

            for _, optionKey in ipairs(ConfigModule.FiltersOrder) do
                if optionKey ~= "SORT" then
                    local filter = ConfigModule.Filters[optionKey]

                    -- Skip filters not relevant to the current map
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

            -- Sort options
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

            -- Display options
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

        -- Create awqContainer and headerButton inside the QuestLog upvalue scope,
        -- and register the SetFrameLayoutIndex hook there too (the hook closure must
        -- capture awqContainer from that scope). Must happen after titleFramePool is
        -- created (headerButton references it).
        self:InitQuestLogFrames()

        hooksecurefunc("QuestLogQuests_Update", function()
            self:RequestQuestLogUpdate()
        end)

        -- Refresh the quest list when the user navigates between maps
        -- (e.g. right-clicking to zoom into a zone) so stale entries from
        -- the previous map are removed and the correct quests are shown.
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
            self:RequestQuestLogUpdate()
        end)

        self:RegisterCallbacks()
    end
end
--endregion

function QuestFrameModule:RequestRewardPreload(questID)
    if not questID then
        return
    end

    if rewardPreloadRequested[questID] then
        return
    end

    rewardPreloadRequested[questID] = true
    C_TaskQuest.RequestPreloadRewardData(questID)
end

function QuestFrameModule:RequestQuestLogUpdate()
    if listRefreshPending then
        return
    end

    listRefreshPending = true
    C_Timer.After(0.05, function()
        listRefreshPending = false
        if QuestMapFrame and QuestMapFrame:IsShown() then
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

        if not CanApplyFullRefresh() then
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
        SafeCall(QuestLogQuests_Update)

        -- Also refresh the world quest data provider so our post-process hook
        -- re-applies pin filtering/visibility with the updated settings.
        if dataProvider and dataProvider.RefreshAllData then
            dataProvider:RefreshAllData()
        end
    end)
end