local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Season = require('wdecay_season/wdecay_season')

local randomizer = WDecay_Random.get()

local WDecay_Trees = {}

-- Each species: id = vanilla sprite prefix, evergreen = whether it keeps its
-- look year-round. Evergreen species never get a seasonal "child" (crown)
-- sprite in vanilla's own data (hasChildSprite is false for them) -- only the
-- snow swap-in frame ever varies for them.
WDecay_Trees.species = {
    { id = "americanholly", evergreen = true },
    { id = "canadianhemlock", evergreen = true },
    { id = "virginiapine", evergreen = true },
    { id = "redmaple", evergreen = false },
    { id = "dogwood", evergreen = false },
    { id = "riverbirch", evergreen = false },
    { id = "americanlinden", evergreen = false },
}

-- Per-species sandbox option names. Each species' weight (0-100) lets the
-- player tune how common it is relative to the others; 0 fully disables it.
-- Cached so the dispatcher's per-square pick isn't hitting the sandbox options
-- table on every roll.
local SPECIES_OPTIONS = {
    { id = "americanholly", opt = "WDecay.treeAmericanhollyPercentage", default = 100 },
    { id = "canadianhemlock", opt = "WDecay.treeCanadianhemlockPercentage", default = 100 },
    { id = "virginiapine", opt = "WDecay.treeVirginiapinePercentage", default = 100 },
    { id = "redmaple", opt = "WDecay.treeRedmaplePercentage", default = 100 },
    { id = "dogwood", opt = "WDecay.treeDogwoodPercentage", default = 100 },
    { id = "riverbirch", opt = "WDecay.treeRiverbirchPercentage", default = 100 },
    { id = "americanlinden", opt = "WDecay.treeAmericanlindenPercentage", default = 100 },
}

local cachedSpeciesWeights = nil

local function getSpeciesWeights()
    if cachedSpeciesWeights then return cachedSpeciesWeights end

    local weights = {}
    local options = getSandboxOptions()
    for i, entry in ipairs(SPECIES_OPTIONS) do
        local value = nil
        local option = options and options:getOptionByName(entry.opt)
        if option then value = option:getValue() end
        weights[i] = value ~= nil and value or entry.default
    end
    cachedSpeciesWeights = weights
    return weights
end

-- Weighted random species pick honoring each species' sandbox percentage.
-- Falls back to uniform selection if every weight is 0 (so disabling all
-- species still yields trees rather than a crash).
function WDecay_Trees.pickSpecies()
    local weights = getSpeciesWeights()

    local total = 0
    for i = 1, #weights do total = total + weights[i] end

    if total <= 0 then
        return WDecay_Trees.species[randomizer:random(1, #WDecay_Trees.species)]
    end

    local roll = randomizer:random(1, total)
    local acc = 0
    for i = 1, #weights do
        acc = acc + weights[i]
        if roll <= acc then
            return WDecay_Trees.species[i]
        end
    end

    return WDecay_Trees.species[#WDecay_Trees.species]
end

-- Ground truth from decompiling vanilla's NatureTrees.init()/ErosionObj.setStageObject():
-- frame = childSlot * columnMultiplier + column. "column" is which growth-stage/
-- size-variant of that tier -- vanilla interleaves multiple stages into one
-- tileset for Small/Jumbo, but XL/XXL each get a dedicated tileset file (multiplier=1).
--   childSlot 0 = trunk/base, used year-round (trees set noSeasonBase=true).
--   childSlot 1 = NOT a season -- the snow-dusted swap-in for the base sprite,
--             used instead of it (not stacked) whenever it's snowing.
--   childSlot seasonValue+1 = "child" sprites (the foliage), attached on top of
--             the base via addAttachedAnimSpriteByName() -- deciduous species
--             only. Winter (seasonValue 0) has no child registered -> bare trunk.
local SMALL_TIER = { suffix = "", columnMultiplier = 4, columns = { 0, 1 } }
local JUMBO_TIER = { suffix = "JUMBO", columnMultiplier = 2, columns = { 0, 1 } }
local JUMBOXL_TIER = { suffix = "JUMBOXL", columnMultiplier = 1, columns = { 0 } }
local JUMBOXXL_TIER = { suffix = "JUMBOXXL", columnMultiplier = 1, columns = { 0 } }

WDecay_Trees.normalTiers = { SMALL_TIER, JUMBO_TIER }
WDecay_Trees.jumboXLXXLTiers = { JUMBOXL_TIER, JUMBOXXL_TIER }
WDecay_Trees.allTiers = { SMALL_TIER, JUMBO_TIER, JUMBOXL_TIER, JUMBOXXL_TIER }

-- Vanilla's own child-frame loop offset is seasonValue+1 (verified against the
-- NatureTrees.init() bytecode: the season values it registers children for --
-- 1/2/4 for Spring/Summer/Autumn -- come from array positions 2/3/5 in that
-- loop). Winter (seasonValue 0) has no child registered at all -- bare trunk.
function WDecay_Trees.isSnowing()
    return WDecay_Season.isSnowing()
end

function WDecay_Trees.getCurrentChildSlot()
    local seasonValue = WDecay_Season.getSeasonValue()
    if not seasonValue or seasonValue == 0 then return nil end
    return seasonValue + 1
end

-- Cached: WDecay_Trees.species is static, and the dispatcher calls this once
-- per tree/road-tree square it scans -- no need to rebuild the table every time.
local cachedSpritePrefixes = nil

function WDecay_Trees.getSpritePrefixes()
    if not cachedSpritePrefixes then
        cachedSpritePrefixes = {}
        for i, species in ipairs(WDecay_Trees.species) do
            cachedSpritePrefixes[i] = "e_" .. species.id
        end
    end
    return cachedSpritePrefixes
end

local function getJumboXLXXLPercentage()
    local options = getSandboxOptions()
    local option = options and options:getOptionByName('WDecay.jumboXLXXLPercentage')
    local value = option and option:getValue()
    return value ~= nil and value or 10
end

-- Returns baseSpriteName, childSpriteName (childSpriteName may be nil: evergreen
-- species, or winter, or currently snowing).
function WDecay_Trees.pickTreeSprites()
    local species = WDecay_Trees.pickSpecies()

    local tiers = WDecay_Trees.normalTiers
    if randomizer:random(1, 100) <= getJumboXLXXLPercentage() then
        tiers = WDecay_Trees.jumboXLXXLTiers
    end

    local tier = tiers[randomizer:random(1, #tiers)]
    local column = tier.columns[randomizer:random(1, #tier.columns)]
    local prefix = "e_" .. species.id .. tier.suffix .. "_1_"

    if WDecay_Trees.isSnowing() then
        return prefix .. (tier.columnMultiplier + column), nil
    end

    local baseSprite = prefix .. column

    if not species.evergreen then
        local childSlot = WDecay_Trees.getCurrentChildSlot()
        if childSlot then
            return baseSprite, prefix .. (childSlot * tier.columnMultiplier + column)
        end
    end

    return baseSprite, nil
end

local cachedBasePercentage = nil
function WDecay_Trees.getBasePercentage()
    if cachedBasePercentage == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.treePercentage')
        cachedBasePercentage = opt and opt:getValue() or 17
    end

    return cachedBasePercentage
end

local cachedBasePercentageOnRoad = nil
function WDecay_Trees.getBasePercentageOnRoad()
    if cachedBasePercentageOnRoad == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.treePercentageOnRoad')
        cachedBasePercentageOnRoad = opt and opt:getValue() or 0
    end

    return cachedBasePercentageOnRoad
end

function WDecay_Trees.resetCaches()
    cachedBasePercentage = nil
    cachedBasePercentageOnRoad = nil
    cachedSpeciesWeights = nil
end

return WDecay_Trees
