local isDebug = isDebugEnabled()

WD_DebugTools = require("Debug/WD_DebugTools")

local DEBUG_TOOLS = "#### - Debug Tools - ####"
local GENERATE_SQUARE = "Generate Square"
local PRINT_CHECKRESULT = "Show Checkresult"
local PRINT_OBJECT_INFO = "Show Object Info"
local PRINT_METRIC = "Metric Info"
local START_BENCHMARK = "Start Benchmark"

local function onSelectSquare(worldobjects, square, playerId, selectionFlag)  
    if selectionFlag == WD_DebugTools.FLAG_PRINT_METRIC then
        WD_DebugTools.printMetric()
    elseif selectionFlag == WD_DebugTools.FLAG_BENCHMARK then
        WD_DebugTools.benchmark()
    else
        local debugCursor = DebugCursor:new(playerId, selectionFlag)
        getCell():setDrag(debugCursor, playerId)
    end
end

local function addSquareGenCheck(player, context, worldobjects)
    if worldobjects then
        local size = #worldobjects
        local object = nil
        local square = nil

        for i = 1, size do
            object = worldobjects[i]
            if object then
                square = object:getSquare()

                if square then
                    break
                end
            end
        end

        if square then
            local subMenuOption = context:addOption(DEBUG_TOOLS)
            local subMenu = ISContextMenu:getNew(context)
            context:addSubMenu(subMenuOption, subMenu)
            subMenu:addOption(GENERATE_SQUARE, worldobjects, onSelectSquare, square, player, WD_DebugTools.FLAG_GENERATE_SQUARE)
            subMenu:addOption(PRINT_CHECKRESULT, worldobjects, onSelectSquare, square, player, WD_DebugTools.FLAG_PRINT_CHECKRESULT)
            subMenu:addOption(PRINT_OBJECT_INFO, worldobjects, onSelectSquare, square, player, WD_DebugTools.FLAG_PRINT_OBJECT_INFO)
            subMenu:addOption(PRINT_METRIC, worldobjects, onSelectSquare, square, player, WD_DebugTools.FLAG_PRINT_METRIC)
            subMenu:addOption(START_BENCHMARK, worldobjects, onSelectSquare, square, player, WD_DebugTools.FLAG_BENCHMARK)
        end
    end
end

local function initDebugContext()
    if isDebug then
        Events.OnFillWorldObjectContextMenu.Add(addSquareGenCheck)
    end
end

initDebugContext()
