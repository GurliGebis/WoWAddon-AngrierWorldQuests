--[[
    Copyright (C) 2024-2026 GurliGebis

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    1: Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.

    2: Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.

    3: Neither the name of the copyright holder nor the names of its contributors
       may be used to endorse or promote products derived from this software
       without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
    IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
    USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
    NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
    ADVISED OF THE POSSIBILITY OF SUCH DAMAGE
]]

local addonName, _ = ...
local AngrierWorldQuests = LibStub("AceAddon-3.0"):GetAddon(addonName)
local QuestFrameModule = AngrierWorldQuests:GetModule("QuestFrameModule")

local MONEY_FORMAT = "%1$s |T%2$s:16:16:0:0:64:64:5:59:5:59|t %3$s |T%4$s:16:16:0:0:64:64:5:59:5:59|t %5$s |T%6$s:16:16:0:0:64:64:5:59:5:59|t"

--region Helpers

local function WrapTextWithColor(color, text)
    if not color or text == nil then
        return text
    end

    local r = math.floor((color.r or 1) * 255 + 0.5)
    local g = math.floor((color.g or 1) * 255 + 0.5)
    local b = math.floor((color.b or 1) * 255 + 0.5)

    return string.format("|cff%02x%02x%02x%s|r", r, g, b, text)
end

local function AddLine(text, color)
    local c = color or NORMAL_FONT_COLOR
    AWQTooltip:AddLine(text or "", c.r, c.g, c.b, true)
end

--endregion

--region Tooltip Show/Hide

function QuestFrameModule.Tooltip_Show(anchor, itemLink)
    AWQTooltip:ClearAllPoints()
    AWQTooltip:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 0)
    AWQTooltip:Show()

    if itemLink then
        AWQItemTooltip:SetOwner(AWQTooltip, "ANCHOR_NONE")
        AWQItemTooltip:ClearAllPoints()
        AWQItemTooltip:SetPoint("TOPLEFT", AWQTooltip, "BOTTOMLEFT", 0, -4)
        AWQItemTooltip:SetHyperlink(itemLink)
        AWQItemTooltip:Show()
    else
        AWQItemTooltip:Hide()
    end
end

function QuestFrameModule.Tooltip_ShowSimple(anchor, text, color)
    AWQTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    AWQTooltip:ClearLines()
    AddLine(text, color)
    QuestFrameModule.Tooltip_Show(anchor)
end

function QuestFrameModule:Tooltip_Hide()
    AWQTooltip:Hide()
    AWQItemTooltip:Hide()
end

--endregion

--region Tooltip Content

function QuestFrameModule.Tooltip_AddRewards(questID)
    local rewardItemLink = nil

    local baseXp = GetQuestLogRewardXP(questID)
    if baseXp and baseXp > 0 then
        AddLine(BONUS_OBJECTIVE_EXPERIENCE_FORMAT:format(baseXp), HIGHLIGHT_FONT_COLOR)
    end

    local artifactXP = GetQuestLogRewardArtifactXP(questID)
    if artifactXP and artifactXP > 0 then
        AddLine(BONUS_OBJECTIVE_ARTIFACT_XP_FORMAT:format(artifactXP), HIGHLIGHT_FONT_COLOR)
    end

    local money = GetQuestLogRewardMoney(questID)
    if money and money > 0 then
        local gold = floor(money / (_AngrierWorldQuests.Constants.MONEY.COPPER_PER_SILVER * _AngrierWorldQuests.Constants.MONEY.SILVER_PER_GOLD))
        local silver = floor((money - (gold * _AngrierWorldQuests.Constants.MONEY.COPPER_PER_SILVER * _AngrierWorldQuests.Constants.MONEY.SILVER_PER_GOLD)) / _AngrierWorldQuests.Constants.MONEY.COPPER_PER_SILVER)
        local copper = mod(money, _AngrierWorldQuests.Constants.MONEY.COPPER_PER_SILVER)

        if gold > 0 or silver > 0 or copper > 0 then
            AddLine(MONEY_FORMAT:format(
                BreakUpLargeNumbers(gold), "Interface\\MoneyFrame\\UI-GoldIcon",
                silver, "Interface\\MoneyFrame\\UI-SilverIcon",
                copper, "Interface\\MoneyFrame\\UI-CopperIcon"
            ))
        end
    end

    local currencies = C_QuestLog.GetQuestRewardCurrencies(questID)
    if currencies then
        for _, currencyInfo in ipairs(currencies) do
            if currencyInfo and currencyInfo.texture and currencyInfo.totalRewardAmount and currencyInfo.name then
                AddLine(BONUS_OBJECTIVE_REWARD_WITH_COUNT_FORMAT:format(currencyInfo.texture, currencyInfo.totalRewardAmount, currencyInfo.name), HIGHLIGHT_FONT_COLOR)
            end
        end
    end

    local numQuestRewards = GetNumQuestLogRewards(questID)
    if numQuestRewards and numQuestRewards > 0 then
        local itemName, itemTexture, quantity, quality = GetQuestLogRewardInfo(1, questID)
        if itemName and itemTexture then
            rewardItemLink = GetQuestLogItemLink("reward", 1, questID)

            local text
            if quantity and quantity > 1 then
                text = BONUS_OBJECTIVE_REWARD_WITH_COUNT_FORMAT:format(itemTexture, quantity, itemName)
            else
                text = BONUS_OBJECTIVE_REWARD_FORMAT:format(itemTexture, itemName)
            end

            local colorData = quality and ColorManager.GetColorDataForItemQuality(quality) or nil
            local color = (colorData and colorData.color) or HIGHLIGHT_FONT_COLOR
            AddLine(text, color)
        end
    end

    if C_QuestLog.QuestContainsFirstTimeRepBonusForPlayer(questID) then
        AddLine(" ")
        AddLine(QUEST_REWARDS_CONTAINS_ONE_TIME_REP_BONUS, QUEST_REWARD_CONTEXT_FONT_COLOR)
    end

    return rewardItemLink
end

function QuestFrameModule.Tooltip_BuildSafe(self)
    local questID = self.questID
    if not questID then
        return
    end

    AWQTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    AWQTooltip:ClearLines()

    local title = self.Text and self.Text:GetText() or C_TaskQuest.GetQuestInfoByQuestID(questID) or ""
    local tagInfo = QuestFrameModule.GetCachedQuestTagInfo(questID)
    local titleColor = HIGHLIGHT_FONT_COLOR
    if tagInfo and tagInfo.quality then
        local colorData = ColorManager.GetColorDataForWorldQuestQuality(tagInfo.quality)
        if colorData then
            titleColor = colorData.color
        end
    end
    AddLine(title, titleColor)

    if C_QuestLog.IsAccountQuest(questID) then
        AddLine(ACCOUNT_QUEST_LABEL, ACCOUNT_WIDE_FONT_COLOR)
    end

    local questTypeText = QuestUtils_GetQuestTypeIconMarkupString(questID, 20, 20)
    if questTypeText then
        AddLine(questTypeText)
    end

    local factionID = self.factionID or select(2, C_TaskQuest.GetQuestInfoByQuestID(questID))
    if factionID then
        local factionData = C_Reputation.GetFactionDataByID(factionID)
        if factionData and factionData.name then
            AddLine(factionData.name)
        end
    end

    local formattedTime, timeColor = WorldMap_GetQuestTimeForTooltip(questID)
    if formattedTime and timeColor then
        AddLine(MAP_TOOLTIP_TIME_LEFT:format(WrapTextWithColor(timeColor, formattedTime)))
    end

    local isThreat = C_QuestLog.IsThreatQuest(questID)
    local numObjectives = self.numbObjectives or C_QuestLog.GetNumQuestObjectives(questID)
    for objectiveIndex = 1, numObjectives do
        local objectiveText, _, finished = GetQuestObjectiveInfo(questID, objectiveIndex, false)
        if not (finished and isThreat) then
            if objectiveText and #objectiveText > 0 then
                AddLine(QUEST_DASH .. objectiveText, finished and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
            end
        end
    end

    AddLine(" ")
    AddLine(QUEST_REWARDS)

    local rewardItemLink = QuestFrameModule.Tooltip_AddRewards(questID)
    QuestFrameModule.Tooltip_Show(self, rewardItemLink)
end

--endregion