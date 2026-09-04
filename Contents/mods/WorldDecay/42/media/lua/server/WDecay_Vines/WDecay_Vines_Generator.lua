local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require("wdecay_random/wdecay_random")
local WDecay_Scaling = require("wdecay_scaling/wdecay_scaling")
local WDecay_CleanVegetation = require("wdecay_cleanvegetation/wdecay_cleanvegetation")
local WDecay_Vines = require("WDecay_Vines/WDecay_Vines")
local WDecay_Vines_SpriteRules = require("WDecay_Vines/WDecay_Vines_SpriteRules")
local WDecay_Protection = require("wdecay_protection/wdecay_protection")

local PROP_FENCE_LOW = IsoPropertyType.lookup("FenceTypeLow")
local PROP_WALL_NW = IsoPropertyType.lookup("WallNW")
local PROP_ATTACHED_NW = IsoPropertyType.lookup("attachedNW")
local PROP_WALL_W = IsoPropertyType.lookup("WallW")
local PROP_WINDOW_W = IsoPropertyType.lookup("WindowW")
local PROP_DOOR_W = IsoPropertyType.lookup("doorW")
local PROP_DOOR_WALL_W = IsoPropertyType.lookup("DoorWallW")
local PROP_ATTACHED_W = IsoPropertyType.lookup("attachedW")
local PROP_WALL_W_TRANS = IsoPropertyType.lookup("WallWTrans")
local PROP_ATTACHED_E = IsoPropertyType.lookup("attachedE")
local PROP_WALL_N = IsoPropertyType.lookup("WallN")
local PROP_WINDOW_N = IsoPropertyType.lookup("WindowN")
local PROP_DOOR_N = IsoPropertyType.lookup("doorN")
local PROP_DOOR_WALL_N = IsoPropertyType.lookup("DoorWallN")
local PROP_WALL_N_TRANS = IsoPropertyType.lookup("WallNTrans")
local PROP_ATTACHED_N = IsoPropertyType.lookup("attachedN")
local PROP_ATTACHED_S = IsoPropertyType.lookup("attachedS")

local SPRITE_FENCE = "fence"
local SPRITE_FENCING = "fencing_"
local TIME_KEY = "WDecay_Vines-LoadGridsquare"
local randomizer = WDecay_Random.get()
local cached = {}

local function option(name, fallback)
    if cached[name] == nil then
        local setting = getSandboxOptions():getOptionByName("WDecay." .. name)
        cached[name] = setting and setting:getValue()
        if cached[name] == nil then cached[name] = fallback end
    end
    return cached[name]
end

local function getFence(objects)
    if not objects then return nil end
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local spriteName = object and object:getSpriteName()
        if object and ((spriteName and (spriteName:contains(SPRITE_FENCE) or spriteName:contains(SPRITE_FENCING))) or object:isHoppable()) then
            return object
        end
    end
end

-- WallOverlay sprites are applied to their existing wall/fence object, so
-- duplicate detection must inspect overlay sprites instead of modData.
local function squareHasVine(square, objects)
    if not square then return true end
    objects = objects or square:getObjects()
    if not objects then return false end
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object and WDecay_Vines.isVine(WDecay_CleanVegetation.getOverlaySpriteName(object)) then
            return true
        end
    end
    return false
end

local function squareHasBlacklistedSprite(objects)
    if not objects then return false end
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object and WDecay_Vines_SpriteRules.matches(object:getSpriteName(), WDecay_Vines_SpriteRules.skipSquare) then
            return true
        end
    end
    return false
end

local function createVine(square, object, isLow, objects)
    if not square or not object then return end
    if WDecay_Protection.isPlayerBuilt(object) and not WDecay_Scaling.isRedecayPass() then return end
    if squareHasVine(square, objects) then return end

    local spriteName = object:getSpriteName()
    if WDecay_Vines_SpriteRules.matches(spriteName, WDecay_Vines_SpriteRules.skip) then return end
    if WDecay_Vines_SpriteRules.matches(spriteName, WDecay_Vines_SpriteRules.forceLow) then isLow = true end

    local properties = object:getProperties()
    if not properties then return end

    local direction
    if properties:has(PROP_WALL_NW, PROP_ATTACHED_NW) then
        direction = "NW"
    elseif properties:has(PROP_WALL_N, PROP_WINDOW_N, PROP_DOOR_N, PROP_DOOR_WALL_N, PROP_WALL_N_TRANS, PROP_ATTACHED_N, PROP_ATTACHED_S) then
        direction = "N"
    elseif properties:has(PROP_WALL_W, PROP_WINDOW_W, PROP_DOOR_W, PROP_DOOR_WALL_W, PROP_ATTACHED_W, PROP_WALL_W_TRANS, PROP_ATTACHED_E) then
        direction = "W"
    else
        return
    end

    local tier = "low"
    if not isLow then
        local squareAbove = square:getSquareAbove()
        local hasAbove = square:getZ() == 0 or (squareAbove and squareAbove:getWall())
        tier = hasAbove and "full" or "top"
    end

    local vineSprite = WDecay_Vines.pickSprite(direction, tier)
    if vineSprite then
        object:setOverlaySprite(vineSprite, 1.0, 1.0, 1.0, 1.0)
        object:transmitUpdatedSpriteToClients()
        if WDecay_DebugCountTransmission then WDecay_DebugCountTransmission("overlay") end
    end
end

local function applyVines(square, checkResult, level, requireCheckResult)
    if not square or (requireCheckResult and not checkResult) then return end
    if checkResult and checkResult.cleaned then return end
    if not option("multiFloorVines", true) and level ~= 0 then return end
    if option("vinesExteriorOnly", true) and checkResult and checkResult.isIndoor then return end
    if WDecay_Scaling.scaleFor("nature", option("vinePercentage", 40)) < randomizer:random(1, 100) then return end

    local objects
    if requireCheckResult then
        objects = checkResult.objects or (checkResult.wall and square:getObjects())
    else
        objects = (checkResult and checkResult.objects) or square:getObjects()
    end
    if squareHasBlacklistedSprite(objects or square:getObjects()) then return end

    if square:hasFence() and option("vinesOnFences", true) then
        local fence = getFence(objects)
        if fence then
            local properties = fence:getProperties()
            createVine(square, fence, properties and properties:has(PROP_FENCE_LOW), objects)
        end
    end

    if checkResult and checkResult.wall and option("vinesOnWalls", true) then
        createVine(square, checkResult.wall, false, objects)
    end
end

local function loadGridSquare(square, checkResult, level)
    return applyVines(square, checkResult, level, true)
end

local function debugLoadGridSquare(square, checkResult, level)
    WD_Debug_Metric.startTimeMeasurement(TIME_KEY)
    local result = loadGridSquare(square, checkResult, level)
    WD_Debug_Metric.endTimeMeasurement(TIME_KEY)
    return result
end

local generator = isDebugEnabled() and debugLoadGridSquare or loadGridSquare
WDecay_ModifierGenerators = WDecay_ModifierGenerators or {}
WDecay_ModifierGeneratorFeatures = WDecay_ModifierGeneratorFeatures or {}
table.insert(WDecay_ModifierGenerators, generator)
WDecay_ModifierGeneratorFeatures[#WDecay_ModifierGenerators] = "vines"

function WDecay_Vines_ApplyToSquare(square, checkResult, level)
    return applyVines(square, checkResult, level, false)
end

Events.EveryDays.Add(function()
    cached = {}
end)

return WDecay_Vines
