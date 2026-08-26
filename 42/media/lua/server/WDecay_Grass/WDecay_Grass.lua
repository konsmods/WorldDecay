local WDecay_Random = require('wdecay_random/wdecay_random')

local randomizer = WDecay_Random.get()

local WDecay_Grass = {}

local vanilla_grass = {
    "e_newgrass_1_0",
    "e_newgrass_1_1",
    "e_newgrass_1_2",
    "e_newgrass_1_3",
    "e_newgrass_1_4",
    "e_newgrass_1_5",
    "e_newgrass_1_16",
    "e_newgrass_1_17",
    "e_newgrass_1_18",
    "e_newgrass_1_19",
    "e_newgrass_1_20",
    "e_newgrass_1_21",
    "e_newgrass_1_24",
    "e_newgrass_1_25",
    "e_newgrass_1_26",
    "e_newgrass_1_27",
    "e_newgrass_1_28",
    "e_newgrass_1_29",
    "e_newgrass_1_32",
    "e_newgrass_1_33",
    "e_newgrass_1_34",
    "e_newgrass_1_35",
    "e_newgrass_1_36",
    "e_newgrass_1_37",
    "e_newgrass_1_40",
    "e_newgrass_1_41",
    "e_newgrass_1_42",
    "e_newgrass_1_43",
    "e_newgrass_1_44",
    "e_newgrass_1_45",
    "e_newgrass_1_48",
    "e_newgrass_1_49",
    "e_newgrass_1_50",
    "e_newgrass_1_51",
    "e_newgrass_1_52",
    "e_newgrass_1_53",
    "e_newgrass_1_56",
    "e_newgrass_1_57",
    "e_newgrass_1_58",
    "e_newgrass_1_59",
    "e_newgrass_1_60",
    "e_newgrass_1_61",
    "e_newgrass_1_64",
    "e_newgrass_1_65",
    "e_newgrass_1_66",
    "e_newgrass_1_67",
    "e_newgrass_1_68",
    "e_newgrass_1_69",
    "e_newgrass_1_70",
    "e_newgrass_1_72",
    "e_newgrass_1_73",
    "e_newgrass_1_74",
    "e_newgrass_1_75",
    "e_newgrass_1_76",
    "e_newgrass_1_77",
    "e_newgrass_1_78",
    "e_newgrass_1_80",
    "e_newgrass_1_81",
    "e_newgrass_1_82",
    "e_newgrass_1_83",
    "e_newgrass_1_84",
    "e_newgrass_1_85",
    "e_newgrass_1_88",
    "e_newgrass_1_89"
}

function WDecay_Grass.getRandomVanillaGrass()
    return vanilla_grass[randomizer:random(1, #vanilla_grass)]
end

local cachedIndoorBase = nil
function WDecay_Grass.getIndoorBasePercentage()
    if cachedIndoorBase == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.indoorGrassPercentage')
        cachedIndoorBase = opt and opt:getValue() or 0
    end

    return cachedIndoorBase
end

function WDecay_Grass.resetCaches()
    cachedIndoorBase = nil
end

return WDecay_Grass
