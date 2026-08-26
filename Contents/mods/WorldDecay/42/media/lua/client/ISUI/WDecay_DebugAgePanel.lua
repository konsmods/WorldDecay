require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"

local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')

WDecay_DebugAgePanel = ISCollapsableWindow:derive("WDecay_DebugAgePanel")
WDecay_DebugAgePanel.instance = nil

function WDecay_DebugAgePanel:createChildren()
    ISCollapsableWindow.createChildren(self)

    local y = 28
    self.ageLabel = ISLabel:new(12, y, 20, "...", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.ageLabel)

    y = y + 22
    self.multLabel = ISLabel:new(12, y, 20, "...", 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    self:addChild(self.multLabel)

    y = y + 28
    self.daysEntry = ISTextEntryBox:new("120", 12, y, 64, 20)
    self.daysEntry:initialise()
    self.daysEntry:instantiate()
    self.daysEntry:setOnlyNumbers(true)
    self:addChild(self.daysEntry)

    self.setBtn = ISButton:new(82, y, 76, 20, "Set Days", self, WDecay_DebugAgePanel.onSetDays)
    self.setBtn:initialise()
    self:addChild(self.setBtn)

    self.clearBtn = ISButton:new(164, y, 90, 20, "Real Age", self, WDecay_DebugAgePanel.onClearDays)
    self.clearBtn:initialise()
    self:addChild(self.clearBtn)

    y = y + 26
    self.add30Btn = ISButton:new(12, y, 76, 20, "+30 days", self, WDecay_DebugAgePanel.onAddDays)
    self.add30Btn.internal = 30
    self.add30Btn:initialise()
    self:addChild(self.add30Btn)

    self.add90Btn = ISButton:new(94, y, 76, 20, "+90 days", self, WDecay_DebugAgePanel.onAddDays)
    self.add90Btn.internal = 90
    self.add90Btn:initialise()
    self:addChild(self.add90Btn)

    self.add365Btn = ISButton:new(176, y, 78, 20, "+365 days", self, WDecay_DebugAgePanel.onAddDays)
    self.add365Btn.internal = 365
    self.add365Btn:initialise()
    self:addChild(self.add365Btn)

    y = y + 30
    self.radiusLabel = ISLabel:new(12, y, 20, "Radius (chunks):", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.radiusLabel)

    self.radiusEntry = ISTextEntryBox:new("3", 130, y, 50, 20)
    self.radiusEntry:initialise()
    self.radiusEntry:instantiate()
    self.radiusEntry:setOnlyNumbers(true)
    self:addChild(self.radiusEntry)

    y = y + 26
    self.regenBtn = ISButton:new(12, y, 118, 20, "Regen Area", self, WDecay_DebugAgePanel.onRegen)
    self.regenBtn:initialise()
    self:addChild(self.regenBtn)

    self.redecayBtn = ISButton:new(136, y, 118, 20, "Re-decay area", self, WDecay_DebugAgePanel.onRedecay)
    self.redecayBtn:initialise()
    self:addChild(self.redecayBtn)

    y = y + 26
    self.cleanBtn = ISButton:new(12, y, 118, 20, "Clean Area", self, WDecay_DebugAgePanel.onClean)
    self.cleanBtn:initialise()
    self:addChild(self.cleanBtn)

    self.statusBtn = ISButton:new(136, y, 118, 20, "Status to Console", self, WDecay_DebugAgePanel.onStatus)
    self.statusBtn:initialise()
    self:addChild(self.statusBtn)

    y = y + 26
    self.overlaysBtn = ISButton:new(12, y, 242, 20, "Reapply Overlays", self, WDecay_DebugAgePanel.onOverlays)
    self.overlaysBtn:initialise()
    self:addChild(self.overlaysBtn)

    y = y + 30
    self.tlLabel = ISLabel:new(12, y, 20, "Timelapse - step/ticks/target:", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.tlLabel)

    y = y + 22
    self.tlStepEntry = ISTextEntryBox:new("7", 12, y, 48, 20)
    self.tlStepEntry:initialise()
    self.tlStepEntry:instantiate()
    self.tlStepEntry:setOnlyNumbers(true)
    self:addChild(self.tlStepEntry)

    self.tlTicksEntry = ISTextEntryBox:new("30", 66, y, 48, 20)
    self.tlTicksEntry:initialise()
    self.tlTicksEntry:instantiate()
    self.tlTicksEntry:setOnlyNumbers(true)
    self:addChild(self.tlTicksEntry)

    self.tlTargetEntry = ISTextEntryBox:new("365", 120, y, 56, 20)
    self.tlTargetEntry:initialise()
    self.tlTargetEntry:instantiate()
    self.tlTargetEntry:setOnlyNumbers(true)
    self:addChild(self.tlTargetEntry)

    self.tlBtn = ISButton:new(182, y, 72, 20, "Iniciar", self, WDecay_DebugAgePanel.onTimelapse)
    self.tlBtn:initialise()
    self:addChild(self.tlBtn)
end

function WDecay_DebugAgePanel:prerender()
    ISCollapsableWindow.prerender(self)

    local days = WDecay_Scaling.getWorldAgeDays()
    local override = WDecay_Scaling.getDebugAgeDays()
    local ageText = "World Age: " .. (days and tostring(math.floor(days)) or "?") .. " days"
    if override ~= nil then
        ageText = ageText .. " (override)"
    end

    self.ageLabel:setName(ageText)

    local function fmt(value)
        return tostring(math.floor(value * 100) / 100)
    end

    self.multLabel:setName("Mult b/n/u/v: " .. fmt(WDecay_Scaling.getMultiplier())
        .. "/" .. fmt(WDecay_Scaling.getMultiplierFor('nature'))
        .. "/" .. fmt(WDecay_Scaling.getMultiplierFor('urban'))
        .. "/" .. fmt(WDecay_Scaling.getMultiplierFor('vehicles')))

    if self.tlBtn then
        local running = WDecay_TimelapseIsRunning and WDecay_TimelapseIsRunning()
        self.tlBtn:setTitle(running and "Stop" or "Start")
    end
end

function WDecay_DebugAgePanel:getRadius()
    local r = tonumber(self.radiusEntry:getText())
    if not r or r < 1 then r = 3 end
    if r > 100 then r = 100 end
    return r
end

function WDecay_DebugAgePanel:onSetDays()
    local days = tonumber(self.daysEntry:getText())
    if days and WDecay_SetDays then
        WDecay_SetDays(days)
    end
end

function WDecay_DebugAgePanel:onClearDays()
    if WDecay_ClearDays then
        WDecay_ClearDays()
    end
end

function WDecay_DebugAgePanel:onAddDays(button)
    if WDecay_AddDays then
        WDecay_AddDays(button.internal)
    end
end

function WDecay_DebugAgePanel:onRegen()
    if WDecay_Regen then
        WDecay_Regen(self:getRadius())
    end
end

function WDecay_DebugAgePanel:onRedecay()
    if WDecay_Redecay then
        WDecay_Redecay(self:getRadius())
    end
end

function WDecay_DebugAgePanel:onClean()
    if WDecay_CleanArea then
        WDecay_CleanArea(self:getRadius())
    end
end

function WDecay_DebugAgePanel:onStatus()
    if WDecay_Status then
        WDecay_Status()
    end
end

function WDecay_DebugAgePanel:onOverlays()
    if WDecay_ReapplyOverlays then
        WDecay_ReapplyOverlays(self:getRadius())
    end
end

function WDecay_DebugAgePanel:onTimelapse()
    if not WDecay_TimelapseToggle then return end

    local step = tonumber(self.tlStepEntry:getText()) or 7
    local ticks = tonumber(self.tlTicksEntry:getText()) or 30
    local target = tonumber(self.tlTargetEntry:getText())
    WDecay_TimelapseToggle(step, ticks, target, self:getRadius())
end

function WDecay_DebugAgePanel:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    WDecay_DebugAgePanel.instance = nil
end

function WDecay_DebugAgePanel:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = "WorldDecay - Debug Age"
    o.resizable = false
    return o
end

function WDecay_Panel()
    if WDecay_DebugAgePanel.instance then
        WDecay_DebugAgePanel.instance:close()
        return
    end

    local panel = WDecay_DebugAgePanel:new(120, 120, 266, 332)
    panel:initialise()
    panel:addToUIManager()
    WDecay_DebugAgePanel.instance = panel
end
