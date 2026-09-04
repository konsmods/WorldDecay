local WDecay_SquareCheck = require('wdecay_squarecheck/wdecay_squarecheck')
local WD_Logger = require("Logging/WD_Logger")
local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WD_Code_Benchmark = require("Debug/WD_Code_Benchmark")

WD_DebugTools = {}

WD_DebugTools.FLAG_GENERATE_SQUARE = 1
WD_DebugTools.FLAG_PRINT_CHECKRESULT = 2
WD_DebugTools.FLAG_STFU_OBJECT_BUFFER = 3
WD_DebugTools.FLAG_PRINT_METRIC = 4
WD_DebugTools.FLAG_BENCHMARK = 5

function WD_DebugTools.disableObjectBufferLog()
    WD_Logger.muteLog("WDecay_Object_Buffer")
end

function WD_DebugTools.printMetric()
    WD_Debug_Metric.print()
end

function WD_DebugTools.printCheckResult(square)
    if square then 
        local level = square:getZ()
        local checkResult = WDecay_SquareCheck.checkAll(square, level)
        WDecay_SquareCheck.printCheckResult(checkResult)
    end
end

function WD_DebugTools.generateSquare(square)
    if square then 
        local level = square:getZ()
        local checkResult = WDecay_SquareCheck.checkAll(square, level)

        if WDecay_PlacementGenerators then
            for i = 1, #WDecay_PlacementGenerators do
                local fn = WDecay_PlacementGenerators[i]
                if fn and fn(square, checkResult, level) then
                    if WDecay_DebugCountPlacement then
                        WDecay_DebugCountPlacement(i)
                    end

                    break
                end
            end
        end

        if not checkResult.hasWalls and not checkResult.hasWindow
            and not checkResult.isRoad and not checkResult.room
            and not checkResult.hasFences then
            return
        end

        if WDecay_ModifierGenerators then
            local mg = WDecay_ModifierGenerators
            if checkResult.hasWalls or checkResult.hasWindow or checkResult.hasFences or checkResult.room then
                local fn = mg[1]
                if fn then fn(square, checkResult, level) end

                if WDecay_DebugCountModifier then WDecay_DebugCountModifier(1) end
            end

            if checkResult.room then
                local fn = mg[2]
                if fn then fn(square, checkResult, level) end

                if WDecay_DebugCountModifier then WDecay_DebugCountModifier(2) end
            end

            if checkResult.hasFences then
                local fn = mg[3]
                if fn then fn(square, checkResult, level) end

                if WDecay_DebugCountModifier then WDecay_DebugCountModifier(3) end
            end

            if checkResult.hasWalls or checkResult.hasFences then
                local fn = mg[4]
                if fn then fn(square, checkResult, level) end

                if WDecay_DebugCountModifier then WDecay_DebugCountModifier(4) end
            end

            if checkResult.hasWalls or checkResult.hasFences then
                local fn = mg[5]
                if fn then fn(square, checkResult, level) end

                if WDecay_DebugCountModifier then WDecay_DebugCountModifier(5) end
            end

            if checkResult.room then
                local fn = mg[6]
                if fn then fn(square, checkResult, level) end

                if WDecay_DebugCountModifier then WDecay_DebugCountModifier(6) end
            end

            if checkResult.hasRoof then
                local fn = mg[8]
                if fn then fn(square, checkResult, level) end

                if WDecay_DebugCountModifier then WDecay_DebugCountModifier(8) end
            end
        end
    end
end

function WD_DebugTools.benchmark()
    WD_Code_Benchmark.benchmark()
end

return WD_DebugTools
