-- Same idea as WDecay_Trees_Reseason.lua/WDecay_Bushes_Reseason.lua: vanilla's
-- own erosion-tracked grass updates its sprite live as the season changes, but
-- only for objects its private simulation is tracking. This gives our own
-- already-placed grass the same live behavior: checked every ten minutes
-- (matching vanilla's own ErosionMain.EveryTenMinutes() rate), but the actual
-- sweep only runs when season or snow has actually changed since the last
-- check. The sweep itself covers a generous radius around every online player
-- (see wdecay_loaded_chunks.lua for why -- see WDecay_Trees_Reseason.lua for
-- the same rationale).
--
-- Grass has no attached child sprite (unlike trees/bushes) -- its own base
-- sprite changes with season, so this is just a straight sprite swap. It
-- stores its (stage, variety) in ModData at spawn time (WDecay_Grass.lua)
-- since a raw frame number alone doesn't tell us those back.

local WDecay_Grass = require('WDecay_Grass/WDecay_Grass')
local WDecay_Season = require('wdecay_season/wdecay_season')
local WDecay_LoadedChunks = require('wdecay_loaded_chunks/wdecay_loaded_chunks')

-- Returns true if the object was actually one of ours we could evaluate.
local function reseasonGrass(object)
    local modData = object:getModData()
    local stage = modData[WDecay_Grass.MODDATA_STAGE]
    local variety = modData[WDecay_Grass.MODDATA_VARIETY]
    if stage == nil or variety == nil then return false end

    local desired = WDecay_Grass.spriteName(WDecay_Grass.getCurrentSeasonValue(), stage, variety)
    if desired == object:getSpriteName() then return true end

    local sprite = getSprite(desired)
    if sprite then
        object:setSprite(sprite)
        object:transmitUpdatedSpriteToClients()
    end

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
        if object and object:hasModData() and object:getModData()["WDecay_Cleanable"] == "grass" then
            local before = object:getSpriteName()
            if reseasonGrass(object) then
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

-- Manual trigger for testing, same pattern as WD_DebugTools.reseasonNearbyTrees/Bushes.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyGrass()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Grass reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
