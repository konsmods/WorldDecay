-- Same idea as WDecay_Trees_Reseason.lua: vanilla's own erosion-tracked bushes
-- update their sprite live as the season changes, but only for objects its
-- private simulation is tracking -- there's no hook to register an externally
-- spawned bush into it. This gives our own already-placed bushes the same
-- live behavior: checked every ten minutes (matching vanilla's own
-- ErosionMain.EveryTenMinutes() rate), but the actual sweep only runs when
-- season or snow has actually changed since the last check. The sweep itself
-- covers every chunk currently loaded (see wdecay_loaded_chunks.lua), not a
-- guessed radius -- see WDecay_Trees_Reseason.lua for why.
--
-- Bushes store their (id, stage) in ModData at spawn time (WDecay_Bushes.lua),
-- unlike trees which reverse-parse their sprite name -- a bush sprite name
-- alone doesn't uniquely identify its species since id%8 wraps every 8 species.

local WDecay_Bushes = require('WDecay_Bushes/WDecay_Bushes')
local WDecay_Season = require('wdecay_season/wdecay_season')
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

-- Manual trigger for testing, same pattern as WD_DebugTools.reseasonNearbyTrees.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyBushes()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Bush reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
