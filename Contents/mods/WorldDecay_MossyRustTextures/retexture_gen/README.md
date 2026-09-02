# retexture_gen

Generates a Project Zomboid mod that retextures vehicle rust overlays:

1. **Mossy rust replacement** — every rust overlay it finds is hue-shifted,
   desaturated, and alpha-boosted, then saved under the *same filename* so it
   overrides the original by mod load order. Existing vehicle skins and the
   game's normal rust-value logic remain unchanged.

It works on any mod that uses KI5's `damn_vehicle_shader` skin format (`skin { texture
= ..., textureRust = ... }` in the vehicle script) — not just KI5's own vehicles. Point
it at a different mod's name and it builds a retexture mod for that instead.

## Requirements

Python 3, `Pillow`, `numpy`.

## Commands

**`scan`** — inventory what's installed (mods, skins, rust textures found):

```
python3 -m retexture_gen scan
```

**`build`** — generate the mod:

```
python3 -m retexture_gen build \
  --out ./out \
  --mod-id TYL_VehicleRetexture \
  --mod-name "10 YEARS LATER - Vehicle Retexture [KI5]" \
  --require damnlib
```

Omit `--vehicle` to process every discovered vehicle mod. Pass it to build just one
(matches by substring against the source mod's folder name):

```
python3 -m retexture_gen build --vehicle 90bmwE30 --out ./out \
  --mod-id MyPack_Retexture --mod-name "My Pack Retexture"
```

### Flags

| Flag | Default | Meaning |
|---|---|---|
| `--workshop` | PZ's Steam Workshop content folder | root to scan for vehicle mods — override for custom install paths or other OSes (see below) |
| `--out` | *(required)* | output directory; the mod is written to `<out>/<mod-id>/` |
| `--mod-id` | *(required)* | output mod id — keep it short, no spaces |
| `--mod-name` | *(required)* | output mod display name |
| `--require` | *(none)* | comma-separated mod dependencies, e.g. `damnlib` |
| `--vehicle` | *(all)* | only build for source mods whose name contains this |
| `--version` | `42.13` | target PZ build version folder |
| `--shift` | `70` | moss hue shift, 0-255 (~70 ≈ +100°, green) |
| `--sat` | `0.75` | moss saturation scale |
| `--alpha` | `3.5` | alpha boost for the replacement rust overlays (1.0 = unchanged) |

## Custom install paths / other OSes

By default it looks for PZ's Workshop content (item 108600) in the standard Steam
location for your platform. If yours is somewhere else — a custom Steam library, a
non-Steam copy, or a different OS — pass `--workshop` (before the subcommand):

```
python3 -m retexture_gen --workshop "/path/to/steamapps/workshop/content/108600" scan
```

Typical defaults, for reference:

- Linux: `~/.local/share/Steam/steamapps/workshop/content/108600`
- Windows: `C:\Program Files (x86)\Steam\steamapps\workshop\content\108600`
- macOS: `~/Library/Application Support/Steam/steamapps/workshop/content/108600`

## Using it for a different vehicle pack

Nothing here is KI5-specific except the defaults you pass on the command line. To build
a retexture mod for someone else's vehicle pack, just point `--vehicle` at it and give
your own `--mod-id`/`--mod-name`/`--require`:

```
python3 -m retexture_gen build --vehicle SomeOtherPack --out ./out \
  --mod-id SomeOtherPack_Retexture --mod-name "Some Other Pack - Retexture" \
  --require SomeOtherPackDependency
```

## Output layout

```
<out>/<mod-id>/
  42/
    mod.info
    media/textures/Vehicles/...                        # replacement rust textures
```

The generator is B42-only and writes the versioned `42/` structure used by
WorldDecay. The default mod id is `WorldDecay_MossyRustTextures` and its display
name is `World Decay - Mossy Rust Textures [B42]`.
