local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Placement = require('wdecay_placement/wdecay_placement')

local TIME_KEY = "WDecay_Grass_X_IndoorGrass-LoadGridsquare"

local randomizer = WDecay_Random.get()

local WDecay_Grass = require('WDecay_Grass/WDecay_Grass')

local function LoadGridsquare(square, checkResult, level)
    if not square then return end

    if not checkResult then return end

    if checkResult.cleaned then return end

    if not checkResult.isGoodSquare then return end

    if not checkResult.isIndoor then return end

    local grassPct = WDecay_Grass.getIndoorBasePercentage()
    if grassPct > 0 and WDecay_Scaling.scaleFor('nature', grassPct) >= randomizer:random(1, 100) then
        if not WDecay_Placement.isSafe(square) then return false end
        return WDecay_Placement.createTagged(square, WDecay_Grass.getRandomVanillaGrass(), "indoorGrass")
    end
end

local patchedFunction = LoadGridsquare

local function debugLoadGridsquare(square, checkResult, level)
    WD_Debug_Metric.startTimeMeasurement(TIME_KEY)
    local result = patchedFunction(square, checkResult, level)
    WD_Debug_Metric.endTimeMeasurement(TIME_KEY)
    return result
end

if isDebugEnabled() then
    LoadGridsquare = debugLoadGridsquare
end

if not WDecay_ModifierGenerators then WDecay_ModifierGenerators = {} end

table.insert(WDecay_ModifierGenerators, LoadGridsquare)

Events.EveryDays.Add(WDecay_Grass.resetCaches)
