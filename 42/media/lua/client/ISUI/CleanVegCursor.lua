local cachedDebugMode = nil
local WDecay_CleanVegetation = require('wdecay_cleanvegetation/wdecay_cleanvegetation')

require('Vehicles/TimedActions/ISPathFindAction')

local function isCleanDebug()
    if cachedDebugMode == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.debugMode')
        cachedDebugMode = opt and opt:getValue() or false
    end

    return cachedDebugMode
end

local function cleanLog(msg)
    if isCleanDebug() then
        print("[WDecay-Clean] " .. msg)
    end
end

if ISBuildingObject then
    CleanVegCursor = ISBuildingObject:derive("CleanVegCursor")
else
    CleanVegCursor = {}
end

local CLEAN_TIME = 75

local function singleTileClean(player, square)
    if luautils.walkAdj(player, square, true) then
        ISTimedActionQueue.add(CleanVegAction:new(player, square, CLEAN_TIME))
    end
end

local function closestSquareIndex(squares, x, y)
    local closestIndex = 1
    local closestDistance = math.huge

    for i, sq in ipairs(squares) do
        local dx = sq:getX() + 0.5 - x
        local dy = sq:getY() + 0.5 - y
        local distance = dx * dx + dy * dy

        if distance < closestDistance then
            closestIndex = i
            closestDistance = distance
        end
    end

    return closestIndex, closestDistance
end

local function orderSquaresByRoom(squares, player)
    local outsideRoom = {}
    local groupsByRoom = {}
    local groups = {}

    for _, sq in ipairs(squares) do
        if WDecay_CleanVegetation.hasCleanable(sq) then
            local room = sq:getRoom()
            local roomKey = room or outsideRoom
            local group = groupsByRoom[roomKey]

            if not group then
                group = { room = room, squares = {} }
                groupsByRoom[roomKey] = group
                groups[#groups + 1] = group
            end

            group.squares[#group.squares + 1] = sq
        end
    end

    local groupCount = #groups
    local ordered = {}
    local anchorX = player:getX()
    local anchorY = player:getY()

    while #groups > 0 do
        local closestGroupIndex = 1
        local closestGroupDistance = math.huge

        for groupIndex, group in ipairs(groups) do
            local _, distance = closestSquareIndex(group.squares, anchorX, anchorY)

            if distance < closestGroupDistance then
                closestGroupIndex = groupIndex
                closestGroupDistance = distance
            end
        end

        local group = table.remove(groups, closestGroupIndex)

        while #group.squares > 0 do
            local squareIndex = closestSquareIndex(group.squares, anchorX, anchorY)
            local sq = table.remove(group.squares, squareIndex)

            ordered[#ordered + 1] = sq
            anchorX = sq:getX() + 0.5
            anchorY = sq:getY() + 0.5
        end
    end

    return ordered, groupCount
end

local function areaClean(player, centerSquare, areaSize)
    local cell = getCell()
    local z = centerSquare:getZ()
    local cx = centerSquare:getX()
    local cy = centerSquare:getY()
    local half = math.floor(areaSize / 2)

    cleanLog("area clean started at " .. cx .. "," .. cy .. " areaSize=" .. tostring(areaSize))

    local squares = {}

    for dx = -half, half do
        for dy = -half, half do
            local sq = cell:getGridSquare(cx + dx, cy + dy, z)

            if sq then
                squares[#squares + 1] = sq
            end
        end
    end

    local roomGroupCount
    squares, roomGroupCount = orderSquaresByRoom(squares, player)
    cleanLog("area clean planned " .. #squares .. " tiles in " .. roomGroupCount .. " room groups")

    if #squares == 0 then
        return
    end

    local idx = 0

    local function nextTile()
        local sq = nil

        repeat
            idx = idx + 1

            if idx > #squares then
                cleanLog("CleanVegCursor area clean DONE")

                return
            end

            sq = squares[idx]
        until WDecay_CleanVegetation.hasCleanable(sq)

        local function skipRemainingRoom()
            local room = sq:getRoom()
            local skipped = 0

            while idx < #squares and squares[idx + 1]:getRoom() == room do
                idx = idx + 1
                skipped = skipped + 1
            end

            cleanLog("CleanVegCursor room unreachable, skipped " .. skipped .. " remaining tiles")
            nextTile()
        end

        local function queueClean()
            if not WDecay_CleanVegetation.hasCleanable(sq) then
                nextTile()

                return
            end

            cleanLog("CleanVegCursor sending server command to " .. sq:getX() .. "," .. sq:getY())

            local clean = CleanVegAction:new(player, sq, CLEAN_TIME)

            clean:setOnComplete(nextTile)
            ISTimedActionQueue.add(clean)
        end

        local playerSquare = player:getCurrentSquare()

        if playerSquare == sq then
            queueClean()

            return
        end

        local function queueAdjacentWalk()
            local adjacentWalk = ISPathFindAction:pathAdjacentToSquares(player, { sq }, false)

            if not adjacentWalk then
                adjacentWalk = ISPathFindAction:pathAdjacentToSquares(player, { sq }, true)
            end

            if not adjacentWalk then
                cleanLog("CleanVegCursor skipping inaccessible tile " .. sq:getX() .. "," .. sq:getY())
                nextTile()

                return
            end

            adjacentWalk:setOnComplete(queueClean)
            adjacentWalk:setOnFail(function()
                adjacentWalk:setRunActionsAfterFailing(true)

                local currentSquare = player:getCurrentSquare()

                if currentSquare and currentSquare:getRoom() ~= sq:getRoom() then
                    cleanLog("CleanVegCursor could not enter target room at " .. sq:getX() .. "," .. sq:getY())
                    skipRemainingRoom()
                else
                    cleanLog("CleanVegCursor adjacent path failed, skipping tile " .. sq:getX() .. "," .. sq:getY())
                    nextTile()
                end
            end)

            ISTimedActionQueue.add(adjacentWalk)
        end

        local exactWalk = ISPathFindAction:pathToLocationF(
            player,
            sq:getX() + 0.5,
            sq:getY() + 0.5,
            sq:getZ()
        )

        exactWalk:setOnComplete(queueClean)
        exactWalk:setOnFail(function()
            exactWalk:setRunActionsAfterFailing(true)
            cleanLog("CleanVegCursor center path failed, trying adjacent tile at " .. sq:getX() .. "," .. sq:getY())
            queueAdjacentWalk()
        end)

        ISTimedActionQueue.add(exactWalk)
    end

    nextTile()
end

function CleanVegCursor:create(x, y, z, north, sprite)
    local square = getWorld():getCell():getGridSquare(x, y, z)

    if not square then
        return
    end

    if self.areaSize then
        areaClean(self.character, square, self.areaSize)
    else
        singleTileClean(self.character, square)
    end
end

function CleanVegCursor.hasCleanable(square)
    cleanLog("hasCleanable called at " .. square:getX() .. "," .. square:getY())

    return WDecay_CleanVegetation.hasCleanable(square)
end

function CleanVegCursor.hasOverlay(square)
    return WDecay_CleanVegetation.hasCleanableDecorationOnSquare(square)
end

function CleanVegCursor:isValid(square)
    return CleanVegCursor.hasCleanable(square)
end

function CleanVegCursor:render(x, y, z, square)
    if not CleanVegCursor.floorSprite then
        CleanVegCursor.floorSprite = IsoSprite.new()
        CleanVegCursor.floorSprite:LoadFramesNoDirPageSimple('media/ui/FloorTileCursor.png')
    end

    if self.areaSize then
        local cell = getCell()
        local half = math.floor(self.areaSize / 2)
        local sx = square:getX()
        local sy = square:getY()

        for dx = -half, half do
            for dy = -half, half do
                local sq = cell:getGridSquare(sx + dx, sy + dy, z)

                if sq then
                    local r, g, b, a = 0.0, 1.0, 0.0, 0.6

                    if not CleanVegCursor.hasCleanable(sq) then
                        r, g, a = 1.0, 0.0, 0.3
                    end

                    CleanVegCursor.floorSprite:RenderGhostTileColor(sx + dx, sy + dy, z, r, g, b, a)
                end
            end
        end
    else
        local r, g, b, a = 0.0, 1.0, 0.0, 0.8

        if not CleanVegCursor.hasCleanable(square) then
            r, g = 1.0, 0.0
        end

        CleanVegCursor.floorSprite:RenderGhostTileColor(x, y, z, r, g, b, a)
    end
end

function CleanVegCursor:new(sprite, northSprite, character, areaSize)
    local o = {}

    setmetatable(o, self)

    self.__index = self
    o:init()
    o:setSprite(sprite)
    o:setNorthSprite(northSprite)
    o.character = character
    o.player = character:getPlayerNum()
    o.noNeedHammer = true
    o.skipBuildAction = true
    o.areaSize = areaSize

    return o
end
