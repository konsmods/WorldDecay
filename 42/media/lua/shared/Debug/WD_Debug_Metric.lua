local WD_Logger = require("Logging/WD_Logger")

local isDebug = isDebugEnabled()

local FILENAME = "WD_Debug_Metric"
local MICRO_SCALE = 1000
local MILI_SCALE = 1000 * MICRO_SCALE

WD_Debug_Metric = {}

GameTime.setServerTimeShift(0)

local dataLookup = {}

local function getMsAsFloat()
    return GameTime.getServerTime() / MILI_SCALE
end

local function initSubTable(name)
    dataLookup[name] = { startTime = 0, hasStarted = false, callCount = 0, avgTime = 0, highest = 0, totalTime = 0, lowest = 2147483647 }
end

function WD_Debug_Metric.startTimeMeasurement(name)
    if isDebug then
        local metric = dataLookup[name]

        if not metric then
            initSubTable(name)
            metric = dataLookup[name]
        end

        if not metric.hasStarted then
            metric.startTime = getMsAsFloat()
            metric.hasStarted = true

            dataLookup[name] = metric
        else

            WD_Logger.printDebug("Time measurement of code section '" .. tostring(name) .. "' has already begun.", FILENAME)
        end
    end
end

function WD_Debug_Metric.endTimeMeasurement(name)
    if isDebug then
        local endTime = getMsAsFloat()
        local metric = dataLookup[name]

        if metric and metric.hasStarted then
            local delta = endTime - metric.startTime

            metric.hasStarted = false
            metric.callCount = metric.callCount + 1
            metric.totalTime = metric.totalTime + delta

            if metric.highest < delta then
                metric.highest = delta
            end

            if metric.lowest > delta then
                metric.lowest = delta
            end

            if metric.totalTime > 0 then
                metric.avgTime = metric.totalTime / metric.callCount
            end
        else
            WD_Logger.printDebug("Time measurement of code section '" .. tostring(name) .. "' don't have a start time.", FILENAME)
        end
    end
end

function WD_Debug_Metric.stopTimeMeasurement(name)
    if isDebug then
        local metric = dataLookup[name]

        if metric then
            metric.hasStarted = false
            metric.startTime = 0
        end
    end
end

function WD_Debug_Metric.printWithName(name)
    WD_Logger.printInfo("############ " .. name .. " ############", FILENAME)
    WD_Logger.printInfo("Callcount:          " .. tostring(dataLookup[name].callCount), FILENAME)
    WD_Logger.printInfo("Average Time:       " .. string.format("%.3f", tostring(dataLookup[name].avgTime)) .. "ms", FILENAME)
    WD_Logger.printInfo("Highest:            " .. string.format("%.3f", tostring(dataLookup[name].highest)) .. "ms", FILENAME)
    WD_Logger.printInfo("Lowest:             " .. string.format("%.3f", tostring(dataLookup[name].lowest)) .. "ms", FILENAME)
    WD_Logger.printInfo("Total Time:         " .. string.format("%.3f", tostring(dataLookup[name].totalTime)) .. "ms", FILENAME)
end

function WD_Debug_Metric.print()
    WD_Logger.printInfo("=====================  -Performance Metric STARTED-  =====================", FILENAME)
    for key, _ in pairs(dataLookup) do
        WD_Debug_Metric.printWithName(key)
    end

    WD_Logger.printInfo("=====================   -Performance Metric END-   =====================", FILENAME)
    WD_Logger.flushBuffer()
end

if isDebug then
    Events.OnPostSave.Add(function()
        if isGameActive then
            WD_Debug_Metric.print()
            isGameActive = false
        end
    end)
    Events.OnInitGlobalModData.Add(function()
        isGameActive = true
    end)
end

return WD_Debug_Metric
