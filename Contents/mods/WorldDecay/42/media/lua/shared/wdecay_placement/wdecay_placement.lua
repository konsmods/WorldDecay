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

function WDecay_Placement.forEachObject(square, fn)
    if not square or not fn then return end
    local seen = {}
    local function scan(objects, special)
        if not objects then return end
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if object and not seen[object] then
                seen[object] = true
                fn(object, special)
            end
        end
    end
    scan(square:getObjects(), false)
    scan(square:getSpecialObjects(), true)
end

function WDecay_Placement.isSafe(square)
    if not square or not square:getObjects() then return false end
    local safe = true
    WDecay_Placement.forEachObject(square, function(object, special)
        if special or hasContainer(object) then
            safe = false
            return
        end
        local modData = object:getModData()
        if modData and modData["WDecay_Cleanable"] and not WDecay_Scaling.isRedecayPass() then
            safe = false
        end
    end)
    return safe
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
                    local found = false
                    WDecay_Placement.forEachObject(target, function(object)
                        local modData = object:hasModData() and object:getModData()
                        if modData and modData["WDecay_Cleanable"] == cleanableType then found = true end
                    end)
                    if found then return math.min(100, chance * getClusterBoost(cleanableType)) end
                end
            end
        end

    return chance
end

function WDecay_Placement.createTaggedObject(square, spriteName, cleanableType)
    if not square or not spriteName or not cleanableType then return nil end

    if cleanableType == "tree" then
        local sprite = getSprite(spriteName)
        if not sprite then return nil end
        local tree = IsoTree.new(square, sprite)
        if not tree then return nil end
        square:AddSpecialObject(tree)
        tree:setAttachedAnimSprite(ArrayList.new())
        tree:getModData()["WDecay_Cleanable"] = cleanableType
        return tree
    end

    if not getSprite(spriteName) then return nil end
    local created = IsoObject.new(getCell(), square, spriteName)
    if not created then return nil end
    square:AddSpecialObject(created)
    created:setAttachedAnimSprite(ArrayList.new())
    created:getModData()["WDecay_Cleanable"] = cleanableType
    return created
end

function WDecay_Placement.finalizeObject(object)
    if not object then return nil end
    object:transmitCompleteItemToClients()
    if WDecay_DebugCountTransmission then WDecay_DebugCountTransmission("complete") end
    object:transmitModData()
    if WDecay_DebugCountTransmission then WDecay_DebugCountTransmission("modData") end
    if WDecay_DebugCountObject then WDecay_DebugCountObject(object:getModData()["WDecay_Cleanable"]) end
    if WDecay_Debug then WDecay_Debug.objectsPlaced = (WDecay_Debug.objectsPlaced or 0) + 1 end
    return object
end

function WDecay_Placement.createTagged(square, spriteName, cleanableType)
    return WDecay_Placement.finalizeObject(WDecay_Placement.createTaggedObject(square, spriteName, cleanableType)) ~= nil
end

return WDecay_Placement
