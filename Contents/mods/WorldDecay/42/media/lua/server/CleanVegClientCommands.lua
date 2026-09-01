require('luautils')
local WDecay_CleanVegetation = require('wdecay_cleanvegetation/wdecay_cleanvegetation')
local WDecay_Season = require('wdecay_season/wdecay_season')

local SEASONAL_DEBUG_MODULE = "WDecaySeasonalDebug"

local REMOVABLE_MARKER_TYPES = {
    grass = true,
    bush = true,
    trash = true,
    vine = true,
    indoorGrass = true
}

local function hasContainer(object)
    local container = nil

    pcall(function()
        container = object:getContainer()
    end)

    return container ~= nil
end

local function removeCleanableDecorations(object)
    if not object then
        return false
    end

    local changed = false
    local attached = object:getAttachedAnimSprite()

    if attached then
        for i = attached:size() - 1, 0, -1 do
            local anim = attached:get(i)
            local name = WDecay_CleanVegetation.getAttachedSpriteName(anim)

            if WDecay_CleanVegetation.isCleanableDecorationSpriteName(name) then
                object:RemoveAttachedAnim(i)
                changed = true
            end
        end
    end

    local overlayName = WDecay_CleanVegetation.getOverlaySpriteName(object)

    if WDecay_CleanVegetation.isCleanableDecorationSpriteName(overlayName) then
        object:setOverlaySprite(nil, -1.0, -1.0, -1.0, -1.0, true)
        changed = true
    end

    if changed then
        object:transmitUpdatedSpriteToClients()
    end

    local modData = object:getModData()

    if modData and modData["WDecay_OverlayApplied"] ~= nil then
        modData["WDecay_OverlayApplied"] = nil
        object:transmitModData()
    end

    return changed
end

local function isSpecialObject(square, object)
    local specialObjects = square:getSpecialObjects()

    if not specialObjects then
        return false
    end

    for i = 0, specialObjects:size() - 1 do
        if specialObjects:get(i) == object then
            return true
        end
    end

    return false
end

local function tryCleanObject(square, object)
    if not object then
        return false
    end

    if hasContainer(object) then
        return false
    end

    local changed = removeCleanableDecorations(object)

    if isSpecialObject(square, object) then
        return changed
    end

    local modData = object:getModData()
    local cleanableType = modData and modData["WDecay_Cleanable"]

    if object ~= square:getFloor() and WDecay_CleanVegetation.isCleanableMainObject(object) then
        square:transmitRemoveItemFromSquare(object)

        return true
    end

    if REMOVABLE_MARKER_TYPES[cleanableType] then
        modData["WDecay_Cleanable"] = nil
        object:transmitModData()
    end

    return changed
end

function WDecay_CleanSquare(square)
    if not square then
        return false
    end

    local changed = false
    local floor = square:getFloor()

    if floor and removeCleanableDecorations(floor) then
        changed = true
    end

    local objects = square:getObjects()

    if objects then
        for i = objects:size() - 1, 0, -1 do
            if tryCleanObject(square, objects:get(i)) then
                changed = true
            end
        end
    end

    local specialObjects = square:getSpecialObjects()

    if specialObjects then
        for i = specialObjects:size() - 1, 0, -1 do
            local object = specialObjects:get(i)

            if object and object:getObjectIndex() ~= -1 and tryCleanObject(square, object) then
                changed = true
            end
        end
    end

    square:getModData()["WDecay_cleaned"] = true
    square:setOverlayDone(true)
    square:RecalcAllWithNeighbours(true)

    return changed
end

local function validCoordinate(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value == math.floor(value)
end

local function isReachable(player, square)
    if not player or not square or player:getZ() ~= square:getZ() then
        return false
    end

    local playerSquare = player:getSquare()

    if not playerSquare then
        return false
    end

    local dx = math.abs(playerSquare:getX() - square:getX())
    local dy = math.abs(playerSquare:getY() - square:getY())

    if dx > 1 or dy > 1 then
        return false
    end

    if dx == 0 and dy == 0 then
        return true
    end

    return not playerSquare:isBlockedTo(square)
end

local function onCleanVegCommand(module, command, player, args)
    if module ~= "CleanVeg" or command ~= "CleanVegCommand" or type(args) ~= "table" then
        return
    end

    local x = args.x
    local y = args.y
    local z = args.z

    if not validCoordinate(x) or not validCoordinate(y) or not validCoordinate(z) then
        return
    end

    local square = getCell():getGridSquare(x, y, z)

    if square and isReachable(player, square) then
        WDecay_CleanSquare(square)
    end
end

local function advanceSeasonalDebugMonth()
    local gameTime = getGameTime()
    if not gameTime then return end

    gameTime:setMonth(gameTime:getMonth() + 1)
    if gameTime:getMonth() >= 12 then
        gameTime:setMonth(0)
        gameTime:setYear(gameTime:getYear() + 1)
    end

    WDecay_Season.invalidateCache()
    print("[WorldDecay Debug] Advanced to month " .. (gameTime:getMonth() + 1) .. "/" .. gameTime:getYear())
end

-- Seasonal debug actions originate in the client context menu, but the
-- vegetation objects are server-owned in both hosted SP and MP. Always route
-- these actions through OnClientCommand so a dedicated server does the actual
-- sweep and transmits the sprite/overlay changes to every client.
local function onSeasonalDebugCommand(module, command, player, args)
    if module ~= SEASONAL_DEBUG_MODULE or command ~= "Run" or type(args) ~= "table" then
        return
    end

    local action = args.action
    if action == "advanceMonth" then
        advanceSeasonalDebugMonth()
        return
    end

    local debugFunctions = {
        trees = "reseasonNearbyTrees",
        bushes = "reseasonNearbyBushes",
        grass = "reseasonNearbyGrass",
        vines = "reseasonNearbyVines",
    }
    local functionName = debugFunctions[action]
    local debugFunction = functionName and WD_DebugTools and WD_DebugTools[functionName]
    if debugFunction then
        debugFunction()
    else
        print("[WorldDecay Debug] Seasonal action unavailable on server: " .. tostring(action))
    end
end

Events.OnClientCommand.Add(onCleanVegCommand)
Events.OnClientCommand.Add(onSeasonalDebugCommand)
