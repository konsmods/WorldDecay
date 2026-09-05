require('luautils')
local WDecay_CleanVegetation = require('wdecay_cleanvegetation/wdecay_cleanvegetation')
local WDecay_Season = require('wdecay_season/wdecay_season')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local Security = require('WDecay_ServerSecurity')

local function markCleaned(square)
    square:getModData()["WDecay_cleaned"] = true
    square:transmitModdata()
    square:flagForHotSave()
end

local function hasContainer(object)
    local container = nil

    pcall(function()
        container = object:getContainer()
    end)

    return container ~= nil
end

local function removeCleanableDecorations(object)
    if not object then
        return false
    end

    local changed = false
    local attached = object:getAttachedAnimSprite()

    if attached then
        for i = attached:size() - 1, 0, -1 do
            local anim = attached:get(i)
            local name = WDecay_CleanVegetation.getAttachedSpriteName(anim)

            if WDecay_CleanVegetation.isCleanableDecorationSpriteName(name) then
                object:RemoveAttachedAnim(i)
                changed = true
            end
        end
    end

    local overlayName = WDecay_CleanVegetation.getOverlaySpriteName(object)

    if WDecay_CleanVegetation.isCleanableDecorationSpriteName(overlayName) then
        object:setOverlaySprite(nil, -1.0, -1.0, -1.0, -1.0, true)
        changed = true
    end

    if changed then
        object:transmitUpdatedSpriteToClients()
    end

    local modData = object:getModData()

    if modData and modData["WDecay_OverlayApplied"] ~= nil then
        modData["WDecay_OverlayApplied"] = nil
        object:transmitModData()
    end

    return changed
end

local function tryCleanObject(square, object)
    if not object then
        return false
    end

    if hasContainer(object) then
        return false
    end

    local changed = removeCleanableDecorations(object)

    -- WorldDecay vegetation is deliberately stored as a special object so it
    -- replicates correctly. That storage detail must not make it immune to
    -- the same clean operation as initial-generation vegetation.
    if object ~= square:getFloor() and WDecay_CleanVegetation.isCleanableMainObject(object) then
        square:transmitRemoveItemFromSquare(object)
        return true
    end

    return changed
end

function WDecay_CleanSquare(square)
    if not square then
        return false
    end

    local changed = false
    local floor = square:getFloor()

    if floor and removeCleanableDecorations(floor) then
        changed = true
    end

    local seen = {}
    local function cleanList(objects)
        if not objects then return end
        for i = objects:size() - 1, 0, -1 do
            local object = objects:get(i)
            if object and not seen[object] then
                seen[object] = true
                if tryCleanObject(square, object) then
                    changed = true
                end
            end
        end
    end

    cleanList(square:getObjects())
    cleanList(square:getSpecialObjects())

    markCleaned(square)
    square:setOverlayDone(true)
    square:RecalcAllWithNeighbours(true)

    return changed
end

local function validCoordinate(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value == math.floor(value)
end

local function isReachable(player, square)
    if not player or not square or player:getZ() ~= square:getZ() then
        return false
    end

    local playerSquare = player:getSquare()

    if not playerSquare then
        return false
    end

    local dx = math.abs(playerSquare:getX() - square:getX())
    local dy = math.abs(playerSquare:getY() - square:getY())

    if dx > 1 or dy > 1 then
        return false
    end

    if dx == 0 and dy == 0 then
        return true
    end

    return not playerSquare:isBlockedTo(square)
end

local function onCleanVegCommand(module, command, player, args)
    if module ~= "CleanVeg" or command ~= "CleanVegCommand" or type(args) ~= "table" then
        return
    end

    local x = args.x
    local y = args.y
    local z = args.z

    if not validCoordinate(x) or not validCoordinate(y) or not validCoordinate(z) then
        return
    end

    local square = getCell():getGridSquare(x, y, z)

    if square and isReachable(player, square)
        and Security.allowPlayerAction(player, "cleanVegetation", 1000) then
        WDecay_CleanSquare(square)
    end
end

local function advanceSeasonalDebugMonth()
    local gameTime = getGameTime()
    if not gameTime then return end

    gameTime:setMonth(gameTime:getMonth() + 1)
    if gameTime:getMonth() >= 12 then
        gameTime:setMonth(0)
        gameTime:setYear(gameTime:getYear() + 1)
    end

    WDecay_Season.invalidateCache()
    print("[WorldDecay Debug] Advanced to month " .. (gameTime:getMonth() + 1) .. "/" .. gameTime:getYear())
end

local function setSeasonalDebugSeason(season)
    local months = { spring = 2, summer = 5, autumn = 8, winter = 11 }
    local month = months[season]
    if month == nil then return end
    local gameTime = getGameTime()
    if not gameTime then return end
    gameTime:setMonth(month)
    WDecay_Season.invalidateCache()
    print("[WorldDecay Debug] Set season to " .. season)
end

local function printSeasonalClimateInfo()
    local climate = getClimateManager()
    if not climate then return end
    print("[WorldDecay Debug] Season=" .. tostring(climate:getSeasonName())
        .. " SnowStrength=" .. tostring(climate:getSnowStrength()))
end

-- Every debug action is server-owned through this sole multiplayer route.
local function onDebugCommand(module, command, player, args)
    if module ~= "WDecayDebug" or command ~= "Run" or type(args) ~= "table" then return end
    if not Security.isAdmin(player) then
        if Security.allowPlayerAction(player, "debugDenied", 5000) then
            print("[WDecay] Denied debug command from non-admin player")
        end
        return
    end

    local action = args.action
    if type(action) ~= "string" then return end
    local cooldown = action == "monitor" and 400 or 1000
    if not Security.allowPlayerAction(player, "debug:" .. action, cooldown) then return end

    local reseasonFunctions = {
        trees = "reseasonNearbyTrees", bushes = "reseasonNearbyBushes",
        grass = "reseasonNearbyGrass", vines = "reseasonNearbyVines",
    }
    local radius = Security.debugRadius(args.radius)

    if action == "season" then setSeasonalDebugSeason(args.season)
    elseif action == "advanceMonth" then advanceSeasonalDebugMonth()
    elseif action == "climate" then printSeasonalClimateInfo()
    elseif action == "reseason" then
        local fn = reseasonFunctions[args.kind] and WD_DebugTools and WD_DebugTools[reseasonFunctions[args.kind]]
        if fn then fn() end
    elseif action == "status" then
        if WDecay_Status then WDecay_Status() end
        if WDecay_DebugPrintStatus then WDecay_DebugPrintStatus() end
    elseif action == "monitor" and player and WDecay_Dispatcher_GetMonitorData then
        sendServerCommand(player, "WDecayDebug", "Monitor", WDecay_Dispatcher_GetMonitorData(player, radius))
    elseif action == "setDays" and WDecay_SetDays then
        local days = Security.clampInteger(args.days, 0, Security.MAX_DEBUG_AGE_DAYS, nil)
        if not days then return end
        WDecay_SetDays(days)
        sendServerCommand(player, "WDecayDebug", "Age", { hasOverride = true, days = WDecay_Scaling.getDebugAgeDays() })
    elseif action == "clearDays" and WDecay_ClearDays then
        WDecay_ClearDays()
        sendServerCommand(player, "WDecayDebug", "Age", { hasOverride = false })
    elseif action == "addDays" and WDecay_AddDays then
        local days = Security.clampInteger(args.days, 1, Security.MAX_DEBUG_AGE_DAYS, nil)
        if not days then return end
        WDecay_AddDays(days)
        sendServerCommand(player, "WDecayDebug", "Age", { hasOverride = true, days = WDecay_Scaling.getDebugAgeDays() })
    elseif action == "regen" and WDecay_Regen then WDecay_Regen(radius, player)
    elseif action == "redecay" and WDecay_Redecay then WDecay_Redecay(radius, player)
    elseif action == "timerRedecay" and WDecay_TimerRedecay then WDecay_TimerRedecay(radius, player)
    elseif action == "clean" and WDecay_CleanArea then WDecay_CleanArea(radius, player)
    elseif action == "overlays" and WDecay_ReapplyOverlays then WDecay_ReapplyOverlays(radius, player)
    elseif action == "timelapse" and WDecay_TimelapseToggle then
        local step = Security.clampInteger(args.step, 1, Security.MAX_TIMELAPSE_STEP_DAYS, nil)
        local ticks = Security.clampInteger(args.ticks, 1, Security.MAX_TIMELAPSE_TICKS, nil)
        local target = Security.clampInteger(args.target, 1, Security.MAX_DEBUG_AGE_DAYS, nil)
        if not step or not ticks or not target then return end
        WDecay_TimelapseToggle(step, ticks, target, radius, player)
    end
end

Events.OnClientCommand.Add(onCleanVegCommand)
Events.OnClientCommand.Add(onDebugCommand)
