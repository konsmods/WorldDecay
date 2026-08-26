local WDecay_Random = require('wdecay_random/wdecay_random')

local randomizer = WDecay_Random.get()

local WDecay_Walls = {}

WDecay_Walls.wallProperties = {
    "WallNW",
    "WallW",
    "WallN"
}

WDecay_Walls.burnedTextures = {
    WallNW = {
        "walls_exterior_wooden_01_70",
        "walls_burnt_01_2"
    },
    WallN = {
        "walls_exterior_wooden_01_69",
        "walls_burnt_01_1"
    },
    WallW = {
        "walls_exterior_wooden_01_68",
        "walls_burnt_01_0"
    }
}

function WDecay_Walls.getBurnedTextures(wallType)
    return WDecay_Walls.burnedTextures[wallType] or nil
end

function WDecay_Walls.getRandomBurnedTexture(wallType)
    local textures = WDecay_Walls.getBurnedTextures(wallType)
    if not textures or #textures == 0 then
        return nil
    end

    return textures[randomizer:random(1, #textures)]
end

function WDecay_Walls.isBurnedWall(spriteName)
    if not spriteName then return false end

    return luautils.stringStarts(spriteName, "walls_burnt_") or
        (luautils.stringStarts(spriteName, "walls_exterior_wooden_01_") and
            (spriteName == "walls_exterior_wooden_01_68" or
                spriteName == "walls_exterior_wooden_01_69" or
                spriteName == "walls_exterior_wooden_01_70" or
                spriteName == "walls_exterior_wooden_01_75" or
                spriteName == "walls_exterior_wooden_01_76" or
                spriteName == "walls_exterior_wooden_01_77" or
                spriteName == "walls_exterior_wooden_01_78"))
end

function WDecay_Walls.isExteriorWall(textureName)
    if not textureName then return false end

    return luautils.stringStarts(textureName, "walls_exterior_") and
        not luautils.stringStarts(textureName, "walls_exterior_roofs_")
end

function WDecay_Walls.isInteriorWall(textureName)
    if not textureName then return false end

    return luautils.stringStarts(textureName, "walls_interior_")
end

return WDecay_Walls
