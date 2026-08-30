local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Season = require('wdecay_season/wdecay_season')
local WDecay_Placement = require('wdecay_placement/wdecay_placement')

local randomizer = WDecay_Random.get()

local WDecay_Bushes = {}

-- Ground truth from decompiling vanilla's NatureBush.init()/constructor. Unlike
-- trees, bush sprites don't carry a per-species name -- every species shares
-- the single "f_bushes_1_<frame>" atlas, and which frame is used is purely a
-- function of the species' array position ("id" below) and its "id % 8"
-- wrapped slot. bloomStart/bloomEnd are fractions of the year (0.0-1.0), taken
-- directly from vanilla's own per-species bloom windows -- all 16 vanilla bush
-- species have flowers, so every entry here blooms.
WDecay_Bushes.species = {
    { id = 0,  name = "Spicebush",              bloomStart = 0.05, bloomEnd = 0.35 },
    { id = 1,  name = "Ninebark",                bloomStart = 0.65, bloomEnd = 0.75 },
    { id = 2,  name = "Ninebark",                bloomStart = 0.65, bloomEnd = 0.75 },
    { id = 3,  name = "Blueberry",               bloomStart = 0.4,  bloomEnd = 0.5 },
    { id = 4,  name = "Blackberry",              bloomStart = 0.4,  bloomEnd = 0.5 },
    { id = 5,  name = "Piedmont azalea",         bloomStart = 0.0,  bloomEnd = 0.15 },
    { id = 6,  name = "Piedmont azalea",         bloomStart = 0.0,  bloomEnd = 0.15 },
    { id = 7,  name = "Arrowwood viburnum",      bloomStart = 0.3,  bloomEnd = 0.8 },
    { id = 8,  name = "Red chokeberry",          bloomStart = 0.9,  bloomEnd = 1.0 },
    { id = 9,  name = "Red chokeberry",          bloomStart = 0.9,  bloomEnd = 1.0 },
    { id = 10, name = "Beautyberry",             bloomStart = 0.7,  bloomEnd = 0.85 },
    { id = 11, name = "New jersey tea",          bloomStart = 0.4,  bloomEnd = 0.8 },
    { id = 12, name = "New jersey tea",          bloomStart = 0.4,  bloomEnd = 0.8 },
    { id = 13, name = "Wild hydrangea",          bloomStart = 0.2,  bloomEnd = 0.35 },
    { id = 14, name = "Wild hydrangea",          bloomStart = 0.2,  bloomEnd = 0.35 },
    { id = 15, name = "Shrubby St. John's wort", bloomStart = 0.35, bloomEnd = 0.75 },
}

WDecay_Bushes.SPRITE_PREFIX = "f_bushes_1_"

-- Frame formula per section (verified against NatureBush.init() bytecode).
-- "wrapped" sections reuse id%8 (they wrap every 8 species, same physical
-- frame reused by species 0 and 8, 1 and 9, etc.); "unwrapped" ones (summer,
-- flower) are unique per species across the full id range.
--   base:   id%8 + stage*8        (year-round)
--   snow:   id%8 + 16 + stage*8   (swap-in while snowing)
--   spring: id%8 + 32 + stage*8   (seasonValue 1)
--   autumn: id%8 + 48 + stage*8   (seasonValue 4)
--   summer: id + 64 + stage*32    (seasonValue 2, unwrapped)
--   flower: id + 80 + stage*32    (bloom window only, unwrapped)
local function frame(id, stage, offset, wrapped)
    local slot = wrapped and (id % 8) or id
    return slot + offset + stage * (wrapped and 8 or 32)
end

-- Public so WDecay_Bushes_Reseason.lua can recompute a stored (id, stage)'s
-- sprite for any section without duplicating the frame formula.
function WDecay_Bushes.spriteName(id, stage, offset, wrapped)
    return WDecay_Bushes.SPRITE_PREFIX .. frame(id, stage, offset, wrapped)
end

function WDecay_Bushes.isSnowing()
    return WDecay_Season.isSnowing()
end

-- Cheap approximation of vanilla's bloom window: is the current point in the
-- year within [bloomStart, bloomEnd]? Vanilla smoothly cross-fades in/out of
-- this window and gates it to Summer only -- we just do a flat window check,
-- same "as simply as possible" spirit as the tree season handling.
local function isBlooming(species)
    local yearFraction = WDecay_Season.getYearFraction()
    if not yearFraction then return false end
    return yearFraction >= species.bloomStart and yearFraction <= species.bloomEnd
end

function WDecay_Bushes.getSpeciesById(id)
    for _, species in ipairs(WDecay_Bushes.species) do
        if species.id == id then return species end
    end
    return nil
end

-- Deterministic core: given a fixed species+stage, what should it look like
-- right now? Returns baseSpriteName, childSpriteName (may be nil),
-- flowerSpriteName (may be nil). Shared by pickBushSprites() (random pick, for
-- spawning) and WDecay_Bushes_Reseason.lua (fixed id/stage read back from
-- ModData, for updating already-placed bushes) so the season logic only
-- lives in one place.
function WDecay_Bushes.spritesFor(species, stage)
    if WDecay_Bushes.isSnowing() then
        return WDecay_Bushes.spriteName(species.id, stage, 16, true), nil, nil
    end

    local baseSprite = WDecay_Bushes.spriteName(species.id, stage, 0, true)
    local childSprite = nil
    local flowerSprite = nil
    local seasonValue = WDecay_Season.getSeasonValue()

    if seasonValue == 1 then
        childSprite = WDecay_Bushes.spriteName(species.id, stage, 32, true)
    elseif seasonValue == 2 then
        childSprite = WDecay_Bushes.spriteName(species.id, stage, 64, false)
        if isBlooming(species) then
            flowerSprite = WDecay_Bushes.spriteName(species.id, stage, 80, false)
        end
    elseif seasonValue == 4 then
        childSprite = WDecay_Bushes.spriteName(species.id, stage, 48, true)
    end

    return baseSprite, childSprite, flowerSprite
end

-- Returns baseSpriteName, childSpriteName, flowerSpriteName, id, stage. id/
-- stage are returned so callers can store them in ModData: unlike trees, a
-- bush sprite name alone doesn't uniquely identify its species (id%8 wraps),
-- so we can't reverse-parse it later the way WDecay_Trees_Reseason.lua does.
function WDecay_Bushes.pickBushSprites()
    local species = WDecay_Bushes.species[randomizer:random(1, #WDecay_Bushes.species)]
    local stage = randomizer:random(0, 1)
    local baseSprite, childSprite, flowerSprite = WDecay_Bushes.spritesFor(species, stage)
    return baseSprite, childSprite, flowerSprite, species.id, stage
end

WDecay_Bushes.MODDATA_ID = "WDecay_BushId"
WDecay_Bushes.MODDATA_STAGE = "WDecay_BushStage"

-- Centralizes spawn + attach + ModData bookkeeping so the three call sites
-- (natural/road/indoor) in the dispatcher and generator don't each repeat it.
-- Returns the created bush object, or nil on failure.
function WDecay_Bushes.spawnBush(square)
    local baseSprite, childSprite, flowerSprite, id, stage = WDecay_Bushes.pickBushSprites()
    local bush = WDecay_Placement.createTaggedObject(square, baseSprite, "bush")
    if not bush then return nil end

    local modData = bush:getModData()
    modData[WDecay_Bushes.MODDATA_ID] = id
    modData[WDecay_Bushes.MODDATA_STAGE] = stage

    if childSprite and getSprite(childSprite) then
        bush:addAttachedAnimSpriteByName(childSprite)
    end
    if flowerSprite and getSprite(flowerSprite) then
        bush:addAttachedAnimSpriteByName(flowerSprite)
    end

    return bush
end

local cachedBase = nil
local cachedBaseRoad = nil
local cachedBaseIndoor = nil
function WDecay_Bushes.getBasePercentage()
    if cachedBase == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.bushesPercentage')
        cachedBase = opt and opt:getValue() or 20
    end

    return cachedBase
end

function WDecay_Bushes.getBasePercentageOnRoad()
    if cachedBaseRoad == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.bushesPercentageOnRoad')
        cachedBaseRoad = opt and opt:getValue() or 0
    end

    return cachedBaseRoad
end

function WDecay_Bushes.getIndoorBasePercentage()
    if cachedBaseIndoor == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.indoorBushesPercentage')
        cachedBaseIndoor = opt and opt:getValue() or 0
    end

    return cachedBaseIndoor
end

local cachedBaseRoof = nil
function WDecay_Bushes.getBasePercentageOnRoof()
    if cachedBaseRoof == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.bushesPercentageOnRoof')
        cachedBaseRoof = opt and opt:getValue() or 0
    end

    return cachedBaseRoof
end

function WDecay_Bushes.resetCaches()
    cachedBase = nil
    cachedBaseRoad = nil
    cachedBaseIndoor = nil
    cachedBaseRoof = nil
end

return WDecay_Bushes
