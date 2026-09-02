from __future__ import annotations

from pathlib import Path

from .colorize import mossify
from .discover import VehicleSpec


_OLD_GENERATED_SUFFIXES = ("_moss.png", "_dirt.png", "_snow.png",
                           "_snow1.png", "_snow2.png", "_snow3.png",
                           "_snow1_melt.png", "_snow2_melt.png", "_snow3_melt.png")


def build_overlays(specs: list[VehicleSpec], out_dir: Path, mod_id: str,
                   mod_name: str, version: str = "42", alpha: float = 3.5) -> dict:
    """Replace source rust masks in place with mossy-rust versions.

    No vehicle skins are added. Existing scripts already reference these
    rust filenames, so the game's normal rust value controls the blend.
    """
    if version != "42":
        raise ValueError("this generator only supports Project Zomboid Build 42")

    mod_dir = out_dir / mod_id
    vdir = mod_dir / "42"
    tex_root = vdir / "media" / "textures" / "Vehicles"
    tex_root.mkdir(parents=True, exist_ok=True)

    rust_names: set[str] = set()
    for spec in specs:
        for src in spec.rust:
            if src.name in rust_names:
                continue
            # Keep the original basename: vehicle scripts need no patching.
            mossify(src, alpha_boost=alpha).save(tex_root / src.name)
            rust_names.add(src.name)

    # Remove artifacts from the former appended-skin implementation.
    for path in tex_root.iterdir():
        if path.is_file() and path.name.endswith(_OLD_GENERATED_SUFFIXES):
            path.unlink()
    for relative in (
        "media/lua/shared/DynamicVehicleOverlays_Skins.lua",
        "media/lua/shared/DynamicVehicleOverlays_Data.lua",
        "media/lua/client/DynamicVehicleOverlays_DebugMenu.lua",
        "media/lua/server/DynamicVehicleOverlays_Snow.lua",
    ):
        path = vdir / relative
        if path.is_file():
            path.unlink()

    (vdir / "mod.info").write_text(
        f"name={mod_name}\nid={mod_id}\n"
        "description=Mossy rust textures replacing vehicle rust overlays.\n"
        "pzversion=42\nmodversion=2.0.0\nversionMin=42.20.0\n"
    )
    return {"rust_textures": len(rust_names), "vehicles": 0, "skin_entries": 0}
