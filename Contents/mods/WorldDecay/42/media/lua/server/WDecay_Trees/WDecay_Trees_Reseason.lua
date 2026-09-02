-- Reseasons WorldDecay trees every ten minutes when season or snow changes.

local WDecay_Trees = require('WDecay_Trees/WDecay_Trees')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Features = require('wdecay_features/wdecay_features')
local WDecay_CleanVegetation = require('wdecay_cleanvegetation/wdecay_cleanvegetation')
local WDecay_LoadedChunks = require('wdecay_loaded_chunks/wdecay_loaded_chunks')

-- Parses a tree sprite into its species, tier, and column.
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

-- Returns true when the object is a recognized WorldDecay tree.
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
    if WDecay_DebugCountTransmission then WDecay_DebugCountTransmission("sprite") end
    return true
end

local function reseasonObject(object)
    if not object or not object:hasModData() or object:getModData()["WDecay_Cleanable"] ~= "tree" then
        return 0, 0
    end
    local before = object:getSpriteName()
    if not reseasonTree(object) then return 0, 0 end
    return 1, object:getSpriteName() ~= before and 1 or 0
end

-- Manual full-area reseason helper.
local function reseasonAllLoadedChunks()
    return WDecay_LoadedChunks.forEachLoadedObject(reseasonObject)
end

-- Registers seasonal hooks only when seasonal tree processing is enabled.
local registered = false
local function registerIfEnabled()
    if registered then return end
    if not (WDecay_Scaling.isSeasonalBiasEnabled() and WDecay_Features.isEnabled("trees")) then return end

    registered = true
    WDecay_LoadedChunks.registerReseasonCallback(reseasonObject)
end

Events.OnGameStart.Add(registerIfEnabled)

-- Debug helper that bypasses feature gating.
WD_DebugTools = WD_DebugTools or {}
function WD_DebugTools.reseasonNearbyTrees()
    local evaluated, changed = reseasonAllLoadedChunks()
    print("[WorldDecay Debug] Reseason: evaluated=" .. evaluated .. " changed=" .. changed)
    return evaluated, changed
end
