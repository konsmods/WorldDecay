local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')

local randomizer = WDecay_Random.get()

local TIME_KEY = "WDecay_Barricades-LoadGridsquare"

local cachedBarricadePercentage = nil
local function getBarricadePercentage()
    if cachedBarricadePercentage == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.barricadePercentage')
        cachedBarricadePercentage = opt and opt:getValue() or 30
    end

    return cachedBarricadePercentage
end

local function resetCaches()
    cachedBarricadePercentage = nil
end

local function LoadGridsquare(square, checkResult, level)
    if not square then return end

    if not checkResult then return end

    if checkResult.cleaned then return end

    if not checkResult.hasWindow and not checkResult.hasDoor then return end

    if level ~= 0 then return end

    local barricadeAble = nil

    if checkResult.hasWindow then
        barricadeAble = square:getWindow()
    elseif checkResult.hasDoor then
        barricadeAble = square:getIsoDoor()
    end

    if barricadeAble then
        if not barricadeAble:isBarricaded() then
            if barricadeAble:isBarricadeAllowed() then
                local randNumber = randomizer:random(1, 100)
                if WDecay_Scaling.scaleFor('urban', getBarricadePercentage()) >= randNumber then

                    if checkResult.hasWindow and (randNumber % 2) == 0 then
                        barricadeAble:addBarricadesDebug(1, true)
                        barricadeAble:transmitCompleteItemToClients()
                    elseif checkResult.hasDoor or checkResult.hasWindow then
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

function WDecay_Barricades_ApplyToSquare(square, checkResult, level)
    LoadGridsquare(square, checkResult, level)
end

Events.EveryDays.Add(resetCaches)

return WDecay_Barricades
