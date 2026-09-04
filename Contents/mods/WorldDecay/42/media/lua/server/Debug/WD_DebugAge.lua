require('luautils')

local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')

local function refreshOverlays()
    if WDecay_Overlays_Refresh then
        WDecay_Overlays_Refresh()
    end
end

function WDecay_Status()
    WDecay_Scaling.printStatus()
end

function WDecay_SetDays(days)
    WDecay_Scaling.setDebugAgeDays(days)
    refreshOverlays()
    WDecay_Scaling.printStatus()
end

function WDecay_AddDays(days)
    local current = WDecay_Scaling.getDebugAgeDays() or WDecay_Scaling.getWorldAgeDays() or 0
    WDecay_Scaling.setDebugAgeDays(current + (tonumber(days) or 30))
    refreshOverlays()
    WDecay_Scaling.printStatus()
end

function WDecay_ClearDays()
    WDecay_Scaling.setDebugAgeDays(nil)
    refreshOverlays()
    WDecay_Scaling.printStatus()
end

local MAX_DEBUG_RADIUS = 100

function WDecay_CleanArea(radius, player)
    radius = tonumber(radius) or 3
    if radius < 1 then radius = 1 end
    if radius > MAX_DEBUG_RADIUS then radius = MAX_DEBUG_RADIUS end
    if not WDecay_CleanSquare then
        print("[WDecay] Debug: WDecay_CleanSquare not available")
        return
    end

    player = player or getSpecificPlayer(0)
    if not player then return end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local cleaned = 0
    for x = px - radius * 8, px + radius * 8 do
        for y = py - radius * 8, py + radius * 8 do
            local sq = getSquare(x, y, 0)
            local chunk = sq and sq:getChunk()
            if chunk then
                for z = chunk:getMinLevel(), chunk:getMaxLevel() do
                    local levelSq = getSquare(x, y, z)
                    if levelSq then
                        WDecay_CleanSquare(levelSq)
                        cleaned = cleaned + 1
                    end
                end
            elseif sq then
                WDecay_CleanSquare(sq)
                cleaned = cleaned + 1
            end
        end
    end

    print("[WDecay] Debug: cleaned " .. cleaned .. " squares (radius=" .. radius .. ")")
end

local overlayPrefixes = {
    "blends_grassoverlays",
    "blends_streetoverlays",
    "blends_dirtoverlays",
    "d_streetcracks",
    "d_floorleaves",
    "d_plants",
    "e_newgrass_",
    "d_generic_",
    "trash_01_"
}

local function stripFloorOverlays(floor)
    local attached = floor:getAttachedAnimSprite()
    if not attached then return end

    for n = attached:size() - 1, 0, -1 do
        local sp = attached:get(n)
        local parent = sp and sp:getParentSprite()
        local name = parent and parent:getName()
        if name then
            for i = 1, #overlayPrefixes do
                if luautils.stringStarts(name, overlayPrefixes[i]) then
                    floor:RemoveAttachedAnim(n)
                    break
                end
            end
        end
    end
end

function WDecay_ReapplyOverlays(radius, player)
    radius = tonumber(radius) or 3
    if radius < 1 then radius = 1 end
    if radius > MAX_DEBUG_RADIUS then radius = MAX_DEBUG_RADIUS end

    local overlays = getTileOverlays()
    if not overlays then return end

    player = player or getSpecificPlayer(0)
    if not player then return end

    refreshOverlays()

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local applied = 0
    for x = px - radius * 8, px + radius * 8 do
        for y = py - radius * 8, py + radius * 8 do
            local sq = getSquare(x, y, 0)
            local floor = sq and sq:getFloor()
            if floor then
                stripFloorOverlays(floor)
                overlays:updateTileOverlaySprite(floor)
                floor:transmitUpdatedSpriteToClients()
                applied = applied + 1
            end
        end
    end

    print("[WDecay] Debug: overlays reapplied on " .. applied .. " squares")
end

function WDecay_Regen(radius, player)
    radius = tonumber(radius) or 3
    WDecay_CleanArea(radius, player)
    if WDecay_Dispatcher_ClearCleanedArea then
        WDecay_Dispatcher_ClearCleanedArea(radius, player)
    end
    if WDecay_Dispatcher_QueueArea then
        WDecay_Dispatcher_QueueArea(radius, true, player, true)
    end

    WDecay_ReapplyOverlays(radius, player)
end

function WDecay_Redecay(radius, player)
    radius = tonumber(radius) or 3
    if WDecay_Dispatcher_ClearCleanedArea then
        WDecay_Dispatcher_ClearCleanedArea(radius, player)
    end
    if WDecay_Dispatcher_QueueArea then
        WDecay_Dispatcher_QueueArea(radius, false, player, true)
    end
end

function WDecay_TimerRedecay(radius, player)
    radius = tonumber(radius) or 3
    if WDecay_Dispatcher_QueueDueRedecayArea then
        WDecay_Dispatcher_QueueDueRedecayArea(radius, player)
    end
end

function WDecay_RedecayFrom(radius, days, player)
    radius = tonumber(radius) or 3
    if WDecay_Dispatcher_StampDoneAt then
        WDecay_Dispatcher_StampDoneAt(radius, days or 0, player)
    end

    WDecay_Redecay(radius, player)
end

local timelapse = nil

function WDecay_TimelapseIsRunning()
    return timelapse ~= nil
end

local function timelapseTick()
    if not timelapse then return end

    timelapse.tickCounter = timelapse.tickCounter + 1
    if timelapse.tickCounter < timelapse.intervalTicks then return end

    timelapse.tickCounter = 0

    if WDecay_Dispatcher_IsQueueIdle and not WDecay_Dispatcher_IsQueueIdle() then
        return
    end

    local current = WDecay_Scaling.getDebugAgeDays() or WDecay_Scaling.getWorldAgeDays() or 0
    local nextAge = current + timelapse.stepDays

    local reachedTarget = timelapse.targetDays and nextAge >= timelapse.targetDays
    if reachedTarget then
        nextAge = timelapse.targetDays
    end

    WDecay_Scaling.setDebugAgeDays(nextAge)
    refreshOverlays()

    if WDecay_Dispatcher_QueueArea then
        WDecay_Dispatcher_QueueArea(timelapse.radius, false, timelapse.player)
    end

    print("[WDecay] Timelapse: age=" .. math.floor(nextAge) .. "d (step " .. timelapse.stepDays .. "d)")

    if reachedTarget then
        WDecay_TimelapseStop()
    end
end

function WDecay_Timelapse(stepDays, intervalTicks, targetDays, radius, player)
    stepDays = tonumber(stepDays) or 7
    if stepDays < 1 then stepDays = 1 end

    intervalTicks = tonumber(intervalTicks) or 30
    if intervalTicks < 1 then intervalTicks = 1 end

    targetDays = tonumber(targetDays)
    if targetDays and targetDays <= 0 then targetDays = nil end

    radius = tonumber(radius) or 5
    if radius < 1 then radius = 1 end
    if radius > MAX_DEBUG_RADIUS then radius = MAX_DEBUG_RADIUS end

    if timelapse then
        Events.OnTick.Remove(timelapseTick)
    end

    timelapse = {
        stepDays = stepDays,
        intervalTicks = intervalTicks,
        targetDays = targetDays,
        radius = radius,
        player = player,
        tickCounter = 0
    }

    Events.OnTick.Add(timelapseTick)
    print("[WDecay] Timelapse started: step=" .. stepDays .. "d every " .. intervalTicks
        .. " ticks, target=" .. (targetDays and (targetDays .. "d") or "manual stop")
        .. ", radius=" .. radius)
end

function WDecay_TimelapseStop()
    if not timelapse then
        print("[WDecay] Timelapse not running")
        return
    end

    Events.OnTick.Remove(timelapseTick)
    timelapse = nil
    print("[WDecay] Timelapse stopped")
end

function WDecay_TimelapseToggle(stepDays, intervalTicks, targetDays, radius, player)
    if timelapse then
        WDecay_TimelapseStop()
    else
        WDecay_Timelapse(stepDays, intervalTicks, targetDays, radius, player)
    end
end

print("[WDecay-Debug] Age tools: WDecay_Status() WDecay_SetDays(d) WDecay_AddDays(d) WDecay_ClearDays() WDecay_Regen(r) WDecay_Redecay(r) WDecay_TimerRedecay(r) WDecay_RedecayFrom(r, d) WDecay_CleanArea(r) WDecay_ReapplyOverlays(r) WDecay_Timelapse(step, ticks, target, r) WDecay_TimelapseStop() WDecay_Panel()")
