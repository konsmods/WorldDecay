local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Protection = require('wdecay_protection/wdecay_protection')

local TIME_KEY = "WDecay_Walls-LoadGridsquare"

local randomizer = WDecay_Random.get()

local WDecay_Walls = require('WDecay_Walls/WDecay_Walls')

local cachedWallPercentage = nil
local function getWallPercentage()
    if cachedWallPercentage == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.wallPercentage')
        cachedWallPercentage = opt and opt:getValue() or 10
    end

    return cachedWallPercentage
end

local function resetCaches()
    cachedWallPercentage = nil
end

local function LoadGridsquare(square, checkResult, level)
    if not square then return end

    if not checkResult then return end

    if checkResult.cleaned and not WDecay_Scaling.isRedecayPass() then return end

    if not checkResult.room then return end

    if level ~= 0 then return end

    if not checkResult.hasWalls then return end

    local objects = checkResult.objects
    if not objects then return end

    local objectCount = objects:size()
    if objectCount == 0 then return end

    local wallPercentage = WDecay_Scaling.scaleFor('urban', getWallPercentage())
    if wallPercentage <= 0 then return end

    for i = 0, objectCount - 1 do
        local obj = objects:get(i)
        if obj then
            local sprite = obj:getSprite()
            if sprite then
                local textureName = obj:getTextureName()

                if textureName and
                    (WDecay_Walls.isExteriorWall(textureName) or WDecay_Walls.isInteriorWall(textureName))
                    and (not WDecay_Protection.isPlayerBuilt(obj) or WDecay_Scaling.isRedecayPass()) then
                    if wallPercentage >= randomizer:random(1, 100) then
                        local properties = sprite:getProperties()
                        if properties then
                            if not (properties:has("DoorWallN") or properties:has("DoorWallW") or
                                properties:has("WindowN") or properties:has("WindowW")) then

                                for _, prop in ipairs(WDecay_Walls.wallProperties) do
                                    if properties:has(prop) then
                                        local burnedTextures = WDecay_Walls.getBurnedTextures(prop)
                                        if burnedTextures and #burnedTextures > 0 then
                                            local randomTexture = burnedTextures[randomizer:random(1, #burnedTextures)]

                                            if randomTexture ~= textureName then
                                                obj:setSpriteFromName(randomTexture)

                                                local objModData = obj:getModData()
                                                if objModData and not objModData["WDecay_Cleanable"] then
                                                    objModData["WDecay_Cleanable"] = "wall"
                                                end

                                                obj:transmitUpdatedSpriteToClients()
                                            end

                                            break
                                        end
                                    end
                                end
                            end
                        end
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
WDecay_ModifierGeneratorFeatures[#WDecay_ModifierGenerators] = "walls"

function WDecay_Walls_ApplyToSquare(square, checkResult, level)
    LoadGridsquare(square, checkResult, level)
end

Events.EveryDays.Add(resetCaches)

return WDecay_Walls
