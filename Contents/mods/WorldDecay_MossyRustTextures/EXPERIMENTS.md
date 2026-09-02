# Mossy-rust texture experiments

This file records the commands and settings used to reproduce the vehicle
texture experiments. Run commands from this directory:

```text
/home/top/Projects/Games/ProjectZomboid/DynamicVehicleOverlays
```

The generator scans the installed B42 Workshop vehicles and vanilla vehicle
scripts. It writes a standalone mod package under the Project Zomboid project
directory. Generated output is not copied into `WorldDecay` until the result
has been inspected.

## Current experiment: broken moss outline + orange rust core

Implementation: `retexture_gen/colorize.py::mossify` retains the original rust
in the center, derives inner and outer edge bands from the alpha mask, and
applies deterministic breakup to the outer band. The edge uses a
shader-compensated green while neutral source pixels remain available for the
shader to warm into orange rust. Existing vehicle skin counts and
`textureRust` references are unchanged.

```bash
python3 -m retexture_gen overlays \
  --out /home/top/Projects/Games/ProjectZomboid \
  --mod-id WorldDecay_MossyRustTextures \
  --mod-name 'World Decay - Mossy Rust Textures [B42]' \
  --alpha 3.5
```

Output:

```text
/home/top/Projects/Games/ProjectZomboid/WorldDecay_MossyRustTextures/42
```

After inspecting an experiment, these are the deployment commands used to
replace the matching WorldDecay submod in the project and live Workshop trees:

```bash
rm -rf /home/top/Projects/Games/ProjectZomboid/WorldDecay/Contents/mods/WorldDecay_MossyRustTextures/42
cp -a /home/top/Projects/Games/ProjectZomboid/WorldDecay_MossyRustTextures/42 \
  /home/top/Projects/Games/ProjectZomboid/WorldDecay/Contents/mods/WorldDecay_MossyRustTextures/

rm -rf /home/top/Zomboid/Workshop/WorldDecay/Contents/mods/WorldDecay_MossyRustTextures/42
cp -a /home/top/Projects/Games/ProjectZomboid/WorldDecay_MossyRustTextures/42 \
  /home/top/Zomboid/Workshop/WorldDecay/Contents/mods/WorldDecay_MossyRustTextures/
```

The `rm -rf` targets above are deliberately limited to the generated `42`
subdirectory so the surrounding WorldDecay package and Workshop metadata are
not removed.

Current color settings in `mossify()`:

```text
hue shift:       70
saturation:      0.75
value scale:     1.0
alpha boost:     3.5
inner edge:      7 px erosion
outer edge:      9 px dilation
outer breakup:   deterministic low-frequency noise
green mix:       65% shader-safe / 35% hue-shifted
rust core value: 82%
```

## Design notes: outlined moss around rust

The planned favorite approach is a baked two-sided, soft, broken outline:

```text
outer ring = dilated rust mask - original rust mask
inner ring = original rust mask - eroded rust mask
outline    = outer ring + inner ring
```

The implementation uses this outline model, with irregular noise and a
shader-safe green because the in-game rust shader applies approximately
`(1.1, 0.7, 0.5)` to `textureRust` RGB.

## Earlier experiment: appended overlay skins

This was the former Dynamic Vehicle Overlays design. It generated extra skin
entries for moss and three snow stages, then used Lua to switch among them.
It is retained here only as a historical reproduction command; it is no longer
the active implementation.

```bash
python3 -m retexture_gen overlays \
  --out /home/top/Projects/Games/ProjectZomboid \
  --mod-id DynamicVehicleOverlays \
  --mod-name 'Dynamic Vehicle Overlays' \
  --alpha 3.5
```

## Legacy WorldDecay vehicle-retexture build

This was the older skin-addition generator used for the original
`WorldDecay_VehicleRetexture` submod. It remains available in the generator,
but the simplified texture-replacement path is preferred for compatibility.

```bash
python3 -m retexture_gen build \
  --out /home/top/Projects/Games/ProjectZomboid \
  --mod-id WorldDecay_VehicleRetexture \
  --mod-name 'World Decay [VehicleRetexture] [B42]' \
  --require damnlib \
  --alpha 3.5
```

## Optional inspection commands

```bash
find /home/top/Projects/Games/ProjectZomboid/WorldDecay_MossyRustTextures/42/media/textures/Vehicles \
  -type f -name '*.png' | wc -l

python3 -m compileall -q retexture_gen
```
