require('luautils')

local WDecay_CleanVegetation = require('wdecay_cleanvegetation/wdecay_cleanvegetation')

local cachedDebugMode = nil

local function isCleanDebug()
    if cachedDebugMode == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.debugMode')
        cachedDebugMode = opt and opt:getValue() or false
    end

    return cachedDebugMode
end

local function cleanLog(msg)
    if isCleanDebug() then
        print("[WDecay-Clean] " .. msg)
    end
end

local function onCleanVegMenu(worldobjects, square, player, areaSize)
    local bo = CleanVegCursor:new("", "", player, areaSize)

    getCell():setDrag(bo, player:getPlayerNum())
end

local function addCleanVegMenu(player, context, worldobjects)
    local player = getSpecificPlayer(player)
    local square

    if player:getVehicle() then
        return
    end

    for i, v in ipairs(worldobjects) do
        square = v:getSquare()
    end

    if not square then
        return
    end

    if not WDecay_CleanVegetation.hasCleanable(square) then
        return
    end

    local submenuOption = context:addOption(getText('UI_REMOVE_VEG'), worldobjects, nil)
    local subMenu = ISContextMenu:getNew(context)

    context:addSubMenu(submenuOption, subMenu)
    subMenu:addOption(getText('UI_CLEAN_TILE'), worldobjects, onCleanVegMenu, square, player, nil)
    subMenu:addOption(getText('UI_CLEAN_AREA_3'), worldobjects, onCleanVegMenu, square, player, 3)
    subMenu:addOption(getText('UI_CLEAN_AREA_5'), worldobjects, onCleanVegMenu, square, player, 5)
    subMenu:addOption(getText('UI_CLEAN_AREA_10'), worldobjects, onCleanVegMenu, square, player, 10)
end

Events.OnFillWorldObjectContextMenu.Add(addCleanVegMenu)
