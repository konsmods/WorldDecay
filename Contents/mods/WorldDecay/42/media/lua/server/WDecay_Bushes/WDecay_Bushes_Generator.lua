local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Placement = require('wdecay_placement/wdecay_placement')

local randomizer = WDecay_Random.get()

local TIME_KEY = "WDecay_Bushes-LoadGridsquare"

local WDecay_Bushes = require('WDecay_Bushes/WDecay_Bushes')
local WDecay_CustomNames_Integration = require('WDecay_CustomNames/WDecay_CustomNames_Integration')

local function LoadGridsquare(square, checkResult, level)
    if not square then return end

    if not checkResult then return end

    if checkResult.cleaned then return end

    if level ~= 0 and not checkResult.hasRoof then return end

    local percentage = 0
    if level ~= 0 and checkResult.hasRoof then
        percentage = WDecay_Bushes.getBasePercentageOnRoof()
    elseif checkResult.isIndoor then
        percentage = WDecay_Bushes.getIndoorBasePercentage()
    elseif checkResult.isRoad then
        percentage = WDecay_Bushes.getBasePercentageOnRoad()
    elseif checkResult.isNatural then
        percentage = WDecay_Bushes.getBasePercentage()
    end

    if percentage <= 0 then return end

    if WDecay_Scaling.scaleFor('nature', percentage) >= randomizer:random(1, 100) then
        if not WDecay_Placement.isSafe(square) then return false end
        return WDecay_Bushes.spawnBush(square) ~= nil
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

Events.EveryDays.Add(WDecay_Bushes.resetCaches)

return WDecay_Bushes
