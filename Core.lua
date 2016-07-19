local ADDON, Addon = ...
local Listener = CreateFrame('Frame', ADDON .. 'Listener')
Listener:SetScript('OnEvent', function(_, event) Addon[event](Addon) end)
Listener:RegisterEvent('PLAYER_ENTERING_WORLD')

Addon.Modules = {}
function Addon:NewModule(name)
	local object = {}
	self.Modules[name] = object
	return object
end

function Addon:ForAllModules(event, ...)
	for name, module in pairs(Addon.Modules) do
		if type(module) == 'table' and module[event] then
			module[event](module, ...)
		end
	end
end

function Addon:PLAYER_ENTERING_WORLD()
	self:ForAllModules('Startup')

	Listener:UnregisterEvent('PLAYER_ENTERING_WORLD')
end

_G[ADDON] = Addon
