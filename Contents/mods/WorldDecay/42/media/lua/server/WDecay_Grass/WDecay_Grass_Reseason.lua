-- Reseasons WorldDecay grass every ten minutes when season or snow changes.
-- Grass stage and variety are stored in ModData because frames do not identify them.

local WDecay_Grass = require('WDecay_Grass/WDecay_Grass')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Features = require('wdecay_features/wdecay_features')
local WDecay_LoadedChunks = require('wdecay_loaded_chunks/wdecay_loaded_chunks')

-- Returns true when the object is recognized WorldDecay grass.
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

-- Reseasons recognized grass on one square.
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

-- Reseasons all grass objects in one chunk.
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

-- Manual full-area reseason helper.
local function reseasonAllLoadedChunks()
    local totalEvaluated, totalChanged = 0, 0
    WDecay_LoadedChunks.forEachLoadedSquare(function(square)
        local evaluated, changed = reseasonSquare(square)
        totalEvaluated = totalEvaluated + evaluated
        totalChanged = totalChanged + changed
    end)
    return totalEvaluated, totalChanged
end

-- Registers seasonal hooks only when seasonal grass processing is enabled.
local registered = false
local function registerIfEnabled()
    if registered then return end
    if not (WDecay_Scaling.isSeasonalBiasEnabled() and WDecay_Features.isEnabled("grass")) then return end

    registered = true
    Events.LoadChunk.Add(reseasonChunk)
    WDecay_LoadedChunks.registerReseasonCallback(reseasonSquare)
end

Events.OnGameStart.Add(registerIfEnabled)

-- Debug helper that bypasses feature gating.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyGrass()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Grass reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
