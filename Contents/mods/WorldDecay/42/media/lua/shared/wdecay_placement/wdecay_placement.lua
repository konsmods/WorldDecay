local WDecay_Placement = {}
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')

local clusterOptions = {
    tree = 'WDecay.treeClusteringEnabled',
    bush = 'WDecay.bushClusteringEnabled',
    grass = 'WDecay.grassClusteringEnabled',
}
local clusterBoostOptions = {
    tree = 'WDecay.treeClusteringBoost',
    bush = 'WDecay.bushClusteringBoost',
    grass = 'WDecay.grassClusteringBoost',
}
local clusterEnabled = {}
local clusterBoosts = {}
local DENSITY_CURVE = 1.5

local function isClusterEnabled(cleanableType)
    if clusterEnabled[cleanableType] ~= nil then return clusterEnabled[cleanableType] end
    local sandbox = getSandboxOptions and getSandboxOptions()
    local option = sandbox and sandbox:getOptionByName(clusterOptions[cleanableType])
    clusterEnabled[cleanableType] = not option or option:getValue() ~= false
    return clusterEnabled[cleanableType]
end

local function getClusterBoost(cleanableType)
    if clusterBoosts[cleanableType] ~= nil then return clusterBoosts[cleanableType] end
    local sandbox = getSandboxOptions and getSandboxOptions()
    local option = sandbox and sandbox:getOptionByName(clusterBoostOptions[cleanableType])
    local boost = option and option:getValue() or 1.0
    clusterBoosts[cleanableType] = math.min(3.0, math.max(1.0, tonumber(boost) or 1.0))
    return clusterBoosts[cleanableType]
end

local function hasContainer(object)
    local container = nil
    pcall(function() container = object:getContainer() end)
    return container ~= nil
end

function WDecay_Placement.isSafe(square)
    if not square then return false end
    local specialObjects = square:getSpecialObjects()
    if specialObjects and specialObjects:size() > 0 then return false end
    local objects = square:getObjects()
    if not objects then return false end
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object then
            if hasContainer(object) then return false end
            local modData = object:getModData()
            if modData and modData["WDecay_Cleanable"] and not WDecay_Scaling.isRedecayPass() then return false end
        end
    end
    return true
end

function WDecay_Placement.clusterChance(square, cleanableType, chance, radius)
    if not chance then return chance end
    if chance > 0 and chance < 100 then
        chance = 100 * (chance / 100) ^ DENSITY_CURVE
    end
    if not square or chance <= 0 or chance >= 100 or not isClusterEnabled(cleanableType) then
        return chance
    end

    local cell = getCell and getCell()
    if not cell then return chance end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    radius = math.max(1, math.floor(tonumber(radius) or 1))
    for ox = -radius, radius do
        for oy = -radius, radius do
            if ox ~= 0 or oy ~= 0 then
                local target = cell:getGridSquare(x + ox, y + oy, z)
                local objects = target and target:getObjects()
                if objects then
                    for i = 0, objects:size() - 1 do
                        local object = objects:get(i)
                        local modData = object and object:hasModData() and object:getModData()
                        if modData and modData["WDecay_Cleanable"] == cleanableType then
                            return math.min(100, chance * getClusterBoost(cleanableType))
                        end
                    end
                end
            end
        end
    end

    return chance
end

-- Returns the created object (or nil on failure), so callers that need to
-- customize it further (e.g. attach a seasonal crown sprite) can. Use
-- createTagged() below when only the boolean success/fail result is needed.
function WDecay_Placement.createTaggedObject(square, spriteName, cleanableType)
    if not square or not spriteName or not cleanableType then return nil end
    local objects = square:getObjects()
    if not objects then return nil end
    local existing = {}
    for i = 0, objects:size() - 1 do existing[objects:get(i)] = true end
    local ok = pcall(function() createTile(spriteName, square) end)
    if not ok then return nil end
    objects = square:getObjects()
    if not objects then return nil end
    local created = nil
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object and not existing[object] and object:getSpriteName() == spriteName then
            if created then return nil end
            created = object
        end
    end
    if not created then return nil end
    created:getModData()["WDecay_Cleanable"] = cleanableType
    return created
end

function WDecay_Placement.createTagged(square, spriteName, cleanableType)
    return WDecay_Placement.createTaggedObject(square, spriteName, cleanableType) ~= nil
end

return WDecay_Placement
