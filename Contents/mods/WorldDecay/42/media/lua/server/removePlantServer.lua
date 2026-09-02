require "BuildingObjects/ISRemovePlantCursor"
local WDecay_CleanVegetation = require('wdecay_cleanvegetation/wdecay_cleanvegetation')

local cachedDebugMode = nil

local function isCleanDebug()
    if cachedDebugMode == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.debugMode')
        cachedDebugMode = opt and opt:getValue() or false
    end

    return cachedDebugMode
end

local IS_CAN_BE_CUT = IsoFlagType.canBeCut
local IS_CAN_BE_REMOVED = IsoFlagType.canBeRemoved

local function markCleaned(square)
    square:getModData()["WDecay_cleaned"] = true
    square:transmitModdata()
    square:flagForHotSave()
end

local function cleanLog(msg)
    if isCleanDebug() then
        print("[WDecay-Clean] " .. msg)
    end
end

local ISRemovePlantCursor_getRemovableObject = ISRemovePlantCursor.getRemovableObject

function ISRemovePlantCursor:getRemovableObject(square)
    local vanillaPass = ISRemovePlantCursor_getRemovableObject(self, square)

    if vanillaPass then
        return vanillaPass
    end

    local function findTagged(objects)
        if not objects then
            return nil
        end

        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            local modData = object and object:getModData()
            local cleanableType = modData and modData["WDecay_Cleanable"]

            if WDecay_CleanVegetation.isCleanableMainObject(object) then
                if self.removeType == "grass" and cleanableType == "grass" then
                    return object
                end

                if self.removeType == "bush" and (cleanableType == "bush" or cleanableType == "trash") then
                    return object
                end

                if self.removeType == "wallVine" and cleanableType == "vine" then
                    return object
                end
            end
        end

        return nil
    end

    return findTagged(square:getObjects()) or findTagged(square:getSpecialObjects())
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

local function hasContainer(object)
    local container = nil

    pcall(function()
        container = object:getContainer()
    end)

    return container ~= nil
end

local function removeUpperVine(square)
    local upper = getCell():getGridSquare(square:getX(), square:getY(), square:getZ() + 1)

    if not upper then
        return
    end

    local objects = upper:getObjects()

    if not objects then
        return
    end

    for i = objects:size() - 1, 0, -1 do
        local object = objects:get(i)
        local modData = object and object:getModData()

        if modData and modData["WDecay_Cleanable"] == "vine"
            and WDecay_CleanVegetation.isWallVineObject(object) then
            if not hasContainer(object) then
                upper:transmitRemoveItemFromSquare(object)
                markCleaned(upper)
            end

            return
        end
    end
end

local function matchesTagged(object, command)
    if not object or hasContainer(object) then
        return false
    end

    if not WDecay_CleanVegetation.isCleanableMainObject(object) then
        return false
    end

    local modData = object:getModData()
    local cleanableType = modData and modData["WDecay_Cleanable"]

    return command == "canBeRemoved" and cleanableType == "grass"
        or command == "canBeCut" and (cleanableType == "bush" or cleanableType == "trash" or cleanableType == "vine")
end

local function hasFlag(object, flag)
    if not object then
        return false
    end

    local sprite = object:getSprite()
    local properties = sprite and sprite:getProperties()

    if properties and properties:has(flag) then
        return true
    end

    local attached = object:getAttachedAnimSprite()

    if attached then
        for i = 0, attached:size() - 1 do
            local anim = attached:get(i)
            local parent = anim and anim:getParentSprite()
            local parentProperties = parent and parent:getProperties()

            if parentProperties and parentProperties:has(flag) then
                return true
            end
        end
    end

    return false
end

local function inspectList(objects, command, result)
    if not objects then
        return
    end

    local flag = command == "canBeCut" and IS_CAN_BE_CUT or IS_CAN_BE_REMOVED

    for i = 0, objects:size() - 1 do
        local object = objects:get(i)

        if hasFlag(object, flag) then
            result.vanilla = true
        end

        if matchesTagged(object, command) then
            result.count = result.count + 1
            result.object = object
        end
    end
end

local function removeUniqueTagged(square, command)
    local result = { count = 0, object = nil, vanilla = false }

    inspectList(square:getObjects(), command, result)
    inspectList(square:getSpecialObjects(), command, result)

    if result.vanilla or result.count ~= 1 then
        return false
    end

    local object = result.object
    local cleanableType = object:getModData()["WDecay_Cleanable"]

    square:transmitRemoveItemFromSquare(object)

    if cleanableType == "vine" then
        removeUpperVine(square)
    end

    return true
end

local function onRemovePlantCommand(module, command, player, args)
    if module ~= "onRemovePlant" or command ~= "canBeCut" and command ~= "canBeRemoved" or type(args) ~= "table" then
        return
    end

    local x = args.x
    local y = args.y
    local z = args.z

    if not validCoordinate(x) or not validCoordinate(y) or not validCoordinate(z) then
        return
    end

    local square = getCell():getGridSquare(x, y, z)

    if not square or not isReachable(player, square) then
        return
    end

    if removeUniqueTagged(square, command) then
        markCleaned(square)
    end
end

Events.OnClientCommand.Add(onRemovePlantCommand)
