require('luautils')

local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Carry = require('wdecay_carry/wdecay_carry')
local WDecay_Placement = require('wdecay_placement/wdecay_placement')
local WDecay_Trees = require('WDecay_Trees/WDecay_Trees')
local WDecay_Bushes = require('WDecay_Bushes/WDecay_Bushes')
local WDecay_Grass = require('WDecay_Grass/WDecay_Grass')
local WDecay_Features = require('wdecay_features/wdecay_features')

-- Bump only when the meaning of a completed chunk changes.
local CACHE_VERSION = 4

-- Version the scan cache independently; changing it never regenerates chunks.
local SCAN_CACHE_VERSION = 1

local DEBUG_MODE = false

local seenChunks = {}
local modDataTable = nil

-- One resumable active job per tier. High always runs before low.
local chunkQueueTailHigh = 0
local chunkQueueTailLow = 0
local chunkQueueHeadHigh = 1
local chunkQueueHeadLow = 1
local chunkQueueHighChunks = {}
local chunkQueueHighKeys = {}
local chunkQueueLowChunks = {}
local chunkQueueLowKeys = {}
local pendingChunks = {}
local pendingOwners = {}
local pendingHigh = {}
local ownerQueueCounts = {}
local ownerHighQueueCounts = {}

-- Resumable state for the at most one active chunk in each tier.
local chunkWork = {}
local currentHighKey = nil
local currentHighChunk = nil
local currentLowKey = nil
local currentLowChunk = nil

-- Retry transient chunk-readiness failures, then apply a short cooldown.
local MAX_CHUNK_FAIL_RETRIES = 3
local CHUNK_FAIL_COOLDOWN_MS = 10000
local chunkFailAttempts = {}
local chunkFailCooldownUntilMs = {}

-- Report failure bursts with the periodic debug summary.
local failedCooldownCount = 0

local function chunkFailedTransiently(key, maxRetries)
    maxRetries = maxRetries or MAX_CHUNK_FAIL_RETRIES
    local attempts = (chunkFailAttempts[key] or 0) + 1
    if attempts <= maxRetries then
        chunkFailAttempts[key] = attempts
        return "pending"
    end
    chunkFailAttempts[key] = nil
    chunkFailCooldownUntilMs[key] = getTimestampMs() + CHUNK_FAIL_COOLDOWN_MS
    failedCooldownCount = failedCooldownCount + 1
    return false
end

local function chunkSucceeded(key)
    chunkFailAttempts[key] = nil
    chunkFailCooldownUntilMs[key] = nil
end

local function isChunkInFailCooldown(key)
    local untilMs = chunkFailCooldownUntilMs[key]
    return untilMs ~= nil and getTimestampMs() < untilMs
end

local TIME_BUDGET_MS = 10
local FAST_TRAVEL_SPEED_KMH = 30
local FAST_TRAVEL_BUDGET_MS = 8
local wasDrivingFast = false
local FAST_TRAVEL_PRIORITY_RADIUS = 2
local ROAD_GRASS_NATURAL_RANGE = 2

local SCAN_RADIUS = 15

-- Keep scan priority smaller than scan coverage so the low tier is useful.
local SCAN_PRIORITY_RADIUS = 5

local FAST_TRAVEL_SCAN_INTERVAL_SECONDS = 0.5
local FAST_TRAVEL_SCAN_RADIUS = 4
local SCAN_INTERVAL_SECONDS = 2.0
local debugTickCounter = 0

-- Limit queued work discovered by scans and bootstrap passes.
local MAX_QUEUE_DEPTH_FOR_SCAN = 60

local scanThrottledCount = 0
local scanRunCount = 0
local scanMovementSkippedCount = 0

local scanQueuedCount = 0

-- Low work receives a conservative share after high-priority work clears.
local LOW_BUDGET_FRACTION = 0.7

local function queueDepth()
    return math.max(0, chunkQueueTailHigh - chunkQueueHeadHigh + 1)
        + math.max(0, chunkQueueTailLow - chunkQueueHeadLow + 1)
end

local function highQueueDepth()
    return math.max(0, chunkQueueTailHigh - chunkQueueHeadHigh + 1)
end

-- Cap high discovery; skipped chunks are rediscovered by later scans.
local MAX_HIGH_QUEUE_DEPTH = 30
local trackedPlayerCount = 0

local function ownerQueueLimit(cap)
    return math.max(1, math.ceil(cap / math.max(1, trackedPlayerCount)))
end

local function canQueueForOwner(owner, high)
    if not owner then return true end
    if (ownerQueueCounts[owner] or 0) >= ownerQueueLimit(MAX_QUEUE_DEPTH_FOR_SCAN) then return false end
    return not high or (ownerHighQueueCounts[owner] or 0) < ownerQueueLimit(MAX_HIGH_QUEUE_DEPTH)
end

local function markPendingChunk(key, owner, high)
    pendingChunks[key] = true
    pendingOwners[key] = owner
    pendingHigh[key] = high or nil
    if owner then
        ownerQueueCounts[owner] = (ownerQueueCounts[owner] or 0) + 1
        if high then ownerHighQueueCounts[owner] = (ownerHighQueueCounts[owner] or 0) + 1 end
    end
end

local function clearPendingChunk(key)
    local owner = pendingOwners[key]
    if owner then
        ownerQueueCounts[owner] = math.max(0, (ownerQueueCounts[owner] or 1) - 1)
        if pendingHigh[key] then
            ownerHighQueueCounts[owner] = math.max(0, (ownerHighQueueCounts[owner] or 0) - 1)
        end
    end
    pendingChunks[key], pendingOwners[key], pendingHigh[key] = nil, nil, nil
end

-- Active player positions, refreshed once per tick.
local trackedPlayerX = {}
local trackedPlayerY = {}
local trackedPlayers = {}
local trackedPlayerKeys = {}
local trackedPlayerStates = {}
local trackedPlayerSource = "none"
local playerStates = {}
local lastScanOriginX = {}
local lastScanOriginY = {}
local lastRedecayCheckDay = {}
local scanRoundRobin = 0
local scanDeferredCount = 0
local scanDueCount = 0
local scanOldestOverdueMs = 0
local fastTravelVehicleCount = 0
local fastTravelMaxSpeedKmh = 0

local function playerKey(player, fallback)
    if player.getOnlineID then
        local id = player:getOnlineID()
        if id and id >= 0 then return "online:" .. id end
    end
    if player.getUsername then
        local username = player:getUsername()
        if username and username ~= "" then return "user:" .. username end
    end
    return trackedPlayerSource .. ":" .. fallback
end

local function refreshTrackedPlayers()
    trackedPlayerCount = 0
    trackedPlayerSource = "none"
    local numPlayers = getNumActivePlayers and getNumActivePlayers() or 0
    for i = 0, numPlayers - 1 do
        local player = getSpecificPlayer(i)
        if player then
            trackedPlayerCount = trackedPlayerCount + 1
            trackedPlayers[trackedPlayerCount] = player
            trackedPlayerX[trackedPlayerCount] = player:getX()
            trackedPlayerY[trackedPlayerCount] = player:getY()
            trackedPlayerSource = "local"
        end
    end
    if trackedPlayerCount == 0 then
        local online = getOnlinePlayers()
        if online and online.size then
            for i = 0, online:size() - 1 do
                local p = online:get(i)
                if p then
                    trackedPlayerCount = trackedPlayerCount + 1
                    trackedPlayers[trackedPlayerCount] = p
                    trackedPlayerX[trackedPlayerCount] = p:getX()
                    trackedPlayerY[trackedPlayerCount] = p:getY()
                    trackedPlayerSource = "online"
                end
            end
        end
    end
    -- Offline SP needs player 0 as a fallback.
    if trackedPlayerCount == 0 and getSpecificPlayer then
        local player = getSpecificPlayer(0)
        if player then
            trackedPlayerCount = 1
            trackedPlayers[1] = player
            trackedPlayerX[1] = player:getX()
            trackedPlayerY[1] = player:getY()
            trackedPlayerSource = "offline-player-0"
        end
    end
    local active = {}
    for i = 1, trackedPlayerCount do
        local key = playerKey(trackedPlayers[i], i)
        local state = playerStates[key]
        if not state then
            state = { key = key, nextScanAtMs = 0, startupScans = 0 }
            playerStates[key] = state
        end
        state.player = trackedPlayers[i]
        state.x, state.y = trackedPlayerX[i], trackedPlayerY[i]
        trackedPlayerKeys[i], trackedPlayerStates[i] = key, state
        active[key] = true
    end
    for key in pairs(playerStates) do
        if not active[key] then
            playerStates[key] = nil
            lastScanOriginX[key], lastScanOriginY[key], lastRedecayCheckDay[key] = nil, nil, nil
        end
    end
    for i = trackedPlayerCount + 1, #trackedPlayers do
        trackedPlayers[i], trackedPlayerKeys[i], trackedPlayerStates[i] = nil, nil, nil
    end
end

-- Updates fast-travel status inputs and returns whether the threshold is met.
local function isAnyPlayerDrivingFast(thresholdKmh)
    fastTravelVehicleCount = 0
    fastTravelMaxSpeedKmh = 0
    for i = 1, trackedPlayerCount do
        local vehicle = trackedPlayers[i]:getVehicle()
        local state = trackedPlayerStates[i]
        local speed = 0
        if vehicle then
            fastTravelVehicleCount = fastTravelVehicleCount + 1
            speed = vehicle:getCurrentSpeedKmHour() or 0
            if speed > fastTravelMaxSpeedKmh then fastTravelMaxSpeedKmh = speed end
        end
        if state then
            state.fast = vehicle and FAST_TRAVEL_BUDGET_MS < TIME_BUDGET_MS and speed >= thresholdKmh or false
        end
    end
    return fastTravelMaxSpeedKmh >= thresholdKmh
end

local function playerScanRadius(state)
    return state and state.fast and FAST_TRAVEL_SCAN_RADIUS or SCAN_RADIUS
end

local function playerPriorityRadius(state)
    return state and state.fast and FAST_TRAVEL_PRIORITY_RADIUS or SCAN_PRIORITY_RADIUS
end

local function playerScanIntervalMs(state)
    local seconds = state and state.fast and FAST_TRAVEL_SCAN_INTERVAL_SECONDS or SCAN_INTERVAL_SECONDS
    return seconds * 1000
end

local function playerSqDistToChunk(state, wx, wy)
    local dx = wx * 8 + 4 - state.x
    local dy = wy * 8 + 4 - state.y
    return dx * dx + dy * dy
end

local function isInAnyPriorityBubble(wx, wy)
    for i = 1, trackedPlayerCount do
        local state = trackedPlayerStates[i]
        local radius = playerPriorityRadius(state)
        if playerSqDistToChunk(state, wx, wy) <= radius * radius * 64 then return true end
    end
    return false
end

-- Squared distance from a chunk center to its nearest tracked player.
local function nearestPlayerSqDistToChunk(wx, wy)
    local cx, cy = wx * 8 + 4, wy * 8 + 4
    local best = nil
    for i = 1, trackedPlayerCount do
        local dx = cx - trackedPlayerX[i]
        local dy = cy - trackedPlayerY[i]
        local d = dx * dx + dy * dy
        if not best or d < best then best = d end
    end
    return best
end

local MAX_STARTUP_SCAN_ATTEMPTS = 5

local SEEN_CHUNKS_MAX = 20000
local seenChunksCount = 0

-- Enabled generators, preserving their original registry index.
local activePlacementGenerators = nil
local activePlacementIndices = nil
local activeModifierGenerators = nil
local activeModifierIndices = nil
local buildActiveGeneratorLists

-- Unregister while fully idle; queueing re-registers the tick handler.
local onTickRegistered = true
local OnTick
-- Debug area queueing can promote nearby low work.
local prioritizeQueuedArea

local function ensureOnTickRegistered()
    if onTickRegistered then return end
    onTickRegistered = true
    Events.OnTick.Add(OnTick)
end

local dispatcherConfigLoaded = false
local function loadDispatcherConfig()
    local function getInt(name, default)
        local opt = getSandboxOptions():getOptionByName('WDecay.' .. name)
        return opt and opt:getValue() or default
    end

    local function getBool(name, default)
        local opt = getSandboxOptions():getOptionByName('WDecay.' .. name)
        if opt then return opt:getValue() end

        return default
    end

    local function getNumber(name, default)
        local opt = getSandboxOptions():getOptionByName('WDecay.' .. name)
        return opt and tonumber(opt:getValue()) or default
    end

    TIME_BUDGET_MS = getInt('timeBudgetMs', 10)
    FAST_TRAVEL_SPEED_KMH = getInt('fastTravelSpeedKmh', 30)
    FAST_TRAVEL_BUDGET_MS = getInt('fastTravelBudgetMs', 8)
    ROAD_GRASS_NATURAL_RANGE = math.max(1, math.min(getInt('roadGrassNaturalRange', 2), 5))
    SCAN_INTERVAL_SECONDS = getNumber('scanIntervalSeconds', 2.0)
    SCAN_RADIUS = getInt('scanRadius', 15)
    -- Preserve priority-radius invariants for old or unusual saved settings.
    SCAN_PRIORITY_RADIUS = math.min(getInt('scanPriorityRadius', 5), SCAN_RADIUS)
    FAST_TRAVEL_SCAN_RADIUS = math.min(getInt('fastTravelScanRadius', 4), SCAN_RADIUS)
    FAST_TRAVEL_PRIORITY_RADIUS = math.min(getInt('fastTravelPriorityRadius', 2), FAST_TRAVEL_SCAN_RADIUS)
    FAST_TRAVEL_SCAN_INTERVAL_SECONDS = getNumber('fastTravelScanIntervalSeconds', 0.5)
    DEBUG_MODE = getBool('debugMode', false)
    buildActiveGeneratorLists()
    dispatcherConfigLoaded = true

    -- No active work: remove future idle ticks.
    if onTickRegistered and #activePlacementGenerators == 0 and #activeModifierGenerators == 0
        and not WDecay_Features.isEnabled("overlays") and not WDecay_Scaling.isSeasonalBiasEnabled() then
        onTickRegistered = false
        Events.OnTick.Remove(OnTick)
    end

    if DEBUG_MODE then
        WDecay_Scaling.printStatus()
    end
end

local perfTickCounter = 0

-- Numeric key instead of a "wx:wy" string -- avoids a string alloc per
-- chunk on every scan cycle. wx/wy never come close to +/-2,000,000 on any
-- real map, keeping the packed key well inside 2^53 (max ~1.6e13).
local KEY_OFFSET = 2000000
local KEY_MULT = 4000001 -- > 2*KEY_OFFSET+1, so adjacent wx bands never overlap

local function GenerateKey(wx, wy)
    return (wx + KEY_OFFSET) * KEY_MULT + (wy + KEY_OFFSET)
end

local function isSafehouseChunk(wx, wy)
    if not SafeHouse or not SafeHouse.getSafehouseOverlapping then return false end
    return SafeHouse.getSafehouseOverlapping(wx * 8, wy * 8, wx * 8 + 7, wy * 8 + 7) ~= nil
end

local function markSeen(key)
    if seenChunks[key] then return end
    if seenChunksCount >= SEEN_CHUNKS_MAX then
        for oldKey in pairs(seenChunks) do
            seenChunks[oldKey] = nil
            if modDataTable then modDataTable[oldKey] = nil end
            seenChunksCount = seenChunksCount - 1
            break
        end
    end
    seenChunks[key] = true
    seenChunksCount = seenChunksCount + 1
    if modDataTable then modDataTable[key] = true end
end

-- Per-feature timing for the debug Status tab.
local generatorTimeMs = {}
local generatorCallCount = {}

local function recordGeneratorTime(name, deltaMs)
    generatorTimeMs[name] = (generatorTimeMs[name] or 0) + deltaMs
    generatorCallCount[name] = (generatorCallCount[name] or 0) + 1
end

local function runGenerator(fn, square, checkResult, level, category, index)
    local ok, result = pcall(fn, square, checkResult, level)
    if not ok then
        print("[WDecay] " .. category .. " generator " .. index .. " error at " .. square:getX() .. "," .. square:getY() .. "," .. square:getZ() .. ": " .. tostring(result):sub(1, 120))
        return false, false
    end
    return true, result == true
end

-- Filter disabled generators while retaining their registry index.
function buildActiveGeneratorLists()
    activePlacementGenerators = {}
    activePlacementIndices = {}
    if WDecay_PlacementGenerators then
        for i = 1, #WDecay_PlacementGenerators do
            local fn = WDecay_PlacementGenerators[i]
            local feature = WDecay_PlacementGeneratorFeatures and WDecay_PlacementGeneratorFeatures[i]
            if fn and (not feature or WDecay_Features.isEnabled(feature)) then
                local n = #activePlacementGenerators + 1
                activePlacementGenerators[n] = fn
                activePlacementIndices[n] = i
            end
        end
    end
    activeModifierGenerators = {}
    activeModifierIndices = {}
    if WDecay_ModifierGenerators then
        for i = 1, #WDecay_ModifierGenerators do
            local fn = WDecay_ModifierGenerators[i]
            local feature = WDecay_ModifierGeneratorFeatures and WDecay_ModifierGeneratorFeatures[i]
            if fn and (not feature or WDecay_Features.isEnabled(feature)) then
                local n = #activeModifierGenerators + 1
                activeModifierGenerators[n] = fn
                activeModifierIndices[n] = i
            end
        end
    end
end

-- Debug mode isolates generator errors by square and generator.
local function dispatchGeneratorsChecked(square, checkResult, level)
    local allSucceeded = true
    if activePlacementGenerators then
        for n = 1, #activePlacementGenerators do
            local fn = activePlacementGenerators[n]
            local origIndex = activePlacementIndices[n]
            local name = (WDecay_PlacementGeneratorFeatures and WDecay_PlacementGeneratorFeatures[origIndex]) or ("placement#" .. origIndex)
            local t0 = getTimestampMs()
            local ok, placed = runGenerator(fn, square, checkResult, level, "placement", origIndex)
            recordGeneratorTime(name, getTimestampMs() - t0)
            if not ok then allSucceeded = false end
            if placed then
                if WDecay_DebugCountPlacement then WDecay_DebugCountPlacement(origIndex) end
                break
            end
        end
    end
    if activeModifierGenerators then
        for n = 1, #activeModifierGenerators do
            local fn = activeModifierGenerators[n]
            local origIndex = activeModifierIndices[n]
            local name = (WDecay_ModifierGeneratorFeatures and WDecay_ModifierGeneratorFeatures[origIndex]) or ("modifier#" .. origIndex)
            local t0 = getTimestampMs()
            local ok = runGenerator(fn, square, checkResult, level, "modifier", origIndex)
            recordGeneratorTime(name, getTimestampMs() - t0)
            if not ok then allSucceeded = false end
        end
    end
    return allSucceeded
end

-- Release mode avoids per-generator pcall; the chunk-level guard still catches errors.
local function dispatchGeneratorsFast(square, checkResult, level)
    if activePlacementGenerators then
        for n = 1, #activePlacementGenerators do
            local fn = activePlacementGenerators[n]
            local origIndex = activePlacementIndices[n]
            local name = (WDecay_PlacementGeneratorFeatures and WDecay_PlacementGeneratorFeatures[origIndex]) or ("placement#" .. origIndex)
            local t0 = getTimestampMs()
            local placed = fn(square, checkResult, level)
            recordGeneratorTime(name, getTimestampMs() - t0)
            if placed then
                if WDecay_DebugCountPlacement then WDecay_DebugCountPlacement(origIndex) end
                break
            end
        end
    end
    if activeModifierGenerators then
        for n = 1, #activeModifierGenerators do
            local origIndex = activeModifierIndices[n]
            local name = (WDecay_ModifierGeneratorFeatures and WDecay_ModifierGeneratorFeatures[origIndex]) or ("modifier#" .. origIndex)
            local t0 = getTimestampMs()
            activeModifierGenerators[n](square, checkResult, level)
            recordGeneratorTime(name, getTimestampMs() - t0)
        end
    end
    return true
end

local function dispatchGenerators(square, checkResult, level)
    if DEBUG_MODE then
        return dispatchGeneratorsChecked(square, checkResult, level)
    end
    return dispatchGeneratorsFast(square, checkResult, level)
end

local function snapshotObjects(square)
    local existing = {}
    WDecay_Placement.forEachObject(square, function(object) existing[object] = true end)
    return existing
end

local function recordNewPlacements(markerData, square, checkResult, existing)
    WDecay_Placement.forEachObject(square, function(object)
        if object and not existing[object] then
            local modData = object:getModData()
            local cleanableType = modData and modData["WDecay_Cleanable"]
            local key = nil
            if cleanableType == "tree" then
                key = checkResult.isRoad and "WDecay_placedTreesRoad" or "WDecay_placedTreesNatural"
            elseif cleanableType == "bush" then
                if checkResult.isIndoor then
                    key = "WDecay_placedBushesIndoor"
                else
                    key = checkResult.isRoad and "WDecay_placedBushesRoad" or "WDecay_placedBushesNatural"
                end
            elseif cleanableType == "grass" then
                if checkResult.isIndoor then
                    key = "WDecay_placedGrassIndoor"
                else
                    key = checkResult.isRoad and "WDecay_placedGrassRoad" or "WDecay_placedGrassNatural"
                end
            end
            if key then markerData[key] = (markerData[key] or 0) + 1 end
        end
    end)
end

local WDecay_SquareCheck = require('wdecay_squarecheck/wdecay_squarecheck')
local WDecay_LoadedChunks = require('wdecay_loaded_chunks/wdecay_loaded_chunks')

-- Timed square classification used by performance diagnostics.
local squareCheckTimeMs = 0
local squareCheckCallCount = 0
local function cachedSquareCheck(square, level)
    local t0 = getTimestampMs()
    local result = WDecay_SquareCheck.checkAll(square, level)
    squareCheckTimeMs = squareCheckTimeMs + (getTimestampMs() - t0)
    squareCheckCallCount = squareCheckCallCount + 1
    return result
end

local getMarkerSquare = WDecay_LoadedChunks.getMarkerSquare

local function saveMarker(square)
    if not square then return end
    square:transmitModdata()
    square:flagForHotSave()
end

local function markChunkDone(square, data, days)
    data["WDecay_done"] = CACHE_VERSION
    if days then data["WDecay_doneAtDays"] = math.floor(days) end
    saveMarker(square)
end

local function isChunkMarkedDone(square)
    return square ~= nil and square:getModData()["WDecay_done"] == CACHE_VERSION
end

local function needsRedecay(square, cachedDays)
    if square == nil then return false end

    if not WDecay_Scaling.isRedecayEnabled() then return false end

    local days = cachedDays
    if days == nil then days = WDecay_Scaling.getWorldAgeDays() end
    if not days then return false end

    local modData = square:getModData()
    local doneAt = modData["WDecay_doneAtDays"]
    if doneAt == nil then
        return true
    end

    return (days - doneAt) >= WDecay_Scaling.getRedecayThresholdDays()
end

local function squareHasSprite(square, prefixes, cleanableType, objects)
    local found = false
    WDecay_Placement.forEachObject(square, function(obj)
        if obj then
            local modData = obj:getModData()
            if modData and cleanableType and modData["WDecay_Cleanable"] == cleanableType then
                found = true
            end

            local spriteName = obj:getSpriteName()
            if not found and spriteName then
                for p = 1, #prefixes do
                    if luautils.stringStarts(spriteName, prefixes[p]) then
                        found = true
                        break
                    end
                end
            end
        end
    end)
    return found
end

local carryCategories = {
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligTreesNatural",
        feature = "trees",
        carryKey = "WDecay_carryTreesNatural",
        placedKey = "WDecay_placedTreesNatural",
        eligible = function(checkResult, level)
            return level == 0 and checkResult and not checkResult.cleaned and checkResult.isNatural == true
        end,
        hasExisting = function(square, objects)
            return squareHasSprite(square, WDecay_Trees.getSpritePrefixes(), "tree", objects)
        end,
        basePercent = function() return WDecay_Trees.getBasePercentage() end,
        place = function(square)
            if not WDecay_Placement.isSafe(square) then return false end
            local baseSprite, childSprite = WDecay_Trees.pickTreeSprites()
            local tree = WDecay_Placement.createTaggedObject(square, baseSprite, "tree")
            if tree and childSprite and getSprite(childSprite) then
                tree:addAttachedAnimSpriteByName(childSprite)
            end
            return WDecay_Placement.finalizeObject(tree) ~= nil
        end,
    },
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligTreesRoad",
        feature = "trees",
        carryKey = "WDecay_carryTreesRoad",
        placedKey = "WDecay_placedTreesRoad",
        eligible = function(checkResult, level)
            return level == 0 and checkResult and not checkResult.cleaned
                and checkResult.isRoad == true and WDecay_Trees.getBasePercentageOnRoad() > 0
        end,
        hasExisting = function(square, objects)
            return squareHasSprite(square, WDecay_Trees.getSpritePrefixes(), "tree", objects)
        end,
        basePercent = function() return WDecay_Trees.getBasePercentageOnRoad() end,
        place = function(square)
            if not WDecay_Placement.isSafe(square) then return false end
            local baseSprite, childSprite = WDecay_Trees.pickTreeSprites()
            local tree = WDecay_Placement.createTaggedObject(square, baseSprite, "tree")
            if tree and childSprite and getSprite(childSprite) then
                tree:addAttachedAnimSpriteByName(childSprite)
            end
            return WDecay_Placement.finalizeObject(tree) ~= nil
        end,
    },
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligBushesNatural",
        feature = "bushes",
        carryKey = "WDecay_carryBushesNatural",
        placedKey = "WDecay_placedBushesNatural",
        eligible = function(checkResult, level)
            return level == 0 and checkResult and not checkResult.cleaned and checkResult.isNatural == true
        end,
        basePercent = function() return WDecay_Bushes.getBasePercentage() end,
        hasExisting = function(square, objects)
            return squareHasSprite(square, { "f_bushes_" }, "bush", objects)
        end,
        place = function(square)
            if not WDecay_Placement.isSafe(square) then return false end
            return WDecay_Bushes.spawnBush(square) ~= nil
        end,
    },
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligBushesRoad",
        feature = "bushes",
        carryKey = "WDecay_carryBushesRoad",
        placedKey = "WDecay_placedBushesRoad",
        eligible = function(checkResult, level)
            return level == 0 and checkResult and not checkResult.cleaned
                and checkResult.isRoad == true and WDecay_Bushes.getBasePercentageOnRoad() > 0
        end,
        basePercent = function() return WDecay_Bushes.getBasePercentageOnRoad() end,
        hasExisting = function(square, objects)
            return squareHasSprite(square, { "f_bushes_" }, "bush", objects)
        end,
        place = function(square)
            if not WDecay_Placement.isSafe(square) then return false end
            return WDecay_Bushes.spawnBush(square) ~= nil
        end,
    },
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligBushesIndoor",
        feature = "bushes",
        carryKey = "WDecay_carryBushesIndoor",
        placedKey = "WDecay_placedBushesIndoor",
        scanAllLevels = true,
        eligible = function(checkResult, level)
            if not checkResult or checkResult.cleaned then return false end
            if level ~= 0 then return checkResult.hasRoof == true and checkResult.isIndoor == true end
            return checkResult.isIndoor == true and WDecay_Bushes.getIndoorBasePercentage() > 0
        end,
        basePercent = function() return WDecay_Bushes.getIndoorBasePercentage() end,
        hasExisting = function(square, objects)
            return squareHasSprite(square, { "f_bushes_" }, "bush", objects)
        end,
        place = function(square)
            if not WDecay_Placement.isSafe(square) then return false end
            return WDecay_Bushes.spawnBush(square) ~= nil
        end,
    },
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligGrassNatural",
        feature = "grass",
        carryKey = "WDecay_carryGrassNatural",
        placedKey = "WDecay_placedGrassNatural",
        eligible = function(checkResult, level)
            return level == 0 and checkResult and not checkResult.cleaned and checkResult.isNatural == true
        end,
        basePercent = function() return WDecay_Grass.getBasePercentage() end,
        hasExisting = function(square, objects)
            return squareHasSprite(square, { "e_newgrass_", "d_generic_", "d_plants_" }, "grass", objects)
        end,
        place = function(square)
            if not WDecay_Placement.isSafe(square) then return false end
            return WDecay_Grass.spawnGrass(square) ~= nil
        end,
    },
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligGrassRoad",
        feature = "grass",
        carryKey = "WDecay_carryGrassRoad",
        placedKey = "WDecay_placedGrassRoad",
        eligible = function(checkResult, level)
            return level == 0 and checkResult and not checkResult.cleaned
                and checkResult.isRoad == true and WDecay_Grass.getBasePercentageOnRoad() > 0
        end,
        basePercent = function() return WDecay_Grass.getBasePercentageOnRoad() end,
        hasExisting = function(square, objects)
            return squareHasSprite(square, { "e_newgrass_", "d_generic_", "d_plants_" }, "grass", objects)
        end,
        place = function(square)
            if not WDecay_Placement.isSafe(square) then return false end
            return WDecay_Grass.spawnGrass(square) ~= nil
        end,
    },
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligGrassIndoor",
        feature = "grass",
        carryKey = "WDecay_carryGrassIndoor",
        placedKey = "WDecay_placedGrassIndoor",
        scanAllLevels = true,
        eligible = function(checkResult, level)
            if not checkResult or checkResult.cleaned then return false end
            if level ~= 0 then return checkResult.hasRoof == true and checkResult.isIndoor == true end
            return checkResult.isGoodSquare == true and checkResult.isIndoor == true
                and WDecay_Grass.getIndoorBasePercentage() > 0
        end,
        basePercent = function() return WDecay_Grass.getIndoorBasePercentage() end,
        hasExisting = function(square, objects)
            return squareHasSprite(square, { "e_newgrass_", "d_generic_", "d_plants_" }, "grass", objects)
        end,
        place = function(square)
            if not WDecay_Placement.isSafe(square) then return false end
            return WDecay_Grass.spawnGrass(square) ~= nil
        end,
    },
}

local carryNeedsAllLevels = false
for c = 1, #carryCategories do
    if carryCategories[c].scanAllLevels then
        carryNeedsAllLevels = true
        break
    end
end

local function isCarryCategoryEnabled(cat)
    return not cat.feature or WDecay_Features.isEnabled(cat.feature)
end

-- Keep eligibility bookkeeping even when redecay is currently disabled.
-- Sandbox settings can be enabled later, and existing chunks need this data
-- for their first redecay pass.
local function recordEligibility(markerData, checkResult, level)
    for c = 1, #carryCategories do
        local cat = carryCategories[c]
        if cat.eligible(checkResult, level) then
            markerData[cat.eligKey] = (markerData[cat.eligKey] or 0) + 1
        end
    end
end

-- Read by processChunkCarry (redecay: run urban carry modifiers?) and
-- WDecay_Vines_Reseason.lua (seasonal bias: vines possible here at all?
-- they're wall/fence overlays with no placed-count of their own).
local function recordUrbanFlag(markerData, checkResult)
    if checkResult.isUrban == true and markerData["WDecay_hasUrban"] ~= true then
        markerData["WDecay_hasUrban"] = true
    end
end

local ROAD_GRASS_CLUSTER_RADIUS = 2
local ROAD_GRASS_CLUSTER_SIZE = 3

local function hasNaturalNeighbor(state, x, y)
    local roadGrass = state.roadGrass
    local range = ROAD_GRASS_NATURAL_RANGE
    local width = 8 + range * 2
    for dy = -range, range do
        for dx = -range, range do
            local nx, ny = x + dx, y + dy
            if nx >= 0 and nx < 8 and ny >= 0 and ny < 8 then
                if roadGrass.natural[ny * 8 + nx + 1] then return true end
            else
                local haloIndex = (ny + range) * width + nx + range + 1
                local natural = roadGrass.haloNatural[haloIndex]
                if natural == nil then
                    local square = getSquare(state.wx * 8 + nx, state.wy * 8 + ny, 0)
                    natural = square and square:hasNaturalFloor() == true or false
                    roadGrass.haloNatural[haloIndex] = natural
                end
                if natural then return true end
            end
        end
    end
    return false
end

local function prepareRoadGrassPlan(state)
    local roadGrass = state.roadGrass
    if roadGrass.plan then return end
    roadGrass.plan = {}
    if not WDecay_Features.isEnabled("grass") then return end

    local chance = WDecay_Scaling.scaleFor('nature', WDecay_Grass.getBasePercentageOnRoad())
    if chance <= 0 then return end

    local candidates = {}
    for i = 1, #roadGrass.roads do
        local candidate = roadGrass.roads[i]
        if hasNaturalNeighbor(state, candidate.x, candidate.y) then
            candidates[#candidates + 1] = candidate
        end
    end
    local target = math.floor(#candidates * chance / 100 + 0.5)
    if target <= 0 then return end

    WDecay_Random.reseedForChunk(state.wx, state.wy, 700001)
    local rng = WDecay_Random.get()
    for i = #candidates, 2, -1 do
        local j = rng:random(1, i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    local used, center = {}, 1
    while #roadGrass.plan < target and center <= #candidates do
        local source = candidates[center]
        center = center + 1
        if not used[source] then
            used[source] = true
            roadGrass.plan[#roadGrass.plan + 1] = source
            for i = 1, #candidates do
                local candidate = candidates[i]
                if #roadGrass.plan >= target then break end
                if not used[candidate]
                    and math.abs(candidate.x - source.x) <= ROAD_GRASS_CLUSTER_RADIUS
                    and math.abs(candidate.y - source.y) <= ROAD_GRASS_CLUSTER_RADIUS then
                    used[candidate] = true
                    roadGrass.plan[#roadGrass.plan + 1] = candidate
                    if #roadGrass.plan % ROAD_GRASS_CLUSTER_SIZE == 0 then break end
                end
            end
        end
    end
end

local function placeRoadGrassClusters(state, deadline)
    prepareRoadGrassPlan(state)
    local roadGrass = state.roadGrass
    roadGrass.index = roadGrass.index or 1
    while roadGrass.index <= #roadGrass.plan do
        if deadline and getTimestampMs() >= deadline then return "pending" end
        local candidate = roadGrass.plan[roadGrass.index]
        roadGrass.index = roadGrass.index + 1
        if not squareHasSprite(candidate.square, { "e_newgrass_", "d_generic_", "d_plants_" }, "grass")
            and WDecay_Placement.isSafe(candidate.square) then
            WDecay_Random.reseedForChunk(state.wx, state.wy, 710000 + roadGrass.index)
            if WDecay_Grass.spawnGrass(candidate.square) then
                state.markerData["WDecay_placedGrassRoad"] = (state.markerData["WDecay_placedGrassRoad"] or 0) + 1
            end
        end
    end
    return true
end

local function runCarryModifier(fn, square, checkResult, level, name)
    if not fn then return true end
    local ok, err = pcall(fn, square, checkResult, level)
    if not ok then
        print("[WDecay] carry " .. name .. " error at " .. square:getX() .. "," .. square:getY() .. "," .. square:getZ() .. ": " .. tostring(err):sub(1, 120))
        return false
    end
    return true
end

local function processChunkCarry(chunk, key, markerSquare, markerData, doneAtDays, deadline)
    WDecay_Scaling.setRedecayContext(doneAtDays)
    local state = chunkWork[key]
    if not state or state.mode ~= "carry" then
        local nowDays = WDecay_Scaling.getWorldAgeDays() or doneAtDays
        local pending = nil
        local pendingCarry = {}
        for c = 1, #carryCategories do
            local cat = carryCategories[c]
            local eligibleCount = isCarryCategoryEnabled(cat) and (markerData[cat.eligKey] or 0) or 0
            if eligibleCount > 0 then
                local basePercent = cat.basePercent({ isNatural = true })
                if basePercent > 0 then
                    local multBefore = WDecay_Scaling.getMultiplierForDaysCategory(doneAtDays, cat.scaleCategory)
                    local multNow = WDecay_Scaling.getMultiplierForDaysCategory(nowDays, cat.scaleCategory)
                    if not WDecay_Scaling.isTimeScalingEnabled() then multBefore = 0 end
                    local maxObjects = math.floor(eligibleCount * (basePercent / 100) * multNow + 0.5)
                    local placed = markerData[cat.placedKey] or 0
                    local toPlace, remainder = WDecay_Carry.preview(markerData, cat.carryKey, eligibleCount, basePercent, multBefore, multNow, maxObjects, placed)
                    pendingCarry[c] = remainder
                    if toPlace > 0 then
                        if not pending then pending = {} end
                        pending[c] = toPlace
                    end
                end
            end
        end
        local urbanRedecay = WDecay_Scaling.isUrbanRedecayEnabled()
        local doVines = urbanRedecay and WDecay_Vines_ApplyToSquare ~= nil and WDecay_Features.isEnabled("vines")
        local hasUrban = markerData["WDecay_hasUrban"] == true
        local doWalls = urbanRedecay and hasUrban and WDecay_Features.isEnabled("walls")
        local doBarricades = urbanRedecay and hasUrban and WDecay_Features.isEnabled("barricades")
        local doFences = urbanRedecay and hasUrban and WDecay_Features.isEnabled("fences")
        local doDestroyed = urbanRedecay and hasUrban and WDecay_Features.isEnabled("destroyedDoorsWindows")
        local positionsByCat = nil
        if pending then
            positionsByCat = {}
            for c in pairs(pending) do positionsByCat[c] = {} end
        end
        local needAllLevels = doVines or doWalls or doBarricades or doFences or doDestroyed
        if pending and carryNeedsAllLevels and not needAllLevels then
            for c in pairs(pending) do
                if carryCategories[c].scanAllLevels then
                    needAllLevels = true
                    break
                end
            end
        end
        local minZ = needAllLevels and chunk:getMinLevel() or 0
        local maxZ = needAllLevels and chunk:getMaxLevel() or 0
        state = {
            mode = "carry",
            markerZ = markerSquare:getZ(),
            markerData = markerData,
            doneAtDays = doneAtDays,
            nowDays = nowDays,
            pending = pending,
            positionsByCat = positionsByCat,
            pendingCarry = pendingCarry,
            finalElig = {},
            doVines = doVines,
            doWalls = doWalls,
            doBarricades = doBarricades,
            doFences = doFences,
            doDestroyed = doDestroyed,
            phase = "scan",
            minZ = minZ,
            maxZ = maxZ,
            z = minZ,
            y = 0,
            x = 0,
            wx = math.floor(markerSquare:getX() / 8),
            wy = math.floor(markerSquare:getY() / 8),
            catIndex = 1
        }
        chunkWork[key] = state
    end

    if state.phase == "scan" then
        WDecay_Scaling.setRedecayContext(state.doneAtDays)
        while state.z <= state.maxZ do
            if deadline and getTimestampMs() >= deadline then
                WDecay_Scaling.clearRedecayContext()
                return "pending"
            end
            local square = chunk:getGridSquare(state.x, state.y, state.z)
            if square then
                local salt = state.doneAtDays + (state.z - state.minZ) * 64 + state.y * 8 + state.x
                WDecay_Random.reseedForChunk(state.wx, state.wy, salt)
                local checkResult = cachedSquareCheck(square, state.z)
                if checkResult then
                    if state.pending then
                        for c in pairs(state.pending) do
                            if carryCategories[c].eligible(checkResult, state.z) then
                                local list = state.positionsByCat[c]
                                list[#list + 1] = square
                            end
                        end
                    end
                    if state.doVines and not runCarryModifier(WDecay_Vines_ApplyToSquare, square, checkResult, state.z, "vines") then state.failed = true end
                    if state.doWalls and not runCarryModifier(WDecay_Walls_ApplyToSquare, square, checkResult, state.z, "walls") then state.failed = true end
                    if state.doBarricades and not runCarryModifier(WDecay_Barricades_ApplyToSquare, square, checkResult, state.z, "barricades") then state.failed = true end
                    if state.doFences and not runCarryModifier(WDecay_Fences_ApplyToSquare, square, checkResult, state.z, "fences") then state.failed = true end
                    if state.doDestroyed and not runCarryModifier(WDecay_Destroyed_ApplyToSquare, square, checkResult, state.z, "destroyed") then state.failed = true end
                end
            end
            state.x = state.x + 1
            if state.x > 7 then
                state.x = 0
                state.y = state.y + 1
                if state.y > 7 then
                    state.y = 0
                    state.z = state.z + 1
                end
            end
        end
        WDecay_Scaling.clearRedecayContext()
        if state.failed then
            chunkWork[key] = nil
            return false
        end
        state.phase = "place"
    end

    while state.catIndex <= #carryCategories do
        if deadline and getTimestampMs() >= deadline then
            WDecay_Scaling.clearRedecayContext()
            return "pending"
        end
        local c = state.catIndex
        local toPlace = state.pending and state.pending[c]
        if toPlace then
            local cat = carryCategories[c]
            local positions = state.positionsByCat[c]
            if state.placeRemaining == nil then
                state.placeRemaining = toPlace
                state.placeCount = #positions
                state.placePlaced = state.markerData[cat.placedKey] or 0
            end
            while state.placeRemaining > 0 and state.placeCount > 0 do
                if deadline and getTimestampMs() >= deadline then
                    WDecay_Scaling.clearRedecayContext()
                    return "pending"
                end
                WDecay_Random.reseedForChunk(state.wx, state.wy, state.doneAtDays + c * 100000 + state.placeRemaining)
                local randomizer = WDecay_Random.get()
                local pick = randomizer:random(1, state.placeCount)
                local square = positions[pick]
                positions[pick] = positions[state.placeCount]
                positions[state.placeCount] = nil
                state.placeCount = state.placeCount - 1
                state.placeRemaining = state.placeRemaining - 1
                if square and not (cat.hasExisting and cat.hasExisting(square)) and cat.place(square) then
                    state.placePlaced = state.placePlaced + 1
                    state.markerData[cat.placedKey] = state.placePlaced
                end
            end
            state.markerData[cat.placedKey] = state.placePlaced
            state.finalElig[c] = state.placeCount + state.placePlaced
            state.placeRemaining = nil
            state.placeCount = nil
            state.placePlaced = nil
        end
        state.catIndex = state.catIndex + 1
    end

    if state.failed then
        chunkWork[key] = nil
        return false
    end
    if WDecay_Overlays_RefreshQuiet then WDecay_Overlays_RefreshQuiet() end
    for c = 1, #carryCategories do
        local cat = carryCategories[c]
        local carryValue = state.pendingCarry[c]
        if carryValue ~= nil then state.markerData[cat.carryKey] = carryValue end
        local eligibleValue = state.finalElig[c]
        if eligibleValue ~= nil then state.markerData[cat.eligKey] = eligibleValue end
    end
    markChunkDone(markerSquare, state.markerData, state.nowDays)
    chunkWork[key] = nil
    WDecay_Scaling.clearRedecayContext()
    chunkSucceeded(key)
    if WDecay_Debug and WDecay_Debug.totalChunksProcessed then
        WDecay_Debug.totalChunksProcessed = WDecay_Debug.totalChunksProcessed + 1
    end
    if WDecay_DebugCountPass then WDecay_DebugCountPass("redecay") end
    return true
end

-- IsoChunk lacks Lua wx/wy fields; derive coordinates from a grid square.
local function chunkWorldCoords(chunk)
    local refSquare = chunk:getGridSquare(0, 0, chunk:getMinLevel())
    if not refSquare then return nil, nil end
    return math.floor(refSquare:getX() / 8), math.floor(refSquare:getY() / 8)
end

local function processChunkSquares(chunk, key, deadline)
    local activeState = chunkWork[key]
    local wx, wy
    if activeState then
        wx, wy = activeState.wx, activeState.wy
    else
        wx, wy = chunkWorldCoords(chunk)
    end
    if wx ~= nil and wy ~= nil and isSafehouseChunk(wx, wy) then
        chunkWork[key] = nil
        WDecay_Scaling.clearRedecayContext()
        return "protected"
    end
    local state = chunkWork[key]
    if not state then
        local minLevel = chunk:getMinLevel()
        local maxLevel = chunk:getMaxLevel()
        local markerSquare = getMarkerSquare(chunk)
        if not markerSquare then
            return chunkFailedTransiently(key)
        end
        local markerData = markerSquare:getModData()
        local doneAtDays = nil
        if markerData["WDecay_done"] == CACHE_VERSION then
            doneAtDays = markerData["WDecay_doneAtDays"]
        end
        if doneAtDays == nil then
            for i = 1, #carryCategories do
                markerData[carryCategories[i].eligKey] = 0
                markerData[carryCategories[i].placedKey] = 0
            end
            markerData["WDecay_hasUrban"] = nil
        end
        WDecay_Random.reseedForChunk(math.floor(markerSquare:getX() / 8), math.floor(markerSquare:getY() / 8), doneAtDays)
        if doneAtDays ~= nil then
            return processChunkCarry(chunk, key, markerSquare, markerData, doneAtDays, deadline)
        end
        state = {
            minLevel = minLevel,
            maxLevel = maxLevel,
            z = minLevel,
            y = 0,
            x = 0,
            wx = math.floor(markerSquare:getX() / 8),
            wy = math.floor(markerSquare:getY() / 8),
            markerZ = markerSquare:getZ(),
            markerData = markerData,
            roadGrass = { natural = {}, haloNatural = {}, roads = {} },
        }
        chunkWork[key] = state
    else
        -- IsoChunk objects can be reassigned while streaming; resolve by key.
        local freshSquare = getSquare(state.wx * 8, state.wy * 8, state.markerZ)
        local freshChunk = freshSquare and freshSquare:getChunk()
        local invalidReason = nil
        if not freshChunk then
            invalidReason = "target chunk (" .. state.wx .. "," .. state.wy .. ") is no longer loaded"
        elseif freshSquare:getModData() ~= state.markerData then
            -- Not just a different pooled object -- the chunk actually
            -- unloaded and reloaded, so our accumulated eligibility/carry
            -- counters live in a ModData table nobody will read back.
            invalidReason = "marker ModData identity changed (chunk was unloaded/reloaded)"
        end
        if invalidReason then
            print("[WDecay] Chunk " .. key .. " resume invalidated: " .. invalidReason)
            chunkWork[key] = nil
            return chunkFailedTransiently(key, 1)
        end
        chunk = freshChunk
        if state.mode == "carry" then
            return processChunkCarry(chunk, key, freshSquare, state.markerData, state.doneAtDays, deadline)
        end
    end

    -- Keep these counters and snapshots for future settings changes. A world
    -- may be generated with redecay/seasonal bias disabled and enable either
    -- option later; omitting the data would make those existing chunks
    -- impossible to redecay or reseason correctly.
    WDecay_Scaling.setRedecayContext(nil)
    while state.z <= state.maxLevel do
        if deadline and getTimestampMs() >= deadline then
            WDecay_Scaling.clearRedecayContext()
            return "pending"
        end
        local square = chunk:getGridSquare(state.x, state.y, state.z)
        if square then
            local salt = (state.z - state.minLevel) * 64 + state.y * 8 + state.x
            local tReseed = getTimestampMs()
            WDecay_Random.reseedForChunk(state.wx, state.wy, salt)
            recordGeneratorTime("reseedForChunk", getTimestampMs() - tReseed)
            local checkResult = cachedSquareCheck(square, state.z)
            if checkResult then
                if state.z == 0 then
                    local index = state.y * 8 + state.x + 1
                    if checkResult.isNatural then state.roadGrass.natural[index] = true end
                    if checkResult.isRoad and not checkResult.cleaned then
                        state.roadGrass.roads[#state.roadGrass.roads + 1] = {
                            square = square, x = state.x, y = state.y,
                        }
                    end
                end
                -- snapshotObjects/recordNewPlacements each do a full
                -- getObjects()+getSpecialObjects() scan of the square just
                -- to diff "what did a generator create" -- since generators
                -- only ever returned true/false, never the object itself.
                -- Measuring both separately (not folded into "generators")
                -- to see whether that diffing overhead, paid on every
                -- square regardless of whether anything got placed, is
                -- worth replacing with generators reporting what they made.
                local tSnap = getTimestampMs()
                local existingObjects = snapshotObjects(square)
                recordGeneratorTime("snapshotObjects", getTimestampMs() - tSnap)

                local tElig = getTimestampMs()
                recordEligibility(state.markerData, checkResult, state.z)
                recordUrbanFlag(state.markerData, checkResult)
                recordGeneratorTime("eligibility+urban", getTimestampMs() - tElig)

                if not dispatchGenerators(square, checkResult, state.z) then state.failed = true end

                local tNew = getTimestampMs()
                recordNewPlacements(state.markerData, square, checkResult, existingObjects)
                recordGeneratorTime("recordNewPlacements", getTimestampMs() - tNew)

                if WDecay_Overlays_ReconcileSquare then
                    local t0 = getTimestampMs()
                    WDecay_Overlays_ReconcileSquare(square, checkResult, state.z)
                    recordGeneratorTime("overlays", getTimestampMs() - t0)
                end
            end
        end
        state.x = state.x + 1
        if state.x > 7 then
            state.x = 0
            state.y = state.y + 1
            if state.y > 7 then
                state.y = 0
                state.z = state.z + 1
            end
        end
    end

    local roadGrassResult = placeRoadGrassClusters(state, deadline)
    if roadGrassResult == "pending" then
        WDecay_Scaling.clearRedecayContext()
        return "pending"
    end

    WDecay_Scaling.clearRedecayContext()
    if state.failed then
        chunkWork[key] = nil
        return false
    end
    local nowDays = WDecay_Scaling.getWorldAgeDays()
    markChunkDone(getMarkerSquare(chunk), state.markerData, nowDays)
    chunkWork[key] = nil
    chunkSucceeded(key)
    if WDecay_Debug and WDecay_Debug.totalChunksProcessed then
        WDecay_Debug.totalChunksProcessed = WDecay_Debug.totalChunksProcessed + 1
    end
    -- totalChunkTimeMs/totalTimedChunks are now tracked in runOneChunk as
    -- accumulated *active* processing time (see there for why) instead of
    -- wall-clock start-to-finish here.
    if WDecay_DebugCountPass then WDecay_DebugCountPass("initial") end
    return true
end

local patchedFunction = processChunkSquares

local function debugProcessChunkSquares(chunk, key, deadline)
    WD_Debug_Metric.startTimeMeasurement("processChunkSquares")
    local result = patchedFunction(chunk, key, deadline)
    WD_Debug_Metric.endTimeMeasurement("processChunkSquares")
    return result
end

if isDebugEnabled() then
    processChunkSquares = debugProcessChunkSquares
end

local function enqueueScannedChunk(key, sq, wx, wy, worldX, worldY, owner)
    local chunk = sq:getChunk()
    if not chunk then return 0 end

    local dx = (wx * 8 + 4) - worldX
    local dy = (wy * 8 + 4) - worldY
    local sqDistance = dx * dx + dy * dy
    local state = owner and playerStates[owner]
    local priorityRadius = playerPriorityRadius(state)
    local isPriority = sqDistance <= priorityRadius * priorityRadius * 64

    -- Don't bother queuing far chunks while driving fast: the fixed
    -- fast-travel budget can't keep up with discovery at speed, so anything
    -- queued now will still be well "behind" the player by the time its
    -- turn comes (see FAST_TRAVEL_PRIORITY_RADIUS above). Leave it
    -- unmarked (not seen, not pending) so a later scan re-evaluates it
    -- fresh once the player is actually close or has stopped -- at which
    -- point it's simply "near" again, not stale backlog.
    if not isPriority and state and state.fast then
        return 0
    end

    -- The outer scan guard only tells us the queue was shallow *before* an
    -- entire ring walk began. Enforce the low-tier cap here as well: a
    -- radius-15 scan used to add hundreds of low entries in one pass despite
    -- MAX_QUEUE_DEPTH_FOR_SCAN being 60.
    if not isPriority and queueDepth() >= MAX_QUEUE_DEPTH_FOR_SCAN then
        return 0
    end

    -- See MAX_HIGH_QUEUE_DEPTH above: discovery can outpace processing
    -- regardless of whether "fast travel" itself is engaged.
    if isPriority and highQueueDepth() >= MAX_HIGH_QUEUE_DEPTH then
        return 0
    end

    if not canQueueForOwner(owner, isPriority) then return 0 end

    markPendingChunk(key, owner, isPriority)
    scanQueuedCount = scanQueuedCount + 1
    if WDecay_Debug then WDecay_Debug.queueAdded = (WDecay_Debug.queueAdded or 0) + 1 end
    if isPriority then
        chunkQueueTailHigh = chunkQueueTailHigh + 1
        chunkQueueHighChunks[chunkQueueTailHigh] = chunk
        chunkQueueHighKeys[chunkQueueTailHigh] = key
    else
        chunkQueueTailLow = chunkQueueTailLow + 1
        chunkQueueLowChunks[chunkQueueTailLow] = chunk
        chunkQueueLowKeys[chunkQueueTailLow] = key
    end

    return 1
end

-- Visits (cx,cy) first, then each expanding Chebyshev-distance ring around it
-- (the 8 neighbours at r=1, the 16 at r=2, ...) instead of row-major order,
-- so callers that enqueue as they visit naturally queue closest-first --
-- like a spiral expanding outward from the origin.
local function forEachCellInRings(cx, cy, radius, fn)
    fn(cx, cy)
    for r = 1, radius do
        local xMin, xMax = cx - r, cx + r
        local yMin, yMax = cy - r, cy + r
        for x = xMin, xMax do
            fn(x, yMin)
            fn(x, yMax)
        end
        for y = yMin + 1, yMax - 1 do
            fn(xMin, y)
            fn(xMax, y)
        end
    end
end

-- Scans initial work every pass; completed chunks only get redecay-checked
-- when the caller's day-based gate is due.
local function ScanChunksAroundPos(worldX, worldY, radius, checkRedecay, owner)
    if not modDataTable then return 0, false end

    local cx = math.floor(worldX / 8)
    local cy = math.floor(worldY / 8)
    local queued = 0
    local scanDays = checkRedecay and WDecay_Scaling.getWorldAgeDays() or nil

    local function visit(wx, wy)
        local key = GenerateKey(wx, wy)
        if isSafehouseChunk(wx, wy) then
        elseif pendingChunks[key] or isChunkInFailCooldown(key) then
        elseif seenChunks[key] and checkRedecay then
            local sq = getSquare(wx * 8, wy * 8, 0)
            if sq and isChunkMarkedDone(sq) and needsRedecay(sq, scanDays) then
                seenChunks[key] = nil
                seenChunksCount = seenChunksCount - 1
                queued = queued + enqueueScannedChunk(key, sq, wx, wy, worldX, worldY, owner)
            end
        elseif not seenChunks[key] then
            local sq = getSquare(wx * 8, wy * 8, 0)
            if sq then
                local marked = isChunkMarkedDone(sq)
                if marked then
                    markSeen(key)
                    if checkRedecay and needsRedecay(sq, scanDays) then
                        seenChunks[key] = nil
                        seenChunksCount = seenChunksCount - 1
                        queued = queued + enqueueScannedChunk(key, sq, wx, wy, worldX, worldY, owner)
                    end
                else
                    queued = queued + enqueueScannedChunk(key, sq, wx, wy, worldX, worldY, owner)
                end
            end
        end
    end

    forEachCellInRings(cx, cy, radius, visit)

    if DEBUG_MODE and queued > 0 then
        print("[WDecay] Scan queued " .. queued .. " chunks around " .. worldX .. "," .. worldY)
    end

    local complete = queueDepth() < MAX_QUEUE_DEPTH_FOR_SCAN and highQueueDepth() < MAX_HIGH_QUEUE_DEPTH
        and (not owner or (ownerQueueCounts[owner] or 0) < ownerQueueLimit(MAX_QUEUE_DEPTH_FOR_SCAN))
        and (not owner or (ownerHighQueueCounts[owner] or 0) < ownerQueueLimit(MAX_HIGH_QUEUE_DEPTH))
    return queued, complete
end

local function initModDataCache()
    modDataTable = ModData.getOrCreate("WDecay_ChunkCache")
    if not modDataTable then return end

    if not modDataTable._version or modDataTable._version ~= SCAN_CACHE_VERSION then
        local keysToClear = {}
        for k in pairs(modDataTable) do
            if k ~= "_seed" then
                keysToClear[#keysToClear + 1] = k
            end
        end

        for i = 1, #keysToClear do
            modDataTable[keysToClear[i]] = nil
        end

        modDataTable._version = SCAN_CACHE_VERSION
        seenChunks = {}
        seenChunksCount = 0
        if DEBUG_MODE then
            print("[WDecay] Chunk cache initialized")
        end
    else
        local count = 0
        for k, v in pairs(modDataTable) do
            if k ~= "_version" and k ~= "_seed" and v then
                seenChunks[k] = true
                seenChunksCount = seenChunksCount + 1
                count = count + 1
            end
        end

        if DEBUG_MODE then
            print("[WDecay] Chunk cache loaded: " .. count .. " legacy seen chunks")
        end
    end

    if not modDataTable._seed then
        modDataTable._seed = ZombRand(1, 2147483647)
    end

    WDecay_Random.setWorldSalt(modDataTable._seed)
end

-- Runs one resumable chunk pass and records active (not waiting) time.
local activeMsByKey = {}

local function runOneChunk(key, chunk, deadline)
    local t0 = getTimestampMs()
    local ok, result = pcall(processChunkSquares, chunk, key, deadline)
    activeMsByKey[key] = (activeMsByKey[key] or 0) + (getTimestampMs() - t0)

    if not ok then
        WDecay_Scaling.clearRedecayContext()
        clearPendingChunk(key)
        chunkWork[key] = nil
        activeMsByKey[key] = nil
        if WDecay_DebugCountChunk then WDecay_DebugCountChunk(false) end
        if WDecay_Debug then WDecay_Debug.queueFailed = (WDecay_Debug.queueFailed or 0) + 1 end
        print("[WDecay] Chunk " .. key .. " error: " .. tostring(result):sub(1, 120))
        return nil
    elseif result == "pending" then
        return "pending" -- keep accumulating activeMsByKey[key] on the next call
    end

    if WDecay_Debug and result ~= "protected" then
        WDecay_Debug.totalChunkTimeMs = (WDecay_Debug.totalChunkTimeMs or 0) + activeMsByKey[key]
        WDecay_Debug.totalTimedChunks = (WDecay_Debug.totalTimedChunks or 0) + 1
    end
    activeMsByKey[key] = nil

    clearPendingChunk(key)
    if result ~= "protected" and WDecay_DebugCountChunk then WDecay_DebugCountChunk(result == true) end
    if result == false and WDecay_Debug then WDecay_Debug.queueFailed = (WDecay_Debug.queueFailed or 0) + 1 end
    if WDecay_Debug then WDecay_Debug.queueCompleted = (WDecay_Debug.queueCompleted or 0) + 1 end
    if result then markSeen(key) end
    return nil
end

-- Drop stale high work and choose the nearest remaining chunk.
local function popNextHigh()
    -- Scan results arrive in ring order, not nearest-first order.
    -- With at most MAX_HIGH_QUEUE_DEPTH entries, compact stale entries and
    -- select the nearest remaining chunk here instead of trusting FIFO.
    local head, tail = chunkQueueHeadHigh, chunkQueueTailHigh
    local write, bestIndex, bestDist = head, nil, nil
    for i = head, tail do
        local chunk, key = chunkQueueHighChunks[i], chunkQueueHighKeys[i]
        local wx, wy = chunkWorldCoords(chunk)
        local dist = wx and nearestPlayerSqDistToChunk(wx, wy)
        if wx and wy and not isInAnyPriorityBubble(wx, wy) then
            clearPendingChunk(key)
        else
            chunkQueueHighChunks[write] = chunk
            chunkQueueHighKeys[write] = key
            -- An unresolvable pooled chunk is retained as a last resort;
            -- normally all entries have coordinates and sort by distance.
            local candidateDist = dist or math.huge
            if not bestIndex or candidateDist < bestDist then
                bestIndex, bestDist = write, candidateDist
            end
            write = write + 1
        end
    end
    for i = write, tail do
        chunkQueueHighChunks[i] = nil
        chunkQueueHighKeys[i] = nil
    end
    chunkQueueTailHigh = write - 1
    if not bestIndex then return nil, nil end

    local chunk, key = chunkQueueHighChunks[bestIndex], chunkQueueHighKeys[bestIndex]
    local last = chunkQueueTailHigh
    if bestIndex ~= last then
        chunkQueueHighChunks[bestIndex] = chunkQueueHighChunks[last]
        chunkQueueHighKeys[bestIndex] = chunkQueueHighKeys[last]
    end
    chunkQueueHighChunks[last] = nil
    chunkQueueHighKeys[last] = nil
    chunkQueueTailHigh = last - 1
    return chunk, key
end

-- Drains the high queue up to highDeadline, working currentHighKey (a
-- chunk paused mid-scan from a previous tick, if any) to completion first.
-- Returns true if high still has outstanding work when it stops (ran out
-- of budget, or a chunk mid-scan) -- callers use this to decide whether low
-- gets any time at all this tick.
local function drainHigh(highDeadline)
    while getTimestampMs() < highDeadline do
        if not currentHighKey then
            currentHighChunk, currentHighKey = popNextHigh()
            if not currentHighKey then return false end
            if DEBUG_MODE and WDecay_Debug and WDecay_Debug.chunksHigh then WDecay_Debug.chunksHigh = WDecay_Debug.chunksHigh + 1 end
        end
        if runOneChunk(currentHighKey, currentHighChunk, highDeadline) == "pending" then return true end
        currentHighKey, currentHighChunk = nil, nil
    end
    return currentHighKey ~= nil or chunkQueueHeadHigh <= chunkQueueTailHigh
end

-- Retain low work until it leaves normal scan coverage.
local function lowStalenessSqDistThreshold()
    return SCAN_RADIUS * SCAN_RADIUS * 64
end

-- Same staleness-discard shape as popNextHigh, just with the wider bound
-- above instead of the priority radius.
local function popNextLow()
    while chunkQueueHeadLow <= chunkQueueTailLow do
        local i = chunkQueueHeadLow
        local chunk, key = chunkQueueLowChunks[i], chunkQueueLowKeys[i]
        chunkQueueLowChunks[i] = nil
        chunkQueueLowKeys[i] = nil
        chunkQueueHeadLow = chunkQueueHeadLow + 1

        local wx, wy = chunkWorldCoords(chunk)
        local dist = wx and nearestPlayerSqDistToChunk(wx, wy)
        if dist and dist > lowStalenessSqDistThreshold() then
            clearPendingChunk(key)
        else
            return chunk, key
        end
    end
    return nil, nil
end

-- Same shape as drainHigh, for the low queue -- only ever called once high
-- has nothing outstanding this tick (see runDispatchLoop). A low chunk
-- paused here to let high through earlier just resumes where it left off;
-- chunkWork[key] preserved its cursor.
local function drainLow(lowDeadline)
    while getTimestampMs() < lowDeadline do
        if not currentLowKey then
            currentLowChunk, currentLowKey = popNextLow()
            if not currentLowKey then return end
            if DEBUG_MODE and WDecay_Debug and WDecay_Debug.chunksLow then WDecay_Debug.chunksLow = WDecay_Debug.chunksLow + 1 end
        end
        if runOneChunk(currentLowKey, currentLowChunk, lowDeadline) == "pending" then return end
        currentLowKey, currentLowChunk = nil, nil
    end
end

-- Every tick, high is always attended to first and completely -- a low
-- chunk mid-scan from a previous tick never blocks newly-arrived
-- near-player work, however long the low chunk takes to finish. Low only
-- gets any time (up to its own, smaller lowDeadline) once high has nothing
-- outstanding this tick: no queued high chunks and no in-progress one.
local function runDispatchLoop(highDeadline, lowDeadline)
    if drainHigh(highDeadline) then return end
    drainLow(lowDeadline)
end

local function nothingActive()
    return currentHighKey == nil and currentLowKey == nil
end

-- Compact empty FIFO storage after the active jobs and both queues drain.
local function resetIdleQueues()
    if not nothingActive() or chunkQueueHeadHigh <= chunkQueueTailHigh or chunkQueueHeadLow <= chunkQueueTailLow then
        return false
    end
    chunkQueueHeadHigh, chunkQueueTailHigh = 1, 0
    chunkQueueHeadLow, chunkQueueTailLow = 1, 0
    return true
end

-- Real wall-clock time between successive OnTick calls -- the missing
-- piece to turn "WDecay spends up to Xms/tick" into "WDecay costs Y% of a
-- tick," which is what actually determines FPS impact. Xms means something
-- very different at a game running 60 ticks/sec (16.7ms budget) vs. one
-- struggling at 20 (50ms budget).
local lastTickRealMs = nil

-- Previous scan origins detect travel farther than current scan coverage.
local function isRedecayCheckDue(trackKey)
    if not WDecay_Scaling.isRedecayEnabled() then return false end
    local day = WDecay_Scaling.getWorldAgeDays()
    if day == nil then return false end
    local interval = math.max(1, WDecay_Scaling.getRedecayCheckIntervalDays() or 1)
    return lastRedecayCheckDay[trackKey] == nil or day - lastRedecayCheckDay[trackKey] >= interval, day
end

-- Returns travel since this player's last scan; nil on their first scan.
local function checkScanGap(trackKey, px, py, scanRadius)
    local lastX, lastY = lastScanOriginX[trackKey], lastScanOriginY[trackKey]
    lastScanOriginX[trackKey] = px
    lastScanOriginY[trackKey] = py
    if not lastX then return nil end
    local dx, dy = px - lastX, py - lastY
    local dist = math.sqrt(dx * dx + dy * dy)
    local coverage = (scanRadius or SCAN_RADIUS) * 8
    if DEBUG_MODE and dist > coverage then
        print("[WDecay] Scan gap (" .. trackKey .. "): moved " .. math.floor(dist)
            .. " tiles since last scan, but scan only covers " .. coverage
            .. " tiles from wherever the player currently is -- up to ~"
            .. math.floor(dist - coverage) .. " tiles of corridor behind them went unswept by either scan.")
    end
    return dist
end

local function selectDuePlayer(nowMs)
    local bestIndex, bestOverdue = nil, nil
    scanDueCount = 0
    scanOldestOverdueMs = 0
    for offset = 1, trackedPlayerCount do
        local index = ((scanRoundRobin + offset - 1) % trackedPlayerCount) + 1
        local state = trackedPlayerStates[index]
        local overdue = nowMs - (state.nextScanAtMs or 0)
        if overdue >= 0 then
            scanDueCount = scanDueCount + 1
            scanOldestOverdueMs = math.max(scanOldestOverdueMs, overdue)
            if not bestIndex or overdue > bestOverdue then
                bestIndex, bestOverdue = index, overdue
            end
        end
    end
    return bestIndex, bestOverdue
end

local function runDuePlayerScan(nowMs)
    if not modDataTable or trackedPlayerCount == 0 then return end
    local index = selectDuePlayer(nowMs)
    if not index then return end
    if queueDepth() >= MAX_QUEUE_DEPTH_FOR_SCAN then
        scanThrottledCount = scanThrottledCount + 1
        scanDeferredCount = scanDeferredCount + 1
        return
    end

    scanRoundRobin = index
    local state = trackedPlayerStates[index]
    local px, py = math.floor(state.x), math.floor(state.y)
    if px == 0 and py == 0 then
        state.nextScanAtMs = nowMs + playerScanIntervalMs(state)
        return
    end
    local checkRedecay, redecayDay = isRedecayCheckDue(state.key)
    local movedTiles = checkScanGap(state.key, px, py, playerScanRadius(state))
    local startupScan = state.startupScans < MAX_STARTUP_SCAN_ATTEMPTS
    state.nextScanAtMs = nowMs + playerScanIntervalMs(state)
    if movedTiles ~= nil and movedTiles < 1 and not checkRedecay and not startupScan then
        scanMovementSkippedCount = scanMovementSkippedCount + 1
        return
    end

    scanRunCount = scanRunCount + 1
    local ok, queuedOrErr, complete = pcall(ScanChunksAroundPos, px, py, playerScanRadius(state), checkRedecay, state.key)
    if not ok then
        print("[WDecay] Scan error: " .. tostring(queuedOrErr):sub(1, 120))
    elseif checkRedecay and complete then
        lastRedecayCheckDay[state.key] = redecayDay
    end

    if startupScan then
        state.startupScans = state.startupScans + 1
        local radius = state.fast and FAST_TRAVEL_SCAN_RADIUS or SCAN_RADIUS * 2
        local bootstrapOk, err = pcall(ScanChunksAroundPos, px, py, radius, false, state.key)
        if not bootstrapOk then print("[WDecay] Spawn scan error: " .. tostring(err):sub(1, 120)) end
    end
end

local function recordTotalTickMs(startMs)
    if not WDecay_Debug then return end
    local totalMs = getTimestampMs() - startMs
    WDecay_Debug.totalMsLast = totalMs
    WDecay_Debug.totalMsMax = math.max(WDecay_Debug.totalMsMax or 0, totalMs)
    local previousAverage = WDecay_Debug.totalMsAvg or totalMs
    WDecay_Debug.totalMsAvg = previousAverage + (totalMs - previousAverage) * 0.1
end

function OnTick()
    if isClient() then return end

    if not dispatcherConfigLoaded then
        loadDispatcherConfig()
        if DEBUG_MODE then
            print("[WDecay] Environment: isServer()=" .. tostring(isServer())
                .. " isClient()=" .. tostring(isClient())
                .. " isMultiplayer()=" .. tostring(isMultiplayer and isMultiplayer() or "n/a")
                .. " isDedicated()=" .. tostring(isDedicated and isDedicated() or "n/a"))
        end
    end

    local onTickStartMs = getTimestampMs()
    local nowRealMs = onTickStartMs
    if lastTickRealMs and WDecay_Debug then
        local interval = nowRealMs - lastTickRealMs
        WDecay_Debug.tickIntervalLast = interval
        local prevAvg = WDecay_Debug.tickIntervalAvg or interval
        WDecay_Debug.tickIntervalAvg = prevAvg + (interval - prevAvg) * 0.1
    end
    lastTickRealMs = nowRealMs

    refreshTrackedPlayers()

    -- Decide this before the scan. Previously wasDrivingFast was updated
    -- after scanning, so even a correctly detected transition used one tick
    -- of normal scan settings. More importantly, refreshTrackedPlayers has
    -- now supplied offline SP's player-0 fallback to this check.
    local effectiveBudgetMs = TIME_BUDGET_MS
    if FAST_TRAVEL_SPEED_KMH > 0 and FAST_TRAVEL_BUDGET_MS < TIME_BUDGET_MS
        and isAnyPlayerDrivingFast(FAST_TRAVEL_SPEED_KMH) then
        effectiveBudgetMs = FAST_TRAVEL_BUDGET_MS
    end
    if (effectiveBudgetMs < TIME_BUDGET_MS) ~= wasDrivingFast then
        wasDrivingFast = effectiveBudgetMs < TIME_BUDGET_MS
        if DEBUG_MODE then
            print("[WDecay] Fast travel budget " .. (wasDrivingFast and "engaged (" .. effectiveBudgetMs .. "ms)" or "released (" .. TIME_BUDGET_MS .. "ms)")
                .. " source=" .. trackedPlayerSource .. " players=" .. trackedPlayerCount
                .. " vehicles=" .. fastTravelVehicleCount .. " maxSpeed=" .. string.format("%.1f", fastTravelMaxSpeedKmh)
                .. "km/h threshold=" .. FAST_TRAVEL_SPEED_KMH .. "km/h")
        end
    end
    if WDecay_Debug then
        WDecay_Debug.budgetMs = effectiveBudgetMs
        WDecay_Debug.scanRadius = wasDrivingFast and FAST_TRAVEL_SCAN_RADIUS or SCAN_RADIUS
        WDecay_Debug.fastTravelActive = wasDrivingFast
        WDecay_Debug.fastTravelPlayerSource = trackedPlayerSource
        WDecay_Debug.fastTravelPlayerCount = trackedPlayerCount
        WDecay_Debug.fastTravelVehicleCount = fastTravelVehicleCount
        WDecay_Debug.fastTravelMaxSpeedKmh = fastTravelMaxSpeedKmh
        WDecay_Debug.fastTravelThresholdKmh = FAST_TRAVEL_SPEED_KMH
        WDecay_Debug.scanIntervalSeconds = SCAN_INTERVAL_SECONDS
        WDecay_Debug.fastTravelScanIntervalSeconds = FAST_TRAVEL_SCAN_INTERVAL_SECONDS
    end

    if DEBUG_MODE then
        perfTickCounter = perfTickCounter + 1
        if perfTickCounter >= 300 then
            perfTickCounter = 0
            if WDecay_Debug and WDecay_Debug.printPerfSummary then
                WDecay_Debug.printPerfSummary(debugTickCounter)
            end
        end
    end

    if not modDataTable then
        initModDataCache()
    end

    local scanStartMs = getTimestampMs()
    runDuePlayerScan(nowRealMs)
    if WDecay_Debug then
        local scanMs = getTimestampMs() - scanStartMs
        WDecay_Debug.scanMsLast = scanMs
        WDecay_Debug.scanMsMax = math.max(WDecay_Debug.scanMsMax or 0, scanMs)
        local prevScanAvg = WDecay_Debug.scanMsAvg or scanMs
        WDecay_Debug.scanMsAvg = prevScanAvg + (scanMs - prevScanAvg) * 0.1
    end

    if resetIdleQueues() then
        recordTotalTickMs(onTickStartMs)
        return
    end

    if WDecay_Debug then
        WDecay_Debug.queueHigh = math.max(0, chunkQueueTailHigh - chunkQueueHeadHigh + 1)
        WDecay_Debug.queueLow = math.max(0, chunkQueueTailLow - chunkQueueHeadLow + 1)
    end
    if DEBUG_MODE then
        debugTickCounter = debugTickCounter + 1
    end
    if DEBUG_MODE and debugTickCounter >= 30 then
        debugTickCounter = 0
        local avgChunkMs = 0
        if WDecay_Debug and WDecay_Debug.totalTimedChunks and WDecay_Debug.totalTimedChunks > 0 then
            avgChunkMs = WDecay_Debug.totalChunkTimeMs / WDecay_Debug.totalTimedChunks
        end
        print("[WDecay] Queue: high=" .. math.max(0, chunkQueueTailHigh - chunkQueueHeadHigh + 1)
            .. " low=" .. math.max(0, chunkQueueTailLow - chunkQueueHeadLow + 1)
            .. " currentHigh=" .. (currentHighKey and tostring(currentHighKey) or "none")
            .. " currentLow=" .. (currentLowKey and tostring(currentLowKey) or "none")
            .. " avgMs/chunk=" .. string.format("%.3f", avgChunkMs))
        if WDecay_Debug then
            print("[WDecay] Total ms last/avg/max=" .. string.format("%.1f/%.1f/%.1f",
                WDecay_Debug.totalMsLast or 0, WDecay_Debug.totalMsAvg or 0, WDecay_Debug.totalMsMax or 0)
                .. " Dispatch ms last/avg/max=" .. string.format("%.1f/%.1f/%.1f",
                WDecay_Debug.tickMsLast or 0, WDecay_Debug.tickMsAvg or 0, WDecay_Debug.tickMsMax or 0)
                .. " Scan ms last/avg/max=" .. string.format("%.1f/%.1f/%.1f",
                WDecay_Debug.scanMsLast or 0, WDecay_Debug.scanMsAvg or 0, WDecay_Debug.scanMsMax or 0))
            -- The actual FPS-relevant number: what fraction of a real game
            -- tick WDecay is consuming, not just raw ms (10ms means very
            -- different things at 60 ticks/sec vs. a struggling 20).
            local tickInterval = WDecay_Debug.tickIntervalAvg or 0
            local pctOfTick = tickInterval > 0 and ((WDecay_Debug.totalMsAvg or 0) / tickInterval * 100) or 0
            local approxFps = tickInterval > 0 and (1000 / tickInterval) or 0
            print("[WDecay] Real tick interval avg=" .. string.format("%.2f", tickInterval)
                .. "ms (~" .. string.format("%.1f", approxFps) .. " FPS) -- WDecay uses ~"
                .. string.format("%.1f", pctOfTick) .. "% of an average tick")
            print("[WDecay] Fast travel: active=" .. tostring(wasDrivingFast)
                .. " source=" .. trackedPlayerSource .. " players=" .. trackedPlayerCount
                .. " vehicles=" .. fastTravelVehicleCount .. " maxSpeed=" .. string.format("%.1f", fastTravelMaxSpeedKmh)
                .. "km/h threshold=" .. FAST_TRAVEL_SPEED_KMH .. "km/h budget=" .. effectiveBudgetMs
                .. "ms scanInterval=" .. string.format("%.2f/%.2fs", SCAN_INTERVAL_SECONDS, FAST_TRAVEL_SCAN_INTERVAL_SECONDS)
                .. " scan runs/skipped/deferred=" .. scanRunCount .. "/" .. scanMovementSkippedCount .. "/" .. scanDeferredCount
                .. " due=" .. scanDueCount .. " oldest=" .. math.floor(scanOldestOverdueMs) .. "ms")
        end
        local avgSquareCheckMs = squareCheckCallCount > 0 and (squareCheckTimeMs / squareCheckCallCount) or 0
        print("[WDecay] checkAll: avg=" .. string.format("%.4f", avgSquareCheckMs) .. "ms x " .. squareCheckCallCount
            .. " calls (total=" .. string.format("%.1f", squareCheckTimeMs) .. "ms)")
        if WDecay_Debug and WDecay_Debug.totalTimedChunks and WDecay_Debug.totalTimedChunks > 0 then
            print("[WDecay] squares/chunk (checkAll calls / completed chunks) = "
                .. string.format("%.1f", squareCheckCallCount / WDecay_Debug.totalTimedChunks))
        end
        if scanThrottledCount > 0 then
            print("[WDecay] Discovery throttled by depth cap: scan=" .. scanThrottledCount)
        end
        print("[WDecay] Discovery source: scan=" .. scanQueuedCount)
        if failedCooldownCount > 0 then
            print("[WDecay] Chunk failures (last 30 ticks): cooled-down=" .. failedCooldownCount)
            failedCooldownCount = 0
        end
        -- Console mirror of the Status tab's generator-cost breakdown, so
        -- it's visible from a console dump alone.
        local statNames, statCount = {}, 0
        for name in pairs(generatorTimeMs) do
            statCount = statCount + 1
            statNames[statCount] = name
        end
        table.sort(statNames, function(a, b) return generatorTimeMs[a] > generatorTimeMs[b] end)
        if statCount > 0 then
            local parts = {}
            for i = 1, statCount do
                local name = statNames[i]
                local calls = generatorCallCount[name] or 0
                local avg = calls > 0 and (generatorTimeMs[name] / calls) or 0
                parts[#parts + 1] = name .. "=" .. string.format("%.3f", avg) .. "ms(x" .. calls .. ")"
            end
            print("[WDecay] Generator cost (avg ms x calls, heaviest first): " .. table.concat(parts, " "))
        end
    end

    local hadWork = not nothingActive() or chunkQueueHeadHigh <= chunkQueueTailHigh or chunkQueueHeadLow <= chunkQueueTailLow
    local startMs = getTimestampMs()
    local highDeadline = startMs + effectiveBudgetMs
    -- Low work can use its normal share only after high is clear.
    local lowDeadline = startMs + math.max(1, math.floor(effectiveBudgetMs * LOW_BUDGET_FRACTION))
    runDispatchLoop(highDeadline, lowDeadline)

    -- How much of this tick's budget actually got used -- only measured on
    -- ticks where there was work to do, so idle ticks (the vast majority)
    -- don't dilute the average toward zero and hide the real cost of busy ticks.
    if hadWork and WDecay_Debug then
        local tickMs = getTimestampMs() - startMs
        WDecay_Debug.tickMsLast = tickMs
        WDecay_Debug.tickMsMax = math.max(WDecay_Debug.tickMsMax or 0, tickMs)
        local prevAvg = WDecay_Debug.tickMsAvg or tickMs
        WDecay_Debug.tickMsAvg = prevAvg + (tickMs - prevAvg) * 0.1
    end

    recordTotalTickMs(onTickStartMs)

    resetIdleQueues()
end

Events.OnTick.Add(OnTick)

Events.OnInitGlobalModData.Add(function(isNewGame)
    if isClient() then return end

    initModDataCache()
end)

-- Per-generator-type cost, most expensive first -- lets the Status tab
-- answer "which generator is actually doing the work" instead of just an
-- aggregate ms/chunk number.
local function buildGeneratorStats()
    local list = {}
    for name, totalMs in pairs(generatorTimeMs) do
        local calls = generatorCallCount[name] or 0
        list[#list + 1] = { name = name, totalMs = totalMs, calls = calls, avgMs = calls > 0 and (totalMs / calls) or 0 }
    end
    table.sort(list, function(a, b) return a.totalMs > b.totalMs end)
    return list
end

-- Read-only data for the debug monitor. It only reads the scheduler tables;
-- opening the panel must never enqueue, scan, or process chunks.
function WDecay_Dispatcher_GetMonitorData(player, radius)
    if not player then return {} end
    radius = math.max(3, math.min(12, math.floor(tonumber(radius) or 12)))
    local cx, cy = math.floor(player:getX() / 8), math.floor(player:getY() / 8)
    local queued = {}
    for i = chunkQueueHeadHigh, chunkQueueTailHigh do queued[chunkQueueHighKeys[i]] = "high" end
    for i = chunkQueueHeadLow, chunkQueueTailLow do queued[chunkQueueLowKeys[i]] = "low" end

    local cells = {}
    local nowMs = getTimestampMs()
    for x = cx - radius, cx + radius do
        for y = cy - radius, cy + radius do
            local key, state = GenerateKey(x, y), "unloaded"
            local remainingMs = nil
            if isSafehouseChunk(x, y) then state = "safehouse"
            elseif chunkWork[key] then state = "pending"
            elseif queued[key] then state = queued[key]
            elseif isChunkInFailCooldown(key) then
                state = "cooldown"
                remainingMs = math.max(0, (chunkFailCooldownUntilMs[key] or nowMs) - nowMs)
            elseif seenChunks[key] then state = "done"
            elseif getSquare(x * 8, y * 8, 0) then state = "loaded"
            end
            cells[#cells + 1] = { x = x, y = y, state = state, remainingMs = remainingMs }
        end
    end

    return {
        centerX = cx, centerY = cy, radius = radius, cells = cells,
        queueHigh = math.max(0, chunkQueueTailHigh - chunkQueueHeadHigh + 1),
        queueLow = math.max(0, chunkQueueTailLow - chunkQueueHeadLow + 1),
        added = WDecay_Debug and WDecay_Debug.queueAdded or 0,
        completed = WDecay_Debug and WDecay_Debug.queueCompleted or 0,
        failed = WDecay_Debug and WDecay_Debug.queueFailed or 0,
        budget = WDecay_Debug and WDecay_Debug.budgetMs or TIME_BUDGET_MS,
        processed = WDecay_Debug and WDecay_Debug.totalChunksProcessed or 0,
        -- Total includes scan/discovery/dispatch; tickMs* remains the
        -- dispatch-only component, so the two can be compared directly.
        avgChunkMs = (WDecay_Debug and WDecay_Debug.totalTimedChunks and WDecay_Debug.totalTimedChunks > 0)
            and (WDecay_Debug.totalChunkTimeMs / WDecay_Debug.totalTimedChunks) or 0,
        totalMsLast = WDecay_Debug and WDecay_Debug.totalMsLast or 0,
        totalMsAvg = WDecay_Debug and WDecay_Debug.totalMsAvg or 0,
        totalMsMax = WDecay_Debug and WDecay_Debug.totalMsMax or 0,
        tickMsLast = WDecay_Debug and WDecay_Debug.tickMsLast or 0,
        tickMsAvg = WDecay_Debug and WDecay_Debug.tickMsAvg or 0,
        tickMsMax = WDecay_Debug and WDecay_Debug.tickMsMax or 0,
        scanMsLast = WDecay_Debug and WDecay_Debug.scanMsLast or 0,
        scanMsAvg = WDecay_Debug and WDecay_Debug.scanMsAvg or 0,
        scanMsMax = WDecay_Debug and WDecay_Debug.scanMsMax or 0,
        generatorStats = buildGeneratorStats(),
        scanQueued = scanQueuedCount,
        currentHigh = currentHighKey,
        currentLow = currentLowKey,
        avgCheckAllMs = squareCheckCallCount > 0 and (squareCheckTimeMs / squareCheckCallCount) or 0,
        checkAllCalls = squareCheckCallCount,
        -- Real FPS-impact proxy (% of an actual tick WDecay consumes) and
        -- how often discovery is actually being throttled by the depth cap.
        tickIntervalAvg = WDecay_Debug and WDecay_Debug.tickIntervalAvg or 0,
        scanThrottled = scanThrottledCount,
        scanRuns = scanRunCount,
        scanMovementSkipped = scanMovementSkippedCount,
        fastTravelActive = wasDrivingFast,
        fastTravelPlayerSource = trackedPlayerSource,
        fastTravelPlayerCount = trackedPlayerCount,
        fastTravelVehicleCount = fastTravelVehicleCount,
        fastTravelMaxSpeedKmh = fastTravelMaxSpeedKmh,
        fastTravelThresholdKmh = FAST_TRAVEL_SPEED_KMH,
        scanIntervalSeconds = SCAN_INTERVAL_SECONDS,
        fastTravelScanIntervalSeconds = FAST_TRAVEL_SCAN_INTERVAL_SECONDS,
        scanDue = scanDueCount,
        scanDeferred = scanDeferredCount,
        scanOldestOverdueMs = scanOldestOverdueMs,
        playerQueueLimit = ownerQueueLimit(MAX_QUEUE_DEPTH_FOR_SCAN),
        playerHighQueueLimit = ownerQueueLimit(MAX_HIGH_QUEUE_DEPTH),
    }
end

function WDecay_Dispatcher_IsQueueIdle()
    return nothingActive() and chunkQueueHeadHigh > chunkQueueTailHigh and chunkQueueHeadLow > chunkQueueTailLow
end

local function forEachChunkAround(radius, fn, player)
    player = player or getSpecificPlayer(0)
    if not player then return end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local cx0 = math.floor((px - radius * 8) / 8)
    local cx1 = math.floor((px + radius * 8) / 8)
    local cy0 = math.floor((py - radius * 8) / 8)
    local cy1 = math.floor((py + radius * 8) / 8)
    for wx = cx0, cx1 do
        for wy = cy0, cy1 do
            local sq = getSquare(wx * 8, wy * 8, 0)
            local chunk = sq and sq:getChunk()
            if chunk then
                fn(chunk, wx, wy)
            end
        end
    end
end

-- Debug-command-only now: moves matching low-queue entries into the high
-- queue on demand (used by WDecay_Dispatcher_QueueArea below). No longer
-- run automatically every scan cycle -- with only one chunk ever active,
-- a stale low-queue entry isn't stealing budget from anything, so there's
-- nothing worth continuously re-sorting for.
prioritizeQueuedArea = function(radius, player)
    local wanted = {}
    forEachChunkAround(radius, function(chunk, wx, wy)
        wanted[GenerateKey(wx, wy)] = true
    end, player)

    local kept = 0
    for i = chunkQueueHeadLow, chunkQueueTailLow do
        local key = chunkQueueLowKeys[i]
        if wanted[key] then
            local owner = pendingOwners[key]
            if owner and not pendingHigh[key] then
                pendingHigh[key] = true
                ownerHighQueueCounts[owner] = (ownerHighQueueCounts[owner] or 0) + 1
            end
            chunkQueueTailHigh = chunkQueueTailHigh + 1
            chunkQueueHighChunks[chunkQueueTailHigh] = chunkQueueLowChunks[i]
            chunkQueueHighKeys[chunkQueueTailHigh] = key
        else
            kept = kept + 1
            chunkQueueLowChunks[chunkQueueHeadLow + kept - 1] = chunkQueueLowChunks[i]
            chunkQueueLowKeys[chunkQueueHeadLow + kept - 1] = key
        end
    end
    for i = chunkQueueHeadLow + kept, chunkQueueTailLow do
        chunkQueueLowChunks[i] = nil
        chunkQueueLowKeys[i] = nil
    end
    chunkQueueTailLow = chunkQueueHeadLow + kept - 1
end

function WDecay_Dispatcher_QueueArea(radius, wipeMarkers, player, highPriority)
    ensureOnTickRegistered()
    radius = radius or 3
    local queued = 0

    if highPriority then prioritizeQueuedArea(radius, player) end

    resetIdleQueues()

    forEachChunkAround(radius, function(chunk, wx, wy)
        if isSafehouseChunk(wx, wy) then return end
        local key = GenerateKey(wx, wy)
        if seenChunks[key] then
            seenChunks[key] = nil
            seenChunksCount = seenChunksCount - 1
        end
        if wipeMarkers then
            local markerSquare = getMarkerSquare(chunk)
            if markerSquare then
                local markerData = markerSquare:getModData()
                markerData["WDecay_done"] = nil
                markerData["WDecay_doneAtDays"] = nil
                markerData["WDecay_eligTrees"] = nil
                markerData["WDecay_carryTrees"] = nil
                markerData["WDecay_placedTrees"] = nil
                markerData["WDecay_eligTreesNatural"] = nil
                markerData["WDecay_carryTreesNatural"] = nil
                markerData["WDecay_placedTreesNatural"] = nil
                markerData["WDecay_eligTreesRoad"] = nil
                markerData["WDecay_carryTreesRoad"] = nil
                markerData["WDecay_placedTreesRoad"] = nil
                markerData["WDecay_eligBushes"] = nil
                markerData["WDecay_carryBushes"] = nil
                markerData["WDecay_placedBushes"] = nil
                markerData["WDecay_eligBushesNatural"] = nil
                markerData["WDecay_carryBushesNatural"] = nil
                markerData["WDecay_placedBushesNatural"] = nil
                markerData["WDecay_eligBushesRoad"] = nil
                markerData["WDecay_carryBushesRoad"] = nil
                markerData["WDecay_placedBushesRoad"] = nil
                markerData["WDecay_eligBushesIndoor"] = nil
                markerData["WDecay_carryBushesIndoor"] = nil
                markerData["WDecay_placedBushesIndoor"] = nil
                markerData["WDecay_eligIndoorGrass"] = nil
                markerData["WDecay_carryIndoorGrass"] = nil
                markerData["WDecay_placedIndoorGrass"] = nil
                markerData["WDecay_eligGrassNatural"] = nil
                markerData["WDecay_carryGrassNatural"] = nil
                markerData["WDecay_placedGrassNatural"] = nil
                markerData["WDecay_eligGrassRoad"] = nil
                markerData["WDecay_carryGrassRoad"] = nil
                markerData["WDecay_placedGrassRoad"] = nil
                markerData["WDecay_eligGrassIndoor"] = nil
                markerData["WDecay_carryGrassIndoor"] = nil
                markerData["WDecay_placedGrassIndoor"] = nil
                saveMarker(markerSquare)
            end
        end

        if not pendingChunks[key] then
            markPendingChunk(key, nil, highPriority)
            if WDecay_Debug then WDecay_Debug.queueAdded = (WDecay_Debug.queueAdded or 0) + 1 end
            if highPriority then
                chunkQueueTailHigh = chunkQueueTailHigh + 1
                chunkQueueHighChunks[chunkQueueTailHigh] = chunk
                chunkQueueHighKeys[chunkQueueTailHigh] = key
            else
                chunkQueueTailLow = chunkQueueTailLow + 1
                chunkQueueLowChunks[chunkQueueTailLow] = chunk
                chunkQueueLowKeys[chunkQueueTailLow] = key
            end
        end

        queued = queued + 1
    end, player)
    print("[WDecay] Debug: queued " .. queued .. " chunks (radius=" .. radius .. ", wipeMarkers=" .. tostring(wipeMarkers == true) .. ")")
    return queued
end

-- Debug overwrite actions use this to explicitly opt an area back into
-- generation. Normal player cleaning leaves the marker in place, including
-- during re-decay passes.
function WDecay_Dispatcher_ClearCleanedArea(radius, player)
    radius = radius or 3
    local cleared = 0
    forEachChunkAround(radius, function(chunk)
        for z = chunk:getMinLevel(), chunk:getMaxLevel() do
            for y = 0, 7 do
                for x = 0, 7 do
                    local square = chunk:getGridSquare(x, y, z)
                    local data = square and square:getModData()
                    if data and data["WDecay_cleaned"] ~= nil then
                        data["WDecay_cleaned"] = nil
                        square:transmitModdata()
                        square:flagForHotSave()
                        cleared = cleared + 1
                    end
                end
            end
        end
    end, player)
    return cleared
end

-- Mirrors the ordinary re-decay scan's eligibility decision, but lets the
-- debug panel ask for that decision immediately instead of waiting for its
-- next periodic scan. It never overwrites cleaned squares or bypasses age.
function WDecay_Dispatcher_QueueDueRedecayArea(radius, player)
    ensureOnTickRegistered()
    radius = radius or 3
    local queued = 0
    local days = WDecay_Scaling.getWorldAgeDays()

    forEachChunkAround(radius, function(chunk, wx, wy)
        if isSafehouseChunk(wx, wy) then return end
        local markerSquare = getMarkerSquare(chunk)
        if not isChunkMarkedDone(markerSquare) or not needsRedecay(markerSquare, days) then return end

        local key = GenerateKey(wx, wy)
        if seenChunks[key] then
            seenChunks[key] = nil
            seenChunksCount = seenChunksCount - 1
        end
        if not pendingChunks[key] then
            markPendingChunk(key, nil, true)
            chunkQueueTailHigh = chunkQueueTailHigh + 1
            chunkQueueHighChunks[chunkQueueTailHigh] = chunk
            chunkQueueHighKeys[chunkQueueTailHigh] = key
            queued = queued + 1
        end
    end, player)

    print("[WDecay] Debug: queued " .. queued .. " due re-decay chunks (radius=" .. radius .. ")")
    return queued
end

function WDecay_Dispatcher_StampDoneAt(radius, days, player)
    radius = radius or 3
    days = math.floor(tonumber(days) or 0)
    local stamped = 0
    forEachChunkAround(radius, function(chunk, wx, wy)
        local markerSquare = getMarkerSquare(chunk)
        if markerSquare then
            local markerData = markerSquare:getModData()
            if markerData["WDecay_done"] == CACHE_VERSION then
                markerData["WDecay_doneAtDays"] = days
                saveMarker(markerSquare)
                stamped = stamped + 1
            end
        end
    end, player)
    print("[WDecay] Debug: stamped " .. stamped .. " chunks doneAtDays=" .. days)
    return stamped
end
