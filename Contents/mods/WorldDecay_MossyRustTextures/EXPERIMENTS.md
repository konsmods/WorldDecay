# Texture rebuild commands

Run from this mod directory. The generator scans installed B42 Workshop and
vanilla vehicle sources.

## Current moss overlays

```bash
python3 -m retexture_gen overlays --out .. \
  --mod-id WorldDecay_MossyRustTextures \
  --mod-name 'World Decay - Mossy Rust Textures [B42]' --alpha 3.5
```

The active moss calibration is in `retexture_gen/colorize.py`:
`safe green = (58, 205, 86)`, with hue shift `70`, saturation `0.75`, and
alpha boost `3.5`.

## Legacy variants

```bash
python3 -m retexture_gen overlays --out /home/top/Projects/Games/ProjectZomboid \
  --mod-id DynamicVehicleOverlays --mod-name 'Dynamic Vehicle Overlays' --alpha 3.5

python3 -m retexture_gen build --out /home/top/Projects/Games/ProjectZomboid \
  --mod-id WorldDecay_VehicleRetexture \
  --mod-name 'World Decay [VehicleRetexture] [B42]' --require damnlib --alpha 3.5
```

## Checks

```bash
find 42/media/textures/Vehicles -type f -name '*.png' | wc -l
python3 -m compileall -q retexture_gen
```
