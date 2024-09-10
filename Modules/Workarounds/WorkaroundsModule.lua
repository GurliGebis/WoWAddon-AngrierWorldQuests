--[[
    Copyright (C) 2024 GurliGebis

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
local WorkaroundsModule = AngrierWorldQuests:NewModule("WorkaroundsModule")
local ConfigModule = AngrierWorldQuests:GetModule("ConfigModule")

local function WorkaroundMapTaints()
    -- Code copied from hack from Kalies Tracker, which is based on the original Blizzard_MapCanvas.lua code.
    local function OnPinReleased(pinPool, pin)
        Pool_HideAndClearAnchors(pinPool, pin);
        pin:OnReleased();
        pin.pinTemplate = nil;
        pin.owningMap = nil;
    end

    local function OnPinMouseUp(pin, button, upInside)
        pin:OnMouseUp(button, upInside);
        if upInside then
            pin:OnClick(button);
        end
    end

    function WorldMapFrame:AcquirePin(pinTemplate, ...)
        if not self.pinPools[pinTemplate] then
            local pinTemplateType = self.pinTemplateTypes[pinTemplate] or "FRAME";
            self.pinPools[pinTemplate] = CreateFramePool(pinTemplateType, self:GetCanvas(), pinTemplate, OnPinReleased);
        end

        local pin, newPin = self.pinPools[pinTemplate]:Acquire();

        pin.pinTemplate = pinTemplate;
        pin.owningMap = self;

        if newPin then
            local isMouseClickEnabled = pin:IsMouseClickEnabled();
            local isMouseMotionEnabled = pin:IsMouseMotionEnabled();

            if isMouseClickEnabled then
                pin:SetScript("OnMouseUp", OnPinMouseUp);
                pin:SetScript("OnMouseDown", pin.OnMouseDown);

                -- Prevent OnClick handlers from being run twice, once a frame is in the mapCanvas ecosystem it needs
                -- to process mouse events only via the map system.
                if pin:IsObjectType("Button") then
                    pin:SetScript("OnClick", nil);
                end
            end

            if isMouseMotionEnabled then
                if newPin and not pin:DisableInheritedMotionScriptsWarning() then
                    -- These will never be called, just define a OnMouseEnter and OnMouseLeave on the pin mixin and it'll be called when appropriate
                    assert(pin:GetScript("OnEnter") == nil);
                    assert(pin:GetScript("OnLeave") == nil);
                end
                pin:SetScript("OnEnter", pin.OnMouseEnter);
                pin:SetScript("OnLeave", pin.OnMouseLeave);
            end

            pin:SetMouseClickEnabled(isMouseClickEnabled);
            pin:SetMouseMotionEnabled(isMouseMotionEnabled);
        end

        if newPin then
            pin:OnLoad();
            pin.CheckMouseButtonPassthrough = function() end
            pin.UpdateMousePropagation = function() end
        end

        self.ScrollContainer:MarkCanvasDirty();
        pin:Show();
        pin:OnAcquired(...);

        return pin;
    end
end

function WorkaroundsModule:LoadWorkarounds(callback)
    if ConfigModule:Get("enableTaintWorkarounds") then
        WorkaroundMapTaints()
    end

    if callback then
        ReloadUI()
    end
end

function WorkaroundsModule:RegisterCallbacks()
    ConfigModule:RegisterCallback("enableTaintWorkarounds", function()
        self:LoadWorkarounds(true)
    end)
end

function WorkaroundsModule:OnEnable()
    self:RegisterCallbacks()

    self:LoadWorkarounds(false)
end