from __future__ import annotations

from pathlib import Path

from .colorize import enhance, mossify, snowify
from .scripts import parse_vehicle_scripts


def _write(img, *paths: Path) -> None:
    for p in paths:
        p.parent.mkdir(parents=True, exist_ok=True)
        img.save(p)


def build(specs: list, out_dir: Path, mod_id: str, mod_name: str, require: str = "",
          version: str = "42", shift: int = 70, sat: float = 0.75,
          alpha: float = 3.5, snowy: bool = False) -> dict:
    """Generate one mod: higher-alpha rust replacing the originals in place, plus a
    mossy-rust variant of every existing paint skin, added as an extra skin choice.
    """
    if version != "42":
        raise ValueError("this generator only supports Project Zomboid Build 42")
    mod_dir = out_dir / mod_id
    version_dir = mod_dir / "42"
    tex_root = version_dir / "media" / "textures" / "Vehicles"

    rust_done = 0
    vehicles_seen = 0
    vehicle_names: list[str] = []
    moss_lua_calls: list[tuple[str, str, str]] = []
    snow_lua_calls: list[tuple[str, str, str]] = []

    for spec in specs:
        if not spec.rust:
            continue

        moss_by_rust: dict[str, str] = {}
        snow_by_rust: dict[str, str] = {}
        for src in spec.rust:
            # B42 mods keep all content below the version directory. Texture
            # names are referenced as Vehicles/<filename>, so flatten the
            # source media tree into B42's texture directory.
            target = tex_root / src.name
            target.parent.mkdir(parents=True, exist_ok=True)
            if not snowy:
                enhance(src, alpha).save(target)
            rust_done += 1

            if not snowy:
                moss_name = src.stem + "_moss"
                if not (tex_root / (moss_name + ".png")).is_file():
                    img = mossify(src, shift, sat, alpha_boost=alpha)
                    _write(img, tex_root / (moss_name + ".png"))
                moss_by_rust[src.stem] = "Vehicles/" + moss_name
            if snowy:
                snow_name = src.stem + "_snow"
                _write(snowify(src, alpha_boost=alpha), tex_root / (snow_name + ".png"))
                snow_by_rust[src.stem] = "Vehicles/" + snow_name

        if not spec.scripts:
            continue
        vehicles = parse_vehicle_scripts(spec.scripts)
        for vi in vehicles.values():
            if not vi.skins or not vi.rust:
                continue
            rust_key = vi.rust.split("/")[-1]
            default_moss = moss_by_rust.get(rust_key)
            default_snow = snow_by_rust.get(rust_key)
            if (not snowy and not default_moss) or (snowy and not default_snow):
                continue
            added = 0
            for sk in vi.skins:
                if not sk.texture:
                    continue
                if not snowy and default_moss:
                    moss_ref = (moss_by_rust.get(sk.textureRust.split("/")[-1])
                                if sk.textureRust else default_moss)
                    if not moss_ref:
                        continue
                    moss_lua_calls.append((f"Base.{vi.name}", sk.texture, moss_ref))
                if snowy:
                    snow_ref = snow_by_rust.get((sk.textureRust or vi.rust).split("/")[-1])
                    if snow_ref:
                        snow_lua_calls.append((f"Base.{vi.name}", sk.texture, snow_ref))
                added += 1
            if added:
                vehicles_seen += 1
                vehicle_names.append(vi.name)

    _write_mod_files(mod_dir, mod_id, mod_name, require, version,
                     moss_lua_calls + snow_lua_calls)
    return {
        "rust_replaced": rust_done,
        "vehicles_with_moss_skins": vehicles_seen,
        "moss_skin_entries": len(moss_lua_calls),
        "snow_skin_entries": len(snow_lua_calls),
        "vehicles": vehicle_names,
    }


def _write_mod_files(mod_dir: Path, mod_id: str, mod_name: str, require: str,
                      version: str, moss_lua_calls: list[tuple[str, str, str]]) -> None:
    info_lines = [f"name={mod_name}", f"id={mod_id}"]
    if require:
        info_lines.append(f"require={require}")
    info = "\n".join(info_lines) + "\n"

    mod_dir.mkdir(parents=True, exist_ok=True)
    vdir = mod_dir / "42"
    vdir.mkdir(parents=True, exist_ok=True)
    (vdir / "mod.info").write_text(
        info
        + "description=Vehicle retexture for decayed KI5 vehicles. Compatible with PZ 42.\n"
        + "pzversion=42\n"
        + "modversion=2.1.4\n"
        + "versionMin=42.20.0\n"
    )

    if not moss_lua_calls:
        return
    lua_dir = vdir / "media" / "lua" / "shared"
    lua_dir.mkdir(parents=True, exist_ok=True)
    lines = [
        # lets the vanilla spawn-time skin randomizer pick moss like any other paint colour
        "local function addMossSkin(script, shell, rust)",
        "    local vs = getScriptManager():getVehicle(script)",
        "    if not vs then return end",
        "    local short = script:gsub(\"^%a+%.\", \"\")",
        "    vs:Load(short, \"{ skin { texture = \" .. shell .. \", textureRust = \" .. rust .. \", } }\")",
        "end",
        "Events.OnGameBoot.Add(function()",
    ]
    for script, shell, moss in moss_lua_calls:
        lines.append(f'    addMossSkin("{script}", "{shell}", "{moss}")')
    lines.append("end)")
    (lua_dir / "vehicle_retexture_moss_skins.lua").write_text("\n".join(lines) + "\n")
