local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')

local randomizer = WDecay_Random.get()

local TIME_KEY = "WDecay_Fences-LoadGridsquare"

local WDecay_Fences = require('WDecay_Fences/WDecay_Fences')

local cachedFencePercentage = nil
local cachedFenceBreakChance = nil
local cachedFenceBendChance = nil
local cachedFenceDestroyWeight = nil
local cachedFenceBendSeverity = nil

--Local variables are better in performance
local NoBrokenAndNotBendableFenceCache = WDecay_Fences.NOT_BROKE_AND_BENDABLE_FENCE
local BrokenFenceCache = WDecay_Fences.BROKEN_FENCE
local BendableFenceCache = WDecay_Fences.BENDABLE_FENCE

local function getFencePercentage()
    if cachedFencePercentage == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.fencePercentage')
        cachedFencePercentage = opt and opt:getValue() or 20
    end

    return cachedFencePercentage
end

local function getFenceBreakChance()
    if cachedFenceBreakChance == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.fenceBreakChance')
        cachedFenceBreakChance = opt and opt:getValue() or 0
    end

    return cachedFenceBreakChance
end

local function getFenceBendChance()
    if cachedFenceBendChance == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.fenceBendChance')
        cachedFenceBendChance = opt and opt:getValue() or 0
    end

    return cachedFenceBendChance
end

local function getFenceDestroyWeight()
    if cachedFenceDestroyWeight == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.fenceDestroyWeight')
        cachedFenceDestroyWeight = opt and opt:getValue() or 20
    end

    return cachedFenceDestroyWeight
end

local function getFenceBendSeverity()
    if cachedFenceBendSeverity == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.fenceBendSeverity')
        cachedFenceBendSeverity = opt and opt:getValue() or 4
    end

    return cachedFenceBendSeverity
end

local function resetCaches()
    cachedFencePercentage = nil
    cachedFenceBreakChance = nil
    cachedFenceBendChance = nil
    cachedFenceDestroyWeight = nil
    cachedFenceBendSeverity = nil
end

local function LoadGridsquare(square, checkResult, level)


    if not checkResult then return end

    if checkResult.cleaned then return end

    if not checkResult.hasFences then return end

    if level ~= 0 then return end

    local objects = checkResult.objects

    if not objects or objects:size() == 0 then return end

    -- objects is live, not a snapshot; destroyFence() below can shrink it
    -- mid-loop, so re-check size() each iteration instead of caching it.
    local i = 0
    while i < objects:size() do
        local obj = objects:get(i)

        if obj then
            local fenceProp = WDecay_Fences.getFenceProperty(obj);

            --Is fence prop is brokeable and bendable and not damaged?
            if fenceProp ~= NoBrokenAndNotBendableFenceCache then --That's not neaded: 'and WDecay_Fences.isNotDamaged(obj) then'
                -- The two override settings apply to different fence types.
                -- A zero override means "use Fence Percentage", matching the
                -- sandbox option descriptions and keeping the base setting
                -- useful for both kinds of fence.
                local baseChance = getFencePercentage()
                local chance = 0
                if fenceProp == BrokenFenceCache then
                    chance = getFenceBreakChance()
                elseif fenceProp == BendableFenceCache then
                    chance = getFenceBendChance()
                end
                if chance <= 0 then chance = baseChance end
                chance = WDecay_Scaling.scale(chance)

                if chance > 0 and chance >= randomizer:random(1, 100) then
                    --Broke or Bendable Fence? 
                    if fenceProp == BrokenFenceCache then
                        local destroyWeight = getFenceDestroyWeight()
                        if WDecay_Scaling.isSeverityScalingEnabled() then
                            destroyWeight = math.floor(WDecay_Scaling.scaleSeverity('urban', destroyWeight))
                        end

                        WDecay_Fences.applyBreakableFenceDamage(obj, destroyWeight)
                    elseif fenceProp == BendableFenceCache then
                        WDecay_Fences.applyBendableFenceDamage(obj, getFenceBendSeverity())
                    end

                    local objModData = obj:getModData()

                    if objModData and not objModData["WDecay_Cleanable"] then
                        objModData["WDecay_Cleanable"] = "fence"
                    end
                end
            end
        end
        i = i + 1
    end
end

local patchedFunction = LoadGridsquare

local function debugLoadGridsquare(square, checkResult, level)
    WD_Debug_Metric.startTimeMeasurement(TIME_KEY)
    local result = patchedFunction(square, checkResult, level)
    WD_Debug_Metric.endTimeMeasurement(TIME_KEY)
    return result
end

if isDebugEnabled() then
    LoadGridsquare = debugLoadGridsquare
end

if not WDecay_ModifierGenerators then WDecay_ModifierGenerators = {} end

table.insert(WDecay_ModifierGenerators, LoadGridsquare)
if not WDecay_ModifierGeneratorFeatures then WDecay_ModifierGeneratorFeatures = {} end
WDecay_ModifierGeneratorFeatures[#WDecay_ModifierGenerators] = "fences"

return WDecay_Fences
