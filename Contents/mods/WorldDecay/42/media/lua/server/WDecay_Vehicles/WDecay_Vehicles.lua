local WDecay_Random = require('wdecay_random/wdecay_random')

local WDecay_Vehicles = {}

local randomizer = newrandom()
randomizer:seed(ZombRand(1, 2147483647))

local sandboxCache = {}
local function sb(key, fallback)
    if sandboxCache[key] == nil then
        local s = getSandboxOptions()
        if not s then sandboxCache[key] = fallback
        else
            local o = s:getOptionByName('WDecay.' .. key)
            local v = o and o:getValue()
            sandboxCache[key] = v ~= nil and v or fallback
        end
    end

    return sandboxCache[key]
end

local function getRustMin()
    return sb('vehicleRustMin', 80) / 100.0
end

local function getRustMax()
    return sb('vehicleRustMax', 100) / 100.0
end

local function getBloodMin()
    return sb('vehicleBloodMin', 0) / 100.0
end

local function getBloodMax()
    return sb('vehicleBloodMax', 30) / 100.0
end

local function getOpt(category, suffix)
    return sb(category .. suffix, 0)
end

local PART_MAP = {
    Engine     = "engine",
    Battery    = "battery",
    GasTank    = "gasTank",
    EngineDoor = "hood",
    Muffler    = "muffler",
    GloveBox   = "gloveBox",
    Radio      = "radio",
    Heater     = "heater",
}

local function classifyPart(part)
    local id = part:getId()
    if not id then return nil end

    local cat = PART_MAP[id]
    if cat then return cat end

    if id:find("Brake") then
        return "brake"
    elseif id:find("Suspension") then
        return "suspension"
    elseif id:find("Tire") then
        return "tire"
    elseif id:find("Window") or id:find("Windshield") or part:getWindow() then
        return "window"
    elseif id:find("HeadlightRear") then
        return "taillight"
    elseif id:find("Headlight") then
        return "headlight"
    elseif id:find("Door") then
        return "door"
    elseif id:find("Trunk") or id:find("TruckBed") then
        return "trunk"
    elseif part:getWheelIndex() >= 0 then
        return "tire"
    end

    return nil
end

local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')

local function adjChance(value)
    if WDecay_Scaling.isSeverityScalingEnabled() then
        return WDecay_Scaling.scaleSeverity('vehicles', value)
    end

    return value
end

local function adjCondition(value)
    if WDecay_Scaling.isSeverityScalingEnabled() then
        return math.floor(WDecay_Scaling.scaleDownFor('vehicles', value))
    end

    return value
end

local function damagePart(vehicle, part, category, missingWheel)
    local miss = adjChance(getOpt(category, 'MissingChance'))

    if category == "tire" then
        if miss > 0 and randomizer:random(0, 100) < miss then
            local wIdx = part:getWheelIndex()
            if wIdx >= 0 then missingWheel[wIdx] = true end

            part:setInventoryItem(nil)
            return
        end
    elseif category == "brake" or category == "suspension" then
        if miss > 0 and randomizer:random(0, 100) < miss then
            -- Brakes/suspension sit under the tire (see vehicle scripts:
            -- both declare area = Tire<pos> and requireUninstalled = Tire<pos>),
            -- so removing one has to remove the tire too, the same way the
            -- "tire" branch above does it: setInventoryItem(nil), which also
            -- zeroes the tire's air/container content via doInventoryItemStats.
            local wIdx = part:getWheelIndex()
            local tirePart = wIdx < 0 and vehicle:getPartById(part:getArea()) or nil
            if tirePart then wIdx = tirePart:getWheelIndex() end

            if wIdx >= 0 and not missingWheel[wIdx] then
                missingWheel[wIdx] = true
                if tirePart then tirePart:setInventoryItem(nil) end
                local ok, err = pcall(function() vehicle:setTireRemoved(wIdx, true) end)
                if not ok then print("[WDecay] Vehicle tire removal error: " .. tostring(err):sub(1, 120)) end
            end

            part:setInventoryItem(nil)
            return
        end
    else
        if miss > 0 and randomizer:random(0, 100) < miss then
            part:setInventoryItem(nil)
            local childWindow = part.getChildWindow and part:getChildWindow()
            if childWindow then
                childWindow:setInventoryItem(nil)
            end
            return
        end
    end

    local chance = adjChance(getOpt(category, 'DamageChance'))
    if randomizer:random(0, 100) >= chance then return end

    local condMin = adjCondition(getOpt(category, 'ConditionMin'))
    local condMax = adjCondition(getOpt(category, 'ConditionMax'))
    if condMax < condMin then condMax = condMin end
    part:setCondition(randomizer:random(condMin, condMax + 1))

    if category == "battery" then
        local chargeMin = getOpt('battery', 'ChargeMin')
        local chargeMax = getOpt('battery', 'ChargeMax')
        local item = part:getInventoryItem()
        if item then
            item:setCurrentUsesFloat(randomizer:random(chargeMin, chargeMax + 1) / 100.0)
        end
    end
end

function WDecay_Vehicles.applyDeterioration(vehicle)
    if not vehicle then return end

    local vx = vehicle:getX()
    local vy = vehicle:getY()
    if vx and vy then
        WDecay_Random.reseedVehicle(randomizer, math.floor(vx), math.floor(vy))
    end

    local rustMin = getRustMin()
    local rustMax = getRustMax()
    local rust = rustMin + (randomizer:random(0, 100) / 100.0) * (rustMax - rustMin)
    vehicle:setRust(rust)
    vehicle:transmitRust()

    local bloodMin = getBloodMin()
    local bloodMax = getBloodMax()
    local blood = bloodMin + (randomizer:random(0, 100) / 100.0) * (bloodMax - bloodMin)
    vehicle:setBloodIntensity("Front", blood)
    vehicle:setBloodIntensity("Rear", blood * 0.5)
    vehicle:setBloodIntensity("Left", blood * 0.7)
    vehicle:setBloodIntensity("Right", blood * 0.7)
    vehicle:transmitBlood()

    local generalCond = sb('generalCondition', 100)
    if generalCond < 100 then
        local generalChance = sb('generalConditionChance', 100)
        local ok, err = pcall(function() vehicle:setGeneralPartCondition(generalCond / 100.0, generalChance) end)
        if not ok then print("[WDecay] Vehicle condition error: " .. tostring(err):sub(1, 120)) end
    end

    local missingWheel = {}
    local partCount = vehicle:getPartCount()
    for i = 0, partCount - 1 do
        local part = vehicle:getPartByIndex(i)
        if part then
            local category = classifyPart(part)
            if category then
                damagePart(vehicle, part, category, missingWheel)
            end
        end
    end

    vehicle:setGoodCar(false)
end

return WDecay_Vehicles
