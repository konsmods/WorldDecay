-- Shared season/snow detection for anything that wants to mirror vanilla's own
-- erosion sprite selection (see WDecay_Trees.lua and WDecay_Bushes.lua for the
-- frame-formula research this feeds). Exposes vanilla's own season VALUE
-- numbering (not just the display name), since that's what the frame formulas
-- for both trees and bushes are keyed on: 0 = Winter (and late Autumn --
-- vanilla reuses slot 0 for both, meaning "no foliage"), 1 = Spring,
-- 2 = Summer, 4 = Autumn. (3 = "Summer2" in vanilla's internal split isn't
-- surfaced by getSeasonName(), so it's folded into Summer here.)
local WDecay_Season = {}

local SEASON_NAME_TO_VALUE = { Winter = 0, Spring = 1, Summer = 2, Autumn = 4 }
local KNOWN_SEASON_NAMES = { Spring = true, Summer = true, Autumn = true, Winter = true }

-- B42 can return phase-qualified names such as "Early Summer" and "Late
-- Autumn". The rest of WorldDecay works with the four canonical seasons, so
-- preserve the climate manager's season while discarding only that phase
-- prefix. Falling back to the calendar month for these names made a debug
-- jump (and custom season lengths) report/use the wrong season.
local function normalizeSeasonName(name)
    if not name then return nil end

    if KNOWN_SEASON_NAMES[name] then
        return name
    end

    local text = tostring(name)
    for _, seasonName in ipairs({ "Spring", "Summer", "Autumn", "Winter" }) do
        if string.find(text, seasonName, 1, true) then
            return seasonName
        end
    end

    return nil
end

-- getClimateManager():getSeasonName() isn't reliably ready during the initial
-- burst of chunk generation when a world is first created -- fall back to
-- simple calendar-month bucketing (same idea NTP uses), which is always
-- available, rather than silently treating "not ready yet" as "no foliage".
local function getFallbackSeasonName()
    local gameTime = getGameTime()
    if not gameTime then return nil end
    local month = gameTime:getMonth() + 1
    if month == 12 or month <= 2 then return "Winter" end
    if month >= 3 and month <= 5 then return "Spring" end
    if month >= 6 and month <= 8 then return "Summer" end
    return "Autumn"
end

-- getSeasonName()/isSnowing() get called once per tree/bush/grass/vine pick,
-- and the dispatcher can roll placement on hundreds of squares per scan --
-- cache both rather than hitting getClimateManager() fresh on every single
-- call. Ten minutes matches vanilla's own ErosionMain.EveryTenMinutes()
-- update rate (see WDecay_*_Reseason.lua, which checks on the same cadence
-- so snow can be caught within the same window vanilla would notice it).
local cachedSeasonName = nil -- nil = not cached, false = cached as unavailable, string = cached value
local cachedIsSnowing = nil -- nil = not cached, true/false = cached

function WDecay_Season.invalidateCache()
    cachedSeasonName = nil
    cachedIsSnowing = nil
end
Events.EveryTenMinutes.Add(WDecay_Season.invalidateCache)

function WDecay_Season.getSeasonName()
    if cachedSeasonName == nil then
        local climate = getClimateManager()
        local rawSeasonName = climate and climate:getSeasonName()
        local seasonName = normalizeSeasonName(rawSeasonName)
        if not seasonName then
            seasonName = getFallbackSeasonName()
        end
        cachedSeasonName = seasonName or false
    end
    if cachedSeasonName == false then return nil end
    return cachedSeasonName
end

function WDecay_Season.getSeasonValue()
    local seasonName = WDecay_Season.getSeasonName()
    return seasonName and SEASON_NAME_TO_VALUE[seasonName] or nil
end

function WDecay_Season.isSnowing()
    if cachedIsSnowing == nil then
        local climate = getClimateManager()
        cachedIsSnowing = climate ~= nil and climate:getSnowStrength() > 0
    end
    return cachedIsSnowing
end

-- Fraction of the year (0.0-1.0) elapsed, for bush bloom-window checks.
-- Cheap approximation: whole months only, ignores day-of-month.
function WDecay_Season.getYearFraction()
    local gameTime = getGameTime()
    if not gameTime then return nil end
    return gameTime:getMonth() / 12
end

return WDecay_Season
