local WDecay_CleanVegetation = {}

local CLEANABLE_TYPES = {
    grass = true,
    indoorGrass = true,
    bush = true,
    vine = true,
    trash = true,
    tree = true
}

local CLEANABLE_MAIN_PREFIXES = {
    "blends_grassoverlays",
    "blends_streetoverlays",
    "blends_dirtoverlays",
    "d_streetcracks",
    "d_floorleaves",
    "d_plants",
    "e_newgrass_",
    "f_bushes_",
    "f_wallvines_",
    "d_generic_",
    "trash_01_"
}

local CLEANABLE_DECORATION_PREFIXES = {
    "blends_grassoverlays",
    "blends_streetoverlays",
    "blends_dirtoverlays",
    "d_streetcracks",
    "d_floorleaves",
    "d_plants",
    "e_newgrass_",
    "f_bushes_",
    "f_wallvines_",
    "d_generic_",
    "trash_01_"
}

local function startsWithAny(value, prefixes)
    if not value then
        return false
    end

    for i = 1, #prefixes do
        local prefix = prefixes[i]

        if string.sub(value, 1, #prefix) == prefix then
            return true
        end
    end

    return false
end

local function getSpriteName(sprite)
    if not sprite then
        return nil
    end

    if type(sprite) == "string" then
        return sprite
    end

    local ok, name = pcall(function()
        return sprite:getName()
    end)

    return ok and name or nil
end

function WDecay_CleanVegetation.getCleanableType(object)
    if not object then
        return nil
    end

    local ok, modData = pcall(function()
        return object:getModData()
    end)
    local cleanableType = ok and modData and modData["WDecay_Cleanable"] or nil

    return CLEANABLE_TYPES[cleanableType] and cleanableType or nil
end

function WDecay_CleanVegetation.getObjectSpriteName(object)
    if not object then
        return nil
    end

    local ok, name = pcall(function()
        return object:getSpriteName()
    end)

    if ok and name then
        return name
    end

    local spriteOk, sprite = pcall(function()
        return object:getSprite()
    end)

    return spriteOk and getSpriteName(sprite) or nil
end

function WDecay_CleanVegetation.getOverlaySpriteName(object)
    if not object then
        return nil
    end

    local ok, sprite = pcall(function()
        return object:getOverlaySprite()
    end)

    return ok and getSpriteName(sprite) or nil
end

function WDecay_CleanVegetation.getAttachedSpriteName(spriteInstance)
    if not spriteInstance then
        return nil
    end

    local ok, parentSprite = pcall(function()
        return spriteInstance:getParentSprite()
    end)

    return ok and getSpriteName(parentSprite) or nil
end

function WDecay_CleanVegetation.isCleanableMainSpriteName(spriteName)
    return startsWithAny(spriteName, CLEANABLE_MAIN_PREFIXES)
end

function WDecay_CleanVegetation.isCleanableDecorationSpriteName(spriteName)
    return startsWithAny(spriteName, CLEANABLE_DECORATION_PREFIXES)
end

function WDecay_CleanVegetation.isCleanableMainObject(object)
    return WDecay_CleanVegetation.isCleanableMainSpriteName(
        WDecay_CleanVegetation.getObjectSpriteName(object)
    )
end

function WDecay_CleanVegetation.isWallVineObject(object)
    local spriteName = WDecay_CleanVegetation.getObjectSpriteName(object)

    return spriteName ~= nil and string.sub(spriteName, 1, 12) == "f_wallvines_"
end

function WDecay_CleanVegetation.hasCleanableDecoration(object)
    if not object then
        return false
    end

    if WDecay_CleanVegetation.isCleanableDecorationSpriteName(
        WDecay_CleanVegetation.getOverlaySpriteName(object)
    ) then
        return true
    end

    local ok, attached = pcall(function()
        return object:getAttachedAnimSprite()
    end)

    if not ok or not attached then
        return false
    end

    for i = 0, attached:size() - 1 do
        if WDecay_CleanVegetation.isCleanableDecorationSpriteName(
            WDecay_CleanVegetation.getAttachedSpriteName(attached:get(i))
        ) then
            return true
        end
    end

    return false
end

local function listHasCleanable(objects, floor)
    if not objects then
        return false
    end

    for i = 0, objects:size() - 1 do
        local object = objects:get(i)

        if (object ~= floor and WDecay_CleanVegetation.isCleanableMainObject(object))
            or WDecay_CleanVegetation.hasCleanableDecoration(object) then
            return true
        end
    end

    return false
end

function WDecay_CleanVegetation.hasCleanableDecorationOnSquare(square)
    if not square then
        return false
    end

    local floor = square:getFloor()

    if WDecay_CleanVegetation.hasCleanableDecoration(floor) then
        return true
    end

    local function listHasDecoration(objects)
        if not objects then
            return false
        end

        for i = 0, objects:size() - 1 do
            if WDecay_CleanVegetation.hasCleanableDecoration(objects:get(i)) then
                return true
            end
        end

        return false
    end

    return listHasDecoration(square:getObjects())
        or listHasDecoration(square:getSpecialObjects())
end

function WDecay_CleanVegetation.hasCleanable(square)
    if not square then
        return false
    end

    local floor = square:getFloor()

    return listHasCleanable(square:getObjects(), floor)
        or listHasCleanable(square:getSpecialObjects(), floor)
        or WDecay_CleanVegetation.hasCleanableDecoration(floor)
end

return WDecay_CleanVegetation
