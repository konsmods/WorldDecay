# World Decay [B42]

## Fixed Issues

- Fence decay generator (`WDecay_Fences.lua`) could misclassify B42 entity-type fences (e.g. `MetalBigWireFence`) as classic breakable/bendable fences via `BrokenFences`/`BentFences`. Now skipped explicitly.
- `blends_grassoverlays_01` had no depth map and no `FloorOverlay` flag, so B42's tile-depth fallback clipped it to a box silhouette (straight-line cutoffs). Removed from the overlay pools.
- Grass only ever spawned as a real object indoors; outdoors/roads it was overlay-only (flat, no depth, no player occlusion). `WDecay_Grass` now mirrors `WDecay_Bushes`: real grass objects on natural ground, roads, and indoors, each with its own sandbox percentage.

## Known Issues

- Tile overlays can never occlude the player. `IsoObject.renderAttachedSprites` calls `glDepthMask(false)` whenever the parent object is a floor, so floor-attached sprites write no depth and characters always draw on top. Unfixable from Lua - vegetation that should hide the player's legs has to be a real `IsoObject` (which is what vanilla's own `WorldGen/features/plant/grass_*.lua` does via `IsoObject.new` + `square:AddTileObject`), not an overlay.

## Roadmap / Ideas

- Clothes Retexture & New Outfits
  - Low-quality, worn-out clothing without relying on vanilla's damage/dirt settings. Think:
  - Faded and sun-bleached colors
  - Torn and patched garments
  - Mud-stained and weathered textures
  - Outfits that tell a story (survivor, scavenger, hermit, etc.)

- New Occupations / Classes
  - Roles that make sense a decade into the apocalypse - not traditional jobs, but survival archetypes. These would complement the mod's decay theme - survivors who adapted to a world that's been falling apart for years. (no burger flippers anymore!) Also realistically they add a bit more traits, since they are real survivors already!
  - https://steamcommunity.com/sharedfiles/filedetails/?id=2856961307

- Disable re-decay incremental inside Safehouses (?)

- Noise-based spread / clustering of vegetation

## Notes to self

- WDecay_Overlays = flat 2D decals attached to the floor (cheap). Renders correctly **only** if the sheet has a `DEPTH_<sheet>.png` or the `FloorOverlay` flag - otherwise it falls back to the whole-tile box depth and gets clipped. Never occludes the player (depth mask off for floor-attached sprites).
- WDecay_Grass / WDecay_Placement.createTagged = a real IsoObject per square (more expensive). The only path that can occlude the player. `createTile()` routes to `CellLoader.DoTileObjectCreation`, the same code the map loader uses.
- To inspect the B42 API directly: `javap`/CFR against `projectzomboid.jar` (the unofficial javadocs online are B41 only).
