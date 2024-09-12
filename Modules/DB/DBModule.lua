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
local DBModule = AngrierWorldQuests:NewModule("DBModule")

local defaultOptions = {
    profile = {
        collapsed = "false",
        showAtTop = "true",
        showHoveredPOI = "false",
        onlyCurrentZone = "true",
        selectedFilters = 0,
        disabledFilters = 3725425,
        __filters = 24,
        filterEmissary = 0,
        filterLoot = 0,
        filterFaction = 0,
        filterZone = 0,
        filterTime = 0,
        lootFilterUpgrades = "false",
        lootUpgradesLevel = -1,
        timeFilterDuration = 6,
        hideUntrackedPOI = "false",
        hideFilteredPOI = "true",
        hideQuestList = "false",
        showContinentPOI = "true",
        colorWarbandBonus = "false",
        enableDebugging = "false",
        enableTaintWorkarounds = "false",
        sortMethod = 2,
        extendedInfo = "false",
        saveFilters = "false"
    }
}

function DBModule:OnInitialize()
    self.AceDB = LibStub("AceDB-3.0"):New("AngrierWorldQuestsDB", defaultOptions, true)

    self:MigrateProfile()
end

function DBModule:GetProfile()
    return self.AceDB.profile
end

function DBModule:GetValue(key)
    return self:GetProfile()[key] or defaultOptions.profile[key]
end

function DBModule:SetValue(key, value)
    if value == defaultOptions.profile[key] then
        self:GetProfile()[key] = nil
    else
        self:GetProfile()[key] = value
    end
end

function DBModule:Reset()
    for k, _ in pairs(defaultOptions.profile) do
        self:SetValue(k, nil)
    end
end

-- region Migrations
do
    local function GetDataVersion(profile)
        return profile.dataVersion or 0
    end

    local function MigrateOldSettings(profile)
        local sharedDB = LibStub("AceDB-3.0"):New("AngrierWorldQuests_Config")

        if sharedDB and sharedDB.sv then
            for k, v in pairs(sharedDB.sv) do
                local usable = defaultOptions.profile[k] ~= nil
    
                if usable then
                    DBModule:SetValue(k, v)
                end

                sharedDB.sv[k] = nil
            end
        end

        profile.dataVersion = 1
        return GetDataVersion(profile)
    end

    local function MigrateTrueFalseToStrings(profile)
        for k, v in pairs(defaultOptions.profile) do
            if DBModule:GetValue(k) == true then
                DBModule:SetValue(k, "true")
            end
        end

        profile.dataVersion = 2
        return GetDataVersion(profile)
    end

    function DBModule:MigrateProfile()
        local profile = self:GetProfile()
        local version = GetDataVersion(profile)

        if version < 1 then
            version = MigrateOldSettings(profile)
        end
        if version < 2 then
            version = MigrateTrueFalseToStrings(profile)
        end
    end
end
--endregion