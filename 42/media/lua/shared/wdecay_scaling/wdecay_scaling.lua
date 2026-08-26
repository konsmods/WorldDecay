local WDecay_Scaling = {}

local DEFAULT_MAX_MULTIPLIER = 4

local cfg = nil
local cachedMultipliers = nil
local redecayDoneAtDays = nil
local redecayBefore = nil
local debugAgeDays = nil

local function readConfig()
    local sandbox = getSandboxOptions()
    if not sandbox then return nil end

    local function getOpt(name, default)
        local opt = sandbox:getOptionByName(name)
        if not opt then return default end

        local value = opt:getValue()
        if value == nil then return default end

        return value
    end

    local c = {}
    c.enabled = getOpt('WDecay.timeScalingEnabled', false)
    c.mode = getOpt('WDecay.timeScalingMode', 1)
    c.perYear = getOpt('WDecay.timeScalingPerYear', 25)
    c.maxMultiplier = getOpt('WDecay.timeScalingMax', DEFAULT_MAX_MULTIPLIER)
    c.curve = getOpt('WDecay.timeScalingCurve', 1)
    c.followErosion = getOpt('WDecay.timeScalingFollowErosion', false)
    c.progressiveDays = getOpt('WDecay.progressiveDays', 365)
    c.progressiveStart = getOpt('WDecay.progressiveStartPercent', 0)
    c.natureFactor = getOpt('WDecay.timeScalingNatureFactor', 150)
    c.urbanFactor = getOpt('WDecay.timeScalingUrbanFactor', 60)
    c.vehiclesFactor = getOpt('WDecay.timeScalingVehiclesFactor', 100)
    c.redecayEnabled = getOpt('WDecay.redecayEnabled', false)
    c.redecayThresholdDays = getOpt('WDecay.redecayThresholdDays', 180)
    c.severityScaling = getOpt('WDecay.severityScalingEnabled', false)
    c.seasonalBias = getOpt('WDecay.seasonalBiasEnabled', false)
    c.erosionDays = getOpt('ErosionDays', 0)

    return c
end

local function getConfig()
    if cfg == nil then
        cfg = readConfig()
    end

    return cfg
end

function WDecay_Scaling.getWorldAgeDays()
    if debugAgeDays ~= nil then return debugAgeDays end

    local gameTime = getGameTime()
    if not gameTime then return nil end

    if gameTime.getWorldAgeDaysSinceBegin then
        return gameTime:getWorldAgeDaysSinceBegin()
    end

    return gameTime:getWorldAgeHours() / 24
end

local function shapeProgress(progress, curve)
    if curve == 2 then
        return math.sqrt(progress)
    elseif curve == 3 then
        return progress * progress
    end

    return progress
end

local function growthForYears(years, rate, curve)
    if curve == 2 then
        return rate * math.log(1 + years) / math.log(2)
    elseif curve == 3 then
        return rate * years * years
    end

    return rate * years
end

function WDecay_Scaling.getMultiplierForDays(days)
    local c = getConfig()
    if not c or not c.enabled or not days then return 1 end

    if days < 0 then days = 0 end

    local maxMultiplier = c.maxMultiplier
    if maxMultiplier < 1 then maxMultiplier = 1 end

    local multiplier

    if c.followErosion and c.erosionDays > 0 then
        local progress = days / c.erosionDays
        if progress > 1 then progress = 1 end

        if c.mode == 2 then
            local startFraction = c.progressiveStart / 100
            if progress < 1 then
                multiplier = startFraction + (1 - startFraction) * shapeProgress(progress, c.curve)
            else
                local extraYears = (days - c.erosionDays) / 365
                multiplier = 1 + growthForYears(extraYears, c.perYear / 100, c.curve)
            end
        else
            multiplier = 1 + progress * (maxMultiplier - 1)
        end
    elseif c.mode == 2 then
        local rampDays = c.progressiveDays
        if rampDays < 1 then rampDays = 1 end

        local startFraction = c.progressiveStart / 100
        if days < rampDays then
            local progress = shapeProgress(days / rampDays, c.curve)
            multiplier = startFraction + (1 - startFraction) * progress
        else
            local extraYears = (days - rampDays) / 365
            multiplier = 1 + growthForYears(extraYears, c.perYear / 100, c.curve)
        end
    else
        multiplier = 1 + growthForYears(days / 365, c.perYear / 100, c.curve)
        if multiplier < 1 then multiplier = 1 end
    end

    if multiplier > maxMultiplier then multiplier = maxMultiplier end
    if multiplier < 0 then multiplier = 0 end

    return multiplier
end

local function getCategoryFactor(category)
    local c = getConfig()
    if not c then return 1 end

    if category == 'nature' then return c.natureFactor / 100 end
    if category == 'urban' then return c.urbanFactor / 100 end
    if category == 'vehicles' then return c.vehiclesFactor / 100 end

    return 1
end

function WDecay_Scaling.getMultiplierForDaysCategory(days, category)
    if days == nil then return 1 end

    return WDecay_Scaling.getMultiplierForDays(days * getCategoryFactor(category))
end

local function computeMultipliersForDays(days)
    return {
        base = WDecay_Scaling.getMultiplierForDays(days),
        nature = WDecay_Scaling.getMultiplierForDays(days * getCategoryFactor('nature')),
        urban = WDecay_Scaling.getMultiplierForDays(days * getCategoryFactor('urban')),
        vehicles = WDecay_Scaling.getMultiplierForDays(days * getCategoryFactor('vehicles'))
    }
end

local function getMultipliers()
    if cachedMultipliers == nil then
        local days = WDecay_Scaling.getWorldAgeDays()
        if days == nil or getConfig() == nil then
            return nil
        end

        cachedMultipliers = computeMultipliersForDays(days)
    end

    return cachedMultipliers
end

function WDecay_Scaling.getMultiplier()
    local multipliers = getMultipliers()
    if not multipliers then return 1 end

    return multipliers.base
end

function WDecay_Scaling.getMultiplierFor(category)
    local multipliers = getMultipliers()
    if not multipliers then return 1 end

    return multipliers[category] or multipliers.base
end

function WDecay_Scaling.scaleFor(category, percentage)
    local scaled = percentage * WDecay_Scaling.getMultiplierFor(category)
    if scaled > 100 then scaled = 100 end
    if scaled < 0 then scaled = 0 end

    if redecayBefore ~= nil then
        local beforeMultiplier = redecayBefore[category] or redecayBefore.base
        local before = percentage * beforeMultiplier
        if before > 100 then before = 100 end
        if before < 0 then before = 0 end

        scaled = scaled - before
        if scaled < 0 then scaled = 0 end
    end

    return scaled
end

function WDecay_Scaling.scale(percentage)
    return WDecay_Scaling.scaleFor(nil, percentage)
end

function WDecay_Scaling.scaleSeverity(category, value)
    local scaled = value * WDecay_Scaling.getMultiplierFor(category)
    if scaled > 100 then scaled = 100 end
    if scaled < 0 then scaled = 0 end

    if redecayBefore ~= nil then
        local beforeMultiplier = redecayBefore[category] or redecayBefore.base
        local before = value * beforeMultiplier
        if before > 100 then before = 100 end
        if before < 0 then before = 0 end
        scaled = scaled - before
        if scaled < 0 then scaled = 0 end
    end

    return scaled
end

function WDecay_Scaling.scaleDownFor(category, value)
    local m = WDecay_Scaling.getMultiplierFor(category)
    if m <= 0 then return 100 end

    local scaled = value / m
    if scaled > 100 then scaled = 100 end
    if scaled < 0 then scaled = 0 end

    return scaled
end

function WDecay_Scaling.scaleDown(value)
    return WDecay_Scaling.scaleDownFor(nil, value)
end

function WDecay_Scaling.isSeverityScalingEnabled()
    local c = getConfig()
    return c ~= nil and c.severityScaling == true
end

function WDecay_Scaling.isRedecayEnabled()
    local c = getConfig()
    return c ~= nil and c.redecayEnabled == true
end

function WDecay_Scaling.isTimeScalingEnabled()
    local c = getConfig()
    return c ~= nil and c.enabled == true
end

function WDecay_Scaling.getRedecayThresholdDays()
    local c = getConfig()
    if not c then return 180 end

    return c.redecayThresholdDays
end

function WDecay_Scaling.setRedecayContext(doneAtDays)
    redecayDoneAtDays = doneAtDays
    if doneAtDays ~= nil then
        if WDecay_Scaling.isTimeScalingEnabled() then
            redecayBefore = computeMultipliersForDays(doneAtDays)
        else
            redecayBefore = { base = 0, nature = 0, urban = 0, vehicles = 0 }
        end
    else
        redecayBefore = nil
    end
end

function WDecay_Scaling.clearRedecayContext()
    redecayDoneAtDays = nil
    redecayBefore = nil
end

function WDecay_Scaling.getSeasonFactor(kind)
    local c = getConfig()
    if not c or not c.seasonalBias then return 1 end

    local gameTime = getGameTime()
    if not gameTime then return 1 end

    local month = gameTime:getMonth()
    local isWinter = month == 11 or month == 0 or month == 1
    local isSummer = month >= 5 and month <= 7
    local isAutumn = month >= 8 and month <= 10

    if kind == 'dryGrass' then
        if isWinter then return 1.5 end
        if isSummer then return 0.6 end
    elseif kind == 'grass' then
        if isWinter then return 0.6 end
        if isSummer then return 1.25 end
    elseif kind == 'leaves' then
        if isWinter then return 0.5 end
        if isAutumn then return 1.5 end
    end

    return 1
end

function WDecay_Scaling.printStatus()
    local c = getConfig()
    if not c then
        print("[WDecay] Scaling: sandbox not ready")
        return
    end

    local days = WDecay_Scaling.getWorldAgeDays()
    if not days then
        print("[WDecay] Scaling: GameTime not ready")
        return
    end

    local curveNames = { "linear", "logarithmic", "quadratic" }
    local modeNames = { "amplify", "progressive" }
    local curve = curveNames[c.curve] or "linear"
    if c.followErosion and c.erosionDays > 0 then
        curve = "erosion"
    end

    local function fmt(value)
        return math.floor(value * 100) / 100
    end

    print("[WDecay] Scaling: enabled=" .. tostring(c.enabled)
        .. " mode=" .. (modeNames[c.mode] or "amplify")
        .. " age=" .. math.floor(days) .. "d" .. (debugAgeDays ~= nil and "*" or "")
        .. " curve=" .. curve
        .. " mult(base/n/u/v)=" .. fmt(WDecay_Scaling.getMultiplier())
        .. "/" .. fmt(WDecay_Scaling.getMultiplierFor('nature'))
        .. "/" .. fmt(WDecay_Scaling.getMultiplierFor('urban'))
        .. "/" .. fmt(WDecay_Scaling.getMultiplierFor('vehicles'))
        .. " redecay=" .. tostring(c.redecayEnabled))
end

function WDecay_Scaling.setDebugAgeDays(days)
    if days ~= nil then
        days = tonumber(days)
        if days == nil then return end
        if days < 0 then days = 0 end
    end

    debugAgeDays = days
    cfg = nil
    cachedMultipliers = nil
end

function WDecay_Scaling.getDebugAgeDays()
    return debugAgeDays
end

function WDecay_Scaling.reset()
    cfg = nil
    cachedMultipliers = nil
end

local function announceStatus()
    WDecay_Scaling.reset()
    WDecay_Scaling.printStatus()
end

Events.OnInitGlobalModData.Add(WDecay_Scaling.reset)
Events.EveryDays.Add(WDecay_Scaling.reset)
Events.OnGameStart.Add(announceStatus)
if Events.OnServerStarted then
    Events.OnServerStarted.Add(announceStatus)
end

return WDecay_Scaling
