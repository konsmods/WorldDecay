-- Same idea as WDecay_Trees_Reseason.lua/WDecay_Bushes_Reseason.lua/
-- WDecay_Grass_Reseason.lua: vanilla's own erosion-tracked vines update their
-- sprite live as the season changes, but only for objects its private
-- simulation is tracking. This gives our own already-placed vines the same
-- live behavior: checked every ten minutes (matching vanilla's own
-- ErosionMain.EveryTenMinutes() rate), but the actual sweep only runs when
-- season or snow has actually changed since the last check. The sweep itself
-- covers a generous radius around every online player, probed level by level
-- from -2 to 7 (see wdecay_loaded_chunks.lua for why -- see
-- WDecay_Trees_Reseason.lua for the same rationale), which is what gives
-- vines their multi-floor coverage.
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
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Features = require('wdecay_features/wdecay_features')
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
-- full sweep below. Returns evaluated, changed counts. Bails immediately if
-- the chunk was never flagged urban -- vines only land on walls/fences, and
-- there's no dedicated placed-count for them (they're a wall/fence overlay,
-- not a standalone WDecay_Cleanable object), so WDecay_hasUrban is the best
-- available proxy for "no vines possible here."
local function reseasonChunk(chunk)
    if not chunk then return 0, 0 end

    local markerSquare = WDecay_LoadedChunks.getMarkerSquare(chunk)
    local markerData = markerSquare and markerSquare:getModData()
    if markerData and markerData["WDecay_hasUrban"] ~= true then
        return 0, 0
    end

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

local warnedMissingLoadedChunks = false

-- Used only by the manual debug trigger below -- the automatic sweep goes
-- through WDecay_LoadedChunks.registerReseasonCallback instead (see
-- registerIfEnabled), which walks every loaded square once for all modules.
local function reseasonAllLoadedChunks()
    if not (WDecay_LoadedChunks and WDecay_LoadedChunks.forEachLoadedSquare) then
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
    WDecay_LoadedChunks.forEachLoadedSquare(function(square)
        local evaluated, changed = reseasonSquare(square)
        totalEvaluated = totalEvaluated + evaluated
        totalChanged = totalChanged + changed
    end)
    return totalEvaluated, totalChanged
end

-- Only register the LoadChunk/full-sweep hooks if seasonal bias and vines
-- are both on -- otherwise there's nothing to reseason. Events.OnGameStart
-- is the readiness point WDecay_Dispatcher.lua's own config load relies on.
local registered = false
local function registerIfEnabled()
    if registered then return end
    if not (WDecay_Scaling.isSeasonalBiasEnabled() and WDecay_Features.isEnabled("vines")) then return end

    registered = true
    Events.LoadChunk.Add(reseasonChunk)
    WDecay_LoadedChunks.registerReseasonCallback(reseasonSquare)
end

Events.OnGameStart.Add(registerIfEnabled)

-- Manual trigger for testing, same pattern as WD_DebugTools.reseasonNearbyTrees/Bushes/Grass.
-- Always available regardless of the toggle above, same as
-- WD_DebugTools.generateSquare bypassing feature gating for manual testing.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyVines()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Vine reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
