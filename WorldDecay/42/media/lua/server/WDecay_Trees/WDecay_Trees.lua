local WDecay_Random = require('wdecay_random/wdecay_random')

local randomizer = WDecay_Random.get()

local WDecay_Trees = {}

WDecay_Trees.normalTreeSprites = {
    "e_americanholly_1_0",
    "e_americanholly_1_1",
    "e_canadianhemlock_1_0",
    "e_canadianhemlock_1_1",
    "e_virginiapine_1_0",
    "e_virginiapine_1_1",
    "e_americanhollyJUMBO_1_0",
    "e_americanhollyJUMBO_1_1",
    "e_canadianhemlockJUMBO_1_0",
    "e_canadianhemlockJUMBO_1_1",
    "e_virginiapineJUMBO_1_0",
    "e_virginiapineJUMBO_1_1"
}

WDecay_Trees.jumboXLXXLSprites = {
    "e_americanhollyJUMBOXL_1_0",
    "e_americanhollyJUMBOXXL_1_0",
    "e_canadianhemlockJUMBOXL_1_0",
    "e_canadianhemlockJUMBOXXL_1_0",
    "e_virginiapineJUMBOXL_1_0",
    "e_virginiapineJUMBOXXL_1_0"
}

local function getJumboXLXXLPercentage()
    local options = getSandboxOptions()
    local option = options and options:getOptionByName('WDecay.jumboXLXXLPercentage')
    local value = option and option:getValue()
    return value ~= nil and value or 10
end

function WDecay_Trees.getRandomTreeSprite()
    function WDecay_Trees.resetCaches()
    cachedBasePercentage = nil
    cachedBasePercentageOnRoad = nil
end

    local sprites = WDecay_Trees.normalTreeSprites
    if randomizer:random(1, 100) <= getJumboXLXXLPercentage() then
        sprites = WDecay_Trees.jumboXLXXLSprites
    end

    return sprites[randomizer:random(1, #sprites)]
end

local cachedBasePercentage = nil
function WDecay_Trees.getBasePercentage()
    if cachedBasePercentage == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.treePercentage')
        cachedBasePercentage = opt and opt:getValue() or 17
    end

    return cachedBasePercentage
end

local cachedBasePercentageOnRoad = nil
function WDecay_Trees.getBasePercentageOnRoad()
    if cachedBasePercentageOnRoad == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.treePercentageOnRoad')
        cachedBasePercentageOnRoad = opt and opt:getValue() or 0
    end

    return cachedBasePercentageOnRoad
end

return WDecay_Trees
