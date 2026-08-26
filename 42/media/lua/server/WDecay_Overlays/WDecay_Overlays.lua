require('luautils')

local Tiles = require("WDecay_Overlays/Data/Tiles")
local Sprites = require("WDecay_Overlays/Data/Sprites")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')

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

local OVERLAY_DENSITY = 60

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

    local gNat = seasonAdj(sb('grassPercentage', 30), 'grass')
    local gRoad = seasonAdj(sb('grassPercentageOnRoad', 20), 'grass')
    local cNat = sb('customGrassPercentage', 10)
    local cRoad = sb('customGrassPercentageOnRoad', 10)
    local dNat = seasonAdj(sb('dryGrassPercentage', 15), 'dryGrass')
    local dRoad = seasonAdj(sb('dryGrassPercentageOnRoad', 10), 'dryGrass')
    local lNat = seasonAdj(sb('floorLeavesPercentage', 10), 'leaves')
    local lRoad = seasonAdj(sb('floorLeavesPercentageOnRoad', 5), 'leaves')
    local bNat = sb('groundDebrisPercentage', 15)
    local bRoad = sb('groundDebrisPercentageOnRoad', 8)
    local trash = sb('trashPercentage', 8)
    local crack = sb('roadCrackOverlayPercentage', 10)

    local registry = {}

    for _, tile in ipairs(Tiles.natural) do
        local pool = {}
        mixSprites(Sprites.vanilla, pool, gNat)
        mixSprites(Sprites.custom, pool, cNat)
        mixSprites(Sprites.dry, pool, dNat)
        mixSprites(Sprites.leaves, pool, lNat)
        mixSprites(Sprites.debris, pool, bNat)
        local top = math.max(gNat, cNat, dNat, lNat, bNat)
        if #pool > 0 and top > 0 then
            registry[tile] = {{ name = "other", chance = computeChance(top), usage = "", tiles = pool }}
        end
    end

    for _, tile in ipairs(Tiles.road) do
        local pool = {}
        mixSprites(Sprites.vanilla, pool, gRoad)
        mixSprites(Sprites.custom, pool, cRoad)
        mixSprites(Sprites.dry, pool, dRoad)
        mixSprites(Sprites.leaves, pool, lRoad)
        mixSprites(Sprites.debris, pool, bRoad)
        mixSprites(Sprites.trash, pool, trash)
        mixSprites(Sprites.crack, pool, crack)
        local top = math.max(gRoad, cRoad, dRoad, lRoad, bRoad, trash, crack)
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

local function stripFloorOverlays(floor)
    local attached = floor:getAttachedAnimSprite()
    if not attached then return 0 end

    local removed = 0
    for n = attached:size() - 1, 0, -1 do
        local sp = attached:get(n)
        local parent = sp and sp:getParentSprite()
        local name = parent and parent:getName()
        if isOverlayName(name) then
            floor:RemoveAttachedAnim(n)
            removed = removed + 1
        end
    end

    return removed
end

local function hasAnyOverlay(floor)
    local attached = floor:getAttachedAnimSprite()
    if not attached then return false end

    for n = 0, attached:size() - 1 do
        local sp = attached:get(n)
        local parent = sp and sp:getParentSprite()
        if isOverlayName(parent and parent:getName()) then
            return true
        end
    end

    return false
end

function WDecay_Overlays_ApplyToChunk(chunk)
    if TILEZED then return end

    local overlays = getTileOverlays()
    if not overlays then return end

    for y = 0, 7 do
        for x = 0, 7 do
            local square = chunk:getGridSquare(x, y, 0)
            local floor = square and square:getFloor()
            if floor and not (square:getModData()["WDecay_cleaned"]) then
                if not hasAnyOverlay(floor) then
                    overlays:updateTileOverlaySprite(floor)
                    if hasAnyOverlay(floor) then
                        floor:getModData()["WDecay_OverlayApplied"] = true
                        floor:transmitModData()
                        floor:transmitUpdatedSpriteToClients()
                    end
                end
            end
        end
    end
end

Events.OnInitGlobalModData.Add(function(isNewGame)
    sandboxCache = {}
    registerTileOverlays()
end)
