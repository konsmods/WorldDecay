from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import discover


def cmd_scan(args) -> None:
    specs = discover.scan(args.workshop, args.vanilla)
    m = discover.manifest(specs)
    rust = sum(len(s.rust) for s in specs)
    print(f"{m['mods']} mods, {len(specs)} vehicle specs, {m['skins']} skins, "
          f"{rust} rust textures ({sum(1 for s in specs if s.rust)} with rust)")
    if args.out:
        discover.save_manifest(specs, args.out)
        print(f"manifest -> {args.out}")
    nomasks = [s for s in specs if not s.rust]
    print(f"no rust texture: {len(nomasks)}")
    for s in nomasks[:10]:
        print(f"  - {s.mod_name}")


def cmd_build(args) -> None:
    from .build import build
    specs = discover.scan(args.workshop, args.vanilla)
    if args.vehicle:
        specs = [s for s in specs if args.vehicle.lower() in s.mod_name.lower()]
        if not specs:
            raise SystemExit(f"no vehicle matching '{args.vehicle}'")
    stats = build(specs, args.out, args.mod_id, args.mod_name, args.require,
                   args.version, args.shift, args.sat, args.alpha, args.snow)
    print(f"mod -> {args.out / args.mod_id}")
    print(f"rust textures replaced: {stats['rust_replaced']}")
    kind = "snow" if args.snow else "moss"
    entries = stats["snow_skin_entries"] if args.snow else stats["moss_skin_entries"]
    print(f"vehicles with {kind} skins added: {stats['vehicles_with_moss_skins']} "
          f"({entries} skin entries)")
    print("vehicles:")
    for name in stats["vehicles"]:
        print(f"  - {name}")


def cmd_overlays(args) -> None:
    from .overlays import build_overlays
    specs = discover.scan(args.workshop, args.vanilla)
    stats = build_overlays(specs, args.out, args.mod_id, args.mod_name,
                           args.version, args.alpha)
    print(f"mod -> {args.out / args.mod_id}")
    print(f"rust textures: {stats['rust_textures']}")
    print(f"vehicles: {stats['vehicles']}; overlay skin entries: {stats['skin_entries']}")


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(prog="retexture_gen")
    ap.add_argument("--workshop", type=Path, default=discover.WORKSHOP,
                     help="path to PZ's Steam Workshop content folder (id 108600), for custom "
                          "install locations or other OSes. Typical defaults: Linux "
                          "~/.local/share/Steam/steamapps/workshop/content/108600, Windows "
                          "C:\\Program Files (x86)\\Steam\\steamapps\\workshop\\content\\108600, "
                          "macOS ~/Library/Application Support/Steam/steamapps/workshop/content/108600"
                          f" (current default: {discover.WORKSHOP})")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("scan", help="inventory vehicle mods/skins/rust textures")
    p.add_argument("--out", type=Path, help="write a JSON manifest here")
    p.add_argument("--vanilla", type=Path, default=discover.VANILLA,
                   help="B42 game directory to include vanilla vehicles")
    p.set_defaults(func=cmd_scan)

    p = sub.add_parser("build", help="generate the retexture mod")
    p.add_argument("--out", type=Path, required=True, help="output directory")
    p.add_argument("--mod-id", default="WorldDecay_MossyRustTextures", help="output mod id (default: WorldDecay_MossyRustTextures)")
    p.add_argument("--mod-name", default="World Decay - Mossy Rust Textures [B42]", help="output mod display name")
    p.add_argument("--require", default="", help="comma-separated mod dependencies (usually not needed)")
    p.add_argument("--vehicle", default="", help="only build mods whose name contains this (default: all)")
    p.add_argument("--vanilla", type=Path, default=discover.VANILLA,
                   help="B42 game directory to include vanilla vehicles")
    p.add_argument("--version", default="42", choices=["42"], help="target PZ build version folder (B42 only)")
    p.add_argument("--shift", type=int, default=70, help="moss hue shift, 0-255 (default 70)")
    p.add_argument("--sat", type=float, default=0.75, help="moss saturation scale (default 0.75)")
    p.add_argument("--alpha", type=float, default=3.5,
                   help="alpha boost for rust/moss overlays (1.0 = original, higher = denser)")
    p.add_argument("--snow", action="store_true",
                   help="also generate white-graded rust textures and selectable snow skins")
    p.set_defaults(func=cmd_build)

    p = sub.add_parser("overlays", help="generate World Decay mossy rust textures")
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--mod-id", default="WorldDecay_MossyRustTextures")
    p.add_argument("--mod-name", default="World Decay - Mossy Rust Textures [B42]")
    p.add_argument("--vanilla", type=Path, default=discover.VANILLA)
    p.add_argument("--version", default="42", choices=["42"])
    p.add_argument("--alpha", type=float, default=3.5)
    p.set_defaults(func=cmd_overlays)

    args = ap.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main(sys.argv[1:])
