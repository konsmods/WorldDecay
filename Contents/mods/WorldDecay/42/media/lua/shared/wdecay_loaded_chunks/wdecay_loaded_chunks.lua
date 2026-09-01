-- Originally tried to mirror vanilla's own ErosionMain.mainTimer() exactly,
-- which walks ServerMap.instance.loadedCells -- but ServerMap turns out to
-- NOT be a Lua-exposed class at all (confirmed by decompiling: no other class
-- in the game, including the Lua exposure list, references it), so
-- `ServerMap.instance` from Lua is just nil and indexing `.loadedCells` on it
-- throws "attempted index: instance of non-table: null".
--
-- IsoCell/IsoChunkMap looked like a substitute, but it's keyed by *local*
-- IsoPlayer.numPlayers (split-screen slots, not online player count), and
-- IsoCell.getGridSquare() only forwards to the real ServerMap.getGridSquare()
-- when GameServer.server is true -- IsoCell.getChunk() has no such branch, so
-- it can't be trusted to reflect real server-loaded state either.
--
-- getSquare(x, y, z) (the plain global every mod already uses) DOES have that
-- branch: on an actual server it calls straight through to
-- ServerMap.getGridSquare(), which is a passive lookup into the currently-
-- active ServerCell (verified via bytecode -- it returns nil rather than
-- forcing a chunk load), so it's safe to probe with at arbitrary coordinates.
-- We approximate "everything currently loaded" by sweeping a generous radius
-- around each online player instead of enumerating a server-internal list --
-- that's the same thing that determines what actually gets/stays loaded in
-- the first place.
local WDecay_Season = require('wdecay_season/wdecay_season')

local WDecay_LoadedChunks = {}

local CHUNK_SIZE = 10
local RADIUS_CHUNKS = 15 -- ~150 tiles around each player
local PROBE_MIN_LEVEL = -2
local PROBE_MAX_LEVEL = 7

-- Calls fn(square) once for every loaded square within range of any online
-- player. Skips a whole chunk x z-level slice with a single nil probe rather
-- than testing all 100 of its squares individually, since most of the swept
-- volume above/below ground level is empty.
function WDecay_LoadedChunks.forEachLoadedSquare(fn)
    local players = getOnlinePlayers()
    if not players then return end

    local seenChunks = {}

    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player then
            local originChunkX = math.floor(player:getX() / CHUNK_SIZE)
            local originChunkY = math.floor(player:getY() / CHUNK_SIZE)

            for ccx = originChunkX - RADIUS_CHUNKS, originChunkX + RADIUS_CHUNKS do
                for ccy = originChunkY - RADIUS_CHUNKS, originChunkY + RADIUS_CHUNKS do
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
    end
end

-- Shared by the dispatcher and the four WDecay_*_Reseason.lua modules for
-- their marker-based "does this chunk have any of our objects" checks.
function WDecay_LoadedChunks.getMarkerSquare(chunk)
    local square = chunk:getGridSquare(0, 0, 0)
    if square then return square end

    for z = chunk:getMinLevel(), chunk:getMaxLevel() do
        square = chunk:getGridSquare(0, 0, z)
        if square then return square end
    end

    return nil
end

-- The four WDecay_*_Reseason.lua modules each want a per-square seasonal
-- update check across every loaded square. Rather than each running its own
-- full forEachLoadedSquare() sweep (same squares, walked four times), they
-- register a callback here so the walk happens once for all of them.
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
