local Config = require "RustRemover/RustRemover_Config"

local RUST_REMOVER_TYPE = "RustRemover.RustRemover"
local SANDPAPER_TYPE = "RustRemover.Sandpaper"
local MAX_DISTANCE = 6
local PENDING_TREATMENTS = setmetatable({}, { __mode = "k" })

local function nowMs()
    return getTimestampMs and getTimestampMs() or 0
end

local function isVehicleStationary(vehicle)
    local speed = vehicle.getCurrentSpeedKmHour and vehicle:getCurrentSpeedKmHour() or 0
    return not speed or math.abs(speed) <= 0.1
end

local function getPlayerItem(player, id, fullType)
    if type(id) ~= "number" then return nil end
    local item = player:getInventory():getItemWithIDRecursiv(id)
    if item and item:getFullType() == fullType then return item end
    return nil
end

local function consumeRustRemover(player, item, amount)
    local remaining = math.max(0, item:getCurrentUsesFloat() - amount)
    if remaining <= 0.0001 then
        local container = item:getContainer() or player:getInventory()
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    else
        item:setCurrentUsesFloat(remaining)
        sendItemStats(item)
    end
end

local function consumeSandpaper(player, item, loss)
    local remaining = item:getCondition() - loss
    if remaining <= 0 then
        local container = item:getContainer() or player:getInventory()
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    else
        item:setCondition(remaining)
        sendItemStats(item)
    end
end

local function getValidatedTreatment(player, args)
    if not Config.isEnabled() or type(args) ~= "table" or not player or player:getVehicle() then return end
    if type(args.vehicleId) ~= "number" then return end

    local vehicle = getVehicleById(args.vehicleId)
    if not vehicle or not isVehicleStationary(vehicle) or vehicle:getRust() <= 0 then return end
    if player:DistTo(vehicle:getX(), vehicle:getY()) > MAX_DISTANCE then return end

    local rustRemover = getPlayerItem(player, args.rustRemoverId, RUST_REMOVER_TYPE)
    local sandpaper = getPlayerItem(player, args.sandpaperId, SANDPAPER_TYPE)
    if not rustRemover or not sandpaper then return end

    local bottleUse = Config.getBottleUse()
    local sandpaperLoss = Config.getSandpaperLoss(sandpaper)
    if rustRemover:getCurrentUsesFloat() + 0.0001 < bottleUse
        or sandpaper:getCondition() < sandpaperLoss then return end

    return vehicle, rustRemover, sandpaper, bottleUse, sandpaperLoss
end

local function startTreatment(player, args)
    local vehicle, rustRemover, sandpaper = getValidatedTreatment(player, args)
    if not vehicle then return end

    local now = nowMs()
    local pending = PENDING_TREATMENTS[player]
    if pending and now > 0 and now < pending.expiresAt then return end

    local duration = Config.getActionDurationMs(player)
    PENDING_TREATMENTS[player] = {
        vehicleId = vehicle:getId(),
        rustRemoverId = rustRemover:getID(),
        sandpaperId = sandpaper:getID(),
        readyAt = now + duration,
        expiresAt = now + duration + 30000,
    }
end

local function completeTreatment(player, args)
    if type(args) ~= "table" then return end
    local pending = PENDING_TREATMENTS[player]
    if not pending then return end

    local now = nowMs()
    if now <= 0 or now < pending.readyAt or now > pending.expiresAt then
        if now > pending.expiresAt then PENDING_TREATMENTS[player] = nil end
        return
    end

    if args.vehicleId ~= pending.vehicleId
        or args.rustRemoverId ~= pending.rustRemoverId
        or args.sandpaperId ~= pending.sandpaperId then
        PENDING_TREATMENTS[player] = nil
        return
    end

    local vehicle, rustRemover, sandpaper, bottleUse, sandpaperLoss = getValidatedTreatment(player, args)
    PENDING_TREATMENTS[player] = nil
    if not vehicle then return end

    consumeRustRemover(player, rustRemover, bottleUse)
    consumeSandpaper(player, sandpaper, sandpaperLoss)
    vehicle:setRust(math.max(0, vehicle:getRust() - Config.getRustReduction()))
    vehicle:transmitRust()
end

local function onClientCommand(module, command, player, args)
    if module ~= "RustRemover" then return end

    if command == "StartTreatment" then
        startTreatment(player, args)
    elseif command == "CompleteTreatment" then
        completeTreatment(player, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)
