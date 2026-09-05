require "TimedActions/ISTimedActionQueue"
require "TimedActions/RustRemoverAction"

local Config = require "RustRemover/RustRemover_Config"

local RUST_REMOVER_TYPE = "RustRemover.RustRemover"
local SANDPAPER_TYPE = "RustRemover.Sandpaper"

local function chooseRustRemover(inventory)
    local items = inventory:getAllTypeRecurse(RUST_REMOVER_TYPE)
    local needed = Config.getBottleUse()
    local chosen = nil
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getCurrentUsesFloat() + 0.0001 >= needed
            and (not chosen or item:getCurrentUsesFloat() > chosen:getCurrentUsesFloat()) then
            chosen = item
        end
    end
    return chosen
end

local function chooseSandpaper(inventory)
    local items = inventory:getAllTypeRecurse(SANDPAPER_TYPE)
    local chosen = nil
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local loss = Config.getSandpaperLoss(item)
        if item:getCondition() >= loss
            and (not chosen or item:getCondition() > chosen:getCondition()) then
            chosen = item
        end
    end
    return chosen
end

local function getTargetVehicle(player)
    local vehicle = IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
    if vehicle then return vehicle end

    local square = player:getCurrentSquare()
    return square and square:getVehicleContainer() or nil
end

local function onRemoveRust(player, vehicle, rustRemover, sandpaper)
    ISTimedActionQueue.add(RustRemoverAction:new(player, vehicle, rustRemover, sandpaper))
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not Config.isEnabled() then return end

    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end

    local vehicle = getTargetVehicle(player)
    if not vehicle or vehicle:getRust() <= 0 then return end
    local speed = vehicle.getCurrentSpeedKmHour and vehicle:getCurrentSpeedKmHour() or 0
    if speed and math.abs(speed) > 0.1 then return end

    local inventory = player:getInventory()
    local rustRemover = chooseRustRemover(inventory)
    local sandpaper = chooseSandpaper(inventory)
    if not rustRemover or not sandpaper then return end

    context:addOption(getText("ContextMenu_RustRemover_RemoveRust"), player, onRemoveRust, vehicle, rustRemover, sandpaper)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
