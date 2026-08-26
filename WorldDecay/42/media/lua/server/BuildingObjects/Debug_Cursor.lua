if not ISBuildingObject then 
    return
end

local WD_DebugTools = require("Debug/WD_DebugTools")
DebugCursor = ISBuildingObject:derive("DebugCursor")

DebugCursor.floorSprite = IsoSprite.new()
DebugCursor.floorSprite:LoadFramesNoDirPageSimple('media/ui/FloorTileCursor.png')

local COLOR_GREEN = {
    r = 0,
    g = 1,
    b = 0,
    alpha = 0.8
}

function DebugCursor:create(x, y, z, north, sprite)
    local square = getWorld():getCell():getGridSquare(x, y, z)
    
    if self.flag == WD_DebugTools.FLAG_GENERATE_SQUARE then 
        WD_DebugTools.generateSquare(square)
    elseif self.flag == WD_DebugTools.FLAG_PRINT_CHECKRESULT then 
        WD_DebugTools.printCheckResult(square)
    end
end

function DebugCursor:render(x, y, z, square)
    DebugCursor.floorSprite:RenderGhostTileColor(x, y, z, COLOR_GREEN.r, COLOR_GREEN.g, COLOR_GREEN.b, COLOR_GREEN.alpha)
end

function DebugCursor.isValid(square)
    return true
end

function DebugCursor:new(playerId, flag)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj:init()
    obj.player = playerId
    obj.flag = flag
    obj.character = getSpecificPlayer(playerId)
    obj.noNeedHammer = true
    obj.skipBuildAction = true
    return obj
end
