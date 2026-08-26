local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WD_Logger = require("Logging/WD_Logger")

local WD_Code_Benchmark = {}
local iterationCount = 20000

local FILENAME = "WD_Code_Benchmark"

local A_BENCHMARK_KEY = "A-Benchmark"
local B_BENCHMARK_KEY = "B-Benchmark"

local function benchmarkA()

end

local function benchmarkB()

end

function WD_Code_Benchmark.benchmark()
    WD_Logger.printDebug("Starting Benchmark", FILENAME)
    for i = 1, iterationCount do
        WD_Debug_Metric.startTimeMeasurement(A_BENCHMARK_KEY)
        benchmarkA()
        WD_Debug_Metric.endTimeMeasurement(A_BENCHMARK_KEY)

        WD_Debug_Metric.startTimeMeasurement(B_BENCHMARK_KEY)
        benchmarkB()
        WD_Debug_Metric.endTimeMeasurement(B_BENCHMARK_KEY)
    end

    WD_Debug_Metric.printWithName(A_BENCHMARK_KEY)
    WD_Debug_Metric.printWithName(B_BENCHMARK_KEY)

    WD_Logger.printDebug("Successful Benchmark", FILENAME)
    WD_Logger.flushBuffer()
end

return WD_Code_Benchmark
