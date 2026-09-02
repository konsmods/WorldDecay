-- Reseasons WorldDecay bushes every ten minutes when season or snow changes.
-- Bush id and stage are stored in ModData because sprites do not identify species.

local WDecay_Bushes = require('WDecay_Bushes/WDecay_Bushes')
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

-- Returns true when the object is a recognized WorldDecay bush.
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
    if WDecay_DebugCountTransmission then WDecay_DebugCountTransmission("sprite") end
    return true
end

local function reseasonObject(object)
    if not object or not object:hasModData() or object:getModData()["WDecay_Cleanable"] ~= "bush" then
        return 0, 0
    end
    local before = object:getSpriteName()
    if not reseasonBush(object) then return 0, 0 end
    return 1, object:getSpriteName() ~= before and 1 or 0
end

-- Manual full-area reseason helper.
local function reseasonAllLoadedChunks()
    return WDecay_LoadedChunks.forEachLoadedObject(reseasonObject)
end

-- Registers seasonal hooks only when seasonal bush processing is enabled.
local registered = false
local function registerIfEnabled()
    if registered then return end
    if not (WDecay_Scaling.isSeasonalBiasEnabled() and WDecay_Features.isEnabled("bushes")) then return end

    registered = true
    WDecay_LoadedChunks.registerReseasonCallback(reseasonObject)
end

Events.OnGameStart.Add(registerIfEnabled)

-- Debug helper that bypasses feature gating.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyBushes()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Bush reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
