local WDecay_Placement = {}

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
            if modData and modData["WDecay_Cleanable"] then return false end
        end
    end
    return true
end

function WDecay_Placement.createTagged(square, spriteName, cleanableType)
    if not square or not spriteName or not cleanableType then return false end
    local objects = square:getObjects()
    if not objects then return false end
    local existing = {}
    for i = 0, objects:size() - 1 do existing[objects:get(i)] = true end
    local ok = pcall(function() createTile(spriteName, square) end)
    if not ok then return false end
    objects = square:getObjects()
    if not objects then return false end
    local created = nil
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object and not existing[object] and object:getSpriteName() == spriteName then
            if created then return false end
            created = object
        end
    end
    if not created then return false end
    created:getModData()["WDecay_Cleanable"] = cleanableType
    return true
end

return WDecay_Placement
