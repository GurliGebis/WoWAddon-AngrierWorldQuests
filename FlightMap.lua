local ADDON, Addon = ...
local Mod = Addon:NewModule('FlightMap')

local function OnShow(self)
	self.ticker:Cancel()
	self.ticker = C_Timer.NewTicker(1, function() self:RefreshAllData() end)
	self:RefreshAllData()
end

function Mod:Blizzard_SharedMapDataProviders()
	hooksecurefunc(WorldQuestDataProviderMixin, "OnShow", OnShow)
end

function Mod:Startup()
	self:RegisterAddOnLoaded("Blizzard_SharedMapDataProviders")
end
