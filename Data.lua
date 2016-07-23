local ADDON, Addon = ...
local Data = Addon:NewModule('Data')

local KNOWLEDGE_CURRENCY_ID = 1171
local fakeTooltip
local cachedKnowledgeLevel
local cachedPower = {}
local cachedItems = {}

local invtype_locations = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_SHIELD = { 17 },
	INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_HOLDABLE = { 17 },
}

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

function Data:RewardIsUpgrade(questID)
	local _, _, _, _, _, itemID = GetQuestLogRewardInfo(1, questID)
	local itemEquipSlot = select(9, GetItemInfo(itemID))

	local ilvl = self:RewardItemLevel(questID)

	if itemEquipSlot and invtype_locations[itemEquipSlot] then
		local isUpgrade = false

		for _, slotID in ipairs(invtype_locations[itemEquipSlot]) do
			local currentItem = GetInventoryItemLink("player", slotID)
			local currentIlvl = select(4, GetItemInfo(currentItem))
			if ilvl > currentIlvl then
				isUpgrade = true
			end
		end

		return isUpgrade
	else
		return true
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