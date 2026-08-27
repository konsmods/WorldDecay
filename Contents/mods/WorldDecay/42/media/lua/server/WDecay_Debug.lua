local debugCounters = {}
local debugLastPrint = 0
local DEBUG_PRINT_INTERVAL = 600

local function initDebugCounters()
    debugCounters.ChunksProcessed = 0
    debugCounters.ChunksFailed = 0
    debugCounters.SquaresProcessed = 0

    if not WDecay_PlacementGenerators then return end

    if not WDecay_ModifierGenerators then return end

    debugCounters.Placement = {}
    debugCounters.Modifier = {}

    for i = 1, #WDecay_PlacementGenerators do
        debugCounters.Placement[i] = 0
    end

    for i = 1, #WDecay_ModifierGenerators do
        debugCounters.Modifier[i] = 0
    end
end

Events.OnGameStart.Add(function()
    initDebugCounters()
    print("[WDecay-Debug] Counters initialized")
end)

Events.EveryOneMinute.Add(function()
    if not debugCounters.Placement then return end

    debugLastPrint = debugLastPrint + 1
    if debugLastPrint < 10 then return end

    debugLastPrint = 0

    local placementTotal = 0
    for i = 1, #debugCounters.Placement do
        placementTotal = placementTotal + debugCounters.Placement[i]
    end

    local modifierTotal = 0
    for i = 1, #debugCounters.Modifier do
        modifierTotal = modifierTotal + debugCounters.Modifier[i]
    end

    print("[WDecay-Debug] === STATUS ===")
    print("[WDecay-Debug] Chunks processed: " .. debugCounters.ChunksProcessed)
    print("[WDecay-Debug] Chunks failed (not ready): " .. debugCounters.ChunksFailed)
    print("[WDecay-Debug] Placement generators calls: " .. placementTotal)
    print("[WDecay-Debug] Modifier generators calls: " .. modifierTotal)

    if WDecay_PlacementGenerators then
        for i = 1, #WDecay_PlacementGenerators - 1 do
            if debugCounters.Placement[i] > 0 then
                print("[WDecay-Debug]   Placement[" .. i .. "]: " .. debugCounters.Placement[i] .. " calls")
            end
        end
    end

    if WDecay_ModifierGenerators then
        --Size is not index-range. #WDecay_ModifierGenerators give you the size. size - l = index-range. Size starts by 1 and index by 0 
        for i = 1, #WDecay_ModifierGenerators - 1 do
            if debugCounters.Modifier[i] > 0 then
                print("[WDecay-Debug]   Modifier[" .. i .. "]: " .. debugCounters.Modifier[i] .. " calls")
            end
        end
    end

    print("[WDecay-Debug] ==============")
end)

function WDecay_DebugCountPlacement(index)
    if debugCounters.Placement and debugCounters.Placement[index] then
        debugCounters.Placement[index] = debugCounters.Placement[index] + 1
    end
end

function WDecay_DebugCountModifier(index)
    if debugCounters.Modifier and debugCounters.Modifier[index] then
        debugCounters.Modifier[index] = debugCounters.Modifier[index] + 1
    end
end

function WDecay_DebugCountChunk(success)
    if not debugCounters.ChunksProcessed then return end

    if success then
        debugCounters.ChunksProcessed = debugCounters.ChunksProcessed + 1
    else
        debugCounters.ChunksFailed = debugCounters.ChunksFailed + 1
    end
end

function WDecay_DebugPrintStatus()
    if not debugCounters.Placement then
        print("[WDecay-Debug] Counters not initialized yet")
        return
    end

    print("[WDecay-Debug] === MANUAL STATUS ===")
    print("[WDecay-Debug] Chunks processed: " .. debugCounters.ChunksProcessed)
    print("[WDecay-Debug] Chunks failed (not ready): " .. debugCounters.ChunksFailed)

    if WDecay_PlacementGenerators then
        print("[WDecay-Debug] Placement generators (" .. #WDecay_PlacementGenerators .. " total):")
        for i = 1, #WDecay_PlacementGenerators do
            print("[WDecay-Debug]   [" .. i .. "] calls=" .. debugCounters.Placement[i])
        end
    end

    if WDecay_ModifierGenerators then
        print("[WDecay-Debug] Modifier generators (" .. #WDecay_ModifierGenerators .. " total):")
        for i = 1, #WDecay_ModifierGenerators do
            print("[WDecay-Debug]   [" .. i .. "] calls=" .. debugCounters.Modifier[i])
        end
    end

    print("[WDecay-Debug] ===================")
end

print("[WDecay-Debug] Debug module loaded. Type in console: WDecay_DebugPrintStatus()")

WDecay_Debug = {
    chunksHigh = 0,
    chunksLow = 0,
    totalChunkTimeMs = 0,
    totalChunksProcessed = 0,
    objectsPlaced = 0,
    objectsPlacedInChunk = 0
}

function WDecay_Debug.resetPerfCounters()
    WDecay_Debug.chunksHigh = 0
    WDecay_Debug.chunksLow = 0
    WDecay_Debug.totalChunkTimeMs = 0
    WDecay_Debug.totalChunksProcessed = 0
    WDecay_Debug.objectsPlaced = 0
end

function WDecay_Debug.printPerfSummary(tickCounter)
    local okScaling, scaling = pcall(require, 'wdecay_scaling/wdecay_scaling')
    if okScaling and scaling and scaling.printStatus then
        scaling.printStatus()
    end

    local avg = 0
    if WDecay_Debug.totalChunksProcessed > 0 then
        avg = math.floor(WDecay_Debug.totalChunkTimeMs / WDecay_Debug.totalChunksProcessed)
    end

    print("[WDecay] Perf tick=" .. tickCounter .. " chunks(H=" .. WDecay_Debug.chunksHigh .. "/L=" .. WDecay_Debug.chunksLow .. ") avg=" .. avg .. "ms total=" .. WDecay_Debug.totalChunksProcessed .. " placed=" .. WDecay_Debug.objectsPlaced)
    WDecay_Debug.resetPerfCounters()
end
