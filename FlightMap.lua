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
	self:RefreshAllData()
end

function Mod:Blizzard_SharedMapDataProviders()
	hooksecurefunc(WorldQuestDataProviderMixin, "OnShow", OnShow)
	hooksecurefunc(WorldQuestDataProviderMixin, "RefreshAllData", RefreshAllData)
end

function Mod:Startup()
	self:RegisterAddOnLoaded("Blizzard_SharedMapDataProviders")
end
