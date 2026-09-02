require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISTabPanel"
require "ISUI/ISPanel"

local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Season = require('wdecay_season/wdecay_season')

WDecay_DebugAgePanel = ISCollapsableWindow:derive("WDecay_DebugAgePanel")
WDecay_DebugAgePanel.instance = nil

local PANEL_MIN_W = 266
local PANEL_MIN_H = 360

function WDecay_DebugAgePanel:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setResizable(true)

    self.tabs = ISTabPanel:new(1, self:titleBarHeight(), self.width - 2, self.height - self:titleBarHeight() - 1)
    self.tabs:initialise()
    self.tabs.equalTabWidth = true
    self.generalTab = ISPanel:new(0, 0, 10, 10)
    self.generalTab:initialise()
    self.generalTab.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.seasonalTab = ISPanel:new(0, 0, 10, 10)
    self.seasonalTab:initialise()
    self.seasonalTab.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.tabs:addView("General", self.generalTab)
    self.tabs:addView("Seasonal", self.seasonalTab)
    self:addChild(self.tabs)

    local y = 28
    self.ageLabel = ISLabel:new(12, y, 20, "...", 1, 1, 1, 1, UIFont.Small, true)
    self.generalTab:addChild(self.ageLabel)

    y = y + 22
    self.multLabel = ISLabel:new(12, y, 20, "...", 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    self.generalTab:addChild(self.multLabel)

    y = y + 28
    self.daysEntry = ISTextEntryBox:new("120", 12, y, 64, 20)
    self.daysEntry:initialise()
    self.daysEntry:instantiate()
    self.daysEntry:setOnlyNumbers(true)
    self.generalTab:addChild(self.daysEntry)

    self.setBtn = ISButton:new(82, y, 76, 20, "Set Days", self, WDecay_DebugAgePanel.onSetDays)
    self.setBtn:initialise()
    self.generalTab:addChild(self.setBtn)

    self.clearBtn = ISButton:new(164, y, 90, 20, "Real Age", self, WDecay_DebugAgePanel.onClearDays)
    self.clearBtn:initialise()
    self.generalTab:addChild(self.clearBtn)

    y = y + 26
    self.add30Btn = ISButton:new(12, y, 76, 20, "+30 days", self, WDecay_DebugAgePanel.onAddDays)
    self.add30Btn.internal = 30
    self.add30Btn:initialise()
    self.generalTab:addChild(self.add30Btn)

    self.add90Btn = ISButton:new(94, y, 76, 20, "+90 days", self, WDecay_DebugAgePanel.onAddDays)
    self.add90Btn.internal = 90
    self.add90Btn:initialise()
    self.generalTab:addChild(self.add90Btn)

    self.add365Btn = ISButton:new(176, y, 78, 20, "+365 days", self, WDecay_DebugAgePanel.onAddDays)
    self.add365Btn.internal = 365
    self.add365Btn:initialise()
    self.generalTab:addChild(self.add365Btn)

    y = y + 30
    self.radiusLabel = ISLabel:new(12, y, 20, "Radius (chunks):", 1, 1, 1, 1, UIFont.Small, true)
    self.generalTab:addChild(self.radiusLabel)

    self.radiusEntry = ISTextEntryBox:new("3", 130, y, 50, 20)
    self.radiusEntry:initialise()
    self.radiusEntry:instantiate()
    self.radiusEntry:setOnlyNumbers(true)
    self.generalTab:addChild(self.radiusEntry)

    y = y + 26
    self.regenBtn = ISButton:new(12, y, 118, 20, "Regen Area", self, WDecay_DebugAgePanel.onRegen)
    self.regenBtn:initialise()
    self.generalTab:addChild(self.regenBtn)

    self.redecayBtn = ISButton:new(136, y, 118, 20, "Re-decay area", self, WDecay_DebugAgePanel.onRedecay)
    self.redecayBtn:initialise()
    self.generalTab:addChild(self.redecayBtn)

    y = y + 26
    self.cleanBtn = ISButton:new(12, y, 118, 20, "Clean Area", self, WDecay_DebugAgePanel.onClean)
    self.cleanBtn:initialise()
    self.generalTab:addChild(self.cleanBtn)

    self.statusBtn = ISButton:new(136, y, 118, 20, "Status to Console", self, WDecay_DebugAgePanel.onStatus)
    self.statusBtn:initialise()
    self.generalTab:addChild(self.statusBtn)

    y = y + 26
    self.overlaysBtn = ISButton:new(12, y, 242, 20, "Reapply Overlays", self, WDecay_DebugAgePanel.onOverlays)
    self.overlaysBtn:initialise()
    self.generalTab:addChild(self.overlaysBtn)

    y = y + 30
    self.tlLabel = ISLabel:new(12, y, 20, "Timelapse - step/ticks/target:", 1, 1, 1, 1, UIFont.Small, true)
    self.generalTab:addChild(self.tlLabel)

    y = y + 22
    self.tlStepEntry = ISTextEntryBox:new("7", 12, y, 48, 20)
    self.tlStepEntry:initialise()
    self.tlStepEntry:instantiate()
    self.tlStepEntry:setOnlyNumbers(true)
    self.generalTab:addChild(self.tlStepEntry)

    self.tlTicksEntry = ISTextEntryBox:new("30", 66, y, 48, 20)
    self.tlTicksEntry:initialise()
    self.tlTicksEntry:instantiate()
    self.tlTicksEntry:setOnlyNumbers(true)
    self.generalTab:addChild(self.tlTicksEntry)

    self.tlTargetEntry = ISTextEntryBox:new("365", 120, y, 56, 20)
    self.tlTargetEntry:initialise()
    self.tlTargetEntry:instantiate()
    self.tlTargetEntry:setOnlyNumbers(true)
    self.generalTab:addChild(self.tlTargetEntry)

    self.tlBtn = ISButton:new(182, y, 72, 20, "Iniciar", self, WDecay_DebugAgePanel.onTimelapse)
    self.tlBtn:initialise()
    self.generalTab:addChild(self.tlBtn)

    self.seasonLabel = ISLabel:new(12, 28, 260, "Season: ?", 1, 1, 1, 1, UIFont.Small, true)
    self.seasonalTab:addChild(self.seasonLabel)
    self.springBtn = ISButton:new(12, 58, 64, 20, "Spring", self, WDecay_DebugAgePanel.onSetSeason)
    self.springBtn.internal = "spring"
    self.springBtn:initialise(); self.seasonalTab:addChild(self.springBtn)
    self.summerBtn = ISButton:new(82, 58, 64, 20, "Summer", self, WDecay_DebugAgePanel.onSetSeason)
    self.summerBtn.internal = "summer"
    self.summerBtn:initialise(); self.seasonalTab:addChild(self.summerBtn)
    self.autumnBtn = ISButton:new(152, 58, 64, 20, "Autumn", self, WDecay_DebugAgePanel.onSetSeason)
    self.autumnBtn.internal = "autumn"
    self.autumnBtn:initialise(); self.seasonalTab:addChild(self.autumnBtn)
    self.winterBtn = ISButton:new(222, 58, 64, 20, "Winter", self, WDecay_DebugAgePanel.onSetSeason)
    self.winterBtn.internal = "winter"
    self.winterBtn:initialise(); self.seasonalTab:addChild(self.winterBtn)
    self.advanceMonthBtn = ISButton:new(12, 88, 134, 20, "+1 Month", self, WDecay_DebugAgePanel.onAdvanceMonth)
    self.advanceMonthBtn:initialise(); self.seasonalTab:addChild(self.advanceMonthBtn)
    self.climateBtn = ISButton:new(152, 88, 134, 20, "Climate Info", self, WDecay_DebugAgePanel.onClimateInfo)
    self.climateBtn:initialise(); self.seasonalTab:addChild(self.climateBtn)
    self.reseasonTreesBtn = ISButton:new(12, 130, 134, 20, "Reseason Trees", self, WDecay_DebugAgePanel.onReseason)
    self.reseasonTreesBtn.internal = "trees"
    self.reseasonTreesBtn:initialise(); self.seasonalTab:addChild(self.reseasonTreesBtn)
    self.reseasonBushesBtn = ISButton:new(152, 130, 134, 20, "Reseason Bushes", self, WDecay_DebugAgePanel.onReseason)
    self.reseasonBushesBtn.internal = "bushes"
    self.reseasonBushesBtn:initialise(); self.seasonalTab:addChild(self.reseasonBushesBtn)
    self.reseasonGrassBtn = ISButton:new(12, 156, 134, 20, "Reseason Grass", self, WDecay_DebugAgePanel.onReseason)
    self.reseasonGrassBtn.internal = "grass"
    self.reseasonGrassBtn:initialise(); self.seasonalTab:addChild(self.reseasonGrassBtn)
    self.reseasonVinesBtn = ISButton:new(152, 156, 134, 20, "Reseason Vines", self, WDecay_DebugAgePanel.onReseason)
    self.reseasonVinesBtn.internal = "vines"
    self.reseasonVinesBtn:initialise(); self.seasonalTab:addChild(self.reseasonVinesBtn)

    self:layout()
end

function WDecay_DebugAgePanel:layout()
    local top = self:titleBarHeight()
    self.tabs:setX(1); self.tabs:setY(top); self.tabs:setWidth(self.width - 2); self.tabs:setHeight(self.height - top - 1)
    self.tabs.maxLength = math.floor((self.tabs.width - 3) / 2)
    local tabW = self.tabs.width
    local tabH = self.tabs.height - self.tabs.tabHeight
    self.generalTab:setWidth(tabW); self.generalTab:setHeight(tabH)
    self.seasonalTab:setWidth(tabW); self.seasonalTab:setHeight(tabH)
    local w = self.generalTab.width - 24
    local half = math.floor((w - 6) / 2)
    local third = math.floor((w - 12) / 3)

    self.ageLabel:setX(12); self.ageLabel:setY(28); self.ageLabel:setWidth(w)
    self.multLabel:setX(12); self.multLabel:setY(50); self.multLabel:setWidth(w)

    self.daysEntry:setX(12); self.daysEntry:setY(78)
    self.setBtn:setX(82); self.setBtn:setY(78)
    self.clearBtn:setX(164); self.clearBtn:setY(78); self.clearBtn:setWidth(math.max(60, w - 152))

    self.add30Btn:setX(12); self.add30Btn:setY(104); self.add30Btn:setWidth(third)
    self.add90Btn:setX(18 + third); self.add90Btn:setY(104); self.add90Btn:setWidth(third)
    self.add365Btn:setX(24 + third * 2); self.add365Btn:setY(104); self.add365Btn:setWidth(w - 24 - third * 2)

    self.radiusLabel:setX(12); self.radiusLabel:setY(134); self.radiusLabel:setWidth(110)
    self.radiusEntry:setX(w - 38); self.radiusEntry:setY(134)

    self.regenBtn:setX(12); self.regenBtn:setY(160); self.regenBtn:setWidth(half)
    self.redecayBtn:setX(18 + half); self.redecayBtn:setY(160); self.redecayBtn:setWidth(w - 6 - half)
    self.cleanBtn:setX(12); self.cleanBtn:setY(186); self.cleanBtn:setWidth(half)
    self.statusBtn:setX(18 + half); self.statusBtn:setY(186); self.statusBtn:setWidth(w - 6 - half)
    self.overlaysBtn:setX(12); self.overlaysBtn:setY(212); self.overlaysBtn:setWidth(w)

    self.tlLabel:setX(12); self.tlLabel:setY(242); self.tlLabel:setWidth(w)
    self.tlStepEntry:setX(12); self.tlStepEntry:setY(264)
    self.tlTicksEntry:setX(66); self.tlTicksEntry:setY(264)
    self.tlTargetEntry:setX(120); self.tlTargetEntry:setY(264)
    self.tlBtn:setX(182); self.tlBtn:setY(264); self.tlBtn:setWidth(math.max(60, w - 194))

    local sw = self.seasonalTab.width - 24
    self.seasonLabel:setWidth(sw)
    local half = math.floor((sw - 6) / 2)
    self.springBtn:setX(12); self.springBtn:setWidth(math.floor((sw - 18) / 4))
    self.summerBtn:setX(18 + self.springBtn.width); self.summerBtn:setWidth(self.springBtn.width)
    self.autumnBtn:setX(24 + self.springBtn.width * 2); self.autumnBtn:setWidth(self.springBtn.width)
    self.winterBtn:setX(30 + self.springBtn.width * 3); self.winterBtn:setWidth(sw - 30 - self.springBtn.width * 3)
    self.advanceMonthBtn:setX(12); self.advanceMonthBtn:setWidth(half)
    self.climateBtn:setX(18 + half); self.climateBtn:setWidth(sw - 6 - half)
    self.reseasonTreesBtn:setX(12); self.reseasonTreesBtn:setWidth(half)
    self.reseasonBushesBtn:setX(18 + half); self.reseasonBushesBtn:setWidth(sw - 6 - half)
    self.reseasonGrassBtn:setX(12); self.reseasonGrassBtn:setWidth(half)
    self.reseasonVinesBtn:setX(18 + half); self.reseasonVinesBtn:setWidth(sw - 6 - half)
end

function WDecay_DebugAgePanel:prerender()
    ISCollapsableWindow.prerender(self)

    if self.lastWidth ~= self.width or self.lastHeight ~= self.height then
        self:layout()
        self.lastWidth = self.width
        self.lastHeight = self.height
    end

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
    if self.seasonLabel and WDecay_Season then
        self.seasonLabel:setName("Season: " .. tostring(WDecay_Season.getSeasonName() or "?"))
    end

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

local function runDebugAction(action, args)
    local player = getSpecificPlayer and getSpecificPlayer(0)
    if sendClientCommand and player then
        args = args or {}
        args.action = action
        sendClientCommand(player, "WDecayDebug", "Run", args)
        return
    end
    if action == "setDays" and WDecay_SetDays then WDecay_SetDays(args.days)
    elseif action == "clearDays" and WDecay_ClearDays then WDecay_ClearDays()
    elseif action == "addDays" and WDecay_AddDays then WDecay_AddDays(args.days)
    elseif action == "regen" and WDecay_Regen then WDecay_Regen(args.radius)
    elseif action == "redecay" and WDecay_Redecay then WDecay_Redecay(args.radius)
    elseif action == "clean" and WDecay_CleanArea then WDecay_CleanArea(args.radius)
    elseif action == "overlays" and WDecay_ReapplyOverlays then WDecay_ReapplyOverlays(args.radius)
    elseif action == "timelapse" and WDecay_TimelapseToggle then WDecay_TimelapseToggle(args.step, args.ticks, args.target, args.radius)
    elseif action == "season" and WDecay_SeasonalDebug then WDecay_SeasonalDebug(args.season)
    elseif action == "advanceMonth" and WDecay_SeasonalAdvanceMonth then WDecay_SeasonalAdvanceMonth()
    elseif action == "climate" and WDecay_SeasonalClimateInfo then WDecay_SeasonalClimateInfo()
    elseif action == "reseason" and WDecay_SeasonalReseason then WDecay_SeasonalReseason(args.kind)
    end
end

function WDecay_DebugAgePanel:onSetDays()
    local days = tonumber(self.daysEntry:getText())
    if days then runDebugAction("setDays", { days = days }) end
end

function WDecay_DebugAgePanel:onClearDays()
    runDebugAction("clearDays")
end

function WDecay_DebugAgePanel:onAddDays(button)
    runDebugAction("addDays", { days = button.internal })
end

function WDecay_DebugAgePanel:onRegen()
    runDebugAction("regen", { radius = self:getRadius() })
end

function WDecay_DebugAgePanel:onRedecay()
    runDebugAction("redecay", { radius = self:getRadius() })
end

function WDecay_DebugAgePanel:onClean()
    runDebugAction("clean", { radius = self:getRadius() })
end

function WDecay_DebugAgePanel:onStatus()
    runDebugAction("status")
end

function WDecay_DebugAgePanel:onOverlays()
    runDebugAction("overlays", { radius = self:getRadius() })
end

function WDecay_DebugAgePanel:onTimelapse()
    local step = tonumber(self.tlStepEntry:getText()) or 7
    local ticks = tonumber(self.tlTicksEntry:getText()) or 30
    local target = tonumber(self.tlTargetEntry:getText())
    runDebugAction("timelapse", { step = step, ticks = ticks, target = target, radius = self:getRadius() })
end

function WDecay_DebugAgePanel:onSetSeason(button)
    runDebugAction("season", { season = button.internal })
end

function WDecay_DebugAgePanel:onAdvanceMonth()
    runDebugAction("advanceMonth")
end

function WDecay_DebugAgePanel:onClimateInfo()
    runDebugAction("climate")
end

function WDecay_DebugAgePanel:onReseason(button)
    runDebugAction("reseason", { kind = button.internal })
end

function WDecay_DebugAgePanel:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    WDecay_DebugAgePanel.instance = nil
end

function WDecay_DebugAgePanel:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = "WorldDecay - Debug Age"
    o.minimumWidth = PANEL_MIN_W
    o.minimumHeight = PANEL_MIN_H
    o.resizable = true
    return o
end

function WDecay_Panel()
    if WDecay_DebugAgePanel.instance then
        WDecay_DebugAgePanel.instance:close()
        return
    end

    local width, height = 300, 380
    local x = getCore():getScreenWidth() / 2 - width / 2
    local y = getCore():getScreenHeight() / 2 - height / 2
    local panel = WDecay_DebugAgePanel:new(x, y, width, height)
    panel:initialise()
    panel:addToUIManager()
    WDecay_DebugAgePanel.instance = panel
end
