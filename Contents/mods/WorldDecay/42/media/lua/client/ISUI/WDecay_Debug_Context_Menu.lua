local FALLBACK_FLAGS = {
    FLAG_GENERATE_SQUARE = 1,
    FLAG_PRINT_CHECKRESULT = 2,
    FLAG_PRINT_OBJECT_INFO = 3,
    FLAG_PRINT_METRIC = 4,
    FLAG_BENCHMARK = 5,
}

WD_DebugTools = WD_DebugTools or FALLBACK_FLAGS

local DEBUG_TOOLS = "#### - Debug Tools - ####"
local GENERATE_SQUARE = "Generate Square"
local PRINT_CHECKRESULT = "Show Checkresult"
local PRINT_OBJECT_INFO = "Show Object Info"
local PRINT_METRIC = "Metric Info"
local START_BENCHMARK = "Start Benchmark"
local SPAWN_TREE = "Spawn Tree (Debug)"
local REMOVE_DEBUG_TREES = "Remove Debug Trees Here"

-- Lets us right-click a tile and spawn any vanilla tree species/size/season
-- preview via IsoTree.new()+AddTileObject(), for visually spot-checking the
-- frame formulas below without waiting on real spawn RNG or season changes.
-- Includes species WorldDecay doesn't spawn on its own (easternredbud,
-- cockspurhawthorn, carolinasilverbell, yellowwood) so all vanilla data can
-- be previewed here even though WDecay_Trees.species only lists the 7 used
-- for actual placement.
local DEBUG_TREE_SPECIES = {
    "redmaple", "easternredbud", "dogwood", "cockspurhawthorn", "carolinasilverbell",
    "americanlinden", "canadianhemlock", "americanholly", "yellowwood", "virginiapine", "riverbirch",
}

-- Ground truth from decompiling NatureTrees.init() / ErosionObj.setStageObject():
-- frame = seasonSlot * columnMultiplier + column, where "column" is which
-- growth-stage/size-variant of that tier (vanilla interleaves multiple stages
-- into one tileset for Small/Jumbo, but XL and XXL each get their own dedicated
-- tileset file, hence multiplier=1). WorldDecay's existing sprite pools only ever
-- use the "_1_0"/"_1_1" pair for Small and Jumbo, i.e. columns 0 and 1.
--   seasonSlot 0 = trunk/base, used year-round (trees set noSeasonBase=true).
--   seasonSlot 1 = NOT a season -- it's the snow-dusted swap-in for the base,
--             registered via ErosionIceQueen.addSprite(), used only while it's
--             actively snowing (replaces the base frame, doesn't stack with it).
--   seasonSlot 2-5 = "child" sprites (the foliage/crown), attached on top of the
--             base via the same addAttachedAnimSpriteByName() mechanism we use
--             below -- DECIDUOUS ONLY (evergreens have hasChildSprite=false, so
--             they never get one): 2=Spring, 3=Summer(early), 4=Summer(late),
--             5=Autumn. Winter has no child sprite registered at all -> bare trunk.
local DEBUG_TREE_TIERS = {
    { label = "Small", suffix = "", columnMultiplier = 4, columns = { 0, 1 } },
    { label = "Jumbo", suffix = "JUMBO", columnMultiplier = 2, columns = { 0, 1 } },
    { label = "Jumbo XL", suffix = "JUMBOXL", columnMultiplier = 1, columns = { 0 } },
    { label = "Jumbo XXL", suffix = "JUMBOXXL", columnMultiplier = 1, columns = { 0 } },
}

local DEBUG_SEASON_PREVIEWS = {
    { label = "Spring", seasonSlot = 2 },
    { label = "Summer (early)", seasonSlot = 3 },
    { label = "Summer (late)", seasonSlot = 4 },
    { label = "Autumn", seasonSlot = 5 },
    { label = "Winter (bare, no snow)", seasonSlot = nil },
    { label = "Snow (swap-in)", seasonSlot = 1 },
}

local DEBUG_TREE_MODDATA_FLAG = "WDecay_DebugTree"

local function isWDecayDebugEnabled()
    if isDebugEnabled and isDebugEnabled() then
        return true
    end

    local sandbox = getSandboxOptions and getSandboxOptions()
    local option = sandbox and sandbox:getOptionByName('WDecay.debugMode')
    return option ~= nil and option:getValue() == true
end

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

local function spawnDebugTreeObject(square, spriteName)
    if not getSprite(spriteName) then
        print("[WorldDecay Debug] Missing sprite: " .. tostring(spriteName))
        return nil
    end

    local tree = IsoTree.new(square, spriteName)
    square:AddTileObject(tree)
    tree:getModData()[DEBUG_TREE_MODDATA_FLAG] = true
    triggerEvent("OnObjectAdded", tree)
    print("[WorldDecay Debug] Spawned " .. spriteName .. " at " .. square:getX() .. "," .. square:getY() .. "," .. square:getZ())
    return tree
end

-- Mirrors ErosionObj.setStageObject(): base frame (seasonSlot 0) stays fixed
-- (trunk), the seasonal "child" sprite (if any) is attached on top -- never a
-- second object, so chopping the trunk once takes the whole tree, same as vanilla.
-- Snow (seasonSlot 1) swaps the base frame itself rather than attaching.
local function onSpawnDebugTree(worldobjects, square, playerId, baseSpriteName, column, columnMultiplier, seasonSlot)
    if not square or not baseSpriteName then return end

    column = column or 0
    columnMultiplier = columnMultiplier or 1

    if seasonSlot == 1 then
        spawnDebugTreeObject(square, baseSpriteName .. "_1_" .. (columnMultiplier + column))
        return
    end

    local tree = spawnDebugTreeObject(square, baseSpriteName .. "_1_" .. column)

    if tree and seasonSlot then
        local childFrame = seasonSlot * columnMultiplier + column
        local childSprite = baseSpriteName .. "_1_" .. childFrame
        if getSprite(childSprite) then
            tree:addAttachedAnimSpriteByName(childSprite)
        else
            print("[WorldDecay Debug] Missing child sprite: " .. childSprite)
        end
    end
end

-- Same setMonth()/setYear() call TIS's own erosion QA tool uses internally
-- (client/erosion/debug/DebugDemoTime.lua) to jump seasons instantly instead of
-- waiting in real time. The month change is authoritative on the server; use
-- one of the Force Reseason actions (or wait for the next seasonal tick) to
-- update already-existing vegetation immediately.
local function onRemoveDebugTrees(worldobjects, square, playerId)
    if not square then return end

    local objects = square:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local object = objects:get(i)
        if object:hasModData() and object:getModData()[DEBUG_TREE_MODDATA_FLAG] then
            square:RemoveTileObject(object)
        end
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

            local spawnTreeOption = subMenu:addOption(SPAWN_TREE)
            local spawnTreeMenu = ISContextMenu:getNew(subMenu)
            subMenu:addSubMenu(spawnTreeOption, spawnTreeMenu)

            for _, species in ipairs(DEBUG_TREE_SPECIES) do
                local speciesOption = spawnTreeMenu:addOption(species)
                local speciesMenu = ISContextMenu:getNew(spawnTreeMenu)
                spawnTreeMenu:addSubMenu(speciesOption, speciesMenu)

                for _, tier in ipairs(DEBUG_TREE_TIERS) do
                    local baseSpriteName = "e_" .. species .. tier.suffix

                    local tierOption = speciesMenu:addOption(tier.label)
                    local tierMenu = ISContextMenu:getNew(speciesMenu)
                    speciesMenu:addSubMenu(tierOption, tierMenu)

                    for _, column in ipairs(tier.columns) do
                        local columnMenu = tierMenu
                        if #tier.columns > 1 then
                            local columnOption = tierMenu:addOption("Variant " .. column)
                            columnMenu = ISContextMenu:getNew(tierMenu)
                            tierMenu:addSubMenu(columnOption, columnMenu)
                        end

                        for _, preview in ipairs(DEBUG_SEASON_PREVIEWS) do
                            columnMenu:addOption(preview.label, worldobjects, onSpawnDebugTree, square, player, baseSpriteName, column, tier.columnMultiplier, preview.seasonSlot)
                        end
                    end
                end
            end

            subMenu:addOption(REMOVE_DEBUG_TREES, worldobjects, onRemoveDebugTrees, square, player)
        end
    end
end

local debugContextRegistered = false
local function initDebugContext()
    if not debugContextRegistered and isWDecayDebugEnabled() then
        Events.OnFillWorldObjectContextMenu.Add(addSquareGenCheck)
        debugContextRegistered = true
    end
end

initDebugContext()
Events.OnGameStart.Add(initDebugContext)
