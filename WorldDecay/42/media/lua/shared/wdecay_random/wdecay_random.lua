local WDecay_Random = {}

local randomizer = newrandom()
randomizer:seed(ZombRand(1, 2147483647))

local worldSalt = 0

function WDecay_Random.get()
    return randomizer
end

function WDecay_Random.setWorldSalt(salt)
    worldSalt = salt or 0
end

function WDecay_Random.reseedForChunk(wx, wy, extraSalt)
    local seed = worldSalt + wx * 374761393 + wy * 668265263
    if extraSalt then
        seed = seed + extraSalt * 2654435761
    end

    randomizer:seed(seed)
end

function WDecay_Random.getWorldSalt()
    return worldSalt
end

function WDecay_Random.reseedVehicle(rng, vx, vy, extraSalt)
    local seed = worldSalt + vx * 2246822519 + vy * 3266489917
    if extraSalt then
        seed = seed + extraSalt * 2654435761
    end

    rng:seed(seed)
end

return WDecay_Random
