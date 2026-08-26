local WDecay_CustomNames = require('WDecay_CustomNames/WDecay_CustomNames')

local function applyCustomNameToObject(object)
    if not object then return end

    local spriteName = nil
    if object:getSprite() then
        spriteName = object:getSprite():getName()
    end

    if not spriteName then return end

    local customName = WDecay_CustomNames.getCustomName(spriteName)

    if customName then
        object:getModData()["WDecay_CustomName"] = customName
    end
end

function getWDecayCustomName(object)
    if not object then return nil end

    local modData = object:getModData()
    if modData and modData["WDecay_CustomName"] then
        return modData["WDecay_CustomName"]
    end

    return nil
end

function hasWDecayCustomName(object)
    if not object then return false end

    local modData = object:getModData()
    if modData and modData["WDecay_CustomName"] then
        return true
    end

    return false
end

_WDecay_CustomNames = {
    applyCustomNameToObject = applyCustomNameToObject,
    getCustomName = getWDecayCustomName,
    hasCustomName = hasWDecayCustomName
}

return _WDecay_CustomNames
