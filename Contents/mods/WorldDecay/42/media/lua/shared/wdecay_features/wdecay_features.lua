-- Resolves, once, which generator/reseason "features" actually have work to
-- do, so callers can skip a feature entirely instead of calling into it and
-- letting it early-return every square/chunk. A feature is enabled only if
-- its sandbox toggle is on AND at least one of its gating percentages is
-- above 0, so a 0%-by-default category is already fast without any
-- toggling required.
local WDecay_Features = {}

local function getOpt(name, default)
    local sandbox = getSandboxOptions()
    if not sandbox then return default end
    local opt = sandbox:getOptionByName('WDecay.' .. name)
    if not opt then return default end
    local value = opt:getValue()
    if value == nil then return default end
    return value
end

local function anyPositive(names)
    for i = 1, #names do
        if (getOpt(names[i], 0) or 0) > 0 then return true end
    end
    return false
end

-- Only the percentages that gate whether a generator does anything at all --
-- not every tuning knob underneath it (e.g. per-species tree weights, fence
-- break/bend chances) -- since those only affect *how* an already-active
-- generator behaves, not whether it fires in the first place.
local featureDefs = {
    trees = {
        toggle = 'enableTrees',
        percentages = { 'treePercentage', 'treePercentageOnRoad' },
    },
    bushes = {
        toggle = 'enableBushes',
        percentages = { 'bushesPercentage', 'bushesPercentageOnRoad', 'indoorBushesPercentage', 'bushesPercentageOnRoof' },
    },
    grass = {
        toggle = 'enableGrass',
        percentages = { 'outdoorGrassPercentage', 'outdoorGrassPercentageOnRoad', 'indoorGrassPercentage', 'roofGrassPercentage' },
    },
    vines = {
        toggle = 'enableVines',
        percentages = { 'vinePercentage' },
    },
    overlays = {
        toggle = 'enableOverlays',
        percentages = {
            'grassPercentage', 'grassPercentageOnRoad', 'customGrassPercentage', 'customGrassPercentageOnRoad',
            'indoorOverlayGrassPercentage', 'roofOverlayGrassPercentage',
            'indoorOverlayCustomGrassPercentage', 'roofOverlayCustomGrassPercentage',
            'floorLeavesPercentage', 'floorLeavesPercentageOnRoad', 'indoorOverlayLeavesPercentage', 'roofOverlayLeavesPercentage',
            'groundDebrisPercentage', 'groundDebrisPercentageOnRoad', 'indoorOverlayDebrisPercentage', 'roofOverlayDebrisPercentage',
            'trashPercentage', 'trashPercentageOnRoad', 'indoorOverlayTrashPercentage', 'roofOverlayTrashPercentage',
            'dirtCrackOverlayPercentage', 'roadCrackOverlayPercentage', 'indoorOverlayCrackPercentage', 'roofOverlayCrackPercentage',
        },
    },
    barricades = {
        toggle = 'enableBarricades',
        percentages = { 'barricadePercentage' },
    },
    destroyedDoorsWindows = {
        toggle = 'enableDestroyedDoorsWindows',
        percentages = { 'destroyedDoorsPercentage', 'destroyedWindowsPercentage' },
    },
    walls = {
        toggle = 'enableWalls',
        percentages = { 'wallPercentage' },
    },
    fences = {
        toggle = 'enableFences',
        -- Break/Bend Chance values override the base Fence Percentage for
        -- their respective fence types, so any of the three can make this
        -- feature active.
        percentages = { 'fencePercentage', 'fenceBreakChance', 'fenceBendChance' },
    },
}

-- nil = not yet resolved this cache generation; table = resolved bool-per-feature
local resolved = nil

local function resolveAll()
    local result = {}
    for name, def in pairs(featureDefs) do
        result[name] = getOpt(def.toggle, true) and anyPositive(def.percentages)
    end
    return result
end

-- Unknown feature names are treated as enabled, so a typo or a future
-- feature that hasn't been added to featureDefs yet fails open rather than
-- silently disappearing.
function WDecay_Features.isEnabled(name)
    if resolved == nil then
        resolved = resolveAll()
    end
    local value = resolved[name]
    if value == nil then return true end
    return value
end

function WDecay_Features.reset()
    resolved = nil
end

-- Same cheap "just in case sandbox options changed" reset every other
-- WDecay cache already does (see e.g. WDecay_Trees_Generator.lua's
-- resetCaches on Events.EveryDays).
Events.OnInitGlobalModData.Add(WDecay_Features.reset)
Events.EveryDays.Add(WDecay_Features.reset)

return WDecay_Features
