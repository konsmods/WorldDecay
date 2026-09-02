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
        if WDecay_DebugCountTransmission then WDecay_DebugCountTransmission("sprite") end
    end

    return true
end

local function reseasonObject(object)
    if not object or not object:hasModData() or object:getModData()["WDecay_Cleanable"] ~= "grass" then
        return 0, 0
    end
    local before = object:getSpriteName()
    if not reseasonGrass(object) then return 0, 0 end
    return 1, object:getSpriteName() ~= before and 1 or 0
end

-- Manual full-area reseason helper.
local function reseasonAllLoadedChunks()
    return WDecay_LoadedChunks.forEachLoadedObject(reseasonObject)
end

-- Registers seasonal hooks only when seasonal grass processing is enabled.
local registered = false
local function registerIfEnabled()
    if registered then return end
    if not (WDecay_Scaling.isSeasonalBiasEnabled() and WDecay_Features.isEnabled("grass")) then return end

    registered = true
    WDecay_LoadedChunks.registerReseasonCallback(reseasonObject)
end

Events.OnGameStart.Add(registerIfEnabled)

-- Debug helper that bypasses feature gating.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyGrass()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Grass reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
