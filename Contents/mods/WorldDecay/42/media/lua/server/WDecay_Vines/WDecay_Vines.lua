local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Season = require('wdecay_season/wdecay_season')

local randomizer = WDecay_Random.get()

local WDecay_Vines = {}

WDecay_Vines.SPRITE_PREFIX = "f_wallvines_1_"

-- Ground truth from decompiling vanilla's WallVines.init()/constructor.
-- Vines use a different vanilla class pair (ErosionObjOverlay/
-- ErosionObjOverlaySprites) than trees/bushes/grass, but the underlying
-- mechanism is the same attached-sprite trick, and the frame formula reduces
-- to the same shape once cross-checked against WorldDecay's own existing
-- (season-less) frame lists below:
--   frame = seasonIndex*24 + stage*6 + variety
-- "variety" (0-5) directly encodes wall direction in vanilla's data --
-- WorldDecay's existing wallW/wallN/wallNW frame lists are exactly the
-- seasonIndex=1 slice of this formula for variety pairs {0,1}/{2,3}/{4,5}
-- respectively -- and "stage" (0-3) is coverage amount, matching WorldDecay's
-- existing low(stage 0 only) / top (stage 0-1) / full (stage 0-3) tiers.
-- seasonIndex: vanilla registers Winter+lateAutumn=5->index0 (dead/bare),
-- Summer-early=2->index1 (peak growth -- what WorldDecay always used before),
-- and reuses the SAME frames for both Summer-late/earlyAutumn=4 and Spring=1
-- ->index2 (vanilla's own "regrowth" look, shared between both seasons).
local DIRECTION_VARIETIES = { W = { 0, 1 }, N = { 2, 3 }, NW = { 4, 5 } }
local TIER_STAGES = { low = { 0 }, top = { 0, 1 }, full = { 0, 1, 2, 3 } }
local SEASON_NAME_TO_INDEX = { Spring = 2, Summer = 1, Autumn = 2, Winter = 0 }

function WDecay_Vines.spriteName(seasonIndex, stage, variety)
    return WDecay_Vines.SPRITE_PREFIX .. (seasonIndex * 24 + stage * 6 + variety)
end

function WDecay_Vines.getCurrentSeasonIndex()
    local seasonName = WDecay_Season.getSeasonName()
    return (seasonName and SEASON_NAME_TO_INDEX[seasonName]) or 1
end

-- direction: "W"/"N"/"NW". tier: "low"/"top"/"full". Returns spriteName, or
-- nil if direction/tier is unrecognized.
function WDecay_Vines.pickSprite(direction, tier)
    local varieties = DIRECTION_VARIETIES[direction]
    local stages = TIER_STAGES[tier]
    if not varieties or not stages then return nil end

    local variety = varieties[randomizer:random(1, #varieties)]
    local stage = stages[randomizer:random(1, #stages)]
    return WDecay_Vines.spriteName(WDecay_Vines.getCurrentSeasonIndex(), stage, variety)
end

WDecay_Vines.wallProperties = {
    "WallNW",
    "WallW",
    "WallN",
    "WindowN",
    "WindowW",
    "DoorWallW",
    "DoorWallN"
}

function WDecay_Vines.isVine(spriteName)
    if not spriteName then return false end

    return luautils.stringStarts(spriteName, "f_wallvines_")
end

return WDecay_Vines
