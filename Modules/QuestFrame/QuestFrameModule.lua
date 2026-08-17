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
-- Hoisted out of the QuestLog region so the taint-safe refresh triggers
-- (defined after it) can schedule pin post-processing (issues #161/#168).
local PostProcessWorldQuestPins
local hoveredQuestID
local titleFramePool
local listRefreshPending = false
local fullRefreshPending = false
local fullRefreshDirty = false
local fullRefreshRetryCount = 0
local fullRefreshReason
local addonAddedPins = {}

-- Cache of per-quest filter decisions, populated by QuestLog_Update in a
-- non-secure context and read back by PostProcessWorldQuestPins.  This keeps
-- the reward-money read (GetQuestLogRewardMoney, via DataModule:IsQuestFiltered)
-- OUT of Blizzard's secure RefreshAllData execution range, where it would taint
-- the quest's money value and break the gold-reward tooltip on hover (issue #156).
local filterDecisionCache = {}
local filterDecisionMapID

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

-- Recompute the per-quest filter-decision cache for the given map.  The reward
-- reads inside DataModule:IsQuestFiltered (GetQuestLogRewardMoney) run here, in a
-- non-secure context, so PostProcessWorldQuestPins can apply hide-filtered from
-- the cache without re-reading reward money inside Blizzard's secure
-- RefreshAllData range (which taints the money and breaks gold tooltips, #156).
local function RebuildFilterDecisionCache(mapID)
    wipe(filterDecisionCache)
    filterDecisionMapID = mapID

    if not mapID then
        return
    end

    local displayMapIDs = DataModule:GetMapIDsToGetQuestsFrom(mapID)

    for mID in pairs(displayMapIDs) do
        local taskInfo = C_TaskQuest.GetQuestsOnMap(mID)

        if taskInfo then
            for _, info in ipairs(taskInfo) do
                if HaveQuestData(info.questID) and QuestUtils_IsQuestWorldQuest(info.questID) then
                    if WorldMap_DoesWorldQuestInfoPassFilters(info) then
                        filterDecisionCache[info.questID] = DataModule:IsQuestFiltered(info, mapID) or false
                    end
                end
            end
        end
    end
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

    -- Executes a deferred tracking action with a clean execution context:
    -- TrackWorldQuest/UntrackWorldQuest and SetSuperTrackedQuestID kick off
    -- Blizzard's objective-tracker and quest-log chains; run from the addon's
    -- C_Timer attribution they tainted those chains (#67, #168).
    local function RunTrackingDeferred(action)
        C_Timer.After(0, function()
            securecallfunction(action)
        end)
    end

    local function QuestButton_OnClick(self, button)
        if ( not ChatEdit_TryInsertQuestLinkForQuestID(self.questID) ) then
            local watchType = C_QuestLog.GetQuestWatchType(self.questID)
            local isSuperTracked = C_SuperTrack.GetSuperTrackedQuestID() == self.questID

            if ( button == "RightButton" ) then
                if ( self.mapID ) then
                    QuestMapFrame:GetParent():SetMapID(self.mapID)
                end
            elseif IsShiftKeyDown() then
                if watchType == Enum.QuestWatchType.Manual or (watchType == Enum.QuestWatchType.Automatic and isSuperTracked) then
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                    RunTrackingDeferred(function() QuestUtil.UntrackWorldQuest(self.questID) end)
                else
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                    RunTrackingDeferred(function() QuestUtil.TrackWorldQuest(self.questID, Enum.QuestWatchType.Manual) end)
                end
            else
                if isSuperTracked then
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                    RunTrackingDeferred(function() C_SuperTrack.SetSuperTrackedQuestID(0) end)
                else
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                    RunTrackingDeferred(function()
                        if watchType ~= Enum.QuestWatchType.Manual then
                            QuestUtil.TrackWorldQuest(self.questID, Enum.QuestWatchType.Automatic)
                        end

                        C_SuperTrack.SetSuperTrackedQuestID(self.questID)
                    end)
                end
            end
        end
    end

    local function QuestButton_ToggleTracking(self)
        local watchType = C_QuestLog.GetQuestWatchType(self.questID)

        if watchType == Enum.QuestWatchType.Manual or (watchType == Enum.QuestWatchType.Automatic and C_SuperTrack.GetSuperTrackedQuestID() == self.questID) then
            RunTrackingDeferred(function() QuestUtil.UntrackWorldQuest(self.questID) end)
        else
            RunTrackingDeferred(function() QuestUtil.TrackWorldQuest(self.questID, Enum.QuestWatchType.Manual) end)
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

        -- Disable word wrap so long titles truncate to "..." instead of
        -- wrapping to a second line. Wrapping also causes a layout loop:
        -- the taller button changes available width, which in turn changes
        -- whether the text fits, oscillating between wrapped and truncated
        -- states and producing visible flicker.
        button.Text:SetWordWrap(false)

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

        local displayLocation, lockedQuestID = C_QuestLog.GetBountySetInfoForMapID(mapID)

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

        -- Blizzard assigned the separator's layoutIndex in its own
        -- QuestLogQuests_Update, which ran before this deferred update; place the
        -- container right after the separator (the 0.5 fallback sorts it to the
        -- very top, e.g. when no separator is displayed).  Previously a
        -- SetFrameLayoutIndex post-hook did this, but that hook ran inside
        -- Blizzard's own chains, tainting everything that followed (issue #168).
        if showAtTop then
            local separatorIndex = QuestScrollFrame.Contents.Separator.layoutIndex
            awqContainer.layoutIndex = (separatorIndex or 0) + 0.5
        else
            awqContainer.layoutIndex = 9999.5
        end

        awqContainer:Show()

        headerButton:Show()
        local prevButton = headerButton

        local usedButtons = {}
        local filtersOwnRow = false

        -- Always gather available world quests, even when collapsed, so we can
        -- hide the header entirely if there are no quests in the current zone.
        -- When collapsed, just count quests without acquiring pool buttons.
        local addedQuests = {}
        local questCount = 0
        local displayMapIDs = DataModule:GetMapIDsToGetQuestsFrom(mapID)
        local searchBoxText = QuestScrollFrame.SearchBox:GetText():lower()

        -- Compute filter decisions once, into the shared cache, so the list below
        -- and the secure pin hook both read the same non-secure result (issue #156).
        RebuildFilterDecisionCache(mapID)

        for mID in pairs(displayMapIDs) do
            local taskInfo = C_TaskQuest.GetQuestsOnMap(mID)

            if taskInfo then
                for _, info in ipairs(taskInfo) do
                    if HaveQuestData(info.questID) and QuestUtils_IsQuestWorldQuest(info.questID) then
                        if WorldMap_DoesWorldQuestInfoPassFilters(info) then
                            local isFiltered = filterDecisionCache[info.questID]
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
            -- No quests available and no active filters — hide the header entirely.
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
                -- In the situation where the normal quest log is empty, but we have world quests.
                -- We shouldn't show the empty quest log text.
                QuestScrollFrame.EmptyText:Hide()

                -- We need to also make sure the "No search results" text is hidden.
                QuestScrollFrame.NoSearchResultsText:Hide()
            end

            table.sort(usedButtons, QuestSorter)

            for i, button in ipairs(usedButtons) do
                -- layoutIndex starts at 2 (headerButton is 1); all addon-owned integers.
                button.layoutIndex = i + 1
                button:Show()

                if hoveredQuestID == button.questID then
                    QuestButton_OnEnter(button)
                end
            end
        end

        headerButton.CollapseButton:UpdateCollapsedState(ConfigModule:Get("collapsed"))
        headerButton.CollapseButton:Show()

        -- Layout now that the container's index is final.  Runs after Blizzard's
        -- own layout pass, so the separator.layoutIndex read above was current.
        QuestScrollFrame.Contents:Layout()
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
        awqContainer.fixedWidth = 304 -- matches the fixed width defined in QuestMapFrame.xml; avoids tainting the value via GetWidth()
        awqContainer.bottomPadding = 2
        awqContainer:Hide()

        headerButton = CreateFrame("BUTTON", "AngrierWorldQuestsHeader", awqContainer, "QuestLogHeaderTemplate")
        headerButton:SetScript("OnClick", HeaderButton_OnClick)
        headerButton:SetText(TRACKER_HEADER_WORLD_QUESTS)
        headerButton.topPadding = 6
        headerButton.titleFramePool = titleFramePool
        headerButton.layoutIndex = 1

        -- The container's layoutIndex is now assigned directly in QuestLog_Update
        -- (read separator.layoutIndex after Blizzard's own QuestLogQuests_Update
        -- finished).  The old SetFrameLayoutIndex post-hook ran inside Blizzard's
        -- quest-log render chains and tainted them (issue #168).
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

--region Taint-safe refresh triggers
--
-- Blizzard invokes its map/quest-log functions from inside its own protected
-- chains: data provider RefreshAllData runs within the map canvas
-- secureexecuterange, and QuestLogQuests_Update is called from the map pin
-- hover chains (QuestMapFrame OnMapCanvasPinEnter).  Any addon hook on those
-- functions places addon Lua frames inside the chains, which in 12.1 makes the
-- rest of the chain execute tainted — protected calls are then blocked
-- (Button:SetPassThroughButtons -> ADDON_ACTION_BLOCKED) and UIWidget geometry
-- reads return SECRET values, erroring Blizzard's own widget Setup code on the
-- next POI hover (issue #168).
--
-- Instead, all refresh work is triggered from contexts the game dispatches
-- cleanly and in isolation, never nested inside a Blizzard chain:
--   * our own event frame (events are delivered to every registered frame in
--     separate calls),
--   * C_Timer callbacks (fire from the game's timer processing, outside any
--     Blizzard chain),
--   * and every outgoing mutation runs inside securecallfunction so nothing is
--     attributed to the addon.
do
    local QUEST_REFRESH_EVENTS = {
        "QUEST_LOG_UPDATE",       -- world quest data provider refresh (WorldQuestDataProvider.lua:166)
        "SUPER_TRACKING_CHANGED", -- the provider's other refresh event (line 106)
        "QUEST_POI_UPDATE",       -- dynamic quest / POI updates (e.g. Void Assaults)
        "UNIT_QUEST_LOG_CHANGED", -- quest log additions/removals
        "WORLD_MAP_OPEN",         -- map opened; the provider's OnShow starts its own ticker
        "PLAYER_ENTERING_WORLD",  -- zone-in refresh
    }

    local questLogEventFrame
    local pinRefreshScheduled = false
    local lastSearchText
    local lastMapID

    -- Runs Blizzard-facing pin work with a clean execution context, so pin
    -- geometry/alpha written here can never surface as SECRET to Blizzard's own
    -- later reads (pin pool recycling, QuestHub tooltip cloning).
    local function RunPinPostProcessing()
        if not dataProvider or not QuestMapFrame or not QuestMapFrame:IsShown() then
            return
        end

        securecallfunction(function()
            PostProcessWorldQuestPins(dataProvider)
        end)
    end

    -- Post-processes pins one frame after a quest/map event.  Blizzard's own
    -- RefreshAllData for the event completes during the event dispatch; this
    -- runs right after it, in an isolated context.
    local function SchedulePinRefresh()
        if pinRefreshScheduled then
            return
        end

        pinRefreshScheduled = true
        C_Timer.After(0, function()
            pinRefreshScheduled = false
            RunPinPostProcessing()
        end)
    end

    function QuestFrameModule:OnMapEvent(event)
        SchedulePinRefresh()

        if event == "SUPER_TRACKING_CHANGED" or event == "QUEST_LOG_UPDATE" or event == "QUEST_POI_UPDATE" then
            self:RequestQuestLogUpdate()
            self:RequestFullRefresh(event)
        elseif event == "WORLD_MAP_OPEN" then
            self:RequestQuestLogUpdate()
            self:RequestFullRefresh(event)
        elseif event == "UNIT_QUEST_LOG_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            self:RequestQuestLogUpdate()
        end
    end

    function QuestFrameModule:InitializeRefreshTriggers()
        questLogEventFrame = CreateFrame("Frame")
        questLogEventFrame:Hide()
        questLogEventFrame:SetScript("OnEvent", function(_, event)
            QuestFrameModule:OnMapEvent(event)
        end)
        for _, event in ipairs(QUEST_REFRESH_EVENTS) do
            questLogEventFrame:RegisterEvent(event)
        end
        questLogEventFrame:Show()

        -- Mirror of the world quest provider's own 0.5s RefreshAllData ticker
        -- (WorldQuestDataProvider.lua:178): it re-acquires pins (resetting their
        -- alpha and position), so event triggers alone would let our filtered
        -- pins flicker back to visible between refetches.  Also detects search
        -- box text changes, which trigger a QuestLogQuests_Update without any
        -- quest/map event (search parity with the old QuestLogQuests_Update hook).
        -- And it detects map display changes via GetMapID() diff (parity with the
        -- old OnMapChanged hook; there is no WORLD_MAP_UPDATE event).
        C_Timer.NewTicker(0.5, function()
            RunPinPostProcessing()

            if QuestMapFrame and QuestMapFrame:IsShown() then
                local mapID = WorldMapFrame:GetMapID()
                if mapID ~= lastMapID then
                    lastMapID = mapID
                    QuestFrameModule:RequestQuestLogUpdate()
                end
            end

            if QuestMapFrame and QuestMapFrame:IsShown() and QuestScrollFrame and QuestScrollFrame.SearchBox then
                local searchText = QuestScrollFrame.SearchBox:GetText()
                if searchText ~= lastSearchText then
                    lastSearchText = searchText
                    QuestFrameModule:RequestQuestLogUpdate()
                end
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

    -- Post-processes pins after Blizzard's data provider refreshed them.  Does
    -- NOT use Hide()/EnableMouse() on pins — SetAlpha(0) is the only safe way to
    -- filter pins; every hit-test-affecting API fires synchronous OnEnter/OnLeave
    -- that, if fired from addon-triggered code while the cursor is over a POI,
    -- permanently taints UIWidget FontString geometry (issues #161/#168).
    PostProcessWorldQuestPins = function(dp)
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

            -- Read the filter decision from the cache QuestLog_Update populated in
            -- a non-secure context.  Calling DataModule:IsQuestFiltered() here would
            -- run GetQuestLogRewardMoney inside Blizzard's secure RefreshAllData
            -- range, tainting the quest's reward money and killing the gold tooltip
            -- on hover (issue #156).  A cache miss or stale map defaults to "not
            -- filtered" (pin shown) until the next QuestLog_Update refreshes it.
            if hideFilteredPOI and filterDecisionMapID == mapID and filterDecisionCache[info.questID] then
                return true
            end

            if hideUntrackedPOI and not WorldMap_IsWorldQuestEffectivelyTracked(info.questID) then
                return true
            end

            return false
        end

        local function AddTrackedWorldQuestPin(info)
            local cx, cy

            if info.mapID == mapID then
                -- info came from GetQuestsOnMap(continentMapID): coordinates are
                -- already in continent-normalised space (cold-continent fallback).
                cx, cy = C_TaskQuest.GetQuestLocation(info.questID, mapID)
            else
                -- info came from GetQuestsOnMap(childMapID): project zone-space
                -- coordinates onto the continent via GetMapRectOnMap (issue #147).
                local x, y = C_TaskQuest.GetQuestLocation(info.questID, info.mapID)

                if x and y and C_Map.GetMapRectOnMap then
                    local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(info.mapID, mapID)

                    if minX and maxX > minX and maxY > minY then
                        cx = minX + x * (maxX - minX)
                        cy = minY + y * (maxY - minY)
                    end
                end
            end

            if not cx or not cy then
                return nil
            end

            local pin = dp:AddWorldQuest(info)

            if pin then
                -- A pin reclaimed from Blizzard's pool may still be alpha-hidden
                -- from when it belonged to a previous map (issue #166), so make
                -- sure pins we actively add are visible.  Tag the pin with the map
                -- and quest it was placed for; PostProcessWorldQuestPins uses these
                -- to re-hide our pins once they are no longer valid.
                pin:SetAlpha(1)
                pin.awqAlphaHidden = nil
                pin.awqMapID = mapID
                pin.awqQuestID = info.questID

                pin:SetPosition(cx, cy)
                table.insert(addonAddedPins, pin)
            end

            return pin
        end

        -- Collects quest info tables from child zones of the given continent map.
        -- Returns a flat list.
        --
        -- On a cold continent open, C_TaskQuest.GetQuestsOnMap(childMapID) returns
        -- nothing because Blizzard's data provider only loads child-zone quest data
        -- after the player has opened that zone map.  However,
        -- C_TaskQuest.GetQuestsOnMap(continentMapID) is always populated by
        -- Blizzard's RefreshAllData when on the continent.  We query both: child
        -- zones first (so info.mapID is the zone mapID for accurate projection),
        -- then fall back to the continent query for any quests not yet found.
        local function GetChildMapQuests()
            local quests = {}
            local seen = {}
            local childMapIDs = DataModule:GetMapIDsToGetQuestsFrom(mapID)

            for mID in pairs(childMapIDs) do
                if mID ~= mapID then
                    local taskInfo = C_TaskQuest.GetQuestsOnMap(mID)
                    if taskInfo then
                        for _, info in ipairs(taskInfo) do
                            if not seen[info.questID] then
                                seen[info.questID] = true
                                table.insert(quests, info)
                            end
                        end
                    end
                end
            end

            -- Fallback: continent-mapID query.  info.mapID will be the continent
            -- mapID, so AddTrackedWorldQuestPin uses GetQuestLocation(questID,
            -- continentMapID) which works even before child-zone data is loaded.
            local continentTaskInfo = C_TaskQuest.GetQuestsOnMap(mapID)
            if continentTaskInfo then
                for _, info in ipairs(continentTaskInfo) do
                    if not seen[info.questID] then
                        seen[info.questID] = true
                        table.insert(quests, info)
                    end
                end
            end

            return quests
        end

        local mapInfo = C_Map.GetMapInfo(mapID)
        local pinTemplate = dp.GetPinTemplate and dp:GetPinTemplate() or dp.pinTemplate
        local isContinent = mapInfo and mapInfo.mapType == Enum.UIMapType.Continent

        if not pinTemplate then
            return
        end

        -- On a cold continent open the pin pool doesn't exist yet: Blizzard's
        -- data provider adds no WQ pins natively on continent maps (child-zone
        -- quests only appear via our own AddTrackedWorldQuestPin calls).  The
        -- alpha-hide passes are no-ops with no active pins, so skip the pool
        -- guard and let dp:AddWorldQuest() create the pool on first use.
        local hasPool = map.pinPools and map.pinPools[pinTemplate]
        if not hasPool and not isContinent then
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
        if hasPool then
            for pin in map.pinPools[pinTemplate]:EnumerateActive() do
                if pin.awqAlphaHidden then
                    pin:SetAlpha(1)
                    pin.awqAlphaHidden = nil
                end
            end
        end

        -- Clean up stale addon-pin references (pins released by Blizzard's
        -- pool:ReleaseAll on the previous RefreshAllData are no longer active).
        -- We do NOT call map:RemovePin — that calls pin:Hide() internally.
        -- Blizzard's own pool management will release them on the next refresh.
        local activeSet = {}
        if hasPool then
            for pin in map.pinPools[pinTemplate]:EnumerateActive() do
                activeSet[pin] = true
            end
        end
        local remainingAddonPins = {}
        for _, pin in ipairs(addonAddedPins) do
            if activeSet[pin] then
                table.insert(remainingAddonPins, pin)
            end
        end
        addonAddedPins = remainingAddonPins

        local childQuests
        local childQuestByID
        local superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()

        local function GetCachedChildQuests()
            if not childQuests then
                childQuests = GetChildMapQuests()
            end

            return childQuests
        end

        local function GetCachedChildQuestByID()
            if not childQuestByID then
                childQuestByID = {}

                for _, info in ipairs(GetCachedChildQuests()) do
                    childQuestByID[info.questID] = info
                end
            end

            return childQuestByID
        end

        local function IsAddonPinExpected(pin)
            if pin.awqMapID ~= mapID then
                return false
            end

            if not mapInfo or mapInfo.mapType ~= Enum.UIMapType.Continent then
                return false
            end

            if superTrackedQuestID and superTrackedQuestID > 0 and pin.awqQuestID == superTrackedQuestID then
                return true
            end

            if not showContinentPOI then
                return false
            end

            local info = GetCachedChildQuestByID()[pin.awqQuestID]

            return info
                and HaveQuestData(info.questID)
                and QuestUtils_IsQuestWorldQuest(info.questID)
                and WorldMap_DoesWorldQuestInfoPassFilters(info)
                and (info.mapID == mapID or DataModule:GetContentMapIDFromMapID(info.mapID) == mapID)
                and not ShouldFilterQuest(info)
        end

        -- Pass 1b: re-hide pins we added that are no longer valid for this map.
        --
        -- AWQ borrows pins from Blizzard's WorldQuest pool to show child-zone
        -- quests on continent maps.  Blizzard normally releases them via
        -- pool:ReleaseAll on the next RefreshAllData, but on some maps (e.g. the
        -- Eastern Kingdoms continent) its data provider returns without refreshing
        -- its pins, so ours stay active and linger at their previous map's
        -- coordinates — out in the ocean (issue #166).  Pass 1 above just restored
        -- their alpha, so re-hide them here on every refresh.  The same guard also
        -- covers same-map stale pins, such as a super-tracked WQ pin after the
        -- quest is untracked while continent POIs are disabled.
        --
        -- Keying on our own tracking list is safe: those pins are always active
        -- (Blizzard only recycles inactive pins), and the questID guard skips any
        -- pin Blizzard has meanwhile reclaimed for a different quest.
        for _, pin in ipairs(addonAddedPins) do
            if pin.questID == pin.awqQuestID and not IsAddonPinExpected(pin) then
                pin:SetAlpha(0)
                pin.awqAlphaHidden = true
            end
        end

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
        if hasPool then
            for pin in map.pinPools[pinTemplate]:EnumerateActive() do
                if pin.questID and C_QuestLog.IsWorldQuest(pin.questID) then
                    if ShouldFilterQuest({ questID = pin.questID, mapID = pin.mapID or mapID }) then
                        pin:SetAlpha(0)
                        pin.awqAlphaHidden = true
                    end
                end
            end
        end

        if mapInfo and mapInfo.mapType == Enum.UIMapType.Continent then
            local childQuests = GetCachedChildQuests()

            if showContinentPOI then
                -- Collect already-shown questIDs to avoid duplicates
                local shownQuests = {}
                if hasPool then
                    for pin in map.pinPools[pinTemplate]:EnumerateActive() do
                        if pin.questID then
                            shownQuests[pin.questID] = true
                        end
                    end
                end

                for _, info in ipairs(childQuests) do
                    if not shownQuests[info.questID]
                        and HaveQuestData(info.questID)
                        and QuestUtils_IsQuestWorldQuest(info.questID)
                        and WorldMap_DoesWorldQuestInfoPassFilters(info)
                        and (info.mapID == mapID or DataModule:GetContentMapIDFromMapID(info.mapID) == mapID)
                        and not ShouldFilterQuest(info) then

                        AddTrackedWorldQuestPin(info)
                        shownQuests[info.questID] = true
                    end
                end
            end

            if superTrackedQuestID and superTrackedQuestID > 0 then
                local hasPin = false
                if hasPool then
                    for pin in map.pinPools[pinTemplate]:EnumerateActive() do
                        if pin.questID == superTrackedQuestID then
                            hasPin = true
                            break
                        end
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
        dataProvider = GetDataProvider()

        -- NOTE: there is deliberately no hooksecurefunc on RefreshAllData here.
        -- RefreshAllData is called from inside Blizzard's map canvas
        -- secureexecuterange (MapCanvas OnEvent -> data provider SignalEvent);
        -- a post-hook on it runs our Lua frames inside that range, tainting
        -- every protected call Blizzard makes afterwards in the same range,
        -- e.g. Button:SetPassThroughButtons() during pin acquisition
        -- (ADDON_ACTION_BLOCKED, issue #168).  Pin post-processing is instead
        -- triggered from our own event frame and a mirror ticker, which run in
        -- isolated game-dispatched contexts after Blizzard's refresh completes.
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
                            C_QuestLog.AddWorldQuestWatch(lastTrackedQuestID, Enum.QuestWatchType.Manual)
                        end
                    end
                    lastTrackedQuestID = questID
                    QuestFrameModule:RequestFullRefresh("TRACK_WORLD_QUEST")
                end

                if watchType == Enum.QuestWatchType.Automatic then
                    local forceAllowTasks = true
                    QuestUtil.CheckAutoSuperTrackQuest(questID, forceAllowTasks)
                end
            end

            function QuestUtil.UntrackWorldQuest(questID)
                if C_QuestLog.RemoveWorldQuestWatch(questID) then
                    if lastTrackedQuestID == questID then
                        lastTrackedQuestID = nil
                    end
                    QuestFrameModule:RequestFullRefresh("UNTRACK_WORLD_QUEST")
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

        -- Create awqContainer and headerButton inside the QuestLog upvalue scope.
        -- Must happen after titleFramePool is created (headerButton references it).
        self:InitQuestLogFrames()

        -- TAINT-SAFE REFRESH TRIGGERS (issue #168).
        --
        -- All refresh work is now driven by our own event frame and a C_Timer
        -- mirror ticker instead of hooksecurefunc hooks on Blizzard functions.
        -- Blizzard invokes the hooked functions (QuestLogQuests_Update,
        -- RefreshAllData, OnMapChanged, SetSuperTrackedQuestID) from inside its
        -- own protected chains — the map canvas secureexecuterange and the map
        -- pin hover/tooltip chains.  Addon hooks there placed our Lua frames
        -- inside those chains, so the remainder of the chain executed tainted:
        -- protected calls (e.g. Button:SetPassThroughButtons during pin
        -- acquisition) were blocked, and UIWidget geometry reads returned SECRET
        -- values that errored Blizzard's widget Setup code on POI hover (#168).
        --
        -- The event frame covers every trigger the provider itself uses
        -- (QUEST_LOG_UPDATE / SUPER_TRACKING_CHANGED, WorldQuestDataProvider.lua:106/166)
        -- plus quest-POI, map-open and quest-log events; the mirror ticker covers
        -- the provider's own 0.5s refresh ticker (line 178), search-box changes,
        -- and map display changes (GetMapID() diff, since no WORLD_MAP_UPDATE
        -- event exists); all outgoing mutations run inside securecallfunction.
        QuestFrameModule:InitializeRefreshTriggers()

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
        -- Skip when any tooltip is shown.  QuestLog_Update shows/hides quest log
        -- buttons (children of WorldMapFrame); from tainted code this can fire a
        -- canvas mouse-focus recalculation and Area POI OnEnter in the addon's
        -- context, permanently tainting UIWidget FontString values (issue #161).
        -- The next QUEST_LOG_UPDATE event reschedules naturally.
        if QuestMapFrame and QuestMapFrame:IsShown() and not GameTooltip:IsShown() then
            -- Render our list in a clean execution context (issue #168).
            securecallfunction(function()
                QuestFrameModule:QuestLog_Update()
            end)
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

        -- Rebuild the filter-decision cache and re-render the quest log in a
        -- clean execution context: reward-money reads (GetQuestLogRewardMoney via
        -- DataModule:IsQuestFiltered) stay unstamped for Blizzard's gold tooltip
        -- (issue #156), and Blizzard's own re-render runs untainted (issue #168).
        -- Pin state is refreshed afterwards by the event frame / mirror ticker,
        -- after the data provider's own RefreshAllData has run for this change.
        securecallfunction(function()
            RebuildFilterDecisionCache(QuestMapFrame and QuestMapFrame:GetParent():GetMapID())
            QuestLogQuests_Update()
        end)

        -- Do NOT call dataProvider:RefreshAllData() directly.  It fires pin
        -- OnMouseEnter handlers synchronously while pins are recreated; called
        -- from addon code it taints those chains, and UIWidget C APIs then
        -- return SECRET values (#161).  Blizzard's own event cycle (our event
        -- frame + the provider's 0.5s ticker, mirrored by our own) performs the
        -- refresh instead, after which RunPinPostProcessing is scheduled.
    end)
end