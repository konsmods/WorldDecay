require('luautils')

local Tiles = require("WDecay_Overlays/Data/Tiles")
local Sprites = require("WDecay_Overlays/Data/Sprites")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Features = require('wdecay_features/wdecay_features')

local randomizer = WDecay_Random.get()

local sandboxCache = {}
local function sb(key, fallback)
    if sandboxCache[key] == nil then
        local s = getSandboxOptions()
        if not s then sandboxCache[key] = fallback
        else
            local o = s:getOptionByName('WDecay.' .. key)
            local v = o and o:getValue()
            sandboxCache[key] = v ~= nil and v or fallback
        end
    end
    return sandboxCache[key]
end

-- Tile overlays use a 1-in-N chance. Calibrate that chance against the same
-- 0-100 values used by object placement, so a setting of 25 means roughly
-- one eligible floor tile in four receives an overlay from the pool.
local OVERLAY_DENSITY = 100

local indoorOverlayRegistered = {}
local roofOverlayRegistered = {}
local lazyOverlayConfigs = {
    indoor = {
        registered = indoorOverlayRegistered,
        percentages = {
            { key = 'indoorOverlayGrassPercentage', default = 55, sprites = Sprites.vanilla },
            { key = 'indoorOverlayCustomGrassPercentage', default = 35, sprites = Sprites.custom },
            { key = 'indoorOverlayCrackPercentage', default = 25, sprites = Sprites.crack },
            { key = 'indoorOverlayLeavesPercentage', default = 35, sprites = Sprites.leaves },
            { key = 'indoorOverlayDebrisPercentage', default = 30, sprites = Sprites.debris },
            { key = 'indoorOverlayTrashPercentage', default = 30, sprites = Sprites.trash },
        }
    },
    roof = {
        registered = roofOverlayRegistered,
        percentages = {
            { key = 'roofOverlayGrassPercentage', default = 50, sprites = Sprites.vanilla },
            { key = 'roofOverlayCustomGrassPercentage', default = 30, sprites = Sprites.custom },
            { key = 'roofOverlayCrackPercentage', default = 15, sprites = Sprites.crack },
            { key = 'roofOverlayLeavesPercentage', default = 30, sprites = Sprites.leaves },
            { key = 'roofOverlayDebrisPercentage', default = 25, sprites = Sprites.debris },
            { key = 'roofOverlayTrashPercentage', default = 20, sprites = Sprites.trash },
        }
    },
}

local function clearLazyOverlayCache()
    indoorOverlayRegistered = {}
    roofOverlayRegistered = {}
    lazyOverlayConfigs.indoor.registered = indoorOverlayRegistered
    lazyOverlayConfigs.roof.registered = roofOverlayRegistered
end

local function computeChance(intensity)
    local mult = WDecay_Scaling.getMultiplierFor('nature')
    if mult < 0.01 then mult = 0.01 end
    local denom = intensity * mult
    if denom <= 0 then return 1 end
    local c = math.ceil(OVERLAY_DENSITY / denom)
    return math.max(1, c)
end

local function mixSprites(list, target, intensity)
    if intensity <= 0 or #list == 0 then return end
    for i = 1, intensity do
        target[#target + 1] = list[randomizer:random(1, #list)]
    end
end

local function seasonAdj(value, kind)
    local adjusted = value * WDecay_Scaling.getSeasonFactor(kind)
    if adjusted > 100 then adjusted = 100 end
    return adjusted
end

local function registerTileOverlays()
    if TILEZED then return end
    if not WDecay_Features.isEnabled("overlays") then return end

    clearLazyOverlayCache()

    local gNat = seasonAdj(sb('grassPercentage', 15), 'grass')
    local gRoad = seasonAdj(sb('grassPercentageOnRoad', 50), 'grass')
    local cNat = sb('customGrassPercentage', 20)
    local cRoad = sb('customGrassPercentageOnRoad', 20)
    local lNat = seasonAdj(sb('floorLeavesPercentage', 20), 'leaves')
    local lRoad = seasonAdj(sb('floorLeavesPercentageOnRoad', 20), 'leaves')
    local bNat = sb('groundDebrisPercentage', 15)
    local bRoad = sb('groundDebrisPercentageOnRoad', 15)
    local trashNat = sb('trashPercentage', 10)
    local trashRoad = sb('trashPercentageOnRoad', 15)
    local crackNat = sb('dirtCrackOverlayPercentage', 0)
    local crackRoad = sb('roadCrackOverlayPercentage', 10)

    local registry = {}

    for _, tile in ipairs(Tiles.natural) do
        local pool = {}
        mixSprites(Sprites.vanilla, pool, gNat)
        mixSprites(Sprites.custom, pool, cNat)
        mixSprites(Sprites.leaves, pool, lNat)
        mixSprites(Sprites.debris, pool, bNat)
        mixSprites(Sprites.trash, pool, trashNat)
        mixSprites(Sprites.crack, pool, crackNat)
        local top = math.max(gNat, cNat, lNat, bNat, trashNat, crackNat)
        if #pool > 0 and top > 0 then
            registry[tile] = {{ name = "other", chance = computeChance(top), usage = "", tiles = pool }}
        end
    end

    for _, tile in ipairs(Tiles.road) do
        local pool = {}
        mixSprites(Sprites.vanilla, pool, gRoad)
        mixSprites(Sprites.custom, pool, cRoad)
        mixSprites(Sprites.leaves, pool, lRoad)
        mixSprites(Sprites.debris, pool, bRoad)
        mixSprites(Sprites.trash, pool, trashRoad)
        mixSprites(Sprites.crack, pool, crackRoad)
        local top = math.max(gRoad, cRoad, lRoad, bRoad, trashRoad, crackRoad)
        if #pool > 0 and top > 0 then
            registry[tile] = {{ name = "other", chance = computeChance(top), usage = "", tiles = pool }}
        end
    end

    getTileOverlays():addOverlays(registry)
end

function WDecay_Overlays_Refresh()
    sandboxCache = {}
    registerTileOverlays()
    print("[WDecay] Overlays re-registered with current multipliers")
end

local lastRefreshDay = nil
function WDecay_Overlays_RefreshQuiet()
    local days = WDecay_Scaling.getWorldAgeDays()
    local day = days and math.floor(days) or nil
    if day ~= nil and lastRefreshDay == day then
        return
    end

    lastRefreshDay = day
    sandboxCache = {}
    registerTileOverlays()
end

local overlayPrefixes = {
    "blends_grassoverlays",
    "blends_streetoverlays",
    "blends_dirtoverlays",
    "d_streetcracks",
    "d_floorleaves",
    "d_plants",
    "e_newgrass_",
    "d_generic_",
    "trash_01_"
}

local function isOverlayName(name)
    if not name then return false end
    for i = 1, #overlayPrefixes do
        if luautils.stringStarts(name, overlayPrefixes[i]) then
            return true
        end
    end
    return false
end

-- The engine already applies TileOverlays as each grid square loads. Its
-- update method appends rather than replaces, so older WorldDecay releases
-- that called it again can leave two matching sprites. Preserve one existing
-- overlay and remove only later duplicates from legacy marked floors.
local function dedupeFloorOverlays(floor)
    local attached = floor:getAttachedAnimSprite()
    if not attached then return 0 end

    local removed = 0
    local kept = false
    for n = attached:size() - 1, 0, -1 do
        local sp = attached:get(n)
        local parent = sp and sp:getParentSprite()
        local name = parent and parent:getName()
        if isOverlayName(name) then
            if kept then
                floor:RemoveAttachedAnim(n)
                removed = removed + 1
            else
                kept = true
            end
        end
    end

    return removed
end

local function hasFloorOverlay(floor)
    local attached = floor:getAttachedAnimSprite()
    if not attached then return false end
    for n = 0, attached:size() - 1 do
        local sprite = attached:get(n)
        local parent = sprite and sprite:getParentSprite()
        if isOverlayName(parent and parent:getName()) then return true end
    end
    return false
end

local function registerLazyOverlay(tileName, config)
    local registered = config.registered
    if registered[tileName] then return true end
    registered[tileName] = true

    local pool = {}
    local top = 0
    for _, entry in ipairs(config.percentages) do
        local intensity = sb(entry.key, entry.default)
        mixSprites(entry.sprites, pool, intensity)
        if intensity > top then
            top = intensity
        end
    end

    if #pool > 0 and top > 0 then
        getTileOverlays():addOverlays({ [tileName] = { { name = "other", chance = computeChance(top), usage = "", tiles = pool } } })
        return true
    end

    return false
end

-- Natural and road tiles are registered before chunks stream in, so the
-- engine applies them automatically. Indoor/roof tiles are lazily registered
-- from their real floor name; for only that first encounter, add an overlay
-- ourselves if the engine could not have done so already. checkResult is the
-- same per-square result the dispatcher already computed for this square this
-- pass -- avoids a second, redundant native square-check here.
local function registerLateLazyOverlay(square, floor, level, checkResult)
    if not WDecay_Features.isEnabled("overlays") or hasFloorOverlay(floor) then return end

    local sprite = floor:getSprite()
    local tileName = sprite and sprite:getName()
    if not tileName then return end

    local config = nil
    if checkResult and checkResult.isIndoor then
        config = lazyOverlayConfigs.indoor
    elseif checkResult and checkResult.hasRoof then
        config = lazyOverlayConfigs.roof
    end
    if config and registerLazyOverlay(tileName, config) then
        -- This tile name was not in the overlay map during the engine's load
        -- pass. It has no overlay yet, so this is the sole safe manual call.
        local overlays = getTileOverlays()
        if overlays then
            overlays:updateTileOverlaySprite(floor)
            floor:transmitUpdatedSpriteToClients()
            if WDecay_DebugCountTransmission then WDecay_DebugCountTransmission("overlay") end
        end
    end
end

-- Called once per square from the dispatcher's own budgeted, resumable scan
-- (WDecay_Dispatcher.processChunkSquares) -- the same per-square pass that
-- places trees/bushes/grass -- instead of its own unbounded, unbudgeted
-- Events.LoadChunk hook. That old hook re-walked every square of every
-- chunk on every load (client and server, done chunks included), which is
-- exactly what made overlay reconciliation the dominant cost while fast
-- chunk streaming (e.g. driving) queued up many LoadChunk events per tick.
-- Folding it into the dispatcher means it now only runs once per square,
-- the first time that square is processed, deadline-checked like everything
-- else.
function WDecay_Overlays_ReconcileSquare(square, checkResult, level)
    if not WDecay_Features.isEnabled("overlays") then return end
    if checkResult and checkResult.cleaned then return end
    if square:getModData()["WDecay_cleaned"] then return end
    local floor = square:getFloor()
    if not floor then return end

    local floorData = floor:getModData()
    if floorData and floorData["WDecay_OverlayApplied"] then
        if dedupeFloorOverlays(floor) > 0 then
            floor:transmitUpdatedSpriteToClients()
            if WDecay_DebugCountTransmission then WDecay_DebugCountTransmission("overlay") end
        end
    else
        registerLateLazyOverlay(square, floor, level, checkResult)
    end
end

Events.OnInitGlobalModData.Add(function(isNewGame)
    sandboxCache = {}
    registerTileOverlays()
end)
