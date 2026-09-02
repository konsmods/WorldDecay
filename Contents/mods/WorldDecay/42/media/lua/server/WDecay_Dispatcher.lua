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

-- Stamped onto each chunk's own WDecay_done marker. Do NOT bump this for
-- internal cache-format changes (see SCAN_CACHE_VERSION) -- it forces every
-- already-generated chunk in every existing save to be reprocessed. Only
-- bump it when what "done" means for a chunk actually changes.
local CACHE_VERSION = 4

-- Versions the persisted "which chunks have we already seen" scan cache
-- (WDecay_ChunkCache) independently of CACHE_VERSION -- wiping this just
-- costs one extra cheap isChunkMarkedDone lookup per chunk, not a
-- reprocess. Bumped when GenerateKey's key format changes.
local SCAN_CACHE_VERSION = 1

local DEBUG_MODE = false

local seenChunks = {}
local modDataTable = nil

local chunkQueueTailHigh = 0
local chunkQueueTailLow = 0
local chunkQueueHeadHigh = 1
local chunkQueueHeadLow = 1
local chunkQueueHighChunks = {}
local chunkQueueHighKeys = {}
local chunkQueueHighWx = {}
local chunkQueueHighWy = {}
local chunkQueueLowChunks = {}
local chunkQueueLowKeys = {}
local chunkQueueLowWx = {}
local chunkQueueLowWy = {}
local PRIORITY_RADIUS = 5
local pendingChunks = {}
local chunkWork = {}

-- A chunk can fail for reasons that are purely about timing (grid squares
-- not populated yet, or unloaded between a "pending" tick and its resume).
-- Retry a bounded number of times, then cool down instead of being
-- immediately re-queued by the next LoadChunk/scan -- confirmed by testing
-- that without this, a small number of chunks can fail indefinitely,
-- forever resetting the scan-interval backoff. chunkSucceeded() clears both
-- so a chunk that does process cleanly doesn't carry this history forward.
local chunkFailAttempts = {}
local MAX_CHUNK_FAIL_RETRIES = 5
local chunkFailCooldownUntilMs = {}
local CHUNK_FAIL_COOLDOWN_MS = 60000

-- Tallied, not printed per-chunk -- a print() per failure was console spam
-- during bursts. Flushed with the "Queue:" summary in OnTick.
local failedCooldownCount = 0

-- Same cooldown for every failure reason -- it's the retrying that costs
-- OnTick time, not the specific reason, so there's no need to special-case one.
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
local FAST_TRAVEL_BUDGET_MS = 3
local wasDrivingFast = false
local SCAN_INTERVAL = 100
local scanInterval = 100
local scanIntervalSet = false
local SCAN_RADIUS = 15
local scanTimer = 0
local debugTickCounter = 0

-- LoadChunk already queues every chunk as it streams in -- this periodic
-- scan is just a safety net for chunks that loaded before the mod
-- initialized. Back the effective interval off exponentially whenever a
-- cycle queues nothing and no tracked player changed chunks; snap back to
-- base the moment either happens again.
local SCAN_BACKOFF_MAX_MULTIPLIER = 30
local scanBackoffMultiplier = 1
local lastScanChunkX = {}
local lastScanChunkY = {}

-- Returns true if this is the first time trackKey has been seen, or if it
-- moved to a different chunk since the last time this was called for it.
local function scanTrackerMoved(trackKey, worldX, worldY)
    local wx = math.floor(worldX / 8)
    local wy = math.floor(worldY / 8)
    local moved = lastScanChunkX[trackKey] ~= wx or lastScanChunkY[trackKey] ~= wy
    lastScanChunkX[trackKey] = wx
    lastScanChunkY[trackKey] = wy
    return moved
end

-- Used to shrink the tick budget during fast travel, when chunk streaming is heaviest.
local function isAnyPlayerDrivingFast(thresholdKmh)
    local numPlayers = getNumActivePlayers and getNumActivePlayers() or 0
    for i = 0, numPlayers - 1 do
        local player = getSpecificPlayer(i)
        local vehicle = player and player:getVehicle()
        if vehicle and vehicle:getCurrentSpeedKmHour() >= thresholdKmh then return true end
    end
    if numPlayers == 0 then
        local online = getOnlinePlayers()
        if online and online.size then
            for i = 0, online:size() - 1 do
                local p = online:get(i)
                local vehicle = p and p:getVehicle()
                if vehicle and vehicle:getCurrentSpeedKmHour() >= thresholdKmh then return true end
            end
        end
    end
    return false
end

-- Live player position for queueChunk's priority check (not the frozen spawn point).
local function currentTrackedPlayerPos()
    local player = getSpecificPlayer and getSpecificPlayer(0)
    if not player then
        local online = getOnlinePlayers()
        player = online and online.size and online:size() > 0 and online:get(0) or nil
    end
    if not player then return nil, nil end
    return math.floor(player:getX()), math.floor(player:getY())
end

local spawnX = nil
local spawnY = nil
local spawnAttempts = 0
local MAX_SPAWN_ATTEMPTS = 5

local SEEN_CHUNKS_MAX = 20000
local seenChunksCount = 0

-- Filtered, index-aligned views of WDecay_PlacementGenerators/
-- WDecay_ModifierGenerators (see buildActiveGeneratorLists) with only the
-- currently-enabled generators. Forward-declared for loadDispatcherConfig.
local activePlacementGenerators = nil
local activePlacementIndices = nil
local activeModifierGenerators = nil
local activeModifierIndices = nil
local buildActiveGeneratorLists

-- OnTick unregisters itself when nothing is active (see loadDispatcherConfig)
-- so an idle mod costs zero per-tick calls. queueChunk/
-- WDecay_Dispatcher_QueueArea re-register it if they ever queue a chunk
-- while it's off.
local onTickRegistered = true
local OnTick

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

    TIME_BUDGET_MS = getInt('timeBudgetMs', 10)
    FAST_TRAVEL_SPEED_KMH = getInt('fastTravelSpeedKmh', 30)
    FAST_TRAVEL_BUDGET_MS = getInt('fastTravelBudgetMs', 3)
    SCAN_INTERVAL = getInt('scanInterval', 100)
    SCAN_RADIUS = getInt('scanRadius', 15)
    PRIORITY_RADIUS = getInt('priorityRadius', 5)
    DEBUG_MODE = getBool('debugMode', false)
    buildActiveGeneratorLists()
    dispatcherConfigLoaded = true

    -- Nothing active to generate, reseason, or overlay at all. Safe to
    -- Remove from inside OnTick's own first invocation -- only affects
    -- future ticks.
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

local function runGenerator(fn, square, checkResult, level, category, index)
    local ok, result = pcall(fn, square, checkResult, level)
    if not ok then
        print("[WDecay] " .. category .. " generator " .. index .. " error at " .. square:getX() .. "," .. square:getY() .. "," .. square:getZ() .. ": " .. tostring(result):sub(1, 120))
        return false, false
    end
    return true, result == true
end

-- Each *GeneratorFeatures[i] (set alongside WDecay_*Generators[i] at
-- registration) names the feature gating that generator. Filters to just
-- the enabled ones so dispatchGenerators never calls a disabled generator
-- at all. Original indices are kept alongside so error messages and
-- WDecay_DebugCount*, which are indexed against the unfiltered arrays,
-- still line up.
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

-- Debug path: one pcall per generator per square, same as before, so an
-- error is attributed to the exact generator/square/index that threw it.
local function dispatchGeneratorsChecked(square, checkResult, level)
    local allSucceeded = true
    if activePlacementGenerators then
        for n = 1, #activePlacementGenerators do
            local fn = activePlacementGenerators[n]
            local origIndex = activePlacementIndices[n]
            local ok, placed = runGenerator(fn, square, checkResult, level, "placement", origIndex)
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
            local ok = runGenerator(fn, square, checkResult, level, "modifier", origIndex)
            if not ok then allSucceeded = false end
        end
    end
    return allSucceeded
end

-- Release path: no per-generator pcall. runQueuedChunk's own pcall around
-- the whole chunk still catches a throw -- it just aborts the rest of that
-- chunk for this tick instead of being logged generator-by-generator, and
-- the chunk gets reprocessed next time it's queued either way. debugMode
-- trades this back for precise per-generator error attribution.
local function dispatchGeneratorsFast(square, checkResult, level)
    if activePlacementGenerators then
        for n = 1, #activePlacementGenerators do
            local fn = activePlacementGenerators[n]
            if fn(square, checkResult, level) then
                if WDecay_DebugCountPlacement then WDecay_DebugCountPlacement(activePlacementIndices[n]) end
                break
            end
        end
    end
    if activeModifierGenerators then
        for n = 1, #activeModifierGenerators do
            activeModifierGenerators[n](square, checkResult, level)
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
    local objects = square:getObjects()
    if objects then
        for i = 0, objects:size() - 1 do existing[objects:get(i)] = true end
    end
    return existing
end

local function recordNewPlacements(markerData, square, checkResult, existing)
    local objects = square:getObjects()
    if not objects then return end
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
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
    end
end

local WDecay_SquareCheck = require('wdecay_squarecheck/wdecay_squarecheck')
local WDecay_LoadedChunks = require('wdecay_loaded_chunks/wdecay_loaded_chunks')

local cachedSquareCheck = WDecay_SquareCheck.checkAll

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
    objects = objects or square:getObjects()
    if not objects then return false end

    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj then
            local modData = obj:getModData()
            if modData and cleanableType and modData["WDecay_Cleanable"] == cleanableType then
                return true
            end

            local spriteName = obj:getSpriteName()
            if spriteName then
                for p = 1, #prefixes do
                    if luautils.stringStarts(spriteName, prefixes[p]) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local carryCategories = {
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligTreesNatural",
        feature = "trees",
        carryKey = "WDecay_carryTreesNatural",
        placedKey = "WDecay_placedTreesNatural",
        eligible = function(checkResult, level)
            return level == 0 and checkResult and (not checkResult.cleaned or WDecay_Scaling.isRedecayPass()) and checkResult.isNatural == true
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
            return tree ~= nil
        end,
    },
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligTreesRoad",
        feature = "trees",
        carryKey = "WDecay_carryTreesRoad",
        placedKey = "WDecay_placedTreesRoad",
        eligible = function(checkResult, level)
            return level == 0 and checkResult and (not checkResult.cleaned or WDecay_Scaling.isRedecayPass())
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
            return tree ~= nil
        end,
    },
    {
        scaleCategory = "nature",
        eligKey = "WDecay_eligBushesNatural",
        feature = "bushes",
        carryKey = "WDecay_carryBushesNatural",
        placedKey = "WDecay_placedBushesNatural",
        eligible = function(checkResult, level)
            return level == 0 and checkResult and (not checkResult.cleaned or WDecay_Scaling.isRedecayPass()) and checkResult.isNatural == true
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
            return level == 0 and checkResult and (not checkResult.cleaned or WDecay_Scaling.isRedecayPass())
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
            if not checkResult or (checkResult.cleaned and not WDecay_Scaling.isRedecayPass()) then return false end
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
            return level == 0 and checkResult and (not checkResult.cleaned or WDecay_Scaling.isRedecayPass()) and checkResult.isNatural == true
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
            return level == 0 and checkResult and (not checkResult.cleaned or WDecay_Scaling.isRedecayPass())
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
            if not checkResult or (checkResult.cleaned and not WDecay_Scaling.isRedecayPass()) then return false end
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
    return true
end

local function processChunkSquares(chunk, key, deadline)
    local activeState = chunkWork[key]
    local wx = activeState and activeState.wx or chunk.wx
    local wy = activeState and activeState.wy or chunk.wy
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
            startedAt = DEBUG_MODE and getTimestampMs() or 0
        }
        chunkWork[key] = state
    else
        local markerSquare = chunk:getGridSquare(0, 0, state.markerZ)
        if chunk.wx ~= state.wx or chunk.wy ~= state.wy or not markerSquare or not markerSquare:getChunk()
            or math.floor(markerSquare:getX() / 8) ~= state.wx or math.floor(markerSquare:getY() / 8) ~= state.wy
            or markerSquare:getModData() ~= state.markerData then
            -- Chunk unloaded before we could resume it; only a fresh
            -- LoadChunk can bring it back, so don't keep retrying.
            chunkWork[key] = nil
            return chunkFailedTransiently(key, 1)
        end
        if state.mode == "carry" then
            return processChunkCarry(chunk, key, markerSquare, state.markerData, state.doneAtDays, deadline)
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
            WDecay_Random.reseedForChunk(state.wx, state.wy, salt)
            local checkResult = cachedSquareCheck(square, state.z)
            if checkResult then
                local existingObjects = snapshotObjects(square)
                recordEligibility(state.markerData, checkResult, state.z)
                recordUrbanFlag(state.markerData, checkResult)
                if not dispatchGenerators(square, checkResult, state.z) then state.failed = true end
                recordNewPlacements(state.markerData, square, checkResult, existingObjects)
                if WDecay_Overlays_ReconcileSquare then WDecay_Overlays_ReconcileSquare(square, checkResult, state.z) end
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
    local nowDays = WDecay_Scaling.getWorldAgeDays()
    markChunkDone(getMarkerSquare(chunk), state.markerData, nowDays)
    chunkWork[key] = nil
    chunkSucceeded(key)
    if WDecay_Debug and WDecay_Debug.totalChunksProcessed then
        WDecay_Debug.totalChunksProcessed = WDecay_Debug.totalChunksProcessed + 1
    end
    if DEBUG_MODE and WDecay_Debug and WDecay_Debug.totalChunkTimeMs then
        WDecay_Debug.totalChunkTimeMs = WDecay_Debug.totalChunkTimeMs + getTimestampMs() - state.startedAt
    end
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

local function enqueueScannedChunk(key, sq, wx, wy, worldX, worldY)
    local chunk = sq:getChunk()
    if not chunk then return 0 end

    pendingChunks[key] = true
    local dx = (wx * 8 + 4) - worldX
    local dy = (wy * 8 + 4) - worldY
    local sqDistance = dx * dx + dy * dy
    local isPriority = sqDistance <= PRIORITY_RADIUS * PRIORITY_RADIUS * 64
    if isPriority then
        chunkQueueTailHigh = chunkQueueTailHigh + 1
        chunkQueueHighChunks[chunkQueueTailHigh] = chunk
        chunkQueueHighKeys[chunkQueueTailHigh] = key
        chunkQueueHighWx[chunkQueueTailHigh] = wx
        chunkQueueHighWy[chunkQueueTailHigh] = wy
    else
        chunkQueueTailLow = chunkQueueTailLow + 1
        chunkQueueLowChunks[chunkQueueTailLow] = chunk
        chunkQueueLowKeys[chunkQueueTailLow] = key
        chunkQueueLowWx[chunkQueueTailLow] = wx
        chunkQueueLowWy[chunkQueueTailLow] = wy
    end

    return 1
end

-- Returns how many chunks this pass queued -- feeds the scan-interval
-- backoff in OnTick (0 queued means nothing new to find right now).
local function ScanChunksAroundPos(worldX, worldY, radius)
    if not modDataTable then return 0 end

    local cx0 = math.floor((worldX - radius * 8) / 8)
    local cx1 = math.floor((worldX + radius * 8) / 8)
    local cy0 = math.floor((worldY - radius * 8) / 8)
    local cy1 = math.floor((worldY + radius * 8) / 8)
    local queued = 0
    local scanDays = WDecay_Scaling.getWorldAgeDays()
    local redecayEnabled = WDecay_Scaling.isRedecayEnabled()
    for wx = cx0, cx1 do
        for wy = cy0, cy1 do
            local key = GenerateKey(wx, wy)
            if isSafehouseChunk(wx, wy) then
            elseif pendingChunks[key] or isChunkInFailCooldown(key) then
            elseif seenChunks[key] and redecayEnabled then
                local sq = getSquare(wx * 8, wy * 8, 0)
                if sq and isChunkMarkedDone(sq) and needsRedecay(sq, scanDays) then
                    seenChunks[key] = nil
                    seenChunksCount = seenChunksCount - 1
                    queued = queued + enqueueScannedChunk(key, sq, wx, wy, worldX, worldY)
                end
            elseif not seenChunks[key] then
                local sq = getSquare(wx * 8, wy * 8, 0)
                if sq then
                    local marked = isChunkMarkedDone(sq)
                    local redecay = marked and needsRedecay(sq, scanDays)
                    if marked and not redecay then
                        if not redecayEnabled then
                            markSeen(key)
                        end
                    else
                        queued = queued + enqueueScannedChunk(key, sq, wx, wy, worldX, worldY)
                    end
                end
            end
        end
    end

    if DEBUG_MODE and queued > 0 then
        print("[WDecay] Scan queued " .. queued .. " chunks around " .. worldX .. "," .. worldY)
    end

    return queued
end

local function queueChunk(chunk)
    local wx = chunk.wx
    local wy = chunk.wy
    if wx == nil or wy == nil then
        local refSquare = chunk:getGridSquare(0, 0, chunk:getMinLevel())
        if refSquare then
            wx = math.floor(refSquare:getX() / 8)
            wy = math.floor(refSquare:getY() / 8)
        else
            return
        end
    end

    if isSafehouseChunk(wx, wy) then return end
    local key = GenerateKey(wx, wy)
    if seenChunks[key] or pendingChunks[key] or isChunkInFailCooldown(key) then return end

    local markerSquare = getMarkerSquare(chunk)
    local marked = isChunkMarkedDone(markerSquare)
    local redecay = marked and needsRedecay(markerSquare)
    if marked and not redecay then
        if not WDecay_Scaling.isRedecayEnabled() then
            markSeen(key)
        end
        return
    end

    ensureOnTickRegistered()
    pendingChunks[key] = true
    local targetDist = 999999
    local cx, cy = wx * 8 + 4, wy * 8 + 4
    local px, py = currentTrackedPlayerPos()
    if px and py then
        local dx = cx - px
        local dy = cy - py
        targetDist = dx * dx + dy * dy
    end

    if targetDist <= PRIORITY_RADIUS * PRIORITY_RADIUS * 64 then
        chunkQueueTailHigh = chunkQueueTailHigh + 1
        chunkQueueHighChunks[chunkQueueTailHigh] = chunk
        chunkQueueHighKeys[chunkQueueTailHigh] = key
        chunkQueueHighWx[chunkQueueTailHigh] = wx
        chunkQueueHighWy[chunkQueueTailHigh] = wy
    else
        chunkQueueTailLow = chunkQueueTailLow + 1
        chunkQueueLowChunks[chunkQueueTailLow] = chunk
        chunkQueueLowKeys[chunkQueueTailLow] = key
        chunkQueueLowWx[chunkQueueTailLow] = wx
        chunkQueueLowWy[chunkQueueTailLow] = wy
    end
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
    scanTimer = scanInterval
end

local function requeueChunkWork(chunk, key, wx, wy, lowPriority)
    if lowPriority then
        chunkQueueTailLow = chunkQueueTailLow + 1
        chunkQueueLowChunks[chunkQueueTailLow] = chunk
        chunkQueueLowKeys[chunkQueueTailLow] = key
        chunkQueueLowWx[chunkQueueTailLow] = wx
        chunkQueueLowWy[chunkQueueTailLow] = wy
    else
        chunkQueueTailHigh = chunkQueueTailHigh + 1
        chunkQueueHighChunks[chunkQueueTailHigh] = chunk
        chunkQueueHighKeys[chunkQueueTailHigh] = key
        chunkQueueHighWx[chunkQueueTailHigh] = wx
        chunkQueueHighWy[chunkQueueTailHigh] = wy
    end
end

local function runQueuedChunk(chunk, key, wx, wy, lowPriority, deadline)
    if not chunk or not pendingChunks[key] then return end
    -- ponytail: wx/wy captured at enqueue time; IsoChunk proxy may reset across ticks
    local ok, result = pcall(processChunkSquares, chunk, key, deadline)
    if not ok then
        WDecay_Scaling.clearRedecayContext()
        pendingChunks[key] = nil
        chunkWork[key] = nil
        if WDecay_DebugCountChunk then WDecay_DebugCountChunk(false) end
        print("[WDecay] Chunk " .. key .. " error: " .. tostring(result):sub(1, 120))
    elseif result == "pending" then
        requeueChunkWork(chunk, key, wx, wy, lowPriority)
    else
        pendingChunks[key] = nil
        if result ~= "protected" and WDecay_DebugCountChunk then WDecay_DebugCountChunk(result == true) end
        if result then markSeen(key) end
    end
end

local function processNextQueuedChunk(highPriority, deadline)
    local chunk = nil
    local key = nil
    local wx = nil
    local wy = nil
    if highPriority then
        if chunkQueueHeadHigh > chunkQueueTailHigh then return false end
        chunk = chunkQueueHighChunks[chunkQueueHeadHigh]
        key = chunkQueueHighKeys[chunkQueueHeadHigh]
        wx = chunkQueueHighWx[chunkQueueHeadHigh]
        wy = chunkQueueHighWy[chunkQueueHeadHigh]
        chunkQueueHighChunks[chunkQueueHeadHigh] = nil
        chunkQueueHighKeys[chunkQueueHeadHigh] = nil
        chunkQueueHighWx[chunkQueueHeadHigh] = nil
        chunkQueueHighWy[chunkQueueHeadHigh] = nil
        chunkQueueHeadHigh = chunkQueueHeadHigh + 1
        if DEBUG_MODE and WDecay_Debug and WDecay_Debug.chunksHigh then WDecay_Debug.chunksHigh = WDecay_Debug.chunksHigh + 1 end
    else
        if chunkQueueHeadLow > chunkQueueTailLow then return false end
        chunk = chunkQueueLowChunks[chunkQueueHeadLow]
        key = chunkQueueLowKeys[chunkQueueHeadLow]
        wx = chunkQueueLowWx[chunkQueueHeadLow]
        wy = chunkQueueLowWy[chunkQueueHeadLow]
        chunkQueueLowChunks[chunkQueueHeadLow] = nil
        chunkQueueLowKeys[chunkQueueHeadLow] = nil
        chunkQueueLowWx[chunkQueueHeadLow] = nil
        chunkQueueLowWy[chunkQueueHeadLow] = nil
        chunkQueueHeadLow = chunkQueueHeadLow + 1
        if DEBUG_MODE and WDecay_Debug and WDecay_Debug.chunksLow then WDecay_Debug.chunksLow = WDecay_Debug.chunksLow + 1 end
    end
    if chunk then runQueuedChunk(chunk, key, wx, wy, not highPriority, deadline) end
    return true
end

function OnTick()
    if isClient() then return end

    if not dispatcherConfigLoaded then
        loadDispatcherConfig()
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

    if not scanIntervalSet and modDataTable then
        scanInterval = SCAN_INTERVAL
        if isMultiplayer() then
            scanInterval = SCAN_INTERVAL * 2
        end

        scanIntervalSet = true
    end

    scanTimer = scanTimer + 1
    if scanTimer >= scanInterval * scanBackoffMultiplier then
        scanTimer = 0
        if modDataTable then
            local totalQueued = 0
            local movedToNewChunk = false
            local scannedLocal = false
            local numPlayers = 1
            if getNumActivePlayers then
                numPlayers = getNumActivePlayers()
            end

            for playerIndex = 0, numPlayers - 1 do
                local player = getSpecificPlayer(playerIndex)
                if player then
                    scannedLocal = true
                    local px = math.floor(player:getX())
                    local py = math.floor(player:getY())
                    if px ~= 0 or py ~= 0 then
                        if not spawnX then
                            spawnX = px
                            spawnY = py
                        end

                        if scanTrackerMoved("local:" .. playerIndex, px, py) then movedToNewChunk = true end
                        local ok, result = pcall(ScanChunksAroundPos, px, py, SCAN_RADIUS)
                        if ok then
                            totalQueued = totalQueued + (result or 0)
                        else
                            print("[WDecay] Scan error: " .. tostring(result):sub(1, 120))
                        end
                    end
                end
            end

            if not scannedLocal then
                local onlinePlayers = getOnlinePlayers()
                if onlinePlayers and onlinePlayers.size then
                    local playerCount = onlinePlayers:size()
                    if playerCount > 0 then
                        for i = 0, playerCount - 1 do
                            local p = onlinePlayers:get(i)
                            if p then
                                local px = math.floor(p:getX())
                                local py = math.floor(p:getY())
                                if px ~= 0 or py ~= 0 then
                                    if not spawnX then
                                        spawnX = px
                                        spawnY = py
                                    end

                                    if scanTrackerMoved("online:" .. i, px, py) then movedToNewChunk = true end
                                    local ok, result = pcall(ScanChunksAroundPos, px, py, SCAN_RADIUS)
                                    if ok then
                                        totalQueued = totalQueued + (result or 0)
                                    else
                                        print("[WDecay] Scan error: " .. tostring(result):sub(1, 120))
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if spawnX and spawnX ~= 0 and spawnAttempts < MAX_SPAWN_ATTEMPTS then
                local radius = SCAN_RADIUS
                if spawnAttempts < 5 then
                    radius = SCAN_RADIUS * 2
                end

                spawnAttempts = spawnAttempts + 1
                local ok, result = pcall(ScanChunksAroundPos, spawnX, spawnY, radius)
                if ok then
                    totalQueued = totalQueued + (result or 0)
                else
                    print("[WDecay] Spawn scan error: " .. tostring(result):sub(1, 120))
                end
            end

            if totalQueued > 0 or movedToNewChunk then
                scanBackoffMultiplier = 1
            else
                scanBackoffMultiplier = math.min(scanBackoffMultiplier * 2, SCAN_BACKOFF_MAX_MULTIPLIER)
            end
        end
    end

    if chunkQueueHeadHigh > chunkQueueTailHigh and chunkQueueHeadLow > chunkQueueTailLow then
        chunkQueueHeadHigh = 1
        chunkQueueTailHigh = 0
        chunkQueueHeadLow = 1
        chunkQueueTailLow = 0
        return
    end

    if DEBUG_MODE then
        debugTickCounter = debugTickCounter + 1
        if debugTickCounter >= 30 then
            debugTickCounter = 0
            local highCount = chunkQueueTailHigh - chunkQueueHeadHigh + 1
            local lowCount = chunkQueueTailLow - chunkQueueHeadLow + 1
            print("[WDecay] Queue: high=" .. highCount .. " low=" .. lowCount)
            if failedCooldownCount > 0 then
                print("[WDecay] Chunk failures (last 30 ticks): cooled-down=" .. failedCooldownCount)
                failedCooldownCount = 0
            end
        end
    end

    local effectiveBudgetMs = TIME_BUDGET_MS
    if FAST_TRAVEL_SPEED_KMH > 0 and FAST_TRAVEL_BUDGET_MS < TIME_BUDGET_MS
        and isAnyPlayerDrivingFast(FAST_TRAVEL_SPEED_KMH) then
        effectiveBudgetMs = FAST_TRAVEL_BUDGET_MS
    end
    if DEBUG_MODE and (effectiveBudgetMs < TIME_BUDGET_MS) ~= wasDrivingFast then
        wasDrivingFast = effectiveBudgetMs < TIME_BUDGET_MS
        print("[WDecay] Fast travel budget " .. (wasDrivingFast and "engaged" or "released"))
    end

    local startMs = getTimestampMs()
    local deadline = startMs + effectiveBudgetMs
    local highDeadline = deadline
    if chunkQueueHeadHigh <= chunkQueueTailHigh and chunkQueueHeadLow <= chunkQueueTailLow and effectiveBudgetMs > 1 then
        highDeadline = startMs + math.max(1, math.floor(effectiveBudgetMs * 0.7))
    end

    while chunkQueueHeadHigh <= chunkQueueTailHigh and getTimestampMs() < highDeadline do
        processNextQueuedChunk(true, highDeadline)
    end
    while chunkQueueHeadLow <= chunkQueueTailLow and getTimestampMs() < deadline do
        processNextQueuedChunk(false, deadline)
    end
    while chunkQueueHeadHigh <= chunkQueueTailHigh and getTimestampMs() < deadline do
        processNextQueuedChunk(true, deadline)
    end

    if chunkQueueHeadHigh > chunkQueueTailHigh and chunkQueueHeadLow > chunkQueueTailLow then
        chunkQueueHeadHigh = 1
        chunkQueueTailHigh = 0
        chunkQueueHeadLow = 1
        chunkQueueTailLow = 0
    end

end

Events.OnTick.Add(OnTick)

Events.OnCreatePlayer.Add(function(playerIndex, player)
    spawnX = math.floor(player:getX())
    spawnY = math.floor(player:getY())
end)

Events.OnInitGlobalModData.Add(function(isNewGame)
    if not isServer() then return end

    initModDataCache()
end)

Events.LoadChunk.Add(function(chunk)
    if not isServer() then return false end

    queueChunk(chunk)
end)

function WDecay_Dispatcher_IsQueueIdle()
    return chunkQueueHeadHigh > chunkQueueTailHigh and chunkQueueHeadLow > chunkQueueTailLow
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

function WDecay_Dispatcher_QueueArea(radius, wipeMarkers, player)
    ensureOnTickRegistered()
    radius = radius or 3
    local queued = 0

    if chunkQueueHeadHigh > chunkQueueTailHigh and chunkQueueHeadLow > chunkQueueTailLow then
        chunkQueueHeadHigh = 1
        chunkQueueTailHigh = 0
        chunkQueueHeadLow = 1
        chunkQueueTailLow = 0
    end

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
            pendingChunks[key] = true
            chunkQueueTailLow = chunkQueueTailLow + 1
            chunkQueueLowChunks[chunkQueueTailLow] = chunk
            chunkQueueLowKeys[chunkQueueTailLow] = key
            chunkQueueLowWx[chunkQueueTailLow] = wx
            chunkQueueLowWy[chunkQueueTailLow] = wy
        end

        queued = queued + 1
    end, player)
    print("[WDecay] Debug: queued " .. queued .. " chunks (radius=" .. radius .. ", wipeMarkers=" .. tostring(wipeMarkers == true) .. ")")
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
