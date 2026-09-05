-- Server-authoritative validation for every client-originated WorldDecay command.
local Security = {}

Security.MAX_DEBUG_RADIUS = 3
Security.MAX_DEBUG_AGE_DAYS = 365000
Security.MAX_TIMELAPSE_STEP_DAYS = 3650
Security.MAX_TIMELAPSE_TICKS = 3600

local actionTimes = setmetatable({}, { __mode = "k" })

function Security.isAdmin(player)
    if not player then return false end

    local ok, allowed = pcall(function()
        return player.isAccessLevel and player:isAccessLevel("admin")
    end)
    if ok and allowed then return true end

    local level = nil
    pcall(function() level = player:getAccessLevel() end)
    return string.lower(tostring(level or "")) == "admin"
end

function Security.isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function Security.clampInteger(value, minimum, maximum, fallback)
    if not Security.isFiniteNumber(value) then return fallback end
    return math.max(minimum, math.min(maximum, math.floor(value)))
end

function Security.debugRadius(value)
    return Security.clampInteger(value, 1, Security.MAX_DEBUG_RADIUS, 3)
end

function Security.allowPlayerAction(player, action, cooldownMs)
    if not player then return false end
    local now = getTimestampMs and getTimestampMs() or 0
    local actions = actionTimes[player] or {}
    local previous = actions[action] or 0
    if now > 0 and now - previous < cooldownMs then return false end
    actions[action] = now
    actionTimes[player] = actions
    return true
end

return Security
