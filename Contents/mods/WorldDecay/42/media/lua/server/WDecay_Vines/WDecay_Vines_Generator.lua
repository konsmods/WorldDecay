local WD_Debug_Metric = require("Debug/WD_Debug_Metric")
local WDecay_Random = require('wdecay_random/wdecay_random')
local WDecay_Scaling = require('wdecay_scaling/wdecay_scaling')
local WDecay_Placement = require('wdecay_placement/wdecay_placement')
local WDecay_Vines = require('WDecay_Vines/WDecay_Vines')
local PROP_FENCE_LOW = IsoPropertyType.lookup("FenceTypeLow")
local PROP_WALL_NW = IsoPropertyType.lookup("WallNW"); local PROP_ATTACHED_NW = IsoPropertyType.lookup("attachedNW")
local PROP_WALL_W = IsoPropertyType.lookup("WallW"); local PROP_WINDOW_W = IsoPropertyType.lookup("WindowW")
local PROP_DOOR_W = IsoPropertyType.lookup("doorW"); local PROP_DOOR_WALL_W = IsoPropertyType.lookup("DoorWallW")
local PROP_ATTACHED_W = IsoPropertyType.lookup("attachedW"); local PROP_WALL_W_TRANS = IsoPropertyType.lookup("WallWTrans")
local PROP_ATTACHED_E = IsoPropertyType.lookup("attachedE"); local PROP_WALL_N = IsoPropertyType.lookup("WallN")
local PROP_WINDOW_N = IsoPropertyType.lookup("WindowN"); local PROP_DOOR_N = IsoPropertyType.lookup("doorN")
local PROP_DOOR_WALL_N = IsoPropertyType.lookup("DoorWallN"); local PROP_WALL_N_TRANS = IsoPropertyType.lookup("WallNTrans")
local PROP_ATTACHED_N = IsoPropertyType.lookup("attachedN"); local PROP_ATTACHED_S = IsoPropertyType.lookup("attachedS")
local SPRITE_FENCE = "fence"; local SPRITE_FENCING = "fencing_"; local SPRITE_ROOF_WALL = "walls_exterior_roofs_"; local SPRITE_ROOF = "roofs_"; local SPRITE_LOW_HOUSE_WALL = "walls_exterior_house_low_"; local SPRITE_CONSTRUCTION = "construction_"
local getLowW = WDecay_Vines.getRandomWallWLow; local getW = WDecay_Vines.getRandomWallW; local getTopW = WDecay_Vines.getRandomWallWTop
local getLowN = WDecay_Vines.getRandomWallNLow; local getN = WDecay_Vines.getRandomWallN; local getTopN = WDecay_Vines.getRandomWallNTop
local getLowNW = WDecay_Vines.getRandomWallNWLow; local getNW = WDecay_Vines.getRandomWallNW; local getTopNW = WDecay_Vines.getRandomWallNWTop
local randomizer = WDecay_Random.get()
local TIME_KEY = "WDecay_Vines-LoadGridsquare"
local cvp=nil; local function getVP() if cvp==nil then local o=getSandboxOptions():getOptionByName('WDecay.vinePercentage'); cvp=o and o:getValue() or 80 end; return cvp end
local cmfv=nil; local function getMFV() if cmfv~=nil then return cmfv end; local o=getSandboxOptions():getOptionByName('WDecay.multiFloorVines'); if not o then return true end; cmfv=o:getValue(); return cmfv end
local cveo=nil; local function isVEO() if cveo==nil then local o=getSandboxOptions():getOptionByName('WDecay.vinesExteriorOnly'); cveo=o and o:getValue(); if cveo==nil then cveo=true end end; return cveo end
local cvow=nil; local function isVOW() if cvow==nil then local o=getSandboxOptions():getOptionByName('WDecay.vinesOnWalls'); cvow=o and o:getValue(); if cvow==nil then cvow=true end end; return cvow end
local cvof=nil; local function isVOF() if cvof==nil then local o=getSandboxOptions():getOptionByName('WDecay.vinesOnFences'); cvof=o and o:getValue(); if cvof==nil then cvof=true end end; return cvof end
local function getFence(objects)
    if not objects then return nil end
    for i=0,objects:size()-1 do local obj=objects:get(i)
        if obj then local n=obj:getSpriteName()
            if n and (n:contains(SPRITE_FENCE) or n:contains(SPRITE_FENCING)) then return obj end
            if obj:isHoppable() then return obj end
        end
    end
    return nil
end
local function squareHasVine(square,objs)
    if not square then return true end
    objs=objs or square:getObjects(); if not objs then return false end
    for i=0,objs:size()-1 do local md=objs:get(i):getModData()
        if md and md["WDecay_Cleanable"]=="vine" then return true end
    end
    return false
end
local function squareHasConstruction(objs)
    if not objs then return false end
    for i=0,objs:size()-1 do local obj=objs:get(i)
        if obj then local n=obj:getSpriteName()
            if n and luautils.stringStarts(n, SPRITE_CONSTRUCTION) then return true end
        end
    end
    return false
end
local function createVine(square,obj,isLow,objs)
    if not square or not obj then return end
    if squareHasVine(square,objs) then return end
    local sprN=obj:getSpriteName()
    if sprN and (luautils.stringStarts(sprN, SPRITE_ROOF_WALL) or luautils.stringStarts(sprN, SPRITE_ROOF) or luautils.stringStarts(sprN, SPRITE_CONSTRUCTION)) then return end
    if sprN and luautils.stringStarts(sprN, SPRITE_LOW_HOUSE_WALL) then isLow=true end
    local props=obj:getProperties(); if not props then return end
    local lf,f,tf=nil,nil,nil
    if props:has(PROP_WALL_NW,PROP_ATTACHED_NW) then lf,f,tf=getLowNW,getNW,getTopNW
    elseif props:has(PROP_WALL_N,PROP_WINDOW_N,PROP_DOOR_N,PROP_DOOR_WALL_N,PROP_WALL_N_TRANS,PROP_ATTACHED_N,PROP_ATTACHED_S) then lf,f,tf=getLowN,getN,getTopN
    elseif props:has(PROP_WALL_W,PROP_WINDOW_W,PROP_DOOR_W,PROP_DOOR_WALL_W,PROP_ATTACHED_W,PROP_WALL_W_TRANS,PROP_ATTACHED_E) then lf,f,tf=getLowW,getW,getTopW
    else return end
    local sn=nil
    if isLow and lf then
        sn=lf()
    else
        local hasAbove=false
        if square:getZ()==0 then
            hasAbove=true
        else
            local above=square:getSquareAbove()
            if above and above:getWall() then hasAbove=true end
        end
        if hasAbove and f then sn=f()
        elseif tf then sn=tf()
        elseif f then sn=f() end
    end
    if sn then WDecay_Placement.createTagged(square, sn, "vine") end
end
local function LoadGridsquare(square,checkResult,level)
    if not checkResult then return end
    if checkResult.cleaned then return end
    if not getMFV() and level~=0 then return end
    if isVEO() and checkResult.isIndoor then return end
    if WDecay_Scaling.scaleFor('nature',getVP())<randomizer:random(1,100) then return end
    local objs = checkResult.objects or (checkResult.wall and square:getObjects())
    if squareHasConstruction(objs or square:getObjects()) then return end
    if square:hasFence() and isVOF() then local fence=getFence(objs); if fence then local fp=fence:getProperties(); createVine(square,fence,fp and fp:has(PROP_FENCE_LOW),objs) end end
    if checkResult.wall and isVOW() then createVine(square,checkResult.wall,false,objs) end
end
local pf=LoadGridsquare; local function dlg(s,cr,l) WD_Debug_Metric.startTimeMeasurement(TIME_KEY); local r=pf(s,cr,l); WD_Debug_Metric.endTimeMeasurement(TIME_KEY); return r end
if isDebugEnabled() then LoadGridsquare=dlg end
if not WDecay_ModifierGenerators then WDecay_ModifierGenerators={} end; table.insert(WDecay_ModifierGenerators,LoadGridsquare)
function WDecay_Vines_ApplyToSquare(square,checkResult,level)
    if not square then return end
    if checkResult and checkResult.cleaned then return end
    if not getMFV() and level~=0 then return end
    if isVEO() and checkResult and checkResult.isIndoor then return end
    if WDecay_Scaling.scaleFor('nature',getVP())<randomizer:random(1,100) then return end
    local objs=(checkResult and checkResult.objects) or square:getObjects()
    if squareHasConstruction(objs) then return end
    if square:hasFence() and isVOF() then local fence=getFence(objs); if fence then local fp=fence:getProperties(); createVine(square,fence,fp and fp:has(PROP_FENCE_LOW),objs) end end
    if checkResult and checkResult.wall and isVOW() then createVine(square,checkResult.wall,false,objs) end
end
local function resetCaches()
    cvp=nil; cmfv=nil; cveo=nil; cvow=nil; cvof=nil
end
Events.EveryDays.Add(resetCaches)
return WDecay_Vines
