local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')

local TIME_KEY = "WDecay_Destroyed_Doors_Windows-LoadGridsquare"

local randomizer = WDecay_Random.get()

local cachedDestroyedDoorsPercentage = nil
local cachedDestroyedWindowsPercentage = nil
local function getDestroyedDoorsPercentage()
    if cachedDestroyedDoorsPercentage == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.destroyedDoorsPercentage')
        cachedDestroyedDoorsPercentage = opt and opt:getValue() or 30
    end

    return cachedDestroyedDoorsPercentage
end

local function getDestroyedWindowsPercentage()
    if cachedDestroyedWindowsPercentage == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.destroyedWindowsPercentage')
        cachedDestroyedWindowsPercentage = opt and opt:getValue() or 30
    end

    return cachedDestroyedWindowsPercentage
end

local function resetCaches()
    cachedDestroyedDoorsPercentage = nil
    cachedDestroyedWindowsPercentage = nil
end

local function LoadGridsquare(square, checkResult, level)
    if not square then return end

    if not checkResult then return end

    if checkResult.cleaned then return end

    local doorWindowObject = nil
    
    if checkResult.hasWindow then
        doorWindowObject = square:getWindow()
    elseif checkResult.hasDoor then
        doorWindowObject = square:getIsoDoor()
    end

    if doorWindowObject and not doorWindowObject:isBarricaded() then
        if checkResult.hasWindow and WDecay_Scaling.scaleFor('urban', getDestroyedWindowsPercentage()) >= randomizer:random(1, 100) then 
            doorWindowObject:smashWindow(false, false)
        elseif checkResult.hasDoor and WDecay_Scaling.scaleFor('urban', getDestroyedDoorsPercentage()) >= randomizer:random(1, 100) and not checkResult.hasWindow then
            -- ponytail: IsoDoor.destroy() no propaga a partes hermanas; skip multi-tile (garage y double doors)
            -- ceiling: las puertas de garaje/doble no se destruyen en el decay; upgrade: usar IsoDoor.destroyGarageDoor
            if IsoDoor.getGarageDoorIndex(doorWindowObject) == -1 and IsoDoor.getDoubleDoorIndex(doorWindowObject) == -1 then
                doorWindowObject:destroy()
            end
        end
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
if not WDecay_ModifierGeneratorFeatures then WDecay_ModifierGeneratorFeatures = {} end
WDecay_ModifierGeneratorFeatures[#WDecay_ModifierGenerators] = "destroyedDoorsWindows"

function WDecay_Destroyed_ApplyToSquare(square, checkResult, level)
    LoadGridsquare(square, checkResult, level)
end

Events.EveryDays.Add(resetCaches)
