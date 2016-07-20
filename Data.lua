local ADDON, Addon = ...
local Data = Addon:NewModule('Data')

local KNOWLEDGE_CURRENCY_ID = 1171
local fakeTooltip
local cachedKnowledgeLevel
local cachedPower = {}
local cachedItems = {}

-- function Data:ItemArtifactPower(itemID)
-- 	local artifactPower = ItemIDs_ArtifactPower[itemID]
-- 	if artifactPower then
-- 		local name, currentAmount, texture, earnedThisWeek, weeklyMax, totalMax, isDiscovered, rarity = GetCurrencyInfo(KNOWLEDGE_CURRENCY_ID)
-- 		if currentAmount and KNOWLEDGE_MODIFIER[currentAmount] then
-- 			artifactPower = floor(artifactPower * (1 + KNOWLEDGE_MODIFIER[currentAmount]) / 5 + 0.5) * 5
-- 		end
-- 		return artifactPower
-- 	end
-- end
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

function Data:QUEST_LOG_UPDATE(...)
	wipe(cachedItems)
end

function Data:Startup()
	fakeTooltip = CreateFrame('GameTooltip', 'ABQFakeTooltip', UIParent, 'GameTooltipTemplate')
	fakeTooltip:Hide()

	self:RegisterEvent('QUEST_LOG_UPDATE')
end