local RustRemover_Config = {}

local DEFAULTS = {
    enabled = true,
    rustPercentPerPass = 5,
    baseActionTime = 600,
    bottleUsePercent = 25,
    sandpaperConditionLoss = 25,
    mechanicsTimeReduction = 5,
}

function RustRemover_Config.get(key)
    local fallback = DEFAULTS[key]
    local options = getSandboxOptions and getSandboxOptions()
    local option = options and options:getOptionByName("RustRemover." .. key)
    local value = option and option:getValue()
    if value == nil then return fallback end
    return value
end

function RustRemover_Config.isEnabled()
    return RustRemover_Config.get("enabled") == true
end

function RustRemover_Config.getBottleUse()
    return RustRemover_Config.get("bottleUsePercent") / 100.0
end

function RustRemover_Config.getRustReduction()
    return RustRemover_Config.get("rustPercentPerPass") / 100.0
end

function RustRemover_Config.getSandpaperLoss(item)
    return math.max(1, math.ceil(item:getConditionMax() * RustRemover_Config.get("sandpaperConditionLoss") / 100.0))
end

function RustRemover_Config.getActionTime(character)
    local reduction = RustRemover_Config.get("mechanicsTimeReduction")
    local level = math.min(10, character:getPerkLevel(Perks.Mechanics))
    local multiplier = math.max(0.5, 1.0 - (level * reduction / 100.0))
    return math.max(1, math.floor(RustRemover_Config.get("baseActionTime") * multiplier))
end

-- ISBaseTimedAction durations are simulation ticks (60 ticks per second).
-- The server uses the same conversion to make completion packets wait for
-- the action that the player actually started.
function RustRemover_Config.getActionDurationMs(character)
    return math.ceil(RustRemover_Config.getActionTime(character) * 1000 / 60)
end

return RustRemover_Config
