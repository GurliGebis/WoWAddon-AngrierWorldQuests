local ADDON, Addon = ...
local Config = Addon:NewModule('Config')

local configVersion = 1
local configDefaults = {
	collapsed = false,
	showAtTop = true,
	showContinentPOI = false,
	onlyCurrentZone = true,
	selectedFilters = 0,
	timeFilterDuration = 6,
	hidePOI = false,
	hideFilteredPOI = false,
}
local callbacks = {}

local timeFilterDurationValues = { 1, 3, 6, 12, 24 }

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
	if AngryWorldQuests_Config == nil or AngryWorldQuests_Config[key] == nil then
		return configDefaults[key]
	else
		return AngryWorldQuests_Config[key]
	end
end

function Config:Set(key, newValue)
	if configDefaults[key] == newValue then
		AngryWorldQuests_Config[key] = nil
	else
		AngryWorldQuests_Config[key] = newValue
	end
	if callbacks[key] then
		for _, func in ipairs(callbacks[key]) do
			func(key, newValue)
		end
	end
end

function Config:RegisterCallback(key, func)
	if callbacks[key] then
		table.insert(callbacks, func)
	else
		callbacks[key] = { func }
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

function Config:HasFilters()
	return self:Get('selectedFilters') > 0
end
function Config:IsOnlyFilter(index)
	local value = self:Get('selectedFilters')
	local mask = 2^(index-1)
	return mask == value
end

function Config:GetFilter(index)
	local value = self:Get('selectedFilters')
	local mask = 2^(index-1)
	return bit.band(value, mask) == mask
end

function Config:GetFilterTable(numFilters)
	local value = self:Get('selectedFilters')
	local ret = {}
	for i=1, numFilters do
		local mask = 2^(i-1)
		ret[i] = bit.band(value, mask) == mask
	end
	return ret
end

function Config:SetFilter(index, newValue)
	local value = self:Get('selectedFilters')
	local mask = 2^(index-1)
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

function Config:SetOnlyFilter(index)
	local mask = 2^(index-1)
	self:Set('selectedFilters', mask)
end

function Config:ToggleFilter(index)
	local value = self:Get('selectedFilters')
	local mask = 2^(index-1)
	local currentValue = bit.band(value, mask) == mask
	if not currentValue then
		value = bit.bor(value, mask)
	else
		value = bit.band(value, bit.bnot(mask))
	end
	self:Set('selectedFilters', value)
	return not currentValue
end

local panelOriginalConfig = {}
local optionPanel

local function Panel_OnSave(self)
	wipe(panelOriginalConfig)
end

local function Panel_OnCancel(self)
	for key, value in pairs(panelOriginalConfig) do
		Config:Set(key, value)
	end
	wipe(panelOriginalConfig)
end

local function Panel_OnDefaults(self)
	Config:Set('onlyCurrentZone', configDefaults['onlyCurrentZone'])
	Config:Set('showAtTop', configDefaults['showAtTop'])
	Config:Set('hidePOI', configDefaults['hidePOI'])
	Config:Set('showContinentPOI', configDefaults['showContinentPOI'])
	Config:Set('hideFilteredPOI', configDefaults['hideFilteredPOI'])
	Config:Set('timeFilterDuration', configDefaults['timeFilterDuration'])
	wipe(panelOriginalConfig)
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

local function CheckBox_Create(self)
	local check = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
	check:SetScript("OnClick", CheckBox_OnClick)
	return check
end

local function DropDown_OnClick(self)
	local dropdown = self:GetParent().dropdown
	local key = dropdown.configKeym
	if panelOriginalConfig[key] == nil then
		panelOriginalConfig[key] = Config[key]
	end
	Config:Set(key, self.value)
	UIDropDownMenu_SetSelectedValue( dropdown, self.value )
end

local function DropDown_Initialize(self)
	local key = self.configKey
	local selectedValue = UIDropDownMenu_GetSelectedValue(self)
	local info = UIDropDownMenu_CreateInfo()
	info.func = DropDown_OnClick
	info.dropdown = self

	if key == 'timeFilterDuration' then
		for _, hours in ipairs(timeFilterDurationValues) do
			info.text = string.format(FORMATED_HOURS, hours)
			info.value = hours
			if ( selectedValue == info.value ) then
				info.checked = 1
			else
				info.checked = nil
			end
			UIDropDownMenu_AddButton(info)
		end
	end
end

local DropDown_Index = 0
local function DropDown_Create(self)
	DropDown_Index = DropDown_Index + 1
	local dropdown = CreateFrame("Frame", ADDON.."ConfigDropDown"..DropDown_Index, self, "UIDropDownMenuTemplate")
	
	local text = dropdown:CreateFontString(ADDON.."ConfigDropLabel"..DropDown_Index, "BACKGROUND", "GameFontNormal")
	text:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 16, 3)
	dropdown.Text = text
	
	return dropdown
end

local panelInit, check_showAtTop, check_onlyCurrentZone, check_hideFilteredPOI, check_hidePOI, check_showContinentPOI, drop_timeFilterDuration
local function Panel_OnRefresh(self)
	if not panelInit then
		local label = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		label:SetPoint("TOPLEFT", 16, -16)
		label:SetJustifyH("LEFT")
		label:SetJustifyV("TOP")
		label:SetText( Addon.Name )

		check_showAtTop = CheckBox_Create(self)
		check_showAtTop.configKey = "showAtTop"
		check_showAtTop.Text:SetText("Display at the top of the Quest Log")
		check_showAtTop:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -2, -8)

		check_onlyCurrentZone = CheckBox_Create(self)
		check_onlyCurrentZone.configKey = "onlyCurrentZone"
		check_onlyCurrentZone.Text:SetText("Only show World Quests for the current zone")
		check_onlyCurrentZone:SetPoint("TOPLEFT", check_showAtTop, "BOTTOMLEFT", 0, -8)

		check_hideFilteredPOI = CheckBox_Create(self)
		check_hideFilteredPOI.configKey = "hideFilteredPOI"
		check_hideFilteredPOI.Text:SetText("Hide filtered World Quest POI icons on the world map")
		check_hideFilteredPOI:SetPoint("TOPLEFT", check_onlyCurrentZone, "BOTTOMLEFT", 0, -8)

		check_hidePOI = CheckBox_Create(self)
		check_hidePOI.configKey = "hidePOI"
		check_hidePOI.Text:SetText("Hide untracked World Quest POI icons on the world map")
		check_hidePOI:SetPoint("TOPLEFT", check_hideFilteredPOI, "BOTTOMLEFT", 0, -8)

		check_showContinentPOI = CheckBox_Create(self)
		check_showContinentPOI.configKey = "showContinentPOI"
		check_showContinentPOI.Text:SetText("Show hovered World Quest POI icon on the Broken Isles continent map")
		check_showContinentPOI:SetPoint("TOPLEFT", check_hidePOI, "BOTTOMLEFT", 0, -8)

		drop_timeFilterDuration = DropDown_Create(self)
		drop_timeFilterDuration.Text:SetText("Time Remaining Filter Duration")
		drop_timeFilterDuration.configKey = "timeFilterDuration"
		drop_timeFilterDuration:SetPoint("TOPLEFT", check_showContinentPOI, "BOTTOMLEFT", -13, -24)

		panelInit = true
	end
	
	CheckBox_Update(check_showAtTop)
	CheckBox_Update(check_onlyCurrentZone)
	CheckBox_Update(check_hidePOI)
	CheckBox_Update(check_hideFilteredPOI)
	CheckBox_Update(check_showContinentPOI)

	UIDropDownMenu_Initialize(drop_timeFilterDuration, DropDown_Initialize)
	UIDropDownMenu_SetSelectedValue(drop_timeFilterDuration, Config:Get('timeFilterDuration'))

end

function Config:CreatePanel()
	local panel = CreateFrame("FRAME")
	panel.name = Addon.Name
	panel.okay = Panel_OnSave
	panel.cancel = Panel_OnCancel
	panel.default  = Panel_OnDefaults
	panel.refresh  = Panel_OnRefresh
	InterfaceOptions_AddCategory(panel)

	return panel
end

function Config:Startup()
	if AngryWorldQuests_Config == nil then AngryWorldQuests_Config = {} end
	if not AngryWorldQuests_Config['__version'] then
		AngryWorldQuests_Config['__version'] = configVersion
	end

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
