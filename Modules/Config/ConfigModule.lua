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
local ConfigModule = AngrierWorldQuests:NewModule("ConfigModule")
local DBModule = AngrierWorldQuests:GetModule("DBModule")

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

--region Variables

local filtersConversion = {
    EMISSARY = 1,
    ARTIFACT_POWER = 2,
    LOOT = 3,
    ORDER_RESOURCES = 4,
    GOLD = 5,
    ITEMS = 6,
    TIME = 7,
    FACTION = 8,
    PVP = 9,
    PROFESSION = 10,
    PETBATTLE = 11,
    SORT = 12,
    TRACKED = 13,
    ZONE = 14,
    RARE = 15,
    DUNGEON = 16,
    WAR_SUPPLIES = 17,
    NETHERSHARD = 18,
    VEILED_ARGUNITE = 19,
    WAKENING_ESSENCE = 20,
    AZERITE = 21,
    WAR_RESOURCES = 22,
    ANIMA = 23,
    CONDUIT = 24
}

ConfigModule.SortOrder = {
    _AngrierWorldQuests.Enums.SortOrder.SORT_NAME,
    _AngrierWorldQuests.Enums.SortOrder.SORT_TIME,
    _AngrierWorldQuests.Enums.SortOrder.SORT_ZONE,
    _AngrierWorldQuests.Enums.SortOrder.SORT_FACTION,
    _AngrierWorldQuests.Enums.SortOrder.SORT_REWARDS
}

local optionPanel
local profilePanel
local callbacks = {}

--endregion

--region Configuration options

do
    local filterTable

    function ConfigModule:Get(key)
        local value = DBModule:GetValue(key)

        if value == "true" then
            return true
        elseif value == "false" then
            return false
        else
            return value
        end
    end

    function ConfigModule:Set(key, newValue, silent)
        DBModule:SetValue(key, newValue)

        if key == 'selectedFilters' then
            filterTable = nil
        end

        if callbacks[key] and not silent then
            for _, func in ipairs(callbacks[key]) do
                func(key, newValue)
            end
        end
    end

    function ConfigModule:RegisterCallback(key, func)
        if type(key) == "table" then
            for _, key2 in ipairs(key) do
                if callbacks[key2] then
                    table.insert(callbacks, func)
                else
                    callbacks[key2] = { func }
                end
            end
        else
            if callbacks[key] then
                table.insert(callbacks, func)
            else
                callbacks[key] = { func }
            end
        end
    end

    function ConfigModule:FilterKeyToMask(key)
        local index = filtersConversion[key]
        return 2^(index - 1)
    end

    function ConfigModule:HasFilters()
        return self:Get('selectedFilters') > 0
    end

    function ConfigModule:IsOnlyFilter(key)
        local value = self:Get('selectedFilters')
        local mask = self:FilterKeyToMask(key)

        return mask == value
    end

    function ConfigModule:GetFilter(key)
        local value = self:Get('selectedFilters')
        local mask = self:FilterKeyToMask(key)

        return bit.band(value, mask) == mask
    end

    function ConfigModule:GetFilterTable()
        if filterTable == nil then
            local value = self:Get('selectedFilters')
            filterTable = {}

            for key, i in pairs(filtersConversion) do
                local mask = 2^(i-1)

                if bit.band(value, mask) == mask then
                    filterTable[key] = true
                end
            end
        end

        return filterTable
    end

    function ConfigModule:GetFilterDisabled(key)
        local value = self:Get('disabledFilters')
        local mask = self:FilterKeyToMask(key)

        return bit.band(value, mask) == mask
    end

    function ConfigModule:SetFilter(key, newValue)
        local value = self:Get('selectedFilters')
        local mask = self:FilterKeyToMask(key)

        if newValue then
            value = bit.bor(value, mask)
        else
            value = bit.band(value, bit.bnot(mask))
        end

        self:Set('selectedFilters', value)
    end

    function ConfigModule:SetNoFilter()
        self:Set('selectedFilters', 0)
    end

    function ConfigModule:SetOnlyFilter(key)
        local mask = self:FilterKeyToMask(key)

        self:Set('selectedFilters', mask)
    end

    function ConfigModule:ToggleFilter(key)
        local value = self:Get('selectedFilters')
        local mask = self:FilterKeyToMask(key)
        local currentValue = bit.band(value, mask) == mask

        if not currentValue then
            value = bit.bor(value, mask)
        else
            value = bit.band(value, bit.bnot(mask))
        end

        self:Set('selectedFilters', value)

        return not currentValue
    end
end

--endregion

--region Configuration dialog

do
    local panelOriginalConfig = {}
    local panelInit, checkboxes, dropdowns, filterCheckboxes
    local lootUpgradeLevelValues = { -1, 0, 5, 10, 15, 20, 25, 30 }

    local DropDown_Index = 0

    local Panel_OnRefresh

    local function FilterCheckBox_Update(self)
        local value = ConfigModule:Get("disabledFilters")
        local mask = self.filterMask

        self:SetChecked( bit.band(value, mask) == 0 )
    end

    local function FilterCheckBox_OnClick(self)
        local key = "disabledFilters"

        if panelOriginalConfig[key] == nil then
            panelOriginalConfig[key] = ConfigModule:Get(key)
        end

        local value = ConfigModule:Get("disabledFilters")
        local mask = self.filterMask

        if self:GetChecked() then
            value = bit.band(value, bit.bnot(mask))
        else
            value = bit.bor(value, mask)
        end

        DBModule:SetValue("selectedFilters", nil)

        ConfigModule:Set(key, value)
    end

    local function CheckBox_Update(self)
        self:SetChecked(ConfigModule:Get(self.configKey))
    end

    local function CheckBox_OnClick(self)
        local key = self.configKey

        if panelOriginalConfig[key] == nil then
            panelOriginalConfig[key] = ConfigModule:Get(key)
        end

        if self:GetChecked() then
            ConfigModule:Set(key, "true")
        else
            ConfigModule:Set(key, "false")
        end
    end

    local function DropDown_OnClick(self, dropdown)
        local key = dropdown.configKey

        if panelOriginalConfig[key] == nil then
            panelOriginalConfig[key] = ConfigModule:Get(key)
        end

        ConfigModule:Set(key, self.value)

        AWQ_UIDropDownMenu_SetSelectedValue( dropdown, self.value )
    end

    local function DropDown_Initialize(self)
        local key = self.configKey
        local selectedValue = AWQ_UIDropDownMenu_GetSelectedValue(self)
        local info = AWQ_UIDropDownMenu_CreateInfo()
        info.func = DropDown_OnClick
        info.arg1 = self

        if key == 'timeFilterDuration' then
            for _, hours in ipairs(ConfigModule.Filters.TIME.values) do
                info.text = string.format(FORMATED_HOURS, hours)
                info.value = hours
                if ( selectedValue == info.value ) then
                    info.checked = 1
                else
                    info.checked = nil
                end
                AWQ_UIDropDownMenu_AddButton(info)
            end
        elseif key == 'sortMethod' then
            for _, index in ipairs(ConfigModule.SortOrder) do
                info.text = L["config_sortMethod_"..index]
                info.value = index
                if ( selectedValue == info.value ) then
                    info.checked = 1
                else
                    info.checked = nil
                end
                AWQ_UIDropDownMenu_AddButton(info)
            end
        elseif key == 'lootUpgradesLevel' then
            for i, ilvl in ipairs(lootUpgradeLevelValues) do
                if L["config_lootUpgradesLevelValue"..i] ~= ("config_lootUpgradesLevelValue"..i) then
                    info.text = L["config_lootUpgradesLevelValue"..i]
                else
                    info.text = format(L["config_lootUpgradesLevelValue"], ilvl)
                end
                info.value = ilvl
                if ( selectedValue == info.value ) then
                    info.checked = 1
                else
                    info.checked = nil
                end
                AWQ_UIDropDownMenu_AddButton(info)
            end
        end
    end

    local function DropDown_Create(self)
        DropDown_Index = DropDown_Index + 1
        local dropdown = CreateFrame("Frame", addonName.."ConfigDropDown"..DropDown_Index, self, AWQ_UIDropDownMenuTemplate)

        local label = dropdown:CreateFontString(addonName.."ConfigDropLabel"..DropDown_Index, "BACKGROUND", "GameFontNormal")
        label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 16, 3)
        dropdown.Label = label

        return dropdown
    end

    local function Panel_OnSave(self)
        wipe(panelOriginalConfig)
    end

    local function Panel_OnCancel(self)
        wipe(panelOriginalConfig)
    end

    local function Panel_OnDefaults(self)
        DBModule:Reset()

        for key, callbacks_key in pairs(callbacks) do
            for _, func in ipairs(callbacks_key) do
                func(key, DBModule:GetValue(key))
            end
        end

        wipe(panelOriginalConfig)
    end

    Panel_OnRefresh = function(self)
        if not panelInit then
            local footer = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            footer:SetPoint('BOTTOMRIGHT', -16, 16)
            footer:SetText( AngrierWorldQuests.Version or "Dev" )

            local label = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            label:SetPoint("TOPLEFT", 16, -16)
            label:SetJustifyH("LEFT")
            label:SetJustifyV("TOP")
            label:SetText( AngrierWorldQuests.Name )

            checkboxes = {}
            dropdowns = {}
            filterCheckboxes = {}

            local checkboxes_order = {
                 "showAtTop",
                 "onlyCurrentZone",
                 "showContinentPOI",
                 "hideFilteredPOI",
                 "hideUntrackedPOI",
                 "hideQuestList",
                 "showHoveredPOI",
                 "lootFilterUpgrades",
                 "enableTaintWorkarounds",
                 "enableDebugging"
            }

            for i,key in ipairs(checkboxes_order) do
                checkboxes[i] = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
                checkboxes[i]:SetScript("OnClick", CheckBox_OnClick)
                checkboxes[i].configKey = key
                checkboxes[i].Text:SetText( L["config_"..key] )
                if i == 1 then
                    checkboxes[i]:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -2, -8)
                else
                    checkboxes[i]:SetPoint("TOPLEFT", checkboxes[i-1], "BOTTOMLEFT", 0, 0)
                end
            end

            local dropdowns_order = { "timeFilterDuration", "sortMethod", "lootUpgradesLevel" }

            for i, key in ipairs(dropdowns_order) do
                dropdowns[i] = DropDown_Create(self)
                dropdowns[i].Label:SetText( L["config_"..key] )
                dropdowns[i].configKey = key
                if i == 1 then
                    dropdowns[i]:SetPoint("TOPLEFT", checkboxes[#checkboxes], "BOTTOMLEFT", -13, -24)
                else
                    dropdowns[i]:SetPoint("TOPLEFT", dropdowns[i-1], "BOTTOMLEFT", 0, -24)
                end
            end

            local label2 = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label2:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 435, -5)
            label2:SetJustifyH("LEFT")
            label2:SetJustifyV("TOP")
            label2:SetText(L["config_enabledFilters"])

            for i,key in ipairs(ConfigModule.FiltersOrder) do
                local filter = ConfigModule.Filters[key]
                filterCheckboxes[i] = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
                filterCheckboxes[i]:SetScript("OnClick", FilterCheckBox_OnClick)
                filterCheckboxes[i].filterMask = ConfigModule:FilterKeyToMask(key)
                filterCheckboxes[i].Text:SetFontObject("GameFontHighlightSmall")
                filterCheckboxes[i].Text:SetPoint("LEFT", filterCheckboxes[i], "RIGHT", 0, 1)
                filterCheckboxes[i].Text:SetText( filter.name )

                if i == 1 then
                    filterCheckboxes[1]:SetPoint("TOPLEFT", label2, "BOTTOMLEFT", 0, -5)
                else
                    filterCheckboxes[i]:SetPoint("TOPLEFT", filterCheckboxes[i-1], "BOTTOMLEFT", 0, 4)
                end
            end

            panelInit = true
        end

        for _, check in ipairs(checkboxes) do
            CheckBox_Update(check)
        end

        for _, dropdown in ipairs(dropdowns) do
            AWQ_UIDropDownMenu_Initialize(dropdown, DropDown_Initialize)
            AWQ_UIDropDownMenu_SetSelectedValue(dropdown, ConfigModule:Get(dropdown.configKey))
        end

        for _, check in ipairs(filterCheckboxes) do
            FilterCheckBox_Update(check)
        end
    end

    function ConfigModule:CreatePanel()
        local panel = CreateFrame("FRAME")
        panel.OnCommit = Panel_OnSave
        panel.OnCancel = Panel_OnCancel
        panel.OnDefault  = Panel_OnDefaults
        panel.OnRefresh  = Panel_OnRefresh
        local category = Settings.RegisterCanvasLayoutCategory(panel, addonName, addonName)
        category.ID = addonName
        Settings.RegisterAddOnCategory(category);

        return panel
    end

    function ConfigModule:CreateProfilePanel()
		local profileOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(DBModule.AceDB)
		LibStub("AceConfig-3.0"):RegisterOptionsTable("AWQ-Profiles", profileOptions)
        local profilePanel = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("AWQ-Profiles", "Profiles", addonName)

        return profilePanel
    end
end

--endregion

--region Initialization

do
    function ConfigModule:InitializeSettings()
        if not DBModule:GetValue("saveFilters") then
            DBModule:SetValue("selectedFilters", nil)
            DBModule:SetValue("filterEmissary", nil)
            DBModule:SetValue("filterLoot", nil)
            DBModule:SetValue("filterFaction", nil)
            DBModule:SetValue("filterZone", nil)
            DBModule:SetValue("filterTime", nil)
        end
    end

    function ConfigModule:InitializeFilters()
        local lastFilter = DBModule:GetValue("__filters")
        local disabledFilters = DBModule:GetValue("disabledFilters") or 0

        local maxFilter = 0
        for key, index in pairs(filtersConversion) do
            if self.Filters[key] then
                local mask = 2^(index-1)

                if not lastFilter or index > lastFilter then
                    if self.Filters[key].default then
                        disabledFilters = bit.band(disabledFilters, bit.bnot(mask))
                    else
                        disabledFilters = bit.bor(disabledFilters, mask)
                    end
                end

                if index > maxFilter then
                    maxFilter = index
                end
            end
        end

        DBModule:SetValue("disabledFilters", disabledFilters)
        DBModule:SetValue("__filters", maxFilter)
    end

    function ConfigModule:OnInitialize()
        self.Filters = {}
        self.FiltersOrder = {}
    end

    function ConfigModule:OnEnable()
        self:InitializeSettings()
        self:InitializeFilters()

        optionPanel = self:CreatePanel()
        profilePanel = self:CreateProfilePanel()
    end
end

SLASH_ANGRIERWORLDQUESTS1 = "/awq"
SLASH_ANGRIERWORLDQUESTS2 = "/angrierworldquests"
function SlashCmdList.ANGRIERWORLDQUESTS(msg, editbox)
    Settings.OpenToCategory(addonName)
end

--endregion