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

do
    local awqTooltip
    local awqHeaderFont

    local function WrapTextWithColor(color, text)
        if not color or text == nil then
            return text
        end

        local r = math.floor((color.r or 1) * 255 + 0.5)
        local g = math.floor((color.g or 1) * 255 + 0.5)
        local b = math.floor((color.b or 1) * 255 + 0.5)

        return string.format("|cff%02x%02x%02x%s|r", r, g, b, text)
    end

    function QuestFrameModule.Tooltip_Show(anchor, lines)
        if InCombatLockdown() then
            return
        end

        if not awqHeaderFont then
            local fontFile, fontSize, fontFlags = GameFontNormal:GetFont()
            awqHeaderFont = CreateFont("AWQHeaderFont")
            awqHeaderFont:SetFont(fontFile, fontSize + 2, fontFlags)
        end

        if not awqTooltip then
            awqTooltip = CreateFrame("Frame", "AWQTooltip", UIParent, "BackdropTemplate")
            awqTooltip:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 }
            })
            awqTooltip:SetBackdropColor(0, 0, 0, 0.9)
            awqTooltip:SetFrameStrata("TOOLTIP")
            awqTooltip.lines = {}
        end

        for i, line in ipairs(lines) do
            local fs = awqTooltip.lines[i]
            if not fs then
                fs = awqTooltip:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                awqTooltip.lines[i] = fs
            end
            if line.fontObject then
                fs:SetFontObject(line.fontObject)
            elseif i == 1 then
                fs:SetFontObject(awqHeaderFont)
            else
                fs:SetFontObject(GameFontNormal)
            end
            fs:SetText(line.text or "")
            local color = line.color or NORMAL_FONT_COLOR
            fs:SetTextColor(color.r, color.g, color.b)
            fs:Show()
            if i == 1 then
                fs:SetPoint("TOPLEFT", awqTooltip, "TOPLEFT", 8, -8)
            else
                fs:SetPoint("TOPLEFT", awqTooltip.lines[i - 1], "BOTTOMLEFT", 0, -2)
            end
        end

        for i = #lines + 1, #awqTooltip.lines do
            awqTooltip.lines[i]:Hide()
        end

        local maxWidth = 0
        local totalHeight = 0
        for i = 1, #lines do
            local fs = awqTooltip.lines[i]
            local w = fs:GetStringWidth()
            if w > maxWidth then
                maxWidth = w
            end
            totalHeight = totalHeight + fs:GetStringHeight() + 2
        end

        awqTooltip:SetWidth(math.max(140, maxWidth + 16))
        awqTooltip:SetHeight(totalHeight + 16)
        awqTooltip:ClearAllPoints()
        awqTooltip:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 0)
        awqTooltip:Show()
    end

    function QuestFrameModule.Tooltip_ShowSimple(anchor, text, color)
        if InCombatLockdown() then
            return
        end

        QuestFrameModule.Tooltip_Show(anchor, { { text = text, color = color } })
    end

    function QuestFrameModule:Tooltip_Hide()
        if awqTooltip then
            awqTooltip:Hide()
        end
    end

    function QuestFrameModule.Tooltip_AddRewards(lines, questID)
        local addedLine = false
        local rewardsStartIndex = #lines + 1

        local baseXp = GetQuestLogRewardXP(questID)
        if baseXp and baseXp > 0 then
            table.insert(lines, { text = BONUS_OBJECTIVE_EXPERIENCE_FORMAT:format(baseXp), color = HIGHLIGHT_FONT_COLOR })
            addedLine = true
        end

        local artifactXP = GetQuestLogRewardArtifactXP(questID)
        if artifactXP and artifactXP > 0 then
            table.insert(lines, { text = BONUS_OBJECTIVE_ARTIFACT_XP_FORMAT:format(artifactXP), color = HIGHLIGHT_FONT_COLOR })
            addedLine = true
        end

        local money = GetQuestLogRewardMoney(questID)
        if money and money > 0 then
            local gold = floor(money / (_AngrierWorldQuests.Constants.MONEY.COPPER_PER_SILVER * _AngrierWorldQuests.Constants.MONEY.SILVER_PER_GOLD))
            local silver = floor((money - (gold * _AngrierWorldQuests.Constants.MONEY.COPPER_PER_SILVER * _AngrierWorldQuests.Constants.MONEY.SILVER_PER_GOLD)) / _AngrierWorldQuests.Constants.MONEY.COPPER_PER_SILVER)
            local copper = mod(money, _AngrierWorldQuests.Constants.MONEY.COPPER_PER_SILVER)

            if gold > 0 or silver > 0 or copper > 0 then
                table.insert(lines, { text = MONEY_FORMAT:format(
                    BreakUpLargeNumbers(gold), "Interface\\MoneyFrame\\UI-GoldIcon",
                    silver, "Interface\\MoneyFrame\\UI-SilverIcon",
                    copper, "Interface\\MoneyFrame\\UI-CopperIcon"
                ), color = HIGHLIGHT_FONT_COLOR })
                addedLine = true
            end
        end

        local currencies = C_QuestLog.GetQuestRewardCurrencies(questID)
        if currencies then
            for _, currencyInfo in ipairs(currencies) do
                if currencyInfo and currencyInfo.texture and currencyInfo.totalRewardAmount and currencyInfo.name then
                    table.insert(lines, { text = BONUS_OBJECTIVE_REWARD_WITH_COUNT_FORMAT:format(currencyInfo.texture, currencyInfo.totalRewardAmount, currencyInfo.name), color = HIGHLIGHT_FONT_COLOR })
                    addedLine = true
                end
            end
        end

        local numQuestRewards = GetNumQuestLogRewards(questID)
        if numQuestRewards and numQuestRewards > 0 then
            local itemName, itemTexture, quantity, quality = GetQuestLogRewardInfo(1, questID)
            if itemName and itemTexture then
                local text
                if quantity and quantity > 1 then
                    text = BONUS_OBJECTIVE_REWARD_WITH_COUNT_FORMAT:format(itemTexture, quantity, itemName)
                else
                    text = BONUS_OBJECTIVE_REWARD_FORMAT:format(itemTexture, itemName)
                end

                local colorData = quality and ColorManager.GetColorDataForItemQuality(quality) or nil
                local color = (colorData and colorData.color) or HIGHLIGHT_FONT_COLOR
                table.insert(lines, { text = text, color = color })
                addedLine = true
            end
        end

        if C_QuestLog.QuestContainsFirstTimeRepBonusForPlayer(questID) then
            table.insert(lines, { text = " ", color = NORMAL_FONT_COLOR })
            table.insert(lines, { text = QUEST_REWARDS_CONTAINS_ONE_TIME_REP_BONUS, color = QUEST_REWARD_CONTEXT_FONT_COLOR })
        end

        if addedLine then
            table.insert(lines, rewardsStartIndex, { text = QUEST_REWARDS, color = NORMAL_FONT_COLOR })
        end
    end

    function QuestFrameModule.Tooltip_BuildSafe(self)
        if InCombatLockdown() then
            return
        end

        local questID = self.questID
        if not questID then
            return
        end

        local lines = {}

        local title = self.Text and self.Text:GetText() or C_TaskQuest.GetQuestInfoByQuestID(questID) or ""
        local tagInfo = QuestFrameModule.GetCachedQuestTagInfo(questID)
        local titleColor = HIGHLIGHT_FONT_COLOR
        if tagInfo and tagInfo.quality then
            local colorData = ColorManager.GetColorDataForWorldQuestQuality(tagInfo.quality)
            if colorData then
                titleColor = colorData.color
            end
        end
        table.insert(lines, { text = title, color = titleColor })

        if C_QuestLog.IsAccountQuest(questID) then
            table.insert(lines, { text = ACCOUNT_QUEST_LABEL, color = ACCOUNT_WIDE_FONT_COLOR })
        end

        local questTypeText = QuestUtils_GetQuestTypeIconMarkupString(questID, 20, 20)
        if questTypeText then
            table.insert(lines, { text = questTypeText, color = NORMAL_FONT_COLOR })
        end

        local factionID = self.factionID or select(2, C_TaskQuest.GetQuestInfoByQuestID(questID))
        if factionID then
            local factionData = C_Reputation.GetFactionDataByID(factionID)
            if factionData and factionData.name then
                table.insert(lines, { text = factionData.name, color = NORMAL_FONT_COLOR })
            end
        end

        local formattedTime, timeColor = WorldMap_GetQuestTimeForTooltip(questID)
        if formattedTime and timeColor then
            table.insert(lines, { text = MAP_TOOLTIP_TIME_LEFT:format(WrapTextWithColor(timeColor, formattedTime)) })
        end

        local isThreat = C_QuestLog.IsThreatQuest(questID)
        local numObjectives = self.numObjectives or C_QuestLog.GetNumQuestObjectives(questID)
        for objectiveIndex = 1, numObjectives do
            local objectiveText, _, finished = GetQuestObjectiveInfo(questID, objectiveIndex, false)
            if not (finished and isThreat) then
                if objectiveText and #objectiveText > 0 then
                    table.insert(lines, { text = QUEST_DASH .. objectiveText, color = finished and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR })
                end
            end
        end

        table.insert(lines, { text = " ", color = NORMAL_FONT_COLOR })
        QuestFrameModule.Tooltip_AddRewards(lines, questID)
        QuestFrameModule.Tooltip_Show(self, lines)
    end
end