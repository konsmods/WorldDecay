-- Stateless, world-coordinate vegetation regions.  This intentionally does
-- not inspect neighbouring objects or save a map: identical seed, coordinate,
-- and sandbox setting always produce the same fertility value.
local WDecay_VegetationPattern = {}

local WDecay_Random = require('wdecay_random/wdecay_random')

local HASH_MODULUS = 104729
local FERTILITY_MIN = 0.55
local FERTILITY_RANGE = 0.90
local SCALE_TILES = { [1] = 16, [2] = 48, [3] = 120, [4] = 0, [5] = 4 }
local cachedScale = nil
local cachedDistribution = nil

local function hash01(x, y, salt)
    -- Keep every intermediate below Lua's exact-integer range.  Unlike the
    -- mutable placement RNG this is safe to call in any order.
    local n = (x * 92821 + y * 68917 + salt * 1237) % HASH_MODULUS
    n = (n * 8191 + 127) % HASH_MODULUS
    n = (n * 8191 + 127) % HASH_MODULUS
    return n / HASH_MODULUS
end

local function smoothstep(value)
    return value * value * (3 - 2 * value)
end

local function getScaleTiles()
    if cachedScale ~= nil then return cachedScale end
    local option = getSandboxOptions():getOptionByName('WDecay.vegetationPatternScale')
    local value = option and option:getValue() or 4
    cachedScale = SCALE_TILES[value] or 0
    return cachedScale
end

local function getDistribution()
    if cachedDistribution ~= nil then return cachedDistribution end
    local option = getSandboxOptions():getOptionByName('WDecay.vegetationPatternDistribution')
    cachedDistribution = option and option:getValue() or 3
    return cachedDistribution
end

local function fertilityFor(seedValue, distribution)
    if distribution ~= 2 then
        return FERTILITY_MIN + seedValue * FERTILITY_RANGE
    end

    -- Weighted tier average is ~1.0: 25%% barren, 30%% sparse, 30%% normal,
    -- and 15%% lush. This keeps sandbox density percentages meaningful while
    -- producing obvious empty-to-overgrown regions.
    if seedValue < 0.25 then return 0.0 end
    if seedValue < 0.55 then return 0.35 end
    if seedValue < 0.85 then return 1.0 end
    return 4.0
end

local function seedPoint(cellX, cellY, distribution)
    local salt = WDecay_Random.getWorldSalt() % HASH_MODULUS
    local xJitter = 0.15 + hash01(cellX, cellY, salt + 101) * 0.70
    local yJitter = 0.15 + hash01(cellX, cellY, salt + 211) * 0.70
    local fertility = fertilityFor(hash01(cellX, cellY, salt + 307), distribution)
    return xJitter, yJitter, fertility
end

function WDecay_VegetationPattern.getMultiplierAt(worldX, worldY)
    local scale = getScaleTiles()
    local distribution = getDistribution()
    -- Disabled exactly reproduces the old white-noise density rolls.
    if scale == 0 or distribution == 3 then return 1 end
    local px, py = worldX / scale, worldY / scale
    local cellX, cellY = math.floor(px), math.floor(py)
    local nearestDistance, secondDistance = nil, nil
    local nearestFertility, secondFertility = nil, nil

    -- A Voronoi point can only be nearest from this 3x3 neighbourhood because
    -- jitter remains inside each cell.  There are no cross-chunk lookups.
    for y = cellY - 1, cellY + 1 do
        for x = cellX - 1, cellX + 1 do
            local seedX, seedY, fertility = seedPoint(x, y, distribution)
            local dx, dy = px - (x + seedX), py - (y + seedY)
            local distance = dx * dx + dy * dy
            if not nearestDistance or distance < nearestDistance then
                secondDistance, secondFertility = nearestDistance, nearestFertility
                nearestDistance, nearestFertility = distance, fertility
            elseif not secondDistance or distance < secondDistance then
                secondDistance, secondFertility = distance, fertility
            end
        end
    end

    if not secondDistance then return nearestFertility or 1 end
    -- Squared distances preserve the same ordering and a natural boundary
    -- blend without two sqrt calls for every vegetation-square lookup.
    local border = nearestDistance / math.max(nearestDistance + secondDistance, 0.0001) * 2
    local blend = smoothstep(math.min(1, border))
    return nearestFertility + (secondFertility - nearestFertility) * blend
end

function WDecay_VegetationPattern.getMultiplier(square)
    if not square then return 1 end
    return WDecay_VegetationPattern.getMultiplierAt(square:getX(), square:getY())
end

function WDecay_VegetationPattern.getMultiplierForCheck(square, checkResult)
    if checkResult and checkResult.WDecay_vegetationMultiplier ~= nil then
        return checkResult.WDecay_vegetationMultiplier
    end
    local multiplier = WDecay_VegetationPattern.getMultiplier(square)
    if checkResult then checkResult.WDecay_vegetationMultiplier = multiplier end
    return multiplier
end

function WDecay_VegetationPattern.isEnabled()
    return getScaleTiles() ~= 0 and getDistribution() ~= 3
end

function WDecay_VegetationPattern.adjustPercentage(square, percentage, checkResult)
    if not percentage or percentage <= 0 then return 0 end
    if not WDecay_VegetationPattern.isEnabled() then return percentage end
    return math.min(100, percentage * WDecay_VegetationPattern.getMultiplierForCheck(square, checkResult))
end

function WDecay_VegetationPattern.getPlacementScore(square, salt)
    if not square then return 0 end
    local jitter = hash01(square:getX(), square:getY(), (salt or 0) + 503)
    return WDecay_VegetationPattern.getMultiplier(square) + jitter * 0.20
end

function WDecay_VegetationPattern.resetCache()
    cachedScale = nil
    cachedDistribution = nil
end

Events.EveryDays.Add(WDecay_VegetationPattern.resetCache)

return WDecay_VegetationPattern
