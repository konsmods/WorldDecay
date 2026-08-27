local WDecay_Random = require('wdecay_random/wdecay_random')

local randomizer = WDecay_Random.get()

local WDecay_Vines = {}

WDecay_Vines.wallW = {
    "f_wallvines_1_43",
    "f_wallvines_1_42",
    "f_wallvines_1_37",
    "f_wallvines_1_36",
    "f_wallvines_1_31",
    "f_wallvines_1_30",
    "f_wallvines_1_25",
    "f_wallvines_1_24"
}

WDecay_Vines.wallW_top = {
    "f_wallvines_1_31",
    "f_wallvines_1_30",
    "f_wallvines_1_25",
    "f_wallvines_1_24"
}

WDecay_Vines.wallW_low = {
    "f_wallvines_1_25",
    "f_wallvines_1_24"
}

WDecay_Vines.wallN = {
    "f_wallvines_1_45",
    "f_wallvines_1_44",
    "f_wallvines_1_39",
    "f_wallvines_1_38",
    "f_wallvines_1_33",
    "f_wallvines_1_32",
    "f_wallvines_1_27",
    "f_wallvines_1_26"
}

WDecay_Vines.wallN_top = {
    "f_wallvines_1_33",
    "f_wallvines_1_32",
    "f_wallvines_1_27",
    "f_wallvines_1_26"
}

WDecay_Vines.wallN_low = {
    "f_wallvines_1_27",
    "f_wallvines_1_26"
}

WDecay_Vines.wallNW = {
    "f_wallvines_1_47",
    "f_wallvines_1_46",
    "f_wallvines_1_41",
    "f_wallvines_1_40",
    "f_wallvines_1_34",
    "f_wallvines_1_35",
    "f_wallvines_1_29",
    "f_wallvines_1_28"
}

WDecay_Vines.wallNW_top = {
    "f_wallvines_1_35",
    "f_wallvines_1_34",
    "f_wallvines_1_29",
    "f_wallvines_1_28"
}

WDecay_Vines.wallNW_low = {
    "f_wallvines_1_29",
    "f_wallvines_1_28"
}

WDecay_Vines.wallProperties = {
    "WallNW",
    "WallW",
    "WallN",
    "WindowN",
    "WindowW",
    "DoorWallW",
    "DoorWallN"
}

function WDecay_Vines.getRandomWallW()
    if #WDecay_Vines.wallW == 0 then
        return nil
    end

    return WDecay_Vines.wallW[randomizer:random(1, #WDecay_Vines.wallW)]
end

function WDecay_Vines.getRandomWallWTop()
    if #WDecay_Vines.wallW_top == 0 then
        return nil
    end

    return WDecay_Vines.wallW_top[randomizer:random(1, #WDecay_Vines.wallW_top)]
end

function WDecay_Vines.getRandomWallWLow()
    if #WDecay_Vines.wallW_low == 0 then
        return nil
    end

    return WDecay_Vines.wallW_low[randomizer:random(1, #WDecay_Vines.wallW_low)]
end

function WDecay_Vines.getRandomWallN()
    if #WDecay_Vines.wallN == 0 then
        return nil
    end

    return WDecay_Vines.wallN[randomizer:random(1, #WDecay_Vines.wallN)]
end

function WDecay_Vines.getRandomWallNTop()
    if #WDecay_Vines.wallN_top == 0 then
        return nil
    end

    return WDecay_Vines.wallN_top[randomizer:random(1, #WDecay_Vines.wallN_top)]
end

function WDecay_Vines.getRandomWallNLow()
    if #WDecay_Vines.wallN_low == 0 then
        return nil
    end

    return WDecay_Vines.wallN_low[randomizer:random(1, #WDecay_Vines.wallN_low)]
end

function WDecay_Vines.getRandomWallNW()
    if #WDecay_Vines.wallNW == 0 then
        return nil
    end

    return WDecay_Vines.wallNW[randomizer:random(1, #WDecay_Vines.wallNW)]
end

function WDecay_Vines.getRandomWallNWTop()
    if #WDecay_Vines.wallNW_top == 0 then
        return nil
    end

    return WDecay_Vines.wallNW_top[randomizer:random(1, #WDecay_Vines.wallNW_top)]
end

function WDecay_Vines.getRandomWallNWLow()
    if #WDecay_Vines.wallNW_low == 0 then
        return nil
    end

    return WDecay_Vines.wallNW_low[randomizer:random(1, #WDecay_Vines.wallNW_low)]
end

function WDecay_Vines.isVine(spriteName)
    if not spriteName then return false end

    return luautils.stringStarts(spriteName, "f_wallvines_")
end

return WDecay_Vines
