local ADDON, Addon = ...
local Mod = Addon:NewModule('FlightMap')

local function RefreshAllData(self)
	for pin, active in self:GetMap():EnumeratePinsByTemplate("WorldQuestPinTemplate") do
		if IsWorldQuestWatched(pin.questID) or (IsWorldQuestHardWatched(pin.questID) or GetSuperTrackedQuestID() == pin.questID) then
			pin:SetAlphaLimits(2.0, 1.0, 1.0)
		else
			pin:SetAlphaLimits(2.0, 0.0, 1.0)
		end
		pin:ApplyCurrentAlpha()
	end
end

local function OnShow(self)
	self.ticker:Cancel()
	self.ticker = C_Timer.NewTicker(1, function() self:RefreshAllData() end)
end

local function WorldQuestDataProvider_Override()
	hooksecurefunc(WorldQuestDataProviderMixin, "OnShow", OnShow)
	hooksecurefunc(WorldQuestDataProviderMixin, "RefreshAllData", RefreshAllData)
end

function Mod:ADDON_LOADED(name)
	if name == 'Blizzard_SharedMapDataProviders' then
		WorldQuestDataProvider_Override()
	end
end

function Mod:Startup()
	if IsAddOnLoaded('Blizzard_SharedMapDataProviders') then
		WorldQuestDataProvider_Override()
	else
		self:RegisterEvent('ADDON_LOADED')
	end
end
