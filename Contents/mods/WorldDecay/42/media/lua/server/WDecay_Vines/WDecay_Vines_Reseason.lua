-- Same idea as WDecay_Trees_Reseason.lua/WDecay_Bushes_Reseason.lua/
-- WDecay_Grass_Reseason.lua: vanilla's own erosion-tracked vines update their
-- sprite live as the season changes, but only for objects its private
-- simulation is tracking. This gives our own already-placed vines the same
-- live behavior: checked every ten minutes (matching vanilla's own
-- ErosionMain.EveryTenMinutes() rate), but the actual sweep only runs when
-- season or snow has actually changed since the last check. The sweep itself
-- covers every chunk currently loaded (see wdecay_loaded_chunks.lua), not a
-- guessed radius -- see WDecay_Trees_Reseason.lua for why. This also fixes
-- vines' multi-floor coverage for free: chunk-based iteration walks a
-- chunk's real min/max level, rather than the old fixed z-offset guess.
--
-- Unlike the other three, vines aren't a standalone object at all --
-- f_wallvines_1_* is WallOverlay-flagged in vanilla's tile definitions, so
-- WDecay_Vines_Generator.lua applies it as an overlay on the host wall/fence
-- via setOverlaySprite(), not a new IsoObject. There's no "WDecay_Cleanable"
-- tag to look for (a modData tag can't land on an object that never gets
-- created), so this checks every object's overlay sprite directly instead --
-- same approach WDecay_CleanVegetation already uses for vine cleanup. A
-- vine's frame alone fully determines its (stage, variety), same as trees.

local WDecay_Vines = require('WDecay_Vines/WDecay_Vines')
local WDecay_Season = require('wdecay_season/wdecay_season')
local WDecay_CleanVegetation = require('wdecay_cleanvegetation/wdecay_cleanvegetation')
local WDecay_LoadedChunks = require('wdecay_loaded_chunks/wdecay_loaded_chunks')

local function parseVineFrame(spriteName)
    local prefix = WDecay_Vines.SPRITE_PREFIX
    if not spriteName or spriteName:sub(1, #prefix) ~= prefix then return nil end

    local frame = tonumber(spriteName:sub(#prefix + 1))
    if not frame then return nil end

    local stage = math.floor((frame % 24) / 6)
    local variety = frame % 6
    return stage, variety
end

-- Returns true if the object actually had one of our vine overlays.
local function reseasonVine(object)
    local overlayName = WDecay_CleanVegetation.getOverlaySpriteName(object)
    local stage, variety = parseVineFrame(overlayName)
    if not stage then return false end

    local desired = WDecay_Vines.spriteName(WDecay_Vines.getCurrentSeasonIndex(), stage, variety)
    if desired == overlayName then return true end

    object:setOverlaySprite(desired, 1.0, 1.0, 1.0, 1.0)
    object:transmitUpdatedSpriteToClients()

    return true
end

-- Shared by both the periodic radius sweep and the chunk-load hook below.
-- Returns evaluated, changed counts.
local function reseasonSquare(square)
    local objects = square and square:getObjects()
    if not objects then return 0, 0 end

    local evaluated, changed = 0, 0

    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object then
            local before = WDecay_CleanVegetation.getOverlaySpriteName(object)
            if reseasonVine(object) then
                evaluated = evaluated + 1
                if WDecay_CleanVegetation.getOverlaySpriteName(object) ~= before then
                    changed = changed + 1
                end
            end
        end
    end

    return evaluated, changed
end

-- Used both standalone (chunk-load hook) and as the per-chunk unit of the
-- full sweep below. Returns evaluated, changed counts.
local function reseasonChunk(chunk)
    if not chunk then return 0, 0 end

    local evaluated, changed = 0, 0
    for z = chunk:getMinLevel(), chunk:getMaxLevel() do
        for cx = 0, 7 do
            for cy = 0, 7 do
                local sqEvaluated, sqChanged = reseasonSquare(chunk:getGridSquare(cx, cy, z))
                evaluated = evaluated + sqEvaluated
                changed = changed + sqChanged
            end
        end
    end
    return evaluated, changed
end

Events.LoadChunk.Add(reseasonChunk)

local warnedMissingLoadedChunks = false

local function reseasonAllLoadedChunks()
    if not (WDecay_LoadedChunks and WDecay_LoadedChunks.forEachLoadedChunk) then
        -- require() can fail on a brand-new shared module until the game is
        -- fully restarted (not just a save reload) -- don't let that turn
        -- into a repeating exception every ten minutes.
        if not warnedMissingLoadedChunks then
            warnedMissingLoadedChunks = true
            print("[WorldDecay] WDecay_LoadedChunks not available (requires a full game restart after this update)")
        end
        return 0, 0
    end

    local totalEvaluated, totalChanged = 0, 0
    WDecay_LoadedChunks.forEachLoadedChunk(function(chunk)
        local evaluated, changed = reseasonChunk(chunk)
        totalEvaluated = totalEvaluated + evaluated
        totalChanged = totalChanged + changed
    end)
    return totalEvaluated, totalChanged
end

local lastSeasonValue, lastSnow, firstCheck = nil, nil, true

local function checkAndReseason()
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

-- Manual trigger for testing, same pattern as WD_DebugTools.reseasonNearbyTrees/Bushes/Grass.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyVines()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Vine reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
