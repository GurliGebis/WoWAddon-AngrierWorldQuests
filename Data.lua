local ADDON, Addon = ...
local Data = Addon:NewModule('Data')

local KNOWLEDGE_CURRENCY_ID = 1171
local fakeTooltip
local cachedKnowledgeLevel
local cachedPower = {}
local cachedItems = {}

function Data:ItemArtifactPower(itemID)
	local currentKnowledge = select(2, GetCurrencyInfo(KNOWLEDGE_CURRENCY_ID))
	if cachedKnowledgeLevel ~= currentKnowledge then
		wipe(cachedPower)
		cachedKnowledgeLevel = currentKnowledge
	end

	if cachedPower[itemID] ~= nil then
		return cachedPower[itemID]
	end

	fakeTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	fakeTooltip:SetItemByID(itemID)
	local text = ABQFakeTooltipTextLeft2:GetText()
	if (text:match ("|cFFE6CC80")) then
		local power = ABQFakeTooltipTextLeft4:GetText():gsub("%p", ""):match("%d+")
		power = tonumber(power)

		cachedPower[itemID] = power

		fakeTooltip:Hide()
		return power
	else
		cachedPower[itemID] = false

		fakeTooltip:Hide()
		return false
	end
end

function Data:RewardItemLevel(questID)
	if cachedItems[questID] == nil then
		fakeTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		fakeTooltip:SetQuestLogItem("reward", 1, questID)
		local matcher = string.gsub(ITEM_LEVEL_PLUS, "%%d%+", "(%%d+)+")
		local itemLevel
		itemLevel = tonumber(ABQFakeTooltipTextLeft2:GetText():match(matcher))
		if not itemLevel then itemLevel = tonumber(ABQFakeTooltipTextLeft3:GetText():match(matcher)) end
		fakeTooltip:Hide()
		cachedItems[questID] = itemLevel or false
	end
	return cachedItems[questID]
end

function Data:UNIT_QUEST_LOG_CHANGED(arg1)
	if arg1 == "player" then
		wipe(cachedItems)
	end
end

function Data:Startup()
	fakeTooltip = CreateFrame('GameTooltip', 'ABQFakeTooltip', UIParent, 'GameTooltipTemplate')
	fakeTooltip:Hide()

	self:RegisterEvent('UNIT_QUEST_LOG_CHANGED')
end