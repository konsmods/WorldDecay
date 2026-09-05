local merged = false

local function addItems(distributions, name, rustRemoverWeight, sandpaperWeight)
    local distribution = distributions and distributions[name]
    if not distribution or not distribution.items then return end
    table.insert(distribution.items, "RustRemover.RustRemover")
    table.insert(distribution.items, rustRemoverWeight)
    table.insert(distribution.items, "RustRemover.Sandpaper")
    table.insert(distribution.items, sandpaperWeight)
end

local function mergeDistributions()
    if merged then return end
    local distributions = ProceduralDistributions and ProceduralDistributions.list
    if not distributions then return end
    merged = true

    -- Rust Remover is intentionally rarer than Sandpaper in automotive and tool loot.
    addItems(distributions, "GarageMechanics", 1, 4)
    addItems(distributions, "MechanicTools", 1, 4)
    addItems(distributions, "CrateMechanics", 1, 3)
    addItems(distributions, "MechanicShelfMisc", 1, 3)
    addItems(distributions, "GarageTools", 0.5, 3)
end

Events.OnPreDistributionMerge.Add(mergeDistributions)
