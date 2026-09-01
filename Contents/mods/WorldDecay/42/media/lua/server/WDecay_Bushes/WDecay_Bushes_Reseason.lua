-- Same idea as WDecay_Trees_Reseason.lua: vanilla's own erosion-tracked bushes
-- update their sprite live as the season changes, but only for objects its
-- private simulation is tracking -- there's no hook to register an externally
-- spawned bush into it. This gives our own already-placed bushes the same
-- live behavior: checked every ten minutes (matching vanilla's own
-- ErosionMain.EveryTenMinutes() rate), but the actual sweep only runs when
-- season or snow has actually changed since the last check. The sweep itself
-- covers a generous radius around every online player (see
-- wdecay_loaded_chunks.lua for why -- see WDecay_Trees_Reseason.lua for the
-- same rationale).
--
-- Bushes store their (id, stage) in ModData at spawn time (WDecay_Bushes.lua),
-- unlike trees which reverse-parse their sprite name -- a bush sprite name
-- alone doesn't uniquely identify its species since id%8 wraps every 8 species.

local WDecay_Bushes = require('WDecay_Bushes/WDecay_Bushes')
local WDecay_Season = require('wdecay_season/wdecay_season')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Features = require('wdecay_features/wdecay_features')
local WDecay_CleanVegetation = require('wdecay_cleanvegetation/wdecay_cleanvegetation')
local WDecay_LoadedChunks = require('wdecay_loaded_chunks/wdecay_loaded_chunks')

local function currentAttachedSpriteNames(object)
    local attached = object:getAttachedAnimSprite()
    if not attached then return {} end

    local names = {}
    for i = 0, attached:size() - 1 do
        names[#names + 1] = WDecay_CleanVegetation.getAttachedSpriteName(attached:get(i))
    end
    return names
end

local function sameSet(listA, listB)
    if #listA ~= #listB then return false end
    local counts = {}
    for _, name in ipairs(listA) do counts[name] = (counts[name] or 0) + 1 end
    for _, name in ipairs(listB) do counts[name] = (counts[name] or 0) - 1 end
    for _, count in pairs(counts) do
        if count ~= 0 then return false end
    end
    return true
end

-- Returns true if the bush was actually one of ours we could evaluate.
local function reseasonBush(object)
    local modData = object:getModData()
    local id = modData[WDecay_Bushes.MODDATA_ID]
    local stage = modData[WDecay_Bushes.MODDATA_STAGE]
    if id == nil or stage == nil then return false end

    local species = WDecay_Bushes.getSpeciesById(id)
    if not species then return false end

    local desiredBase, desiredChild, desiredFlower = WDecay_Bushes.spritesFor(species, stage)

    local desired = {}
    if desiredChild then desired[#desired + 1] = desiredChild end
    if desiredFlower then desired[#desired + 1] = desiredFlower end

    local spriteName = object:getSpriteName()
    local haveAttached = currentAttachedSpriteNames(object)

    if desiredBase == spriteName and sameSet(desired, haveAttached) then
        return true
    end

    if desiredBase ~= spriteName then
        local sprite = getSprite(desiredBase)
        if sprite then object:setSprite(sprite) end
    end

    if not sameSet(desired, haveAttached) then
        object:clearAttachedAnimSprite()
        for _, name in ipairs(desired) do
            if getSprite(name) then
                object:addAttachedAnimSpriteByName(name)
            end
        end
    end

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
        if object and object:hasModData() and object:getModData()["WDecay_Cleanable"] == "bush" then
            local before = object:getSpriteName()
            if reseasonBush(object) then
                evaluated = evaluated + 1
                if object:getSpriteName() ~= before then changed = changed + 1 end
            end
        end
    end

    return evaluated, changed
end

-- Used both standalone (chunk-load hook) and as the per-chunk unit of the
-- full sweep below. Returns evaluated, changed counts. Bails immediately if
-- the chunk never placed a bush, rather than walking all ~512 squares to
-- find nothing every time this chunk streams back in.
local function reseasonChunk(chunk)
    if not chunk then return 0, 0 end

    local markerSquare = WDecay_LoadedChunks.getMarkerSquare(chunk)
    local markerData = markerSquare and markerSquare:getModData()
    if markerData then
        local placed = (markerData["WDecay_placedBushesNatural"] or 0)
            + (markerData["WDecay_placedBushesRoad"] or 0)
            + (markerData["WDecay_placedBushesIndoor"] or 0)
        if placed <= 0 then return 0, 0 end
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

-- Only register the LoadChunk/full-sweep hooks if seasonal bias and bushes
-- are both on -- otherwise there's nothing to reseason. Events.OnGameStart
-- is the readiness point WDecay_Dispatcher.lua's own config load relies on.
local registered = false
local function registerIfEnabled()
    if registered then return end
    if not (WDecay_Scaling.isSeasonalBiasEnabled() and WDecay_Features.isEnabled("bushes")) then return end

    registered = true
    Events.LoadChunk.Add(reseasonChunk)
    WDecay_LoadedChunks.registerReseasonCallback(reseasonSquare)
end

Events.OnGameStart.Add(registerIfEnabled)

-- Manual trigger for testing, same pattern as WD_DebugTools.reseasonNearbyTrees.
-- Always available regardless of the toggle above, same as
-- WD_DebugTools.generateSquare bypassing feature gating for manual testing.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyBushes()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Bush reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
