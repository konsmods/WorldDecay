local WDecay_Random = require('wdecay_random/wdecay_random')
local randomizer = WDecay_Random.get()

local classBrokenFences = BrokenFences.getInstance()
local classBentFences = BentFences.getInstance()

local IS_COLLIDE_N = IsoFlagType.collideN
local IS_COLLIDE_W = IsoFlagType.collideW

local ISO_DIRECTIONS_N = IsoDirections.N
local ISO_DIRECTIONS_S = IsoDirections.S
local ISO_DIRECTIONS_W = IsoDirections.W
local ISO_DIRECTIONS_E = IsoDirections.E

local WDecay_Fences = {}

--Local variables are better every time!
local NOT_BROKE_AND_BENDABLE_FENCE = 0
local BROKEN_FENCE = 1
local BENDABLE_FENCE = 2

--Global one for the generator.
WDecay_Fences.NOT_BROKE_AND_BENDABLE_FENCE = NOT_BROKE_AND_BENDABLE_FENCE
WDecay_Fences.BROKEN_FENCE = BROKEN_FENCE
WDecay_Fences.BENDABLE_FENCE = BENDABLE_FENCE

--Skip B42 entity fences, BrokenFences/BentFences aren't built for them.
--Map may no longer place sprite-based fences at all - keeping just in case.
local function isEntityObject(obj)
    return instanceof(obj, "IsoEntity")
end

function WDecay_Fences.getFenceProperty(obj)
    if isEntityObject(obj) then
        return NOT_BROKE_AND_BENDABLE_FENCE
    elseif classBentFences:isBentObject(obj) then
        return BENDABLE_FENCE
    elseif classBrokenFences:isBreakableObject(obj) then
        return BROKEN_FENCE
    else
        return NOT_BROKE_AND_BENDABLE_FENCE
    end
end

function WDecay_Fences.determineDirection(obj)
    local properties = obj:getProperties()
    local randValue = randomizer:random(0, 2)

    if properties:has(IS_COLLIDE_N) then
        if randValue == 0 then
            return ISO_DIRECTIONS_N
        else
            return ISO_DIRECTIONS_S
        end
    elseif properties:has(IS_COLLIDE_W) then
        if randValue == 0 then
            return ISO_DIRECTIONS_W
        else
            return ISO_DIRECTIONS_E
        end
    else
        return nil
    end
end

function WDecay_Fences.getRandomStage(severity)
    severity = severity or 4
    if severity == 1 then
        return 1
    elseif severity == 2 then
        return 2
    elseif severity == 3 then
        return 3
    else
        local roll = randomizer:random(0, 100)
        if roll < 33 then
            return 1
        elseif roll < 66 then
            return 2
        else
            return 3
        end
    end
end

local function tagFenceDebris(sq)
    if sq then
        local objs = sq:getObjects()
        local len = objs:size()
        if objs then
            for i = 0, len - 1 do
                local o = objs:get(i)

                if o then
                    local sprite = o:getSprite()

                    if sprite then
                        local name = sprite:getName()

                        if name then
                            --Contains is way faster then luautils.
                            if name:contains("fencing_damaged_") or name:contains("carpentry_02_") then
                                local md = o:getModData()

                                if md and not md["WDecay_Cleanable"] then
                                    md["WDecay_Cleanable"] = "fence"
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function WDecay_Fences.applyBreakableFenceDamage(obj, destroyWeight)
    local dir = WDecay_Fences.determineDirection(obj)
    if not dir then return end

    destroyWeight = destroyWeight or 20
    local roll = randomizer:random(0, 100)

    if roll < destroyWeight then
        classBrokenFences:destroyFence(obj, dir)

        local sq = obj:getSquare()

        tagFenceDebris(sq)
        tagFenceDebris(sq:getTileInDirection(ISO_DIRECTIONS_E))
        tagFenceDebris(sq:getTileInDirection(ISO_DIRECTIONS_W))
        tagFenceDebris(sq:getTileInDirection(ISO_DIRECTIONS_S))
        tagFenceDebris(sq:getTileInDirection(ISO_DIRECTIONS_N))
    else
        local damageRoll = randomizer:random(0, 100)
        if damageRoll < 50 then
            classBrokenFences:updateSprite(obj, true, false)
        else
            classBrokenFences:updateSprite(obj, false, true)
        end
    end
end

function WDecay_Fences.applyBendableFenceDamage(obj, severity)
    if not obj then return end

    local dir = WDecay_Fences.determineDirection(obj)
    if not dir then return false end

    local stage = WDecay_Fences.getRandomStage(severity)

    classBentFences:swapTiles(obj, dir, true, stage)
    tagFenceDebris(obj:getSquare())
end

return WDecay_Fences
