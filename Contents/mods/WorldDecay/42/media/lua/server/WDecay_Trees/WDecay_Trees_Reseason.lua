-- Vanilla's own erosion-tracked trees update their sprite live as the season
-- changes (see the research behind pickTreeSprites() in WDecay_Trees.lua), but
-- that only applies to objects the private erosion simulation is tracking --
-- there's no hook to register an externally-spawned tree into it. This gives
-- our own already-placed trees the same live behavior: checked every ten
-- minutes (matching vanilla's own ErosionMain.EveryTenMinutes() rate), but
-- the actual sweep only runs when season or snow has actually changed since
-- the last check -- most ten-minute ticks are a no-op, same as vanilla's own
-- per-object cooldown checks mostly finding nothing to do. The sweep itself
-- covers a generous radius around every online player (see
-- wdecay_loaded_chunks.lua for why it's not vanilla's own loaded-cells list --
-- that turned out not to be reachable from Lua at all).

local WDecay_Trees = require('WDecay_Trees/WDecay_Trees')
local WDecay_Season = require('wdecay_season/wdecay_season')
local WDecay_CleanVegetation = require('wdecay_cleanvegetation/wdecay_cleanvegetation')
local WDecay_LoadedChunks = require('wdecay_loaded_chunks/wdecay_loaded_chunks')

-- Reverse-parses a WorldDecay tree's current sprite name back into the
-- species/tier/column it was spawned with, so we know what it should look
-- like right now. Matches against both the plain base frame and the snow
-- swap-in frame, since either could be the tree's current sprite.
local function parseTreeSprite(spriteName)
    if not spriteName then return nil end

    for _, species in ipairs(WDecay_Trees.species) do
        for _, tier in ipairs(WDecay_Trees.allTiers) do
            local prefix = "e_" .. species.id .. tier.suffix .. "_1_"
            if spriteName:sub(1, #prefix) == prefix then
                local frame = tonumber(spriteName:sub(#prefix + 1))
                if frame then
                    for _, column in ipairs(tier.columns) do
                        if frame == column or frame == tier.columnMultiplier + column then
                            return species, tier, prefix, column
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function desiredChildSprite(species, tier, prefix, column)
    if species.evergreen or WDecay_Trees.isSnowing() then return nil end
    local childSlot = WDecay_Trees.getCurrentChildSlot()
    if not childSlot then return nil end
    return prefix .. (childSlot * tier.columnMultiplier + column)
end

local function currentAttachedChildSprite(object)
    local attached = object:getAttachedAnimSprite()
    if not attached or attached:size() == 0 then return nil end
    return WDecay_CleanVegetation.getAttachedSpriteName(attached:get(0))
end

-- Returns true if the tree was actually a WorldDecay tree we could evaluate
-- (regardless of whether it needed a change), false if it wasn't one of ours.
local function reseasonTree(object)
    local spriteName = object:getSpriteName()
    local species, tier, prefix, column = parseTreeSprite(spriteName)
    if not species then return false end

    local desiredBaseFrame = column
    if WDecay_Trees.isSnowing() then
        desiredBaseFrame = tier.columnMultiplier + column
    end
    local desiredBase = prefix .. desiredBaseFrame

    local wantChild = desiredChildSprite(species, tier, prefix, column)
    local haveChild = currentAttachedChildSprite(object)

    if desiredBase == spriteName and wantChild == haveChild then
        return true
    end

    if desiredBase ~= spriteName then
        local sprite = getSprite(desiredBase)
        if sprite then object:setSprite(sprite) end
    end

    if wantChild ~= haveChild then
        object:clearAttachedAnimSprite()
        if wantChild and getSprite(wantChild) then
            object:addAttachedAnimSpriteByName(wantChild)
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
        if object and object:hasModData() and object:getModData()["WDecay_Cleanable"] == "tree" then
            local before = object:getSpriteName()
            if reseasonTree(object) then
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

-- Catches a chunk up the moment it loads, regardless of whether the periodic
-- sweep below has run recently -- cheap (64 squares) and handles the case of
-- a chunk loading between two sweep ticks.
Events.LoadChunk.Add(reseasonChunk)

local warnedMissingLoadedChunks = false

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

-- Manual trigger for testing -- same global-table pattern WD_DebugTools.lua
-- already uses so the client debug menu can reach this without a full
-- client/server command round-trip (debug-only; see that file's own
-- SP-shared-Lua-state precedent for printMetric()/benchmark()).
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyTrees()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
