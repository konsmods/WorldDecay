-- Reseasons WorldDecay vine overlays every ten minutes when season or snow changes.
-- Vines are wall/fence overlays identified directly from their sprite.

local WDecay_Vines = require('WDecay_Vines/WDecay_Vines')
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

-- Returns true when the object has a recognized WorldDecay vine overlay.
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

-- Reseasons recognized vines on one square.
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

-- Reseasons all vines in one chunk.
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

-- Registers seasonal hooks only when seasonal vine processing is enabled.
local registered = false
local function registerIfEnabled()
    if registered then return end
    if not (WDecay_Scaling.isSeasonalBiasEnabled() and WDecay_Features.isEnabled("vines")) then return end

    registered = true
    Events.LoadChunk.Add(reseasonChunk)
    WDecay_LoadedChunks.registerReseasonCallback(reseasonSquare)
end

Events.OnGameStart.Add(registerIfEnabled)

-- Debug helper that bypasses feature gating.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyVines()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Vine reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
