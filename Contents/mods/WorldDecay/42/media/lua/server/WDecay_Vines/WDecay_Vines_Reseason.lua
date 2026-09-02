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
    if WDecay_DebugCountTransmission then WDecay_DebugCountTransmission("overlay") end

    return true
end

local function reseasonObject(object)
    if not object then return 0, 0 end
    local before = WDecay_CleanVegetation.getOverlaySpriteName(object)
    if not reseasonVine(object) then return 0, 0 end
    return 1, WDecay_CleanVegetation.getOverlaySpriteName(object) ~= before and 1 or 0
end

-- Manual full-area reseason helper.
local function reseasonAllLoadedChunks()
    return WDecay_LoadedChunks.forEachLoadedObject(reseasonObject)
end

-- Registers seasonal hooks only when seasonal vine processing is enabled.
local registered = false
local function registerIfEnabled()
    if registered then return end
    if not (WDecay_Scaling.isSeasonalBiasEnabled() and WDecay_Features.isEnabled("vines")) then return end

    registered = true
    WDecay_LoadedChunks.registerReseasonCallback(reseasonObject)
end

Events.OnGameStart.Add(registerIfEnabled)

-- Debug helper that bypasses feature gating.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyVines()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Vine reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
