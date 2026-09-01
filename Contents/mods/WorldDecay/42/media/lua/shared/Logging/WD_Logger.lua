WD_Logger = {}

local buffer = ""
local isFlushed = true
local tickCounter = 0

local TICKS_BEFORE_FLUSH = 200
local PREFIX_ALL = "[World Decay] -> "
local PREFIX_INFO = PREFIX_ALL .. "[INFO] ->"
local PREFIX_DEBUG = PREFIX_ALL .. "[DEBUG] ->"
local PREFIX_WARNING = PREFIX_ALL .. "[WARNING] ->"
local PREFIX_ERROR = PREFIX_ALL .. "[ERROR] -> "
local PREFIX_FILENAME = "["
local SUFFIX_FILENAME = "]: "

local isDebug = isDebugEnabled()

local muteLogLookup = {}

-- This module is shared (runs on both client and server), so an always-on
-- Events.OnTickEvenPaused handler here costs a call on both sides every
-- tick for nothing, most of the time. Register it only while there's
-- buffered output to flush; writeBuffer re-registers on the next log call.
-- onTick is forward-declared since flush needs to Remove it and onTick
-- needs to call flush -- one has to be declared before the other exists.
local tickHandlerRegistered = false
local onTick

local function flush()
    if not isFlushed then
        isFlushed = true
        print(buffer)
        buffer = ""
    end
    if tickHandlerRegistered then
        tickHandlerRegistered = false
        Events.OnTickEvenPaused.Remove(onTick)
    end
end

function onTick()
    if tickCounter >= TICKS_BEFORE_FLUSH then
        tickCounter = 0
        flush()
    else
        tickCounter = tickCounter + 1
    end
end

local function ensureTickHandlerRegistered()
    if tickHandlerRegistered then return end
    tickHandlerRegistered = true
    tickCounter = 0
    Events.OnTickEvenPaused.Add(onTick)
end

local function writeBuffer(line)
    buffer = buffer .. "\n" .. line
    isFlushed = false
    ensureTickHandlerRegistered()
end

function WD_Logger.printInfo(message, fileName)
    if not muteLogLookup[fileName] then
        writeBuffer(PREFIX_INFO .. PREFIX_FILENAME .. fileName .. SUFFIX_FILENAME .. message) 
    end
end

function WD_Logger.printDebug(message, fileName)
    if isDebug then 
        if not muteLogLookup[fileName] then
            writeBuffer(PREFIX_DEBUG .. PREFIX_FILENAME .. fileName .. SUFFIX_FILENAME .. message)
        end
    end
end

function WD_Logger.printWarning(message, fileName)
    if not muteLogLookup[fileName] then
        writeBuffer(PREFIX_WARNING .. PREFIX_FILENAME .. fileName .. SUFFIX_FILENAME .. message)
    end
end

function WD_Logger.printError(message, fileName)
    if not muteLogLookup[fileName] then
        writeBuffer(PREFIX_ERROR .. PREFIX_FILENAME .. fileName .. SUFFIX_FILENAME .. message)
    end
end

function WD_Logger.flushBuffer()
    flush()
end

function WD_Logger.muteLog(fileName)
    muteLogLookup[fileName] = true
end

function WD_Logger.unmuteLog(fileName)
    muteLogLookup[fileName] = false
end

-- Always flushes on save (a no-op if nothing's buffered) -- the ticker
-- above is the only thing made conditional.
Events.OnPostSave.Add(flush)

return WD_Logger
