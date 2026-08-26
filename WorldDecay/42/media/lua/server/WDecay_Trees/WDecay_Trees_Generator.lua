local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Placement = require('wdecay_placement/wdecay_placement')

local TIME_KEY = "WDecay_Trees-LoadGridsquare"

local randomizer = WDecay_Random.get()

local WDecay_Trees = require('WDecay_Trees/WDecay_Trees')

local function LoadGridsquare(square, checkResult, level)
    if not square then return end

    if not checkResult then return end

    if checkResult.cleaned then return end

    if level ~= 0 then return end

    local isRoad = checkResult.isRoad

    if not isRoad and not checkResult.isNatural then return end

    local percentage = isRoad and WDecay_Trees.getBasePercentageOnRoad() or WDecay_Trees.getBasePercentage()

    if WDecay_Scaling.scaleFor('nature', percentage) >= randomizer:random(1, 100) then
        if not WDecay_Placement.isSafe(square) then return false end
        return WDecay_Placement.createTagged(square, WDecay_Trees.getRandomTreeSprite(), "tree")
    end

    return false
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

if not WDecay_PlacementGenerators then WDecay_PlacementGenerators = {} end

table.insert(WDecay_PlacementGenerators, LoadGridsquare)

Events.EveryDays.Add(WDecay_Trees.resetCaches)

return WDecay_Trees
