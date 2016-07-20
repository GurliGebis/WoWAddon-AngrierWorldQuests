local ADDON, Addon = ...

local Listener = CreateFrame('Frame', ADDON .. 'Listener')
local EventListeners = {}
local function Addon_OnEvent(frame, event, ...)
	if EventListeners[event] then
		for _, callback in ipairs(EventListeners[event]) do
			callback[event](callback, ...)
		end
	end
end
Listener:SetScript('OnEvent', Addon_OnEvent)
function Addon:RegisterEvent(event, callback)
	if EventListeners[event] == nil then
		Listener:RegisterEvent(event)
		EventListeners[event] = { callback }
	else
		table.insert(EventListeners[event], callback)
	end
end

local ModulePrototype = {}
function ModulePrototype:RegisterEvent(event)
	Addon:RegisterEvent(event, self)
end

Addon.Modules = {}
function Addon:NewModule(name)
	local object = {}
	self.Modules[name] = object
	setmetatable(object, {__index=ModulePrototype})
	return object
end
setmetatable(Addon, {
	__index = function(self, key)
		if self.Modules[key] then
			return self.Modules[key]
		end
	end
})

function Addon:ForAllModules(event, ...)
	for name, module in pairs(Addon.Modules) do
		if type(module) == 'table' and module[event] then
			module[event](module, ...)
		end
	end
end

Addon:RegisterEvent('PLAYER_ENTERING_WORLD', Addon)
function Addon:PLAYER_ENTERING_WORLD()
	self:ForAllModules('Startup')

	Listener:UnregisterEvent('PLAYER_ENTERING_WORLD')
end

_G[ADDON] = Addon
