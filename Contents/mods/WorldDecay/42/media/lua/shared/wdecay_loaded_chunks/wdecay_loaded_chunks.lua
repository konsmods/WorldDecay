-- Scans loaded squares around active players because the loaded-cell list is not Lua-exposed.
local WDecay_Season = require('wdecay_season/wdecay_season')

local WDecay_LoadedChunks = {}

local CHUNK_SIZE = 8
local DEFAULT_RADIUS_CHUNKS = 15
local PROBE_MIN_LEVEL = -2
local PROBE_MAX_LEVEL = 7

function WDecay_LoadedChunks.getMarkerSquare(chunk)
    if not chunk then return nil end
    for z = chunk:getMinLevel(), chunk:getMaxLevel() do
        local square = chunk:getGridSquare(0, 0, z)
        if square and square:getChunk() then return square end
    end
    return nil
end

local function getRadiusChunks()
    local sandbox = getSandboxOptions and getSandboxOptions()
    local option = sandbox and sandbox:getOptionByName('WDecay.scanRadius')
    local value = option and tonumber(option:getValue())
    if not value then return DEFAULT_RADIUS_CHUNKS end

    -- scanRadius is a half-width; 15 means a 31x31 chunk sweep.
    return math.max(1, math.floor(value))
end

-- Calls fn for loaded squares around local SP/host and online MP players.
function WDecay_LoadedChunks.forEachLoadedSquare(fn)
    local seenChunks = {}
    local radiusChunks = getRadiusChunks()

    local function scanPlayer(player)
        if not player then return end

        local originChunkX = math.floor(player:getX() / CHUNK_SIZE)
        local originChunkY = math.floor(player:getY() / CHUNK_SIZE)

        for ccx = originChunkX - radiusChunks, originChunkX + radiusChunks do
            for ccy = originChunkY - radiusChunks, originChunkY + radiusChunks do
                local key = ccx .. "," .. ccy
                if not seenChunks[key] then
                    seenChunks[key] = true
                    local originX = ccx * CHUNK_SIZE
                    local originY = ccy * CHUNK_SIZE

                    for z = PROBE_MIN_LEVEL, PROBE_MAX_LEVEL do
                        if getSquare(originX, originY, z) then
                            for sx = 0, CHUNK_SIZE - 1 do
                                for sy = 0, CHUNK_SIZE - 1 do
                                    local square = getSquare(originX + sx, originY + sy, z)
                                    if square then fn(square) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Include the local player because getOnlinePlayers may omit SP/host players.
    if getSpecificPlayer then
        scanPlayer(getSpecificPlayer(0))
    end

    local onlinePlayers = getOnlinePlayers()
    if onlinePlayers then
        for i = 0, onlinePlayers:size() - 1 do
            scanPlayer(onlinePlayers:get(i))
        end
    end
end

-- Registered callbacks share one loaded-square sweep.
local reseasonCallbacks = {}

function WDecay_LoadedChunks.registerReseasonCallback(fn)
    reseasonCallbacks[#reseasonCallbacks + 1] = fn
end

local function reseasonAllLoadedChunks()
    if #reseasonCallbacks == 0 then return 0, 0 end

    local totalEvaluated, totalChanged = 0, 0
    WDecay_LoadedChunks.forEachLoadedSquare(function(square)
        for i = 1, #reseasonCallbacks do
            local evaluated, changed = reseasonCallbacks[i](square)
            totalEvaluated = totalEvaluated + evaluated
            totalChanged = totalChanged + changed
        end
    end)
    return totalEvaluated, totalChanged
end

local lastSeasonValue, lastSnow, firstCheck = nil, nil, true

local function checkAndReseason()
    if #reseasonCallbacks == 0 then return end

    local seasonValue = WDecay_Season.getSeasonValue()
    local snow = WDecay_Season.isSnowing()
    if not firstCheck and seasonValue == lastSeasonValue and snow == lastSnow then
        return
    end

    firstCheck = false
    lastSeasonValue = seasonValue
    lastSnow = snow
    reseasonAllLoadedChunks()
end

Events.EveryTenMinutes.Add(checkAndReseason)

return WDecay_LoadedChunks
