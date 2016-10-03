local ADDON, Addon = ...
local Mod = Addon:NewModule('FlightMap')

local setup = {}

local function RefreshAllData(self)
	for pin, active in self:GetMap():EnumeratePinsByTemplate("WorldQuestPinTemplate") do
		if (Addon.Config.flightMapTracked and (IsWorldQuestHardWatched(pin.questID) or GetSuperTrackedQuestID() == pin.questID)) or Addon.Config.flightMapAll then
			pin:SetAlphaLimits(2.0, 1.0, 1.0)
			pin:SetScalingLimits(1, 1.5, 0.50)
		else
			pin:SetAlphaLimits(2.0, 0.0, 1.0)
			pin:SetScalingLimits(1, 1.0, 0.50)
		end
	end
end

local function WorldQuestDataProvider_Override()
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
