local WDecay_Placement = {}
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')

local DENSITY_CURVE = 1.5

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

-- Clustering was removed because its neighbor scans dominated placement cost.
-- The density curve remains as inexpensive chance shaping.
function WDecay_Placement.clusterChance(square, cleanableType, chance, radius)
    if not chance then return chance end
    if chance > 0 and chance < 100 then
        chance = 100 * (chance / 100) ^ DENSITY_CURVE
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
