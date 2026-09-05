require "TimedActions/ISBaseTimedAction"

local Config = require "RustRemover/RustRemover_Config"

RustRemoverAction = ISBaseTimedAction:derive("RustRemoverAction")

function RustRemoverAction:isValid()
    return Config.isEnabled()
        and self.character:getVehicle() == nil
        and self.vehicle
        and self.vehicle:getRust() > 0
        and self.rustRemover:getCurrentUsesFloat() + 0.0001 >= Config.getBottleUse()
        and self.sandpaper:getCondition() >= Config.getSandpaperLoss(self.sandpaper)
end

function RustRemoverAction:waitToStart()
    self.character:faceThisObject(self.vehicle)
    return self.character:shouldBeTurning()
end

function RustRemoverAction:update()
    self.character:faceThisObject(self.vehicle)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function RustRemoverAction:start()
    self:setActionAnim("VehicleWorkOnMid")
    self:setOverrideHandModels(self.rustRemover, self.sandpaper)
    sendClientCommand(self.character, "RustRemover", "StartTreatment", {
        vehicleId = self.vehicle:getId(),
        rustRemoverId = self.rustRemover:getID(),
        sandpaperId = self.sandpaper:getID(),
    })
end

function RustRemoverAction:perform()
    if self.character:DistTo(self.vehicle:getX(), self.vehicle:getY()) <= 6 then
        sendClientCommand(self.character, "RustRemover", "CompleteTreatment", {
            vehicleId = self.vehicle:getId(),
            rustRemoverId = self.rustRemover:getID(),
            sandpaperId = self.sandpaper:getID(),
        })
    end
    ISBaseTimedAction.perform(self)
end

function RustRemoverAction:new(character, vehicle, rustRemover, sandpaper)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.vehicle = vehicle
    o.rustRemover = rustRemover
    o.sandpaper = sandpaper
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = Config.getActionTime(character)
    o.caloriesModifier = 8
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end
