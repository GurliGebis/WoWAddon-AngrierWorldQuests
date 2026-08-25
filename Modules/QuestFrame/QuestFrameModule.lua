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

-- For the reasoning behind the taint workarounds in this module (and the
-- rest of QuestFrame), see ARCHITECTURE.md instead of scattered inline comments.

local addonName, _ = ...
local AngrierWorldQuests = LibStub("AceAddon-3.0"):GetAddon(addonName)
local QuestFrameModule = AngrierWorldQuests:NewModule("QuestFrameModule", "AceConsole-3.0")
local ConfigModule = AngrierWorldQuests:GetModule("ConfigModule")
local DataModule = AngrierWorldQuests:GetModule("DataModule")

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

--region Variables

local dataProvider
local titleFramePool
local listRefreshDirty = false
local fullRefreshDirty = false
local fullRefreshReason
local addonAddedPins = {}

-- The quest whose row is currently hovered in the list. Written by the
-- QuestLog region below (QuestButton_OnEnter/OnLeave), read by the pin
-- post-processing below (ShouldFilterQuest, for the "showHoveredPOI" option).
QuestFrameModule.hoveredQuestID = nil

-- Set while the player character is moving (PLAYER_STARTED_MOVING/
-- PLAYER_STOPPED_MOVING, see the player-movement show/hide trigger region).
-- While set - and the "hideWhenMoving" option is on - QuestLog_Update keeps
-- the AWQ panel hidden no matter who requested the update, so nothing can
-- flash it back up mid-run.
QuestFrameModule.playerIsMoving = nil

-- Cache of per-quest filter decisions, populated by QuestLog_Update in a
-- non-secure context and read back by PostProcessWorldQuestPins. This keeps
-- the reward-money read (GetQuestLogRewardMoney, via DataModule:IsQuestFiltered)
-- OUT of Blizzard's secure RefreshAllData execution range, where it would taint
-- the quest's money value and break the gold-reward tooltip on hover (issue #156).
QuestFrameModule.filterDecisionCache = {}
QuestFrameModule.filterDecisionMapID = nil

function QuestFrameModule:DebugLog(message)
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

    return true
end

-- True when it is safe for us to create, show or move a map pin.
-- See ARCHITECTURE.md (#174).
local function CanMutateMapPins()
    if not WorldMapFrame then
        return false
    end

    -- A tooltip is up, which means the cursor is sitting on a POI right now.
    if GameTooltip and GameTooltip:IsShown() then
        return false
    end

    -- Cursor anywhere over the canvas.
    local canvas = WorldMapFrame.ScrollContainer

    if canvas and canvas.IsMouseOver and canvas:IsMouseOver() then
        return false
    end

    return true
end

-- Recompute the per-quest filter-decision cache for the given map. The reward
-- reads inside DataModule:IsQuestFiltered (GetQuestLogRewardMoney) run here, in a
-- non-secure context, so PostProcessWorldQuestPins can apply hide-filtered from
-- the cache without re-reading reward money inside Blizzard's secure
-- RefreshAllData range (which taints the money and breaks gold tooltips, #156).
function QuestFrameModule:RebuildFilterDecisionCache(mapID)
    wipe(self.filterDecisionCache)
    self.filterDecisionMapID = mapID

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
                        self.filterDecisionCache[info.questID] = DataModule:IsQuestFiltered(info, mapID) or false
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

    local PANEL_WIDTH = 340
    local CONTAINER_WIDTH = 304 -- matches the fixed width defined in QuestMapFrame.xml; avoids tainting the value via GetWidth()

    local awqPanel
    local awqScrollFrame
    local awqContainer
    local headerButton
    local filterButtons = {}

    -- QuestMapFrame.QuestsTab and .MapLegendTab are the side tabs that stick
    -- out from the edge of the quest log frame. With awqPanel docked next to
    -- the map they end up visually behind/underneath our panel, so we move
    -- them onto awqPanel's edge while it is shown and put them back exactly
    -- where they came from when it's hidden.
    local SIDE_TAB_KEYS = { "QuestsTab", "MapLegendTab" }
    local sideTabOriginal = {}
    local sideTabsMoved = false

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
            ConfigModule:Set("filterEmissary", value)
        elseif filterKey == "LOOT" then
            ConfigModule:Set("filterLoot", value)
        elseif filterKey == "FACTION" then
            ConfigModule:Set("filterFaction", value)
        elseif filterKey == "ZONE" then
            ConfigModule:Set("filterZone", value)
        elseif filterKey == "TIME" then
            ConfigModule:Set("filterTime", value)
        end

        if filterKey == "SORT" then
            ConfigModule:Set("sortMethod", value)
        elseif IsShiftKeyDown() then
            ConfigModule:SetFilter(filterKey, true)
        else
            ConfigModule:SetOnlyFilter(filterKey)
        end
    end

    -- Shared by every branch of FilterMenu_Generator below: builds the
    -- IsSelected/SetSelected radio-button predicate pair for a given filter
    -- key and its currently selected value.
    local function MakeFilterRadioHandlers(filterKey, currentValue)
        local function IsSelected(value) return value == currentValue end
        local function SetSelected(value) FilterMenu_ApplySelection(filterKey, value) end
        return IsSelected, SetSelected
    end

    local function FilterMenu_Generator(owner, rootDescription)
        local filterKey = owner.filter

        if filterKey == "EMISSARY" then
            local currentValue = ConfigModule:Get("filterEmissary")
            if not C_QuestLog.IsOnQuest(currentValue) then currentValue = 0 end

            local IsSelected, SetSelected = MakeFilterRadioHandlers(filterKey, currentValue)

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

            local IsSelected, SetSelected = MakeFilterRadioHandlers(filterKey, currentValue)

            rootDescription:CreateRadio(ALL, IsSelected, SetSelected, _AngrierWorldQuests.Constants.FILTERS.LOOT_ALL)
            rootDescription:CreateRadio(L["UPGRADES"], IsSelected, SetSelected, _AngrierWorldQuests.Constants.FILTERS.LOOT_UPGRADES)

        elseif filterKey == "ZONE" then
            local currentValue = ConfigModule:Get("filterZone")

            local IsSelected, SetSelected = MakeFilterRadioHandlers(filterKey, currentValue)

            rootDescription:CreateRadio(L["CURRENT_ZONE"], IsSelected, SetSelected, 0)

        elseif filterKey == "FACTION" then
            local currentValue = ConfigModule:Get("filterFaction")

            local IsSelected, SetSelected = MakeFilterRadioHandlers(filterKey, currentValue)

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

            local IsSelected, SetSelected = MakeFilterRadioHandlers(filterKey, currentValue)

            for _, hours in ipairs(ConfigModule.Filters.TIME.values) do
                rootDescription:CreateRadio(string.format(FORMATED_HOURS, hours), IsSelected, SetSelected, hours)
            end

        elseif filterKey == "SORT" then
            local currentValue = ConfigModule:Get("sortMethod")

            local IsSelected, SetSelected = MakeFilterRadioHandlers(filterKey, currentValue)

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

    -- Resets every filter-value config key that gets zeroed whenever a
    -- different filter button becomes the "only" active filter (or when all
    -- filters are cleared), except the one owned by exceptFilter (pass nil
    -- to reset all of them, e.g. when clearing every filter).
    local function ResetOtherFilterValues(exceptFilter)
        local resettableFilterValues = {
            { filter = "FACTION", key = "filterFaction" },
            { filter = "EMISSARY", key = "filterEmissary" },
            { filter = "LOOT", key = "filterLoot" },
            { filter = "ZONE", key = "filterZone" },
            { filter = "TIME", key = "filterTime" },
        }

        for _, entry in ipairs(resettableFilterValues) do
            if entry.filter ~= exceptFilter then
                ConfigModule:Set(entry.key, 0, true)
            end
        end
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
                    ResetOtherFilterValues(nil)
                    ConfigModule:SetNoFilter()
                else
                    ResetOtherFilterValues(self.filter)
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
        QuestFrameModule.hoveredQuestID = self.questID
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
        QuestFrameModule.hoveredQuestID = nil
        self.HighlightTexture:SetShown(false)
        QuestFrameModule.Tooltip_Hide(self)
    end

    -- Executes a deferred tracking action with a clean execution context.
    -- See ARCHITECTURE.md (#67, #168).
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
        -- wrapping. See ARCHITECTURE.md (#161).
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

    -- Moves QuestMapFrame.QuestsTab / .MapLegendTab onto awqPanel, stacked the
    -- same way they are stacked on QuestMapFrame. Idempotent: safe to call
    -- every time the panel is shown.
    local function MoveSideTabsToPanel()
        if sideTabsMoved or not awqPanel then
            return
        end

        local prevTab

        for _, key in ipairs(SIDE_TAB_KEYS) do
            local tab = QuestMapFrame[key]

            if tab then
                if not sideTabOriginal[key] then
                    local point, relativeTo, relativePoint, xOfs, yOfs = tab:GetPoint(1)
                    sideTabOriginal[key] = {
                        parent = tab:GetParent(),
                        point = point,
                        relativeTo = relativeTo,
                        relativePoint = relativePoint,
                        xOfs = xOfs,
                        yOfs = yOfs,
                    }
                end

                tab:SetParent(awqPanel)
                tab:ClearAllPoints()

                if prevTab then
                    tab:SetPoint("TOP", prevTab, "BOTTOM", 0, -3)
                else
                    tab:SetPoint("TOPLEFT", awqPanel, "TOPRIGHT", -2, -28)
                end

                prevTab = tab
            end
        end

        sideTabsMoved = true
    end

    -- Restores the side tabs to their original parent/anchor on QuestMapFrame.
    -- Idempotent: safe to call every time the panel is hidden.
    local function RestoreSideTabs()
        if not sideTabsMoved then
            return
        end

        for _, key in ipairs(SIDE_TAB_KEYS) do
            local tab = QuestMapFrame[key]
            local original = sideTabOriginal[key]

            if tab and original then
                tab:SetParent(original.parent)
                tab:ClearAllPoints()
                tab:SetPoint(original.point, original.relativeTo, original.relativePoint, original.xOfs, original.yOfs)
            end
        end

        sideTabsMoved = false
    end

    function QuestFrameModule:HideWorldQuestWindow()
        if awqPanel then
            awqPanel:Hide()
        end

        RestoreSideTabs()
    end

    function QuestFrameModule:QuestLog_Update()
        if not QuestMapFrame or not QuestMapFrame:IsShown() then
            return
        end

        if QuestFrameModule:IsQuestListLockedDown() then
            return
        end

        -- Player is moving (and hideWhenMoving is enabled): the panel stays
        -- hidden, and this is the one place that decides that.
        -- PLAYER_STOPPED_MOVING re-runs this whole update (with all the checks
        -- below) instead of the event showing it directly, so the panel only
        -- returns when it actually should. See the player-movement show/hide
        -- trigger region.
        if self.playerIsMoving and ConfigModule:Get("hideWhenMoving") then
            self:HideWorldQuestWindow()
            self.lastRenderedMapID = QuestMapFrame:GetParent():GetMapID()
            return
        end

        titleFramePool:ReleaseAll()

        local mapID = QuestMapFrame:GetParent():GetMapID()

        local displayLocation, lockedQuestID = C_QuestLog.GetBountySetInfoForMapID(mapID)

        local tasksOnMap = C_TaskQuest.GetQuestsOnMap(mapID)
        if (ConfigModule:Get("onlyCurrentZone")) and (not displayLocation or lockedQuestID) and not (tasksOnMap and #tasksOnMap > 0) and (mapID ~= MAPID_ARGUS) then
            QuestFrameModule:HideWorldQuestWindow()
            QuestFrameModule.lastRenderedMapID = mapID
            return
        end

        if (ConfigModule:Get("hideQuestList")) then
            QuestFrameModule:HideWorldQuestWindow()
            QuestFrameModule.lastRenderedMapID = mapID
            return
        end

        if awqPanel then
            awqPanel:Show()
        end

        MoveSideTabsToPanel()

        local prevButton = headerButton

        local usedButtons = {}
        local filtersOwnRow = false

        -- The list has its own scroll frame in its own panel now, so there's
        -- no reason to offer collapsing it to save space the way Blizzard's
        -- shared quest log needed to. Always gather and show every available
        -- world quest.
        local addedQuests = {}
        local questCount = 0
        local displayMapIDs = DataModule:GetMapIDsToGetQuestsFrom(mapID)
        local searchBoxText = QuestScrollFrame.SearchBox:GetText():lower()

        -- Compute filter decisions once, into the shared cache, so the list below
        -- and the pin-processing hook below both read the same non-secure result.
        -- See ARCHITECTURE.md (#156).
        QuestFrameModule:RebuildFilterDecisionCache(mapID)

        for mID in pairs(displayMapIDs) do
            local taskInfo = C_TaskQuest.GetQuestsOnMap(mID)

            if taskInfo then
                for _, info in ipairs(taskInfo) do
                    if HaveQuestData(info.questID) and QuestUtils_IsQuestWorldQuest(info.questID) then
                        if WorldMap_DoesWorldQuestInfoPassFilters(info) then
                            local isFiltered = QuestFrameModule.filterDecisionCache[info.questID]
                            if not isFiltered then
                                if addedQuests[info.questID] == nil then
                                    addedQuests[info.questID] = true
                                    questCount = questCount + 1
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

        if questCount == 0 and ConfigModule:HasFilters() == false then
            -- No quests available and no active filters — hide the window entirely.
            QuestFrameModule:HideWorldQuestWindow()
            QuestFrameModule.lastRenderedMapID = mapID
            return
        end

        do
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
                        -- CollapseButton is hidden now (see QuestLog_Update), so
                        -- anchor straight off the header's right edge instead of
                        -- leaving room for it.
                        filterButton:SetPoint("RIGHT", prevButton, "RIGHT", -6, 0)
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

            table.sort(usedButtons, QuestSorter)

            for i, button in ipairs(usedButtons) do
                -- layoutIndex starts at 2 (headerButton is 1); all addon-owned integers.
                button.layoutIndex = i + 1
                button:Show()

                if QuestFrameModule.hoveredQuestID == button.questID then
                    QuestButton_OnEnter(button)
                end
            end
        end

        headerButton.CollapseButton:Hide()

        awqContainer:Layout()
        QuestFrameModule.lastRenderedMapID = mapID
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
        -- calling GetText() on a FontString. See ARCHITECTURE.md (#161).
        button.awqTitle = title
        button.Text:SetText(title)

        local color

        if ShouldQuestBeBonusColored(button.questID) then
            color = QUEST_REWARD_CONTEXT_FONT_COLOR
        else
            color = GetQuestDifficultyColor( UnitLevel("player") + QuestButton_RarityColorTable[questTagInfo.quality] )
        end

        button.Text:SetTextColor(color.r, color.g, color.b)

        -- Hard-coded line height. See ARCHITECTURE.md (#161).
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
        -- GetHeight(). See ARCHITECTURE.md (#161).
        button.fixedHeight = totalHeight
        button:SetHeight(totalHeight)
        button:Show()

        return button
    end

    function QuestFrameModule:InitQuestLogFrames()
        awqPanel = CreateFrame("Frame", "AngrierWorldQuestsPanel", QuestMapFrame, "BackdropTemplate")
        awqPanel:SetFrameStrata(QuestScrollFrame:GetFrameStrata())
        awqPanel:SetFrameLevel(QuestScrollFrame:GetFrameLevel())
        awqPanel:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 4, 0)
        awqPanel:SetSize(PANEL_WIDTH, WorldMapFrame:GetHeight())
        awqPanel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        awqPanel:SetBackdropColor(0, 0, 0, 1)
        awqPanel:SetBackdropBorderColor(1, 1, 1, 1)
        awqPanel:Hide()

        awqScrollFrame = CreateFrame("ScrollFrame", "AngrierWorldQuestsScrollFrame", awqPanel, "UIPanelScrollFrameTemplate")
        awqScrollFrame:SetPoint("TOPLEFT", awqPanel, "TOPLEFT", 8, -8)
        awqScrollFrame:SetPoint("BOTTOMRIGHT", awqPanel, "BOTTOMRIGHT", -28, 8)

        awqContainer = CreateFrame("Frame", "AngrierWorldQuestsContainer", awqScrollFrame, "VerticalLayoutFrame")
        awqContainer.fixedWidth = CONTAINER_WIDTH
        awqContainer.bottomPadding = 2
        awqScrollFrame:SetScrollChild(awqContainer)

        titleFramePool = CreateFramePool("BUTTON", awqContainer, "QuestLogTitleTemplate")

        headerButton = CreateFrame("BUTTON", "AngrierWorldQuestsHeader", awqContainer, "QuestLogHeaderTemplate")
        headerButton:SetText(TRACKER_HEADER_WORLD_QUESTS)
        headerButton.topPadding = 6
        headerButton.titleFramePool = titleFramePool
        headerButton.layoutIndex = 1
        headerButton.CollapseButton:Hide()
    end

    function QuestFrameModule:UpdatePanelGeometry(mapShown)
        if not awqPanel then
            return
        end

        if not mapShown then
            awqPanel:Hide()
            RestoreSideTabs()
            return
        end

        local width, height = WorldMapFrame:GetSize()
        if width ~= awqPanel.lastWorldMapWidth or height ~= awqPanel.lastWorldMapHeight then
            awqPanel.lastWorldMapWidth = width
            awqPanel.lastWorldMapHeight = height
            awqPanel:SetSize(PANEL_WIDTH, height)
        end
    end

    function QuestFrameModule:IsQuestListLockedDown()
        local inInstance, instanceType = IsInInstance()

        return inInstance and (instanceType == "pvp" or instanceType == "arena")
    end
end
--endregion

-- True when it is unsafe to touch map pins (combat, or a pvp/arena instance).
-- See ARCHITECTURE.md (#173).
function QuestFrameModule:IsLockedDown()
    if InCombatLockdown and InCombatLockdown() then
        return true
    end

    local inInstance, instanceType = IsInInstance()

    return inInstance and (instanceType == "pvp" or instanceType == "arena")
end

--region Taint-safe list refresh trigger
--
-- Driven entirely by a C_Timer ticker, deliberately with NO event
-- registrations. See ARCHITECTURE.md (#168) for why, and for what state this
-- ticker polls in place of the events it replaces.
do
    local lastMapShown = false
    local lastMapID
    local lastSearchText
    local lastSuperTrackedQuestID
    local lastNumQuestLogEntries
    local lastInCombat

    function QuestFrameModule:InitializeListRefreshTriggers()
        C_Timer.NewTicker(0.5, function()
            local inCombat = InCombatLockdown()

            if inCombat then
                lastInCombat = true
            elseif lastInCombat then
                -- Combat just ended: force one extra full refresh in case
                -- nothing else changed while we were in combat.
                lastInCombat = false
                QuestFrameModule:RequestFullRefresh("COMBAT_ENDED")
            end

            local mapShown = QuestMapFrame and QuestMapFrame:IsShown()

            -- Panel visibility/size follow the quest log the same way the list
            -- itself does: polled here, never via a Show/Hide hook on
            -- WorldMapFrame/QuestMapFrame.
            QuestFrameModule:UpdatePanelGeometry(mapShown)

            if not mapShown then
                lastMapShown = false
                return
            end

            if not lastMapShown then
                -- Map just opened: baseline the diffs and run the same refresh
                -- the old WORLD_MAP_OPEN event triggered.
                lastMapShown = true
                lastMapID = WorldMapFrame:GetMapID()
                lastSearchText = QuestScrollFrame and QuestScrollFrame.SearchBox and QuestScrollFrame.SearchBox:GetText() or ""
                lastSuperTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
                lastNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries()
                QuestFrameModule:RequestQuestLogUpdate()
                QuestFrameModule:RequestFullRefresh("MAP_OPEN")
                return
            end

            local mapID = WorldMapFrame:GetMapID()
            -- Also re-request while the shown map has no definitive render yet
            -- (lastRenderedMapID): a render skipped or failed on the open
            -- transition self-heals here instead of leaving a stale list up.
            if mapID ~= lastMapID or mapID ~= QuestFrameModule.lastRenderedMapID then
                lastMapID = mapID
                QuestFrameModule:RequestQuestLogUpdate()
            end

            local searchText = QuestScrollFrame and QuestScrollFrame.SearchBox and QuestScrollFrame.SearchBox:GetText() or ""
            if searchText ~= lastSearchText then
                lastSearchText = searchText
                QuestFrameModule:RequestQuestLogUpdate()
            end

            local superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
            if superTrackedQuestID ~= lastSuperTrackedQuestID then
                lastSuperTrackedQuestID = superTrackedQuestID
                QuestFrameModule:RequestQuestLogUpdate()
            end

            local numEntries = C_QuestLog.GetNumQuestLogEntries()
            if numEntries ~= lastNumQuestLogEntries then
                lastNumQuestLogEntries = numEntries
                QuestFrameModule:RequestQuestLogUpdate()
                QuestFrameModule:RequestFullRefresh("QUEST_LOG_CHANGED")
            end

            -- Safety net: a dirty flag can be left set if a tooltip was
            -- shown when it was requested. See ARCHITECTURE.md (misc self-healing notes).
            QuestFrameModule:TryApplyFullRefresh()
            QuestFrameModule:TryApplyQuestLogUpdate()
        end)
    end

    function QuestFrameModule:RequestQuestLogUpdate()
        listRefreshDirty = true
        QuestFrameModule:TryApplyQuestLogUpdate()
    end

    function QuestFrameModule:TryApplyQuestLogUpdate()
        if not listRefreshDirty then
            return
        end

        if not (QuestMapFrame and QuestMapFrame:IsShown()) then
            return
        end

        if GameTooltip:IsShown() then
            -- Leave lastRenderedMapID unset so the ticker's own mapID-diff check
            -- re-requests this until the tooltip clears, instead of leaving a
            -- stale list/checkbox up.
            QuestFrameModule.lastRenderedMapID = nil
            return
        end

        listRefreshDirty = false

        -- Render in a clean execution context. See ARCHITECTURE.md (misc self-healing
        -- notes) for why the render is wrapped in pcall/DebugLog instead of left
        -- to error silently.
        securecallfunction(function()
            local ok, err = pcall(QuestFrameModule.QuestLog_Update, QuestFrameModule)
            if not ok then
                QuestFrameModule:DebugLog(string.format("QuestLog_Update failed: %s", tostring(err)))
            end
        end)
    end

    function QuestFrameModule:RequestFullRefresh(reason)
        fullRefreshDirty = true
        fullRefreshReason = reason or fullRefreshReason or "unknown"
        QuestFrameModule:TryApplyFullRefresh()
    end

    function QuestFrameModule:TryApplyFullRefresh()
        if not fullRefreshDirty then
            return
        end

        -- Also defer if any tooltip is currently shown. See ARCHITECTURE.md (#161).
        if not CanApplyFullRefresh() or GameTooltip:IsShown() then
            return
        end

        local reasonText = fullRefreshReason or "unknown"
        fullRefreshDirty = false
        fullRefreshReason = nil

        QuestFrameModule:DebugLog(string.format("Applying full refresh (%s)", reasonText))

        -- Rebuild the filter-decision cache in a clean execution context. See
        -- ARCHITECTURE.md (#156).
        securecallfunction(function()
            QuestFrameModule:RebuildFilterDecisionCache(QuestMapFrame and QuestMapFrame:GetParent():GetMapID())
        end)

        QuestFrameModule:RequestQuestLogUpdate()
    end
end
--endregion

--region Player-movement show/hide trigger
--
-- The one deliberate exception to the no-event-registrations rule from #168:
-- PLAYER_STARTED_MOVING/PLAYER_STOPPED_MOVING are dispatched by the engine,
-- never from inside Blizzard's secure RefreshAllData/hover chains, so running
-- addon code here cannot taint anything. The handlers also only touch
-- AWQ-owned state (the flag + our panel), never pins or tooltips.
do
    function QuestFrameModule:InitializeMovementTriggers()
        local function OnEvent(_, event)
            if event == "PLAYER_STARTED_MOVING" then
                -- The flag always tracks the real movement state (regardless
                -- of the option), so toggling the option mid-move is picked
                -- up by the QuestLog_Update guard immediately.
                QuestFrameModule.playerIsMoving = true

                if ConfigModule:Get("hideWhenMoving") and QuestMapFrame and QuestMapFrame:IsShown() then
                    QuestFrameModule:HideWorldQuestWindow()
                end
            else
                local wasMoving = QuestFrameModule.playerIsMoving == true
                QuestFrameModule.playerIsMoving = nil

                -- Only refresh when movement was actually controlling the
                -- panel; PLAYER_STOPPED_MOVING fires constantly during normal
                -- play. Never Show() directly: route through the normal update
                -- so its hide conditions (onlyCurrentZone, hideQuestList, no
                -- quests, lockdown, map closed) still decide the outcome.
                if wasMoving then
                    QuestFrameModule:RequestQuestLogUpdate()
                end
            end
        end

        local movementEventFrame = CreateFrame("Frame")
        movementEventFrame:SetScript("OnEvent", OnEvent)
        movementEventFrame:RegisterEvent("PLAYER_STARTED_MOVING")
        movementEventFrame:RegisterEvent("PLAYER_STOPPED_MOVING")

        -- Re-evaluate the panel the moment the option is toggled, so it takes
        -- effect immediately instead of waiting for the next movement change.
        ConfigModule:RegisterCallback("hideWhenMoving", function()
            QuestFrameModule:RequestQuestLogUpdate()
        end)
    end
end
--endregion

--region Initialization
do
    -- Shared tail of AddFilter/AddCurrencyFilter: registers the filter under
    -- its key and appends it to the display order.
    local function RegisterFilter(filter)
        ConfigModule.Filters[filter.key] = filter
        table.insert(ConfigModule.FiltersOrder, filter.key)

        return filter
    end

    local function AddFilter(key, name, icon, default)
        return RegisterFilter({
            key = key,
            name = name,
            icon = "Interface\\Icons\\" .. icon,
            default = default,
            index = #ConfigModule.FiltersOrder + 1,
        })
    end

    local function AddCurrencyFilter(key, currencyID, default)
        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)

        return RegisterFilter({
            key = key,
            name = currencyInfo.name,
            icon = currencyInfo.iconFileID,
            default = default,
            index = #ConfigModule.FiltersOrder + 1,
            preset = _AngrierWorldQuests.Constants.FILTERS.CURRENCY,
            currencyID = currencyID,
        })
    end

    function QuestFrameModule:InitializeFilterLists()
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

    -- ShouldFilterQuest/AddTrackedWorldQuestPin/GetChildMapQuests/
    -- GetCachedChildQuests/GetCachedChildQuestByID/IsAddonPinExpected all take
    -- a per-call "ctx" table instead of being closures. See ARCHITECTURE.md
    -- (misc self-healing notes).
    local function ShouldFilterQuest(ctx, info)
        if ctx.showHoveredPOI and QuestFrameModule.hoveredQuestID == info.questID then
            return false
        end

        -- Read the filter decision from the cache RebuildFilterDecisionCache
        -- populated above. See ARCHITECTURE.md (#156).
        if ctx.hideFilteredPOI and QuestFrameModule.filterDecisionMapID == ctx.mapID and QuestFrameModule.filterDecisionCache[info.questID] then
            return true
        end

        if ctx.hideUntrackedPOI and not WorldMap_IsWorldQuestEffectivelyTracked(info.questID) then
            return true
        end

        return false
    end

    local function AddTrackedWorldQuestPin(ctx, info)
        -- See ARCHITECTURE.md (#174).
        if not CanMutateMapPins() then
            return nil
        end

        local mapID = ctx.mapID
        local cx, cy

        if info.mapID == mapID then
            -- info came from GetQuestsOnMap(continentMapID): coordinates are
            -- already in continent-normalised space (cold-continent fallback).
            cx, cy = C_TaskQuest.GetQuestLocation(info.questID, mapID)
        else
            -- info came from GetQuestsOnMap(childMapID): project zone-space
            -- coordinates onto the continent via GetMapRectOnMap. See
            -- ARCHITECTURE.md (#147).
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

        local pin = ctx.dp:AddWorldQuest(info)

        if pin then
            -- A pin reclaimed from Blizzard's pool may still be alpha-hidden
            -- from a previous map. See ARCHITECTURE.md (#166). Tag the pin with
            -- the map/quest it was placed for; PostProcessWorldQuestPins
            -- uses these to re-hide our pins once they are no longer valid.
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
    -- Returns a flat list. See ARCHITECTURE.md (cold-continent quest data).
    local function GetChildMapQuests(ctx)
        local mapID = ctx.mapID
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

        -- Fallback: continent-mapID query. See ARCHITECTURE.md
        -- (cold-continent quest data).
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

    local function GetCachedChildQuests(ctx)
        if not ctx.childQuests then
            ctx.childQuests = GetChildMapQuests(ctx)
        end

        return ctx.childQuests
    end

    local function GetCachedChildQuestByID(ctx)
        if not ctx.childQuestByID then
            ctx.childQuestByID = {}

            for _, info in ipairs(GetCachedChildQuests(ctx)) do
                ctx.childQuestByID[info.questID] = info
            end
        end

        return ctx.childQuestByID
    end

    local function IsAddonPinExpected(ctx, pin)
        if pin.awqMapID ~= ctx.mapID then
            return false
        end

        if not ctx.mapInfo or ctx.mapInfo.mapType ~= Enum.UIMapType.Continent then
            return false
        end

        if ctx.superTrackedQuestID and ctx.superTrackedQuestID > 0 and pin.awqQuestID == ctx.superTrackedQuestID then
            return true
        end

        if not ctx.showContinentPOI then
            return false
        end

        local info = GetCachedChildQuestByID(ctx)[pin.awqQuestID]

        return info
            and HaveQuestData(info.questID)
            and QuestUtils_IsQuestWorldQuest(info.questID)
            and WorldMap_DoesWorldQuestInfoPassFilters(info)
            and (info.mapID == ctx.mapID or DataModule:GetContentMapIDFromMapID(info.mapID) == ctx.mapID)
            and not ShouldFilterQuest(ctx, info)
    end

    -- Post-processes pins after Blizzard's data provider refreshed them.
    -- See ARCHITECTURE.md (#161, #168) for why this never calls Hide()/
    -- EnableMouse() on pins, only SetAlpha().
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

        -- Per-tick state shared by the helper functions above; kept in one
        -- small table instead of upvalues so those helpers don't need to be
        -- recreated as closures every tick.
        local ctx = {
            dp = dp,
            mapID = mapID,
            hideFilteredPOI = ConfigModule:Get("hideFilteredPOI"),
            hideUntrackedPOI = ConfigModule:Get("hideUntrackedPOI"),
            showHoveredPOI = ConfigModule:Get("showHoveredPOI"),
            showContinentPOI = ConfigModule:Get("showContinentPOI"),
            superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID(),
        }

        local mapInfo = C_Map.GetMapInfo(mapID)
        ctx.mapInfo = mapInfo

        local pinTemplate = dp.GetPinTemplate and dp:GetPinTemplate() or dp.pinTemplate
        local isContinent = mapInfo and mapInfo.mapType == Enum.UIMapType.Continent

        if not pinTemplate then
            return
        end

        -- See ARCHITECTURE.md (cold-continent quest data).
        local hasPool = map.pinPools and map.pinPools[pinTemplate]
        if not hasPool and not isContinent then
            return
        end

        -- TAINT-SAFE FILTERING: never call Hide() on pins, only SetAlpha().
        -- See ARCHITECTURE.md (#161).
        --
        -- Pass 1: restore alpha on any pins we previously hidden, and build
        -- the active-pin set used below to prune stale addon-pin references.
        local activeSet = {}
        if hasPool then
            for pin in map.pinPools[pinTemplate]:EnumerateActive() do
                if pin.awqAlphaHidden then
                    pin:SetAlpha(1)
                    pin.awqAlphaHidden = nil
                end
                activeSet[pin] = true
            end
        end

        -- Clean up stale addon-pin references (pins released by Blizzard's
        -- pool:ReleaseAll on the previous RefreshAllData are no longer active).
        -- We do NOT call map:RemovePin — that calls pin:Hide() internally.
        local remainingAddonPins = {}
        for _, pin in ipairs(addonAddedPins) do
            if activeSet[pin] then
                table.insert(remainingAddonPins, pin)
            end
        end
        addonAddedPins = remainingAddonPins

        -- Pass 1b: re-hide addon-added pins that are no longer valid for
        -- this map. See ARCHITECTURE.md (#166).
        for _, pin in ipairs(addonAddedPins) do
            if pin.questID == pin.awqQuestID and not IsAddonPinExpected(ctx, pin) then
                pin:SetAlpha(0)
                pin.awqAlphaHidden = true
            end
        end

        -- Pass 2: alpha-hide filtered pins. See ARCHITECTURE.md (#161) for why
        -- only SetAlpha(0) is used here (never Hide/EnableMouse/
        -- SetHitRectInsets).
        if hasPool then
            for pin in map.pinPools[pinTemplate]:EnumerateActive() do
                if pin.questID and C_QuestLog.IsWorldQuest(pin.questID) then
                    if ShouldFilterQuest(ctx, { questID = pin.questID, mapID = pin.mapID or mapID }) then
                        pin:SetAlpha(0)
                        pin.awqAlphaHidden = true
                    end
                end
            end
        end

        -- Pass 3: place our own pins for child-zone quests on continent maps.
        -- This is the only pass that shows or moves pins, so it is gated on
        -- CanMutateMapPins(). See ARCHITECTURE.md (#174).
        if mapInfo and mapInfo.mapType == Enum.UIMapType.Continent and CanMutateMapPins() then
            local childQuests = GetCachedChildQuests(ctx)

            if ctx.showContinentPOI then
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
                        and not ShouldFilterQuest(ctx, info) then

                        AddTrackedWorldQuestPin(ctx, info)
                        shownQuests[info.questID] = true
                    end
                end
            end

            local superTrackedQuestID = ctx.superTrackedQuestID
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
                            AddTrackedWorldQuestPin(ctx, info)
                            break
                        end
                    end
                end
            end
        end
    end

    function QuestFrameModule:InitializeProvider()
        dataProvider = GetDataProvider()

        -- NOTE: there is deliberately no hooksecurefunc on RefreshAllData
        -- here. See ARCHITECTURE.md (#168). Pin post-processing is instead
        -- triggered from our own ticker below.
    end

    --region Taint-safe pin refresh trigger
    --
    -- Driven entirely by a C_Timer ticker, deliberately with NO event
    -- registrations. See ARCHITECTURE.md (#168, #174).
    function QuestFrameModule:InitializePinRefreshTriggers()
        C_Timer.NewTicker(0.5, function()
            if not dataProvider or not QuestMapFrame or not QuestMapFrame:IsShown() then
                return
            end

            securecallfunction(function()
                PostProcessWorldQuestPins(dataProvider)
            end)
        end)
    end
    --endregion

    function QuestFrameModule:ApplyWorkarounds()
        -- Override QuestUtil.TrackWorldQuest/UntrackWorldQuest to remove the
        -- ObjectiveTrackerManager:UpdateAll() call. See ARCHITECTURE.md (#67).
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
                    QuestFrameModule:RequestQuestLogUpdate()
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
                    QuestFrameModule:RequestQuestLogUpdate()
                    QuestFrameModule:RequestFullRefresh("UNTRACK_WORLD_QUEST")
                end
                --ObjectiveTrackerManager:UpdateAll(); -- see ARCHITECTURE.md (#67)
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
        ConfigModule:RegisterCallback({ "hideUntrackedPOI", "hideFilteredPOI", "showContinentPOI", "onlyCurrentZone", "sortMethod", "selectedFilters","disabledFilters", "filterEmissary", "filterLoot", "filterFaction", "filterZone", "filterTime", "lootFilterUpgrades", "lootUpgradesLevel", "timeFilterDuration" }, function(key)
            QuestFrameModule:RequestQuestLogUpdate()
            self:RequestFullRefresh(key)
        end)
    end

    function QuestFrameModule:OnInitialize()
        self:InitializeFilterLists()
    end

    function QuestFrameModule:OnEnable()
        self:InitializeProvider()
        self:ApplyWorkarounds()
        self:ExtendMapMenu()

        -- Create awqPanel, awqContainer, titleFramePool and headerButton.
        self:InitQuestLogFrames()

        -- Taint-safe refresh triggers: see ARCHITECTURE.md (#168, #173, #174) for
        -- why these are C_Timer tickers instead of hooks or event frames.
        self:InitializeListRefreshTriggers()
        self:InitializePinRefreshTriggers()

        -- The one event-driven trigger (player movement); see the
        -- player-movement show/hide trigger region for why it is safe.
        self:InitializeMovementTriggers()

        self:RegisterCallbacks()
    end
end
--endregion
