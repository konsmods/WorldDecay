-- Matches vanilla's own ErosionMain.mainTimer() (the real body behind
-- EveryTenMinutes()): it walks ServerMap.instance.loadedCells -- the
-- server-authoritative "what's currently loaded" list, each holding an 8x8
-- grid of chunks -- not a per-player rendering/streaming radius. This gives
-- WDecay_*_Reseason.lua the same scope, and it's also just the more correct
-- source to use here anyway: these reseason modules are server-side scripts,
-- and IsoChunkMap (what this used to read) is a client-side rendering/
-- streaming construct that may not behave the same way (or exist at all) on
-- a true dedicated server with no local client attached.
local WDecay_LoadedChunks = {}

local CELL_CHUNK_GRID = 8

-- Calls fn(chunk) once for every chunk in every currently-loaded server cell.
function WDecay_LoadedChunks.forEachLoadedChunk(fn)
    local serverMap = ServerMap.instance
    local cells = serverMap and serverMap.loadedCells
    if not cells then return end

    for i = 0, cells:size() - 1 do
        local cell = cells:get(i)
        if cell and cell.isLoaded then
            for cx = 0, CELL_CHUNK_GRID - 1 do
                for cy = 0, CELL_CHUNK_GRID - 1 do
                    local chunk = cell:getChunk(cx, cy)
                    if chunk then fn(chunk) end
                end
            end
        end
    end
end

return WDecay_LoadedChunks
