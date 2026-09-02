local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Protection = require('wdecay_protection/wdecay_protection')

local randomizer = WDecay_Random.get()

local TIME_KEY = "WDecay_Barricades-LoadGridsquare"

local cachedBarricadePercentage = nil
local cachedWoodMultiplier = nil
local cachedMetalMultiplier = nil
local function getBarricadePercentage()
    if cachedBarricadePercentage == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.barricadePercentage')
        cachedBarricadePercentage = opt and opt:getValue() or 30
    end

    return cachedBarricadePercentage
end

local function getBarricadeTypeMultiplier(key, fallback)
    local opt = getSandboxOptions():getOptionByName('WDecay.' .. key)
    return opt and opt:getValue() or fallback
end

local function getWoodMultiplier()
    if cachedWoodMultiplier == nil then
        cachedWoodMultiplier = getBarricadeTypeMultiplier('woodBarricadeMultiplier', 100)
    end
    return cachedWoodMultiplier
end

local function getMetalMultiplier()
    if cachedMetalMultiplier == nil then
        cachedMetalMultiplier = getBarricadeTypeMultiplier('metalBarricadeMultiplier', 100)
    end
    return cachedMetalMultiplier
end

local function pickMetalBarricade()
    local wood = math.max(0, getWoodMultiplier())
    local metal = math.max(0, getMetalMultiplier())
    if wood + metal <= 0 then return false end
    return randomizer:random(1, wood + metal) > wood
end

local function resetCaches()
    cachedBarricadePercentage = nil
    cachedWoodMultiplier = nil
    cachedMetalMultiplier = nil
end

local function LoadGridsquare(square, checkResult, level)
    if not square then return end

    if not checkResult then return end

    if checkResult.cleaned and not WDecay_Scaling.isRedecayPass() then return end

    if not checkResult.hasWindow and not checkResult.hasDoor then return end

    if level ~= 0 then return end

    local barricadeAble = nil

    if checkResult.hasWindow then
        barricadeAble = square:getWindow()
    elseif checkResult.hasDoor then
        barricadeAble = square:getIsoDoor()
    end

    if barricadeAble and (not WDecay_Protection.isPlayerBuilt(barricadeAble) or WDecay_Scaling.isRedecayPass()) then
        if not barricadeAble:isBarricaded() then
            if barricadeAble:isBarricadeAllowed() then
                local randNumber = randomizer:random(1, 100)
                if WDecay_Scaling.scaleFor('urban', getBarricadePercentage()) >= randNumber then

                    if checkResult.hasWindow then
                        local count = randomizer:random(1, 4)
                        barricadeAble:addBarricadesDebug(count, pickMetalBarricade())
                        barricadeAble:transmitCompleteItemToClients()
                    elseif checkResult.hasDoor then
                        -- IsoDoor does not expose addBarricadesDebug in B42.
                        -- Keep the vanilla path for doors.
                        barricadeAble:addRandomBarricades()
                    end
                end
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
WDecay_ModifierGeneratorFeatures[#WDecay_ModifierGenerators] = "barricades"

function WDecay_Barricades_ApplyToSquare(square, checkResult, level)
    LoadGridsquare(square, checkResult, level)
end

Events.EveryDays.Add(resetCaches)

return WDecay_Barricades
