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
-- Frequent enough to show queue-state transitions in the map.
local MONITOR_INTERVAL_MS = 400
local monitorLastRequest = 0

-- Shared order for the map legend and Status breakdown.
local MONITOR_STATES = { "high", "low", "pending", "cooldown", "done", "safehouse", "loaded", "unloaded" }
local MONITOR_STATE_LABELS = {
    high = "High", low = "Low", pending = "Pending", cooldown = "Cooldown",
    done = "Done", safehouse = "Safehouse", loaded = "Loaded", unloaded = "Unloaded",
}

local function drawMonitorText(panel, value, x, y)
    panel:drawText(tostring(value or ""), x, y, 1, 1, 1, 1, UIFont.Small)
end

local function requestMonitor()
    local now = getTimestampMs and getTimestampMs() or 0
    if now - monitorLastRequest < MONITOR_INTERVAL_MS then return end
    local player = getSpecificPlayer and getSpecificPlayer(0)
    if not player then return end
    monitorLastRequest = now
    if isClient and isClient() then
        sendClientCommand(player, "WDecayDebug", "Run", { action = "monitor", radius = 12 })
    elseif WDecay_Dispatcher_GetMonitorData and WDecay_DebugAgePanel.instance then
        WDecay_DebugAgePanel.instance:setMonitorData(WDecay_Dispatcher_GetMonitorData(player, 12))
    end
end

local function refreshMonitor()
    monitorLastRequest = 0
    requestMonitor()
end

local WDecay_DebugStatusPanel = ISPanel:derive("WDecay_DebugStatusPanel")

function WDecay_DebugStatusPanel:new(x, y, width, height)
    local panel = ISPanel.new(self, x, y, width, height)
    panel.data = {}
    panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0.35 }
    return panel
end

function WDecay_DebugStatusPanel:createChildren()
    self.refreshButton = ISButton:new(12, 8, 80, 20, "Refresh", self, refreshMonitor)
    self.refreshButton:initialise(); self:addChild(self.refreshButton)
end

function WDecay_DebugStatusPanel:prerender()
    ISPanel.prerender(self); requestMonitor()
    local d, y = self.data, 36
    local c = d.stateCounts or {}
    local lines = {
        "WorldDecay server status",
        "Queue H/L: " .. (d.queueHigh or 0) .. "/" .. (d.queueLow or 0),
        "Added/completed/failed: " .. (d.added or 0) .. "/" .. (d.completed or 0) .. "/" .. (d.failed or 0),
        "Processed: " .. (d.processed or 0),
        "Budget: " .. (d.budget or 0) .. "ms",
        "Fast travel: " .. ((d.fastTravelActive and "ACTIVE" or "normal")
            .. " | " .. (d.fastTravelPlayerSource or "none")
            .. " players=" .. (d.fastTravelPlayerCount or 0)
            .. " vehicles=" .. (d.fastTravelVehicleCount or 0)),
        "Speed: " .. string.format("%.1f", d.fastTravelMaxSpeedKmh or 0) .. "/"
            .. (d.fastTravelThresholdKmh or 0) .. " km/h | scan every "
            .. string.format("%.2f/%.2fs", d.scanIntervalSeconds or 0, d.fastTravelScanIntervalSeconds or 0),
        "Current high: " .. (d.currentHigh and tostring(d.currentHigh) or "none"),
        "Current low: " .. (d.currentLow and tostring(d.currentLow) or "none"),
        "-- computational cost --",
        "Avg ms/chunk: " .. string.format("%.2f", d.avgChunkMs or 0),
        "Total ms last/avg/max: " .. string.format("%.1f/%.1f/%.1f",
            d.totalMsLast or 0, d.totalMsAvg or 0, d.totalMsMax or 0),
        "Dispatch ms last/avg/max: " .. string.format("%.1f/%.1f/%.1f",
            d.tickMsLast or 0, d.tickMsAvg or 0, d.tickMsMax or 0),
        "Scan ms last/avg/max: " .. string.format("%.1f/%.1f/%.1f",
            d.scanMsLast or 0, d.scanMsAvg or 0, d.scanMsMax or 0),
        "checkAll avg ms x calls: " .. string.format("%.4f", d.avgCheckAllMs or 0) .. " x " .. (d.checkAllCalls or 0),
        "Tick interval avg: " .. string.format("%.2f", d.tickIntervalAvg or 0) .. "ms (~"
            .. string.format("%.1f", (d.tickIntervalAvg or 0) > 0 and (1000 / d.tickIntervalAvg) or 0) .. " FPS, WDecay ~"
            .. string.format("%.1f", (d.tickIntervalAvg or 0) > 0 and ((d.totalMsAvg or 0) / d.tickIntervalAvg * 100) or 0) .. "% of a tick)",
        "Discovery throttled: scan=" .. (d.scanThrottled or 0),
        "Scans: ran=" .. (d.scanRuns or 0) .. " skipped=" .. (d.scanMovementSkipped or 0)
            .. " due=" .. (d.scanDue or 0) .. " deferred=" .. (d.scanDeferred or 0)
            .. " oldest=" .. math.floor(d.scanOldestOverdueMs or 0) .. "ms",
        "Per-player queue cap H/T: " .. (d.playerHighQueueLimit or 0) .. "/" .. (d.playerQueueLimit or 0),
        "Discovery source: scan=" .. (d.scanQueued or 0),
        "-- visible chunk states (radius " .. (d.radius or 12) .. ") --",
        "High/Low/Pending: " .. (c.high or 0) .. "/" .. (c.low or 0) .. "/" .. (c.pending or 0),
        "Cooldown/Done: " .. (c.cooldown or 0) .. "/" .. (c.done or 0),
        "Safehouse/Loaded/Unloaded: " .. (c.safehouse or 0) .. "/" .. (c.loaded or 0) .. "/" .. (c.unloaded or 0),
        "-- generator cost, avg ms x calls (heaviest first) --",
    }
    local stats = d.generatorStats or {}
    for i = 1, #stats do
        local s = stats[i]
        lines[#lines + 1] = "  " .. s.name .. ": " .. string.format("%.3f", s.avgMs) .. "ms x " .. s.calls
    end
    for i = 1, #lines do drawMonitorText(self, lines[i], 12, y); y = y + 20 end
end

local WDecay_DebugMapPanel = ISPanel:derive("WDecay_DebugMapPanel")
-- Keep queue states visually distinct.
local monitorColors = {
    unloaded = { 0.12, 0.12, 0.12 }, loaded = { 0.42, 0.42, 0.45 },
    done = { 0.15, 0.65, 0.25 }, low = { 0.85, 0.65, 0.1 },
    high = { 0.9, 0.2, 0.15 }, pending = { 0.85, 0.25, 0.85 },
    safehouse = { 0.2, 0.45, 0.9 }, cooldown = { 0.1, 0.75, 0.75 },
}

function WDecay_DebugMapPanel:new(x, y, width, height)
    local panel = ISPanel.new(self, x, y, width, height)
    panel.data = { cells = {}, radius = 12 }
    panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0.35 }
    return panel
end

function WDecay_DebugMapPanel:createChildren()
    self.refreshButton = ISButton:new(12, 2, 80, 20, "Refresh", self, refreshMonitor)
    self.refreshButton:initialise(); self:addChild(self.refreshButton)
end

-- Two-row map legend.
local LEGEND_COLS = 4
local LEGEND_ROWS = 2
local LEGEND_ROW_H = 16
local LEGEND_SWATCH = 10

function WDecay_DebugMapPanel:prerender()
    ISPanel.prerender(self); requestMonitor()
    local d, radius = self.data, tonumber(self.data.radius) or 12
    local cells = radius * 2 + 1
    local legendH = LEGEND_ROWS * LEGEND_ROW_H + 4
    local size = math.max(3, math.floor(math.min((self.width - 24) / cells, (self.height - 30 - legendH) / cells)))
    local ox, oy = math.floor((self.width - size * cells) / 2), 28
    for i = 1, #(d.cells or {}) do
        local cell, color = d.cells[i], monitorColors[d.cells[i].state] or monitorColors.unloaded
        self:drawRect(ox + (cell.x - d.centerX + radius) * size, oy + (cell.y - d.centerY + radius) * size,
            size - 1, size - 1, 1, color[1], color[2], color[3])
    end

    -- The monitor is centered on the requesting player.
    if d.centerX then
        local px, py = ox + radius * size, oy + radius * size
        self:drawRectBorder(px - 1, py - 1, size + 1, size + 1, 1, 1, 1, 1)
        self:drawRectBorder(px - 2, py - 2, size + 3, size + 3, 1, 0, 0, 0)
    end

    -- Show exact chunk and cooldown state on hover.
    local mx, my = self:getMouseX(), self:getMouseY()
    if mx >= ox and mx < ox + size * cells and my >= oy and my < oy + size * cells then
        local gx, gy = math.floor((mx - ox) / size), math.floor((my - oy) / size)
        local wx, wy = gx - radius + (d.centerX or 0), gy - radius + (d.centerY or 0)
        local hovered = self.cellLookup and self.cellLookup[wx .. ":" .. wy]
        self:drawRect(ox + gx * size, oy + gy * size, size, size, 0.6, 1, 1, 1)
        local label = "Chunk " .. wx .. "," .. wy .. ": " .. (hovered and hovered.state or "?")
        if hovered and hovered.state == "cooldown" then
            label = label .. " (" .. string.format("%.1f", (hovered.remainingMs or 0) / 1000) .. "s left)"
        end
        drawMonitorText(self, label, 12, 10)
    end

    local legendY = self.height - legendH
    for i = 1, #MONITOR_STATES do
        local state = MONITOR_STATES[i]
        local col = (i - 1) % LEGEND_COLS
        local row = math.floor((i - 1) / LEGEND_COLS)
        local colW = math.floor((self.width - 24) / LEGEND_COLS)
        local sx, sy = 12 + col * colW, legendY + row * LEGEND_ROW_H
        local color = monitorColors[state]
        self:drawRect(sx, sy + 2, LEGEND_SWATCH, LEGEND_SWATCH, 1, color[1], color[2], color[3])
        drawMonitorText(self, MONITOR_STATE_LABELS[state], sx + LEGEND_SWATCH + 4, sy)
    end
end

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
    self.statusTab = WDecay_DebugStatusPanel:new(0, 0, 10, 10)
    self.statusTab:initialise()
    self.mapTab = WDecay_DebugMapPanel:new(0, 0, 10, 10)
    self.mapTab:initialise()
    self.tabs:addView("General", self.generalTab)
    self.tabs:addView("Seasonal", self.seasonalTab)
    self.tabs:addView("Status", self.statusTab)
    self.tabs:addView("Map", self.mapTab)
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
    self.regenBtn = ISButton:new(12, y, 118, 20, "Overwrite Regen", self, WDecay_DebugAgePanel.onRegen)
    self.regenBtn:initialise()
    self.generalTab:addChild(self.regenBtn)

    self.redecayBtn = ISButton:new(136, y, 118, 20, "Force Re-decay", self, WDecay_DebugAgePanel.onRedecay)
    self.redecayBtn:initialise()
    self.generalTab:addChild(self.redecayBtn)

    y = y + 26
    self.timerRedecayBtn = ISButton:new(12, y, 242, 20, "Timer Re-decay (due only)", self, WDecay_DebugAgePanel.onTimerRedecay)
    self.timerRedecayBtn:initialise()
    self.generalTab:addChild(self.timerRedecayBtn)

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
    local resizeH = 0
    if self.resizable and self.resizeWidget and self.resizeWidget:getIsVisible() then resizeH = self:resizeWidgetHeight() end
    self.tabs:setX(1); self.tabs:setY(top); self.tabs:setWidth(self.width - 2)
    self.tabs:setHeight(self.height - top - resizeH - 1)
    self.tabs.maxLength = math.floor((self.tabs.width - 3) / 4)
    local tabW = self.tabs.width
    local tabH = self.tabs.height - self.tabs.tabHeight
    self.generalTab:setWidth(tabW); self.generalTab:setHeight(tabH)
    self.seasonalTab:setWidth(tabW); self.seasonalTab:setHeight(tabH)
    self.statusTab:setWidth(tabW); self.statusTab:setHeight(tabH)
    self.mapTab:setWidth(tabW); self.mapTab:setHeight(tabH)
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
    self.timerRedecayBtn:setX(12); self.timerRedecayBtn:setY(186); self.timerRedecayBtn:setWidth(w)
    self.cleanBtn:setX(12); self.cleanBtn:setY(212); self.cleanBtn:setWidth(half)
    self.statusBtn:setX(18 + half); self.statusBtn:setY(212); self.statusBtn:setWidth(w - 6 - half)
    self.overlaysBtn:setX(12); self.overlaysBtn:setY(238); self.overlaysBtn:setWidth(w)

    self.tlLabel:setX(12); self.tlLabel:setY(268); self.tlLabel:setWidth(w)
    self.tlStepEntry:setX(12); self.tlStepEntry:setY(290)
    self.tlTicksEntry:setX(66); self.tlTicksEntry:setY(290)
    self.tlTargetEntry:setX(120); self.tlTargetEntry:setY(290)
    self.tlBtn:setX(182); self.tlBtn:setY(290); self.tlBtn:setWidth(math.max(60, w - 194))

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

-- Index monitor data once per poll for both tabs.
local function deriveCellIndex(data)
    local counts, lookup = {}, {}
    for i = 1, #MONITOR_STATES do counts[MONITOR_STATES[i]] = 0 end
    local cells = data.cells or {}
    for i = 1, #cells do
        local cell = cells[i]
        counts[cell.state] = (counts[cell.state] or 0) + 1
        lookup[cell.x .. ":" .. cell.y] = cell
    end
    return counts, lookup
end

function WDecay_DebugAgePanel:setMonitorData(data)
    data = data or {}
    local counts, lookup = deriveCellIndex(data)
    data.stateCounts = counts
    if self.statusTab then self.statusTab.data = data end
    if self.mapTab then
        self.mapTab.data = data.cells and data or self.mapTab.data
        self.mapTab.cellLookup = data.cells and lookup or self.mapTab.cellLookup
    end
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
    elseif action == "timerRedecay" and WDecay_TimerRedecay then WDecay_TimerRedecay(args.radius)
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

function WDecay_DebugAgePanel:onTimerRedecay()
    runDebugAction("timerRedecay", { radius = self:getRadius() })
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

Events.OnServerCommand.Add(function(module, command, data)
    local panel = WDecay_DebugAgePanel.instance
    if module == "WDecayDebug" and command == "Monitor" and panel then panel:setMonitorData(data) end
end)

function WDecay_DebugAgePanel:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = "WorldDecay - Debug"
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

    -- Leave room for the variable-length Status tab.
    local width, height = 300, 460
    local x = getCore():getScreenWidth() / 2 - width / 2
    local y = getCore():getScreenHeight() / 2 - height / 2
    local panel = WDecay_DebugAgePanel:new(x, y, width, height)
    panel:initialise()
    panel:addToUIManager()
    WDecay_DebugAgePanel.instance = panel
end
