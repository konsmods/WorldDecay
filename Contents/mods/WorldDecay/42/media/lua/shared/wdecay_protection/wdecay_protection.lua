local WDecay_Protection = {}

function WDecay_Protection.isPlayerBuilt(object)
    if not object then return false end
    if instanceof(object, "IsoThumpable") then return true end
    local modData = object:getModData()
    return modData and modData["WDecay_PlayerBuilt"] == true
end

function WDecay_Protection.markPlayerBuilt(object)
    if not object then return end
    object:getModData()["WDecay_PlayerBuilt"] = true
    object:transmitModData()
    object:flagForHotSave()
end

function WDecay_Protection.protectRepairedWindows()
    if WDecay_Protection.windowRecipeWrapped then return end
    local recipe = BuildRecipeCode and BuildRecipeCode.windowGlass
    if not recipe or not recipe.OnCreate then return end

    local original = recipe.OnCreate
    recipe.OnCreate = function(params)
        local result = original(params)
        if result and result.object then WDecay_Protection.markPlayerBuilt(result.object) end
        return result
    end
    WDecay_Protection.windowRecipeWrapped = true
end

return WDecay_Protection
