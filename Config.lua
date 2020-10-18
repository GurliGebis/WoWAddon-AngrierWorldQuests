local ADDON, Addon = ...
local Config = Addon:NewModule('Config')

local configVersion = 20
local configDefaults = {
	collapsed = false,
	showAtTop = true,
	showHoveredPOI = false,
	onlyCurrentZone = true,
	selectedFilters = 0,
	disabledFilters = 0,
	filterEmissary = 0,
	filterLoot = 0,
	filterFaction = 0,
	filterZone = 0,
	filterTime = 0,
	lootFilterUpgrades = false,
	lootUpgradesLevel = -1,
	timeFilterDuration = 6,
	hideUntrackedPOI = false,
	hideFilteredPOI = true,
	showContinentPOI = true,
	showComparisonRight = false,
	sortMethod = 2,
	extendedInfo = false,
	saveFilters = false,
}

local FiltersConversion = { EMISSARY = 1, ARTIFACT_POWER = 2, LOOT = 3, ORDER_RESOURCES = 4, GOLD = 5, ITEMS = 6, TIME = 7, FACTION = 8, PVP = 9, PROFESSION = 10, PETBATTLE = 11, SORT = 12, TRACKED = 13, ZONE = 14, RARE = 15, DUNGEON = 16, WAR_SUPPLIES = 17, NETHERSHARD = 18, VEILED_ARGUNITE = 19, WAKENING_ESSENCE = 20, AZERITE = 21, WAR_RESOURCES = 22 }

local callbacks = {}
local __filterTable

local My_UIDropDownMenu_SetSelectedValue, My_UIDropDownMenu_GetSelectedValue, My_UIDropDownMenu_CreateInfo, My_UIDropDownMenu_AddButton, My_UIDropDownMenu_Initialize, My_UIDropDownMenuTemplate
function Config:InitializeDropdown()
	My_UIDropDownMenu_SetSelectedValue = Lib_UIDropDownMenu_SetSelectedValue or UIDropDownMenu_SetSelectedValue
	My_UIDropDownMenu_GetSelectedValue = Lib_UIDropDownMenu_GetSelectedValue or UIDropDownMenu_GetSelectedValue
	My_UIDropDownMenu_CreateInfo = Lib_UIDropDownMenu_CreateInfo or UIDropDownMenu_CreateInfo
	My_UIDropDownMenu_AddButton = Lib_UIDropDownMenu_AddButton or UIDropDownMenu_AddButton
	My_UIDropDownMenu_Initialize = Lib_UIDropDownMenu_Initialize or UIDropDownMenu_Initialize
	My_UIDropDownMenuTemplate = Lib_UIDropDownMenu_Initialize and "Lib_UIDropDownMenuTemplate" or "UIDropDownMenuTemplate"
end

local lootUpgradeLevelValues = { -1, 0, 5, 10, 15, 20, 25, 30 }

setmetatable(Config, {
	__index = function(self, key)
		if configDefaults[key] ~= nil then
			return self:Get(key)
		else
			return Addon.ModulePrototype[key]
		end
	end,
	-- __newindex = function(self, key, value)
	-- 	if configDefaults[key] ~= nil then
	-- 		self:Set(key, value)
	-- 	else
	-- 		self[key] = value
	-- 	end
	-- end,
})

function Config:Get(key)
	if self:CharacterConfig() then
		if AngryWorldQuests_CharacterConfig == nil or AngryWorldQuests_CharacterConfig[key] == nil then
			return configDefaults[key]
		else
			return AngryWorldQuests_CharacterConfig[key]
		end
	else
		if AngryWorldQuests_Config == nil or AngryWorldQuests_Config[key] == nil then
			return configDefaults[key]
		else
			return AngryWorldQuests_Config[key]
		end
	end
end

function Config:Set(key, newValue, silent)
	if self:CharacterConfig() then
		if configDefaults[key] == newValue then
			AngryWorldQuests_CharacterConfig[key] = nil
		else
			AngryWorldQuests_CharacterConfig[key] = newValue
		end
	else
		if configDefaults[key] == newValue then
			AngryWorldQuests_Config[key] = nil
		else
			AngryWorldQuests_Config[key] = newValue
		end
	end
	if key == 'selectedFilters' then 
		__filterTable = nil
	end
	if callbacks[key] and not silent then
		for _, func in ipairs(callbacks[key]) do
			func(key, newValue)
		end
	end
end

function Config:RegisterCallback(key, func)
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

function Config:UnregisterCallback(key, func)
	if callbacks[key] then
		local table = callbacks[key]
		for i=1, #table do
			if table[i] == func then
				table.remove(table, 1)
				i = i - 1
			end
		end
		if #table == 0 then callbacks[key] = nil end
	end
end

function Config:FilterKeyToMask(key)
	local index = FiltersConversion[key]
	return 2^(index-1)
end

function Config:HasFilters()
	return self:Get('selectedFilters') > 0
end
function Config:IsOnlyFilter(key)
	local value = self:Get('selectedFilters')
	local mask = self:FilterKeyToMask(key)
	return mask == value
end

function Config:GetFilter(key)
	local value = self:Get('selectedFilters')
	local mask = self:FilterKeyToMask(key)
	return bit.band(value, mask) == mask
end

function Config:GetFilterTable(numFilters)
	if __filterTable == nil then
		local value = self:Get('selectedFilters')
		__filterTable = {}
		for key,i in pairs(FiltersConversion) do
			local mask = 2^(i-1)
			if bit.band(value, mask) == mask then __filterTable[key] = true end
		end
	end
	return __filterTable
end

function Config:GetFilterDisabled(key)
	local value = self:Get('disabledFilters')
	local mask = self:FilterKeyToMask(key)
	return bit.band(value, mask) == mask
end

function Config:SetFilter(key, newValue)
	local value = self:Get('selectedFilters')
	local mask = self:FilterKeyToMask(key)
	if newValue then
		value = bit.bor(value, mask)
	else
		value = bit.band(value, bit.bnot(mask))
	end
	self:Set('selectedFilters', value)
end

function Config:SetNoFilter()
	self:Set('selectedFilters', 0)
end

function Config:SetOnlyFilter(key)
	local mask = self:FilterKeyToMask(key)
	self:Set('selectedFilters', mask)
end

function Config:ToggleFilter(key)
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

function Config:CharacterConfig()
	return AngryWorldQuests_CharacterConfig and AngryWorldQuests_CharacterConfig['__enabled']
end

function Config:SetCharacterConfig(enabled)
	AngryWorldQuests_CharacterConfig['__enabled'] = enabled
	if not AngryWorldQuests_CharacterConfig['__init'] then
		AngryWorldQuests_CharacterConfig['__init'] = true
		for key,value in pairs(AngryWorldQuests_Config) do
			AngryWorldQuests_CharacterConfig[key] = value
		end
	end
end

local panelOriginalConfig = {}
local optionPanel

local Panel_OnRefresh

local function Panel_OnSave(self)
	wipe(panelOriginalConfig)
end

local function Panel_OnCancel(self)
	-- for key, value in pairs(panelOriginalConfig) do
	-- 	if key == "disabledFilters" then AngryWorldQuests_Config["selectedFilters"] = nil end
	-- 	Config:Set(key, value)
	-- end
	wipe(panelOriginalConfig)
end

local function Panel_OnDefaults(self)
	AngryWorldQuests_Config = { __version = configVersion }
	for key,callbacks_key in pairs(callbacks) do
		for _, func in ipairs(callbacks_key) do
			func(key, configDefaults[key])
		end
	end
	wipe(panelOriginalConfig)
end

local function FilterCheckBox_Update(self)
	local value = Config:Get("disabledFilters")
	local mask = self.filterMask
	self:SetChecked( bit.band(value,mask) == 0 )
end

local function FilterCheckBox_OnClick(self)
	local key = "disabledFilters"
	if panelOriginalConfig[key] == nil then
		panelOriginalConfig[key] = Config[key]
	end
	local value = Config:Get("disabledFilters")
	local mask = self.filterMask
	if self:GetChecked() then
		value = bit.band(value, bit.bnot(mask))
	else
		value = bit.bor(value, mask)
	end
	AngryWorldQuests_Config["selectedFilters"] = nil
	Config:Set(key, value)
end

local function CheckBox_Update(self)
	self:SetChecked( Config:Get(self.configKey) )
end

local function CheckBox_OnClick(self)
	local key = self.configKey
	if panelOriginalConfig[key] == nil then
		panelOriginalConfig[key] = Config[key]
	end
	Config:Set(key, self:GetChecked())
end

local function CharConfigCheckBox_OnClick(self)
	local status = Config:CharacterConfig()
	Config:SetCharacterConfig( not status )

	for key,callbacks_key in pairs(callbacks) do
		for _, func in ipairs(callbacks_key) do
			func(key, Config:Get(key))
		end
	end
	Panel_OnRefresh(optionPanel)
end

local function DropDown_OnClick(self, dropdown)
	local key = dropdown.configKey
	if panelOriginalConfig[key] == nil then
		panelOriginalConfig[key] = Config[key]
	end
	Config:Set(key, self.value)
	My_UIDropDownMenu_SetSelectedValue( dropdown, self.value )
end

local function DropDown_Initialize(self)
	local key = self.configKey
	local selectedValue = My_UIDropDownMenu_GetSelectedValue(self)
	local info = My_UIDropDownMenu_CreateInfo()
	info.func = DropDown_OnClick
	info.arg1 = self

	if key == 'timeFilterDuration' then
		for _, hours in ipairs(Addon.QuestFrame.Filters.TIME.values) do
			info.text = string.format(FORMATED_HOURS, hours)
			info.value = hours
			if ( selectedValue == info.value ) then
				info.checked = 1
			else
				info.checked = nil
			end
			My_UIDropDownMenu_AddButton(info)
		end
	elseif key == 'sortMethod' then
		for _, index in ipairs(Addon.QuestFrame.SortOrder) do
			info.text = Addon.Locale['config_sortMethod_'..index]
			info.value = index
			if ( selectedValue == info.value ) then
				info.checked = 1
			else
				info.checked = nil
			end
			My_UIDropDownMenu_AddButton(info)
		end
	elseif key == 'lootUpgradesLevel' then
		for i, ilvl in ipairs(lootUpgradeLevelValues) do
			if Addon.Locale:Exists('config_lootUpgradesLevelValue'..i) then
				info.text = Addon.Locale['config_lootUpgradesLevelValue'..i]
			else
				info.text = format(Addon.Locale['config_lootUpgradesLevelValue'], ilvl)
			end
			info.value = ilvl
			if ( selectedValue == info.value ) then
				info.checked = 1
			else
				info.checked = nil
			end
			My_UIDropDownMenu_AddButton(info)
		end
	end
end

local DropDown_Index = 0
local function DropDown_Create(self)
	DropDown_Index = DropDown_Index + 1
	local dropdown = CreateFrame("Frame", ADDON.."ConfigDropDown"..DropDown_Index, self, My_UIDropDownMenuTemplate)
	
	local label = dropdown:CreateFontString(ADDON.."ConfigDropLabel"..DropDown_Index, "BACKGROUND", "GameFontNormal")
	label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 16, 3)
	dropdown.Label = label
	
	return dropdown
end

local panelInit, checkboxes, dropdowns, filterCheckboxes, charConfigCheckbox
Panel_OnRefresh = function(self)
	if not panelInit then
		local footer = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		footer:SetPoint('BOTTOMRIGHT', -16, 16)
		footer:SetText( Addon.Version or "Dev" )

		charConfigCheckbox = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
		charConfigCheckbox:SetScript("OnClick", CharConfigCheckBox_OnClick)
		charConfigCheckbox.Text:SetFontObject("GameFontHighlightSmall")
		charConfigCheckbox.Text:SetPoint("LEFT", charConfigCheckbox, "RIGHT", 0, 1)
		charConfigCheckbox.Text:SetText( Addon.Locale.config_characterConfig )
		charConfigCheckbox:SetPoint("BOTTOMLEFT", 14, 12)

		local label = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		label:SetPoint("TOPLEFT", 16, -16)
		label:SetJustifyH("LEFT")
		label:SetJustifyV("TOP")
		label:SetText( Addon.Name )

		checkboxes = {}
		dropdowns = {}
		filterCheckboxes = {}

		local checkboxes_order = { "showAtTop", "onlyCurrentZone", "showContinentPOI", "hideFilteredPOI", "hideUntrackedPOI", "showHoveredPOI", "lootFilterUpgrades" }

		for i,key in ipairs(checkboxes_order) do
			checkboxes[i] = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
			checkboxes[i]:SetScript("OnClick", CheckBox_OnClick)
			checkboxes[i].configKey = key
			checkboxes[i].Text:SetText( Addon.Locale['config_'..key] )
			if i == 1 then
				checkboxes[i]:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -2, -8)
			else
				checkboxes[i]:SetPoint("TOPLEFT", checkboxes[i-1], "BOTTOMLEFT", 0, -8)
			end
		end

		local dropdowns_order = { "timeFilterDuration", "sortMethod", "lootUpgradesLevel" }

		for i,key in ipairs(dropdowns_order) do
			dropdowns[i] = DropDown_Create(self)
			dropdowns[i].Label:SetText( Addon.Locale['config_'..key] )
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
		label2:SetText(Addon.Locale['config_enabledFilters'])

		for i,key in ipairs(Addon.QuestFrame.FiltersOrder) do
			local filter = Addon.QuestFrame.Filters[key]
			filterCheckboxes[i] = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
			filterCheckboxes[i]:SetScript("OnClick", FilterCheckBox_OnClick)
			filterCheckboxes[i].filterMask = Config:FilterKeyToMask(key)
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

	charConfigCheckbox:SetChecked( Config:CharacterConfig() )
	
	for _, check in ipairs(checkboxes) do
		CheckBox_Update(check)
	end

	for _, dropdown in ipairs(dropdowns) do
		My_UIDropDownMenu_Initialize(dropdown, DropDown_Initialize)
		My_UIDropDownMenu_SetSelectedValue(dropdown, Config:Get(dropdown.configKey))
	end

	for _, check in ipairs(filterCheckboxes) do
		FilterCheckBox_Update(check)
	end

end

function Config:CreatePanel()
	self:InitializeDropdown()
	local panel = CreateFrame("FRAME")
	panel.name = Addon.Name
	panel.okay = Panel_OnSave
	panel.cancel = Panel_OnCancel
	panel.default  = Panel_OnDefaults
	panel.refresh  = Panel_OnRefresh
	InterfaceOptions_AddCategory(panel)

	return panel
end

function Config:BeforeStartup()
	if AngryWorldQuests_Config == nil then AngryWorldQuests_Config = {} end
	if AngryWorldQuests_CharacterConfig == nil then AngryWorldQuests_CharacterConfig = {} end

	if not AngryWorldQuests_Config['__version'] then
		AngryWorldQuests_Config['__version'] = configVersion
	end
	if not AngryWorldQuests_CharacterConfig['__version'] then
		AngryWorldQuests_CharacterConfig['__version'] = configVersion
	end

	AngryWorldQuests_Config['__version'] = configVersion
	AngryWorldQuests_CharacterConfig['__version'] = configVersion

	if not self:Get('saveFilters') then
		AngryWorldQuests_Config.selectedFilters = nil
		AngryWorldQuests_Config.filterEmissary = nil
		AngryWorldQuests_Config.filterLoot = nil
		AngryWorldQuests_Config.filterFaction = nil
		AngryWorldQuests_Config.filterZone = nil
		AngryWorldQuests_Config.filterTime = nil
		AngryWorldQuests_CharacterConfig.selectedFilters = nil
		AngryWorldQuests_CharacterConfig.filterEmissary = nil
		AngryWorldQuests_CharacterConfig.filterLoot = nil
		AngryWorldQuests_CharacterConfig.filterFaction = nil
		AngryWorldQuests_CharacterConfig.filterZone = nil
		AngryWorldQuests_CharacterConfig.filterTime = nil
	end

end

function Config:Startup()
	local lastFilter = AngryWorldQuests_Config['__filters']
	local lastFilter2 = AngryWorldQuests_CharacterConfig['__filters']
	local value = AngryWorldQuests_Config['disabledFilters'] or 0
	local value2 = AngryWorldQuests_CharacterConfig['disabledFilters'] or 0
	local maxFilter = 0
	for key,index in pairs(FiltersConversion) do
		if Addon.QuestFrame.Filters[key] then
			local mask = 2^(index-1)
			if not lastFilter or index > lastFilter then
				if Addon.QuestFrame.Filters[key].default then
					value = bit.band(value, bit.bnot(mask))
				else
					value = bit.bor(value, mask)
				end
			end
			if not lastFilter2 or index > lastFilter2 then
				if Addon.QuestFrame.Filters[key].default  then
					value2 = bit.band(value2, bit.bnot(mask))
				else
					value2 = bit.bor(value2, mask)
				end
			end
			if index > maxFilter then maxFilter = index end
		end
	end
	AngryWorldQuests_Config['disabledFilters'] = value
	AngryWorldQuests_Config['__filters'] = maxFilter
	AngryWorldQuests_CharacterConfig['disabledFilters'] = value2
	AngryWorldQuests_CharacterConfig['__filters'] = maxFilter

	optionPanel = self:CreatePanel(ADDON)
end

SLASH_ANGRYWORLDQUESTS1 = "/awq"
SLASH_ANGRYWORLDQUESTS2 = "/angryworldquests"
function SlashCmdList.ANGRYWORLDQUESTS(msg, editbox)
	if optionPanel then
		InterfaceOptionsFrame_OpenToCategory(optionPanel)
		InterfaceOptionsFrame_OpenToCategory(optionPanel)
	end
end
