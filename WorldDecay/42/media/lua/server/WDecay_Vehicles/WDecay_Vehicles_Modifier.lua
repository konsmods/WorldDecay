local WD_Debug_Metric = require("Debug/WD_Debug_Metric")

local TIME_KEY = "WDecay_Vehicles-OnSpawnVehicleEnd"

local WDecay_Vehicles = require('WDecay_Vehicles/WDecay_Vehicles')

local cachedVehicleDecayEnabled = nil
local function isVehicleDecayEnabled()
    if cachedVehicleDecayEnabled == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.vehicleDecayEnabled')
        cachedVehicleDecayEnabled = opt and opt:getValue()
        if cachedVehicleDecayEnabled == nil then cachedVehicleDecayEnabled = true end
    end

    return cachedVehicleDecayEnabled
end

local function OnSpawnVehicleEnd(vehicle)
    if isVehicleDecayEnabled() then
        local modData = vehicle:getModData()
        if not modData["WDecay_Processed"] then
            WDecay_Vehicles.applyDeterioration(vehicle)
            modData["WDecay_Processed"] = true
        end
    end
end

local patchedFunction = OnSpawnVehicleEnd

local function debugOnSpawnVehicleEnd(vehicle)
    WD_Debug_Metric.startTimeMeasurement(TIME_KEY)
    pcall(patchedFunction, vehicle)
    WD_Debug_Metric.endTimeMeasurement(TIME_KEY)
end

if isDebugEnabled() then 
    OnSpawnVehicleEnd = debugOnSpawnVehicleEnd 
end

Events.OnSpawnVehicleEnd.Add(OnSpawnVehicleEnd)

return WDecay_Vehicles
