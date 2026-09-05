local WD_Debug_Metric = require("Debug/WD_Debug_Metric")

local TIME_KEY = "WDecay_SquareCheck-checkAll"

local WDecay_SquareCheck = {}

local ISO_OBJECT_CLASS = IsoObject.class

local ZONE_TOWN = "TownZone"
local ZONE_TRAILER_PARK = "TrailerPark"

local roadTiles = {
    "blends_street_01_0",
    "blends_street_01_5",
    "blends_street_01_16",
    "blends_street_01_21",
    "blends_street_01_32",
    "blends_street_01_37",
    "blends_street_01_38",
    "blends_street_01_39",
    "blends_street_01_48",
    "blends_street_01_53",
    "blends_street_01_54",
    "blends_street_01_55",
    "blends_street_01_64",
    "blends_street_01_69",
    "blends_street_01_70",
    "blends_street_01_71",
    "blends_street_01_80",
    "blends_street_01_85",
    "blends_street_01_86",
    "blends_street_01_87",
    "blends_street_01_96",
    "blends_street_01_101",
    "blends_street_01_102",
    "blends_street_01_103",
    "floors_exterior_tilesandstone_01_3",
    "floors_exterior_tilesandstone_01_4",
    "floors_exterior_tilesandstone_01_5",
    "floors_exterior_tilesandstone_01_6",
}
local roadTilesSet = {}
for _, v in ipairs(roadTiles) do roadTilesSet[v] = true end


local r = {}

local function fastCheckPlacement(square, level)
    if square:isWaterSquare() then return nil end

    r.isGoodSquare = square:isFree(false)
    r.hasWindow = false
    r.hasDoor = false
    r.isUrban = false
    r.isNatural = false
    r.hasWalls = false
    r.hasFences = false
    r.wall = false
    r.room = false
    r.isIndoor = false
    r.isRoad = false
    r.hasRoof = false
    r.objects = false
    r.cleaned = false
    -- Per-dispatch cache used by trees, bushes, and grass. This result table
    -- is deliberately reused, so reset it before checking every square.
    r.WDecay_vegetationMultiplier = nil

    local sqModData = square:getModData()
    if sqModData and sqModData["WDecay_cleaned"] then
        r.cleaned = true
    end

    r.hasWindow = square:hasWindowOrWindowFrame()
    if r.hasWindow then
        r.isUrban = true
    else
        r.hasDoor = square:isDoorSquare()
        if r.hasDoor then
            r.isUrban = true
        end
    end

    r.room = square:getRoom() or false

    r.hasWalls = square:isWallSquare()
    if r.hasWalls then
        r.isUrban = true
        r.wall = square:getWall()
    end

    r.hasFences = square:hasFence()
    if r.hasFences then
        r.isUrban = true
    end

    r.objects = square:getObjects()

    if r.isGoodSquare then

        local floorName = nil
        local floor = square:getFloor()
        if floor then
            local floorSprite = floor:getSprite()
            floorName = floorSprite and floorSprite:getName()
        end

        if level == 0 then
            if floorName and roadTilesSet[floorName] == true then
                r.isRoad = true
                r.isUrban = true
                return r
            end

            r.isNatural = square:hasNaturalFloor()
            if r.isNatural then
                r.isUrban = false
                return r
            end

            r.isUrban = false
        end

        if r.room then
            r.isIndoor = true
            r.isUrban = true
        end

        if level == 0 and floorName then
            r.isRoad = roadTilesSet[floorName] == true
            if r.isRoad then
                r.isUrban = true
            end
        end

        if not r.isUrban then
            local squareZone = square:getZoneType()
            r.isUrban = squareZone == ZONE_TOWN or
                squareZone == ZONE_TRAILER_PARK
        end

        if level > 0 then
            local squareAbove = square:getSquareAbove()
            r.hasRoof = squareAbove == nil
            if not r.hasRoof then
                r.hasRoof = square:haveRoofFull()
            end
        end
    end

    return r
end

function WDecay_SquareCheck.printCheckResult(checkresult)
    print("########## CHECKRESULT-DEBUG-INFORMATIONS ##########")
    if checkresult then
        for key, value in pairs(checkresult) do
            print(tostring(key) .. ": " .. tostring(value))
        end
    else
        print("checkresult: " .. tostring(checkresult))
    end
end

-- Called once per square, per chunk. WD_Debug_Metric's start/end calls are
-- no-ops in release already, but still cost two calls per square for
-- nothing -- same pattern as the generator files: bind the plain function
-- directly, only swap in the measured wrapper under isDebugEnabled().
WDecay_SquareCheck.checkAll = fastCheckPlacement

local function debugCheckAll(square, level)
    WD_Debug_Metric.startTimeMeasurement(TIME_KEY)
    local checkResult = fastCheckPlacement(square, level)
    WD_Debug_Metric.endTimeMeasurement(TIME_KEY)
    return checkResult
end

if isDebugEnabled() then
    WDecay_SquareCheck.checkAll = debugCheckAll
end

return WDecay_SquareCheck
