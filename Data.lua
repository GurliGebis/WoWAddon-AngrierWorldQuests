local ADDON, Addon = ...
local Data = Addon:NewModule('Data')

local KNOWLEDGE_CURRENCY_ID = 1171
local fakeTooltip
local cachedKnowledgeLevel
local cachedPower = {}
local cachedItems = {}

local invtype_locations = {
	INVTYPE_HEAD = { INVSLOT_HEAD },
	INVTYPE_NECK = { INVSLOT_NECK },
	INVTYPE_SHOULDER = { INVSLOT_SHOULDER },
	INVTYPE_BODY = { INVSLOT_BODY },
	INVTYPE_CHEST = { INVSLOT_CHEST },
	INVTYPE_ROBE = { INVSLOT_CHEST },
	INVTYPE_WAIST = { INVSLOT_WAIST },
	INVTYPE_LEGS = { INVSLOT_LEGS },
	INVTYPE_FEET = { INVSLOT_FEET },
	INVTYPE_WRIST = { INVSLOT_WRIST },
	INVTYPE_HAND = { INVSLOT_HAND },
	INVTYPE_FINGER = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
	INVTYPE_TRINKET = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 },
	INVTYPE_CLOAK = { INVSLOT_BACK },
	INVTYPE_WEAPON = { INVSLOT_MAINHAND, INVSLOT_OFFHAND },
	INVTYPE_SHIELD = { INVSLOT_OFFHAND },
	INVTYPE_2HWEAPON = { INVSLOT_MAINHAND },
	INVTYPE_WEAPONMAINHAND = { INVSLOT_MAINHAND },
	INVTYPE_WEAPONOFFHAND = { INVSLOT_OFFHAND },
	INVTYPE_HOLDABLE = { INVSLOT_OFFHAND },
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

	local textLine2 = AWQFakeTooltipTextLeft2 and AWQFakeTooltipTextLeft2:IsShown() and AWQFakeTooltipTextLeft2:GetText()
	local textLine4 = AWQFakeTooltipTextLeft4 and AWQFakeTooltipTextLeft4:IsShown() and AWQFakeTooltipTextLeft4:GetText()

	if textLine2 and textLine4 and(textLine2:match ("|cFFE6CC80")) then
		local power = textLine4:gsub("%p", ""):match("%d+")
		power = tonumber(power)

		cachedPower[itemID] = power
		return power
	else
		cachedPower[itemID] = false
		return false
	end
end

function Data:RewardIsUpgrade(questID)
	local _, _, _, _, _, itemID = GetQuestLogRewardInfo(1, questID)
	local _, _, _, _, _, _, _, _, equipSlot, _, _ = GetItemInfo(itemID)
	local ilvl = self:RewardItemLevel(questID)

	if equipSlot and invtype_locations[equipSlot] then
		local isUpgrade = false

		for _, slotID in ipairs(invtype_locations[equipSlot]) do
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

		local textLine2 = AWQFakeTooltipTextLeft2 and AWQFakeTooltipTextLeft2:IsShown() and AWQFakeTooltipTextLeft2:GetText()
		local textLine3 = AWQFakeTooltipTextLeft3 and AWQFakeTooltipTextLeft3:IsShown() and AWQFakeTooltipTextLeft3:GetText()
		local matcher = string.gsub(ITEM_LEVEL_PLUS, "%%d%+", "(%%d+)+")
		local itemLevel

		if textLine2 then
			itemLevel = tonumber(textLine2:match(matcher))
		end
		if textLine3 and not itemLevel then
			itemLevel = tonumber(textLine3:match(matcher))
		end
		
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
	fakeTooltip = CreateFrame('GameTooltip', 'AWQFakeTooltip', UIParent, 'GameTooltipTemplate')
	fakeTooltip:Hide()

	self:RegisterEvent('UNIT_QUEST_LOG_CHANGED')
end