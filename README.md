# World Decay [B42]

## Known Issues

- Some Maniks Tiles are a bit too dark (quick fix in .pack?, put up the brightness)
- Vines on walls do not disappear when walls disappear to allow player to see inside places (I lowkey like it like that though, makes it cozy, I wonder if it stops zombie vision :O)
- Roadlines overlap with grass overlays (limitation of overlays)

## Roadmap / Ideas

- Noise-based spread / clustering of vegetation

## Notes to self

- WDecay_Overlays = flat 2D decals attached to the floor (cheap). Renders correctly **only** if the sheet has a `DEPTH_<sheet>.png` or the `FloorOverlay` flag - otherwise it falls back to the whole-tile box depth and gets clipped. Never occludes the player (depth mask off for floor-attached sprites).
- WDecay_Grass / WDecay_Placement.createTagged = a real IsoObject per square (more expensive). The only path that can occlude the player. `createTile()` routes to `CellLoader.DoTileObjectCreation`, the same code the map loader uses.
- To inspect the B42 API directly: `javap`/CFR against `projectzomboid.jar` (the unofficial javadocs online are B41 only).
