local WDecay_Vines_SpriteRules = {}

--Prefixes (or exact sprite names): skip vines on the object itself.
WDecay_Vines_SpriteRules.skip = {
    "walls_exterior_roofs_",
    "roofs_",
}

--Prefixes (or exact sprite names): skip the whole square if any object on it matches.
WDecay_Vines_SpriteRules.skipSquare = {
    "construction_",
}

--Prefixes (or exact sprite names): force the single-tile/low vine variant.
WDecay_Vines_SpriteRules.forceLow = {
    "walls_exterior_house_low_",
    "industry_railroad_05_40",
    "industry_railroad_05_41",
    "industry_railroad_05_42",
}

function WDecay_Vines_SpriteRules.matches(name, list)
    if not name then return false end
    for i = 1, #list do
        if luautils.stringStarts(name, list[i]) then return true end
    end
    return false
end

return WDecay_Vines_SpriteRules
