local debugCounters = {}
local debugLastPrint = 0
local DEBUG_PRINT_INTERVAL = 600
local countersInitialized = false

local function ensureDebugCounters()
    if not countersInitialized then
        debugCounters.ChunksProcessed = 0
        debugCounters.ChunksFailed = 0
        debugCounters.SquaresProcessed = 0
        debugCounters.Passes = { initial = 0, redecay = 0, seasonal = 0 }
        debugCounters.Objects = { grass = 0, bush = 0, tree = 0 }
        debugCounters.Transmissions = { complete = 0, modData = 0, sprite = 0, overlay = 0 }
        debugCounters.Placement = {}
        debugCounters.Modifier = {}
        countersInitialized = true
    end

    if WDecay_PlacementGenerators then
        for i = 1, #WDecay_PlacementGenerators do
            if debugCounters.Placement[i] == nil then debugCounters.Placement[i] = 0 end
        end
    end
    if WDecay_ModifierGenerators then
        for i = 1, #WDecay_ModifierGenerators do
            if debugCounters.Modifier[i] == nil then debugCounters.Modifier[i] = 0 end
        end
    end
end

local initDebugCounters = ensureDebugCounters

Events.OnGameStart.Add(function()
    initDebugCounters()
    print("[WDecay-Debug] Counters initialized")
end)

if Events.OnInitGlobalModData then
    Events.OnInitGlobalModData.Add(ensureDebugCounters)
end

Events.EveryOneMinute.Add(function()
    ensureDebugCounters()

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
    if WDecay_Debug then
        print("[WDecay-Debug] Queue: " .. WDecay_Debug.queueHigh .. "/" .. WDecay_Debug.queueLow .. " added=" .. WDecay_Debug.queueAdded .. " requeued=" .. WDecay_Debug.queueRequeued .. " done=" .. WDecay_Debug.queueCompleted .. " failed=" .. WDecay_Debug.queueFailed)
    end
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
    ensureDebugCounters()
    if debugCounters.Placement and debugCounters.Placement[index] then
        debugCounters.Placement[index] = debugCounters.Placement[index] + 1
    end
end

function WDecay_DebugCountModifier(index)
    ensureDebugCounters()
    if debugCounters.Modifier and debugCounters.Modifier[index] then
        debugCounters.Modifier[index] = debugCounters.Modifier[index] + 1
    end
end

function WDecay_DebugCountChunk(success)
    ensureDebugCounters()
    if not debugCounters.ChunksProcessed then return end

    if success then
        debugCounters.ChunksProcessed = debugCounters.ChunksProcessed + 1
    else
        debugCounters.ChunksFailed = debugCounters.ChunksFailed + 1
    end
end

function WDecay_DebugCountObject(kind)
    ensureDebugCounters()
    if debugCounters.Objects and debugCounters.Objects[kind] then
        debugCounters.Objects[kind] = debugCounters.Objects[kind] + 1
    end
end

function WDecay_DebugCountTransmission(kind)
    ensureDebugCounters()
    if debugCounters.Transmissions and debugCounters.Transmissions[kind] then
        debugCounters.Transmissions[kind] = debugCounters.Transmissions[kind] + 1
    end
end

function WDecay_DebugCountPass(kind)
    ensureDebugCounters()
    if debugCounters.Passes and debugCounters.Passes[kind] then
        debugCounters.Passes[kind] = debugCounters.Passes[kind] + 1
    end
end

function WDecay_DebugPrintStatus()
    ensureDebugCounters()

    print("[WDecay-Debug] === MANUAL STATUS ===")
    print("[WDecay-Debug] Chunks processed: " .. debugCounters.ChunksProcessed)
    print("[WDecay-Debug] Chunks failed (not ready): " .. debugCounters.ChunksFailed)

    if debugCounters.Objects then
        print("[WDecay-Debug] Objects: grass=" .. debugCounters.Objects.grass .. " bush=" .. debugCounters.Objects.bush .. " tree=" .. debugCounters.Objects.tree)
    end
    if debugCounters.Transmissions then
        print("[WDecay-Debug] Transmissions: complete=" .. debugCounters.Transmissions.complete .. " modData=" .. debugCounters.Transmissions.modData .. " sprite=" .. debugCounters.Transmissions.sprite .. " overlay=" .. debugCounters.Transmissions.overlay)
    end
    if debugCounters.Passes then
        print("[WDecay-Debug] Passes: initial=" .. debugCounters.Passes.initial .. " redecay=" .. debugCounters.Passes.redecay .. " seasonal=" .. debugCounters.Passes.seasonal)
    end

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
    totalTimedChunks = 0,
    objectsPlaced = 0,
    objectsPlacedInChunk = 0,
    queueAdded = 0,
    queueRequeued = 0,
    queueCompleted = 0,
    queueFailed = 0,
    queueHigh = 0,
    queueLow = 0,
    budgetMs = 0,
    scanRadius = 0
}

function WDecay_Debug.resetPerfCounters()
    WDecay_Debug.chunksHigh = 0
    WDecay_Debug.chunksLow = 0
    WDecay_Debug.totalChunkTimeMs = 0
    WDecay_Debug.totalChunksProcessed = 0
    WDecay_Debug.totalTimedChunks = 0
    WDecay_Debug.objectsPlaced = 0
    WDecay_Debug.queueAdded = 0
    WDecay_Debug.queueRequeued = 0
    WDecay_Debug.queueCompleted = 0
    WDecay_Debug.queueFailed = 0
    if debugCounters.Objects then
        for kind in pairs(debugCounters.Objects) do debugCounters.Objects[kind] = 0 end
    end
    if debugCounters.Transmissions then
        for kind in pairs(debugCounters.Transmissions) do debugCounters.Transmissions[kind] = 0 end
    end
    if debugCounters.Passes then
        for kind in pairs(debugCounters.Passes) do debugCounters.Passes[kind] = 0 end
    end
end

function WDecay_Debug.printPerfSummary(tickCounter)
    ensureDebugCounters()
    local okScaling, scaling = pcall(require, 'wdecay_scaling/wdecay_scaling')
    if okScaling and scaling and scaling.printStatus then
        scaling.printStatus()
    end

    local avg = 0
    if WDecay_Debug.totalTimedChunks > 0 then
        avg = WDecay_Debug.totalChunkTimeMs / WDecay_Debug.totalTimedChunks
    end

    local objects = debugCounters.Objects or {}
    local transmissions = debugCounters.Transmissions or {}
    local passes = debugCounters.Passes or {}
    print("[WDecay] Perf tick=" .. tickCounter .. " queue=" .. WDecay_Debug.queueHigh .. "/" .. WDecay_Debug.queueLow .. " added=" .. WDecay_Debug.queueAdded .. " requeued=" .. WDecay_Debug.queueRequeued .. " done=" .. WDecay_Debug.queueCompleted .. " failed=" .. WDecay_Debug.queueFailed .. " budget=" .. WDecay_Debug.budgetMs .. "ms radius=" .. WDecay_Debug.scanRadius .. " chunks=" .. WDecay_Debug.totalChunksProcessed .. " avg=" .. string.format("%.2f", avg) .. "ms placed=" .. WDecay_Debug.objectsPlaced .. " objects=" .. (objects.grass or 0) .. "/" .. (objects.bush or 0) .. "/" .. (objects.tree or 0) .. " tx=" .. (transmissions.complete or 0) .. "/" .. (transmissions.modData or 0) .. "/" .. (transmissions.sprite or 0) .. "/" .. (transmissions.overlay or 0) .. " passes=" .. (passes.initial or 0) .. "/" .. (passes.redecay or 0) .. "/" .. (passes.seasonal or 0))
    WDecay_Debug.resetPerfCounters()
end
