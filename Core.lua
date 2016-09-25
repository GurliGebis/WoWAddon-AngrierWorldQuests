-- Core v1.1
local ADDON, Addon = ...

local Listener = CreateFrame('Frame', ADDON .. 'Listener')
local EventListeners = {}
local function Addon_OnEvent(frame, event, ...)
	if EventListeners[event] then
		for callback, func in pairs(EventListeners[event]) do
			if func == 0 then
				callback[event](callback, ...)
			else
				callback[func](callback, event, ...)
			end
		end
	end
end
Listener:SetScript('OnEvent', Addon_OnEvent)
function Addon:RegisterEvent(event, callback, func)
	if func == nil then func = 0 end
	if EventListeners[event] == nil then
		Listener:RegisterEvent(event)
		EventListeners[event] = { [callback]=func }
	else
		EventListeners[event][callback] = func
	end
end
function Addon:UnregisterEvent(event, callback)
	local listeners = EventListeners[event]
	if listeners then
		local count = 0
		for index,_ in pairs(listeners) do
			if index == callback then
				listeners[index] = nil
			else
				count = count + 1
			end
		end
		if count == 0 then
			EventListeners[event] = nil
			Listener:UnregisterEvent(event)
		end
	end
end

local ModulePrototype = {}
function ModulePrototype:RegisterEvent(event, func)
	Addon:RegisterEvent(event, self, func)
end
function ModulePrototype:UnregisterEvent(event)
	Addon:UnregisterEvent(event, self)
end
Addon.ModulePrototype = ModulePrototype

Addon.Modules = {}
function Addon:NewModule(name)
	local object = {}
	self.Modules[name] = object
	table.insert(self.Modules, object)
	setmetatable(object, {__index=ModulePrototype})
	return object
end
setmetatable(Addon, {__index = Addon.Modules})

function Addon:ForAllModules(event, ...)
	for _, module in ipairs(Addon.Modules) do
		if type(module) == 'table' and module[event] then
			module[event](module, ...)
		end
	end
end

Addon:RegisterEvent('PLAYER_ENTERING_WORLD', Addon)
function Addon:PLAYER_ENTERING_WORLD()
	self:ForAllModules('Startup')

	self:UnregisterEvent('PLAYER_ENTERING_WORLD', self)
end

Addon.Name = GetAddOnMetadata(ADDON, "Title")
Addon.Version = GetAddOnMetadata(ADDON, "X-Curse-Packaged-Version")
_G[ADDON] = Addon
