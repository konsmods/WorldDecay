local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Season = require('wdecay_season/wdecay_season')
local WDecay_Placement = require('wdecay_placement/wdecay_placement')

local randomizer = WDecay_Random.get()

local WDecay_Grass = {}

WDecay_Grass.SPRITE_PREFIX = "e_newgrass_1_"

-- Ground truth from decompiling vanilla's NatureGeneric.init()/constructor
-- ("Grass" entry). Unlike trees/bushes, grass has no attached "child" sprite
-- and no snow swap-in (ErosionObjSprites registered with hasSnow=false for
-- Grass) -- its BASE sprite itself changes with season, because grass sets
-- noSeasonBase=false (trees/bushes set it true, which is why their trunk/base
-- never changes and only an attached child sprite does).
--   frame = (seasonValue-1)*24 + (2-stage)*8 + variety
-- stage (0-2) and variety (0-5) are just visual variety, picked randomly like
-- trees'/bushes' "column"; seasonValue is vanilla's real registered value --
-- 1=Spring, 2=Summer(early)/3=Summer(late), 4=Autumn(early)/5=Autumn(late),
-- 5=Winter. We collapse the Summer and Autumn splits for simplicity and use
-- 5 (the dry/yellow look) for all of Autumn, matching Winter exactly as
-- vanilla always does (its Autumn split does the same thing later in the
-- season -- we just apply it to the whole season rather than the back half).
local SEASON_NAME_TO_VALUE = { Spring = 1, Summer = 2, Autumn = 5, Winter = 5 }

function WDecay_Grass.spriteName(seasonValue, stage, variety)
    local frame = (seasonValue - 1) * 24 + (2 - stage) * 8 + variety
    return WDecay_Grass.SPRITE_PREFIX .. frame
end

function WDecay_Grass.getCurrentSeasonValue()
    local seasonName = WDecay_Season.getSeasonName()
    return (seasonName and SEASON_NAME_TO_VALUE[seasonName]) or 2
end

WDecay_Grass.MODDATA_STAGE = "WDecay_GrassStage"
WDecay_Grass.MODDATA_VARIETY = "WDecay_GrassVariety"

-- Returns spriteName, stage, variety. stage/variety are returned so callers
-- can store them in ModData for WDecay_Grass_Reseason.lua to recompute the
-- correct sprite later without guessing them back out of the frame number.
function WDecay_Grass.pickGrassSprite()
    local stage = randomizer:random(0, 2)
    local variety = randomizer:random(0, 5)
    local seasonValue = WDecay_Grass.getCurrentSeasonValue()
    return WDecay_Grass.spriteName(seasonValue, stage, variety), stage, variety
end

-- Centralizes spawn + ModData bookkeeping, same pattern as WDecay_Bushes.spawnBush.
function WDecay_Grass.spawnGrass(square, cleanableType)
    local sprite, stage, variety = WDecay_Grass.pickGrassSprite()
    local grass = WDecay_Placement.createTaggedObject(square, sprite, cleanableType or "grass")
    if not grass then return nil end

    local modData = grass:getModData()
    modData[WDecay_Grass.MODDATA_STAGE] = stage
    modData[WDecay_Grass.MODDATA_VARIETY] = variety

    return grass
end

local cachedBase = nil
function WDecay_Grass.getBasePercentage()
    if cachedBase == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.outdoorGrassPercentage')
        cachedBase = opt and opt:getValue() or 5
    end

    return cachedBase
end

local cachedBaseRoad = nil
function WDecay_Grass.getBasePercentageOnRoad()
    if cachedBaseRoad == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.outdoorGrassPercentageOnRoad')
        cachedBaseRoad = opt and opt:getValue() or 10
    end

    return cachedBaseRoad
end

local cachedIndoorBase = nil
function WDecay_Grass.getIndoorBasePercentage()
    if cachedIndoorBase == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.indoorGrassPercentage')
        cachedIndoorBase = opt and opt:getValue() or 10
    end

    return cachedIndoorBase
end

local cachedRoofBase = nil
function WDecay_Grass.getBasePercentageOnRoof()
    if cachedRoofBase == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.roofGrassPercentage')
        cachedRoofBase = opt and opt:getValue() or 0
    end

    return cachedRoofBase
end

function WDecay_Grass.resetCaches()
    cachedBase = nil
    cachedBaseRoad = nil
    cachedIndoorBase = nil
    cachedRoofBase = nil
end

return WDecay_Grass
