--[[
    Copyright (C) 2024 GurliGebis

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
local DataModule = AngrierWorldQuests:NewModule("DataModule", "AceEvent-3.0")
local ConfigModule = AngrierWorldQuests:GetModule("ConfigModule")

local cachedItems = {}

do
    --region Maps and data

    --region Legion
    local CONTINENT_LEGION = 619 -- Broken Isles main map
    local CONTINENT_LEGION_ARGUS = 905
    local FACTION_ORDER_LEGION = {
        1900, -- Court of Farondis
        1883, -- Dreamweavers
        1828, -- Highmountain Tribe
        1948, -- Valarjar
        1894, -- The Wardens
        1859, -- The Nightfallen
        1090, -- Kirin Tor
        2045, -- Armies of Legionfall
        2165, -- Army of the Light
        2170, -- Argussian Reach
    }
    local FILTERS_LEGION = { "ORDER_RESOURCES", "WAKENING_ESSENCE" }
    local MAPS_LEGION = {
        [627] = true, -- Dalaran
        [630] = true, -- Azsuna
        [634] = true, -- Stormheim
        [641] = true, -- Val'sharah
        [646] = true, -- Broken Shore
        [650] = true, -- Highmountain
        [680] = true, -- Suramar
        [790] = true, -- Eye of Azshara
        [830] = true, -- Krokuun
        [882] = true, -- Eredath
        [885] = true, -- Antoran Wastes
        [905] = true, -- Argus
    }
    local MAPS_LEGION_ARGUS = {
        [830] = true, -- Krokuun
        [882] = true, -- Eredath
        [885] = true, -- Antoran Wastes
    }
    --endregion

    --region Battle for Azeroth
    local CONTINENT_BFA_HORDE = 875    -- Zandalar
    local CONTINENT_BFA_ALLIANCE = 876 -- Kul Tiras
    local FACTION_ORDER_BFA_ALLIANCE = {
        2159, -- 7th Legion
        2164, -- Champions of Azeroth
        2160, -- Proudmoore Admiralty
        2161, -- Order of Embers
        2162, -- Storm's Wake
        2163, -- Tortollan Seekers
    }
    local FACTION_ORDER_BFA_HORDE = {
        2157, -- The Honorbound
        2164, -- Champions of Azeroth
        2156, -- Talanji's Expedition
        2158, -- Voldunai
        2103, -- Zandalari Empire
        2163, -- Tortollan Seekers
    }
    local FILTERS_BFA = { "AZERITE", "WAR_RESOURCES" }
    local MAPS_BFA_ALLIANCE = {
        [895] = true,  -- Tiragarde Sound
        [896] = true,  -- Drustvar
        [942] = true,  -- Stormsong Valley
        [1355] = true, -- Nazjatar
        [1462] = true, -- Mechagon
    }
    local MAPS_BFA_HORDE = {
        [862] = true,  -- Zuldazar
        [863] = true,  -- Nazmir
        [864] = true,  -- Vol'dun
        [1355] = true, -- Nazjatar
    }
    --endregion

    --region Shadowlands
    local CONTINENT_SHADOWLANDS = 1550 -- Shadowlands main map
    local FACTION_ORDER_SHADOWLANDS = {
        2413, -- Court of Harvesters
        2407, -- The Ascended
        2410, -- The Undying Army
        2465, -- The Wild Hunt
    }
    local FILTERS_SHADOWLANDS = { "ANIMA", "CONDUIT" }
    local MAPS_SHADOWLANDS = {
        [1543] = true, -- The Maw
        [1536] = true, -- Maldraxxus
        [1525] = true, -- Revendreth
        [1533] = true, -- Bastion
        [1565] = true, -- Ardenweald
    }
    --endregion

    --region Dragonflight
    local CONTINENT_DRAGONFLIGHT = 1978 -- Dragonflight main map
    local FACTION_ORDER_DRAGONFLIGHT = {
        2507, -- Dragonscale Expedition
        2503, -- Maruuk Centaur
        2511, -- Iskaara Tuskarr
        2510, -- Valdrakken Accord
        2518, -- Sabellian
        2517, -- Wrathion
        2523, -- Dark Talons
        2564, -- Loamm Niffen
        2574, -- Dream Wardens
        2615, -- Azerothian Archives
    }
    local MAPS_DRAGONFLIGHT = {
        [2022] = true, -- The Waking Shore
        [2023] = true, -- Ohn'ahran Plains
        [2024] = true, -- Azure Span
        [2025] = true, -- Thaldrazus
        [2112] = true, -- Valdrakken
        [2133] = true, -- Zaralek Cavern
        [2151] = true, -- The Forbidden Reach
        [2200] = true, -- Emerald Dream
    }
    --endregion

    --region The War Within
    local CONTINENT_THE_WAR_WITHIN = 2274 -- Khaz Algar main map
    local FACTION_ORDER_THE_WAR_WITHIN = {
        2570, -- Hallowfall Arathi
        2590, -- Council of Dornogal
        2594, -- The Assembly of the Deeps
        2600, -- The Severed Threads
    }
    local MAPS_THE_WAR_WITHIN = {
        [2214] = true, -- The Ringing Deeps
        [2215] = true, -- Hallowfall
        [2248] = true, -- Isle of Dorn
        [2255] = true, -- Azj-Kahet
    }
    --endregion

    --endregion

    function DataModule:GetExpansionByMapID(mapID)
        if MAPS_LEGION[mapID] or mapID == CONTINENT_LEGION then
            return _AngrierWorldQuests.Enums.Expansion.LEGION
        elseif MAPS_BFA_ALLIANCE[mapID] or MAPS_BFA_HORDE[mapID] or mapID == CONTINENT_BFA_ALLIANCE or mapID == CONTINENT_BFA_HORDE then
            return _AngrierWorldQuests.Enums.Expansion.BFA
        elseif MAPS_SHADOWLANDS[mapID] or mapID == CONTINENT_SHADOWLANDS then
            return _AngrierWorldQuests.Enums.Expansion.SHADOWLANDS
        elseif MAPS_DRAGONFLIGHT[mapID] or mapID == CONTINENT_DRAGONFLIGHT then
            return _AngrierWorldQuests.Enums.Expansion.DRAGONFLIGHTS
        elseif MAPS_THE_WAR_WITHIN[mapID] or mapID == CONTINENT_THE_WAR_WITHIN then
            return _AngrierWorldQuests.Enums.Expansion.THE_WAR_WITHIN
        else
            return nil
        end
    end

    function DataModule:GetFactionsByMapID(mapID)
        local expansion = DataModule:GetExpansionByMapID(mapID)

        if expansion == _AngrierWorldQuests.Enums.Expansion.LEGION then
            return FACTION_ORDER_LEGION
        elseif expansion == _AngrierWorldQuests.Enums.Expansion.BFA then
            if UnitFactionGroup("player") == "Alliance" then
                return FACTION_ORDER_BFA_ALLIANCE
            else
                return FACTION_ORDER_BFA_HORDE
            end
        elseif expansion == _AngrierWorldQuests.Enums.Expansion.SHADOWLANDS then
            return FACTION_ORDER_SHADOWLANDS
        elseif expansion == _AngrierWorldQuests.Enums.Expansion.DRAGONFLIGHTS then
            return FACTION_ORDER_DRAGONFLIGHT
        elseif expansion == _AngrierWorldQuests.Enums.Expansion.THE_WAR_WITHIN then
            return FACTION_ORDER_THE_WAR_WITHIN
        else
            return nil
        end
    end

    function DataModule:GetMapIDsToGetQuestsFrom(mapID)
        local expansion = DataModule:GetExpansionByMapID(mapID)

        if ConfigModule:Get("onlyCurrentZone") then
            if expansion == _AngrierWorldQuests.Enums.Expansion.LEGION then
                if mapID == CONTINENT_LEGION then
                    return MAPS_LEGION
                end

                if mapID == CONTINENT_LEGION_ARGUS then
                    return MAPS_LEGION_ARGUS
                end
            elseif expansion == _AngrierWorldQuests.Enums.Expansion.BFA then
                if mapID == CONTINENT_BFA_ALLIANCE then
                    return MAPS_BFA_ALLIANCE
                end

                if mapID == CONTINENT_BFA_HORDE then
                    return MAPS_BFA_HORDE
                end
            elseif expansion == _AngrierWorldQuests.Enums.Expansion.SHADOWLANDS and mapID == CONTINENT_SHADOWLANDS then
                return MAPS_SHADOWLANDS
            elseif expansion == _AngrierWorldQuests.Enums.Expansion.DRAGONFLIGHTS and mapID == CONTINENT_DRAGONFLIGHT then
                return MAPS_DRAGONFLIGHT
            elseif expansion == _AngrierWorldQuests.Enums.Expansion.THE_WAR_WITHIN and mapID == CONTINENT_THE_WAR_WITHIN then
                return MAPS_THE_WAR_WITHIN
            end
        else
            if expansion == _AngrierWorldQuests.Enums.Expansion.LEGION then
                if MAPS_LEGION_ARGUS[mapID] then
                    return MAPS_LEGION_ARGUS
                elseif MAPS_LEGION[mapID] then
                    return MAPS_LEGION
                end
            elseif expansion == _AngrierWorldQuests.Enums.Expansion.BFA then
                if MAPS_BFA_ALLIANCE[mapID] then
                    return MAPS_BFA_ALLIANCE
                elseif MAPS_BFA_HORDE[mapID] then
                    return MAPS_BFA_HORDE
                end
            elseif expansion == _AngrierWorldQuests.Enums.Expansion.SHADOWLANDS then
                return MAPS_SHADOWLANDS
            elseif expansion == _AngrierWorldQuests.Enums.Expansion.DRAGONFLIGHTS then
                return MAPS_DRAGONFLIGHT
            elseif expansion == _AngrierWorldQuests.Enums.Expansion.THE_WAR_WITHIN then
                return MAPS_THE_WAR_WITHIN
            end
        end

        return { [mapID] = true }
    end

    local continentMapID = {}

    function DataModule:GetContentMapIDFromMapID(mapID)
        if continentMapID[mapID] == nil then
            local continentInfo = MapUtil.GetMapParentInfo(mapID, Enum.UIMapType.Continent)

            if continentInfo then
                continentMapID[mapID] = continentInfo.mapID
            end
        end

        return continentMapID[mapID]
    end

    function DataModule:IsFilterOnCorrectMap(filter, mapID)
        local expansion = DataModule:GetExpansionByMapID(mapID)

        if expansion == _AngrierWorldQuests.Enums.Expansion.LEGION and has_value(FILTERS_LEGION, filter) then
            return true
        elseif expansion == _AngrierWorldQuests.Enums.Expansion.BFA and has_value(FILTERS_BFA, filter) then
            return true
        elseif expansion == _AngrierWorldQuests.Enums.Expansion.SHADOWLANDS and has_value(FILTERS_SHADOWLANDS, filter) then
            return true
        end

        -- If the filter being checked is in none of the lists, it is correct for the current map.
        return not has_value(FILTERS_LEGION, filter)
               and not has_value(FILTERS_BFA, filter)
               and not has_value(FILTERS_SHADOWLANDS, filter)
    end

    function DataModule:IsQuestRewardFiltered(selectedFilters, questID)
        local positiveMatch = false
        local hasCurrencyFilter = false

        local money = GetQuestLogRewardMoney(questID)
        if money > 0 and selectedFilters["GOLD"] then
            positiveMatch = true
        end

        for key, _ in pairs(selectedFilters) do
            local filter = ConfigModule.Filters[key]
            if filter.preset == _AngrierWorldQuests.Constants.FILTERS.CURRENCY then
                hasCurrencyFilter = true
                for k, currencyInfo in ipairs(C_QuestLog.GetQuestRewardCurrencies(questID)) do
                    if filter.currencyID == currencyInfo.currencyID then
                        positiveMatch = true
                    end
                end
            end
        end

        local numQuestRewards = GetNumQuestLogRewards(questID)
        if numQuestRewards > 0 then
            local itemName, itemTexture, _, _, _, itemID = GetQuestLogRewardInfo(1, questID)
            if itemName and itemTexture then
                local iLevel = self:RewardItemLevel(itemID, questID)
                if C_Item.IsAnimaItemByID(itemID) then
                    if selectedFilters.ANIMA then
                        positiveMatch = true
                    end
                else
                    if iLevel then
                        local isConduit = C_Soulbinds.IsItemConduitByItemInfo(itemID)
                        local filterLoot = ConfigModule:Get("filterLoot")
                        local lootFilterUpgrades = ConfigModule:Get("lootFilterUpgrades")
                        local upgradesOnly = filterLoot == _AngrierWorldQuests.Constants.FILTERS.LOOT_UPGRADES or
                            (filterLoot == 0 and lootFilterUpgrades)
                        if selectedFilters.CONDUIT and isConduit or selectedFilters.LOOT and (not upgradesOnly or self:RewardIsUpgrade(itemID, questID)) and not isConduit then
                            positiveMatch = true
                        end
                    else
                        if selectedFilters.ITEMS then
                            positiveMatch = true
                        end
                    end
                end
            end
        end

        if positiveMatch then
            return false
        elseif hasCurrencyFilter or selectedFilters.ANIMA or selectedFilters.LOOT or selectedFilters.ITEMS then
            return true
        end
    end

    function DataModule:IsQuestFiltered(info, displayMapID)
        local hasFilters = ConfigModule:HasFilters()
        local selectedFilters = ConfigModule:GetFilterTable()

        local _, factionID = C_TaskQuest.GetQuestInfoByQuestID(info.questID)
        local questTagInfo = C_QuestLog.GetQuestTagInfo(info.questID)

        if not questTagInfo then
            return -- fix for nil tag
        end

        local tradeskillLineID = questTagInfo.tradeskillLineID
        local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(info.questID)
        C_TaskQuest.RequestPreloadRewardData(info.questID)

        local isQuestFiltered = hasFilters

        if hasFilters then
            local lootFiltered = self:IsQuestRewardFiltered(selectedFilters, info.questID)
            if lootFiltered ~= nil then
                isQuestFiltered = lootFiltered
            end

            if selectedFilters.FACTION then
                local filterFaction = ConfigModule:Get("filterFaction")

                if (factionID == filterFaction) then
                    isQuestFiltered = false
                end
            end

            if selectedFilters.TIME then
                local filterTime = ConfigModule:Get("filterTime")
                local timeFilterDuration = ConfigModule:Get("timeFilterDuration")
                local hours = filterTime ~= 0 and filterTime or timeFilterDuration

                if timeLeftMinutes and (timeLeftMinutes - WORLD_QUESTS_TIME_CRITICAL_MINUTES) <= (hours * 60) then
                    isQuestFiltered = false
                end
            end

            if selectedFilters.PVP then
                if questTagInfo.worldQuestType == Enum.QuestTagType.PvP then
                    isQuestFiltered = false
                end
            end

            if selectedFilters.PETBATTLE then
                if questTagInfo.worldQuestType == Enum.QuestTagType.PetBattle then
                    isQuestFiltered = false
                end
            end

            if selectedFilters.PROFESSION then
                if tradeskillLineID and WORLD_QUEST_ICONS_BY_PROFESSION[tradeskillLineID] then
                    isQuestFiltered = false
                end
            end

            if selectedFilters.TRACKED then
                if C_QuestLog.GetQuestWatchType(info.questID) == Enum.QuestWatchType.Manual or C_SuperTrack.GetSuperTrackedQuestID() == info.questID then
                    isQuestFiltered = false
                end
            end

            if selectedFilters.RARE then
                if questTagInfo.quality ~= Enum.WorldQuestQuality.Common then
                    isQuestFiltered = false
                end
            end

            if selectedFilters.DUNGEON then
                if questTagInfo.worldQuestType == Enum.QuestTagType.Dungeon or questTagInfo.worldQuestType == Enum.QuestTagType.Raid then
                    isQuestFiltered = false
                end
            end

            if selectedFilters.ZONE then
                local currentMapID = QuestMapFrame:GetParent():GetMapID()
                local filterMapID = ConfigModule:Get("filterZone")

                if filterMapID ~= 0 then
                    if info.mapID and info.mapID == filterMapID then
                        isQuestFiltered = false
                    end
                else
                    if info.mapID and info.mapID == currentMapID then
                        isQuestFiltered = false
                    end
                end
            end

            if selectedFilters.EMISSARY then
                local mapID = QuestMapFrame:GetParent():GetMapID()

                if mapID == _AngrierWorldQuests.Constants.MAP_IDS.BROKENISLES then
                    mapID = _AngrierWorldQuests.Constants.MAP_IDS.DALARAN -- fix no emissary on broken isles continent map
                end

                local bounties = C_QuestLog.GetBountiesForMapID(mapID)

                if bounties then
                    local bountyFilter = ConfigModule:Get("filterEmissary")
                    if not C_QuestLog.IsOnQuest(bountyFilter) or C_QuestLog.IsComplete(bountyFilter) then
                        bountyFilter = 0 -- show all bounties
                    end

                    for _, bounty in ipairs(bounties) do
                        if bounty and not C_QuestLog.IsComplete(bounty.questID) and C_QuestLog.IsQuestCriteriaForBounty(info.questID, bounty.questID) and (bountyFilter == 0 or bountyFilter == bounty.questID) then
                            isQuestFiltered = false
                        end
                    end
                end
            end

            -- don't filter quests if not in the right map
            for key in pairs(selectedFilters) do
                local rightMap = self:IsFilterOnCorrectMap(key, displayMapID)

                if not rightMap then
                    isQuestFiltered = false
                end
            end
        end

        if ConfigModule:Get("onlyCurrentZone") and info.mapID ~= displayMapID and displayMapID ~= _AngrierWorldQuests.Constants.MAP_IDS.AZEROTH then
            -- Needed since C_TaskQuest.GetQuestsForPlayerByMapID returns quests not on the passed map.....
            -- But, if we are on a continent (the quest continent map id matches the currently shown map)
            -- we should not be changing anything, since quests should be shown here.
            if (self:GetContentMapIDFromMapID(info.mapID) ~= displayMapID) then
                isQuestFiltered = true
            end
        end

        return isQuestFiltered
    end
end

do
    local invtype_locations = {
        INVTYPE_HEAD = { INVSLOT_HEAD },
        INVTYPE_NECK = { INVSLOT_NECK },
        INVTYPE_SHOULDER = { INVSLOT_SHOULDER },
        INVTYPE_BODY = { INVSLOT_BODY },
        INVTYPE_CHEST = { INVSLOT_CHEST },
        INVTYPE_ROBE = { INVSLOT_CHEST },
        INVTYPE_WAIST = { INVSLOT_WAIST },
        INVTYPE_LEGS = { INVSLOT_LEGS },
        INVTYPE_FEET = { INVSLOT_FEET },
        INVTYPE_WRIST = { INVSLOT_WRIST },
        INVTYPE_HAND = { INVSLOT_HAND },
        INVTYPE_FINGER = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
        INVTYPE_TRINKET = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 },
        INVTYPE_CLOAK = { INVSLOT_BACK },
        INVTYPE_WEAPON = { INVSLOT_MAINHAND, INVSLOT_OFFHAND },
        INVTYPE_SHIELD = { INVSLOT_OFFHAND },
        INVTYPE_2HWEAPON = { INVSLOT_MAINHAND },
        INVTYPE_WEAPONMAINHAND = { INVSLOT_MAINHAND },
        INVTYPE_WEAPONOFFHAND = { INVSLOT_OFFHAND },
        INVTYPE_HOLDABLE = { INVSLOT_OFFHAND },
    }

    function DataModule:RewardIsUpgrade(itemID, questID)
        local equipSlot = select(4, C_Item.GetItemInfoInstant(itemID))
        local ilvl = self:RewardItemLevel(itemID, questID)

        if equipSlot and invtype_locations[equipSlot] then
            local lootUpgradesLevel = ConfigModule:Get("lootUpgradesLevel")

            for _, slotID in ipairs(invtype_locations[equipSlot]) do
                local currentItem = ItemLocation:CreateFromEquipmentSlot(slotID)

                if currentItem:IsValid() then
                    local currentIlvl = C_Item.GetCurrentItemLevel(currentItem)

                    if not currentIlvl or ilvl >= (currentIlvl - lootUpgradesLevel) then
                        return true
                    end
                else
                    return true
                end
            end

            return false
        else
            return true
        end
    end

    function DataModule:RewardItemLevel(itemID, questID)
        local key = itemID .. ":" .. questID

        if cachedItems[key] == nil then
            local invType = C_Item.GetItemInventoryTypeByID(itemID)
            local _, _, _, _, _, itemClassID, itemSubClassID = C_Item.GetItemInfoInstant(itemID)

            if invType == Enum.InventoryType.IndexNonEquipType and (itemClassID ~= Enum.ItemClass.Gem or itemSubClassID ~= Enum.ItemGemSubclass.Artifactrelic) then
                cachedItems[key] = false
                return false
            end

            local itemLink = GetQuestLogItemLink("reward", 1, questID)
            cachedItems[key] = C_Item.GetDetailedItemLevelInfo(itemLink)
        end
        return cachedItems[key]
    end
end

--region Initialization
do
    function DataModule:QuestLogChanged(arg1)
        if arg1 == "player" then
            wipe(cachedItems)
        end
    end

    function DataModule:EnteringWorld()
        wipe(cachedItems)
    end

    function DataModule:RegisterEventHandlers()
        self:RegisterEvent("UNIT_QUEST_LOG_CHANGED", "QuestLogChanged")
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "EnteringWorld")
    end

    function DataModule:OnInitialize()
        self:RegisterEventHandlers()
    end
end
--endregion
