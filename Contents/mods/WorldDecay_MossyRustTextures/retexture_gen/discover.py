from __future__ import annotations

import hashlib
import json
import os
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

WORKSHOP = Path.home() / ".local/share/Steam/steamapps/workshop/content/108600"
VANILLA = Path.home() / ".local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid"

_SHELL_RE = re.compile(r"^.+_Shell_.+\.png$", re.IGNORECASE)


@dataclass
class VehicleSpec:
    workshop_id: str
    mod_name: str
    mod_root: Path
    media_root: Path
    version_dirs: list[str] = field(default_factory=list)
    skins: list[Path] = field(default_factory=list)
    masks: list[Path] = field(default_factory=list)
    rust: list[Path] = field(default_factory=list)
    models: list[Path] = field(default_factory=list)
    scripts: list[Path] = field(default_factory=list)
    vehicle_id: str = ""


def _media_roots(mod_root: Path) -> list[Path]:
    roots = []
    common = mod_root / "common" / "media"
    if common.is_dir():
        roots.append(common)
    legacy = mod_root / "media"
    if legacy.is_dir() and not (common.is_dir() and _same_tree(legacy, common)):
        roots.append(legacy)
    return roots


def _same_tree(a: Path, b: Path) -> bool:
    try:
        return all(p.relative_to(b).exists() for p in a.rglob("*") if p.is_file())
    except Exception:
        return False


def _scan_root(mod_root: Path, workshop_id: str, mod_name: str) -> VehicleSpec | None:
    scripts: set[Path] = set()
    versions = []
    for v in sorted(mod_root.iterdir()):
        if v.is_dir() and v.name.replace(".", "").isdigit():
            versions.append(v.name)
            sdir = v / "media" / "scripts"
            if sdir.is_dir():
                scripts.update(sdir.rglob("*.txt"))
    for base in (mod_root / "media" / "scripts", mod_root / "common" / "media" / "scripts"):
        if base.is_dir():
            scripts.update(base.rglob("*.txt"))
    spec = VehicleSpec(workshop_id, mod_name, mod_root, mod_root,
                       version_dirs=versions, scripts=sorted(scripts))
    roots = _media_roots(mod_root)
    tex_dirs: set[Path] = set()
    model_files: dict[str, Path] = {}
    for r in roots:
        vt = r / "textures" / "Vehicles"
        if vt.is_dir():
            tex_dirs.add(vt)
        mx = r / "models_X" / "vehicles"
        if mx.is_dir():
            for f in mx.glob("*.fbx"):
                model_files.setdefault(f.name.lower(), f)
    seen_skin: set[str] = set()
    seen_mask: set[str] = set()
    seen_rust: set[str] = set()
    for td in tex_dirs:
        for f in sorted(td.glob("*.png")):
            key = f.name.lower()
            if _SHELL_RE.match(f.name):
                if f.stem.lower() not in seen_skin:
                    seen_skin.add(f.stem.lower()); spec.skins.append(f)
            elif "_mask" in f.name.lower():
                if f.stem.lower() not in seen_mask:
                    seen_mask.add(f.stem.lower()); spec.masks.append(f)
            elif "_rust" in f.name.lower() and key not in seen_rust:
                seen_rust.add(key); spec.rust.append(f)
    spec.models = sorted(model_files.values())
    return spec if (spec.skins or spec.masks or spec.rust) else None


def scan(workshop: Path = WORKSHOP, vanilla: Path | None = VANILLA) -> list[VehicleSpec]:
    out: list[VehicleSpec] = []
    if vanilla and vanilla.is_dir():
        spec = _scan_root(vanilla, "vanilla", "Project Zomboid (Vanilla)")
        if spec:
            out.append(spec)
    if not workshop.is_dir():
        return out
    for wid_dir in sorted(p for p in workshop.iterdir() if p.is_dir()):
        for mods_dir in sorted(wid_dir.glob("mods")):
            for mod_root in sorted(p for p in mods_dir.iterdir() if p.is_dir()):
                spec = _scan_root(mod_root, wid_dir.name, mod_root.name)
                if spec and (spec.skins or spec.masks):
                    out.append(spec)
    return out


def manifest(specs: list[VehicleSpec]) -> dict:
    return {
        "mods": len({s.mod_name for s in specs}),
        "vehicles": len(specs),
        "skins": sum(len(s.skins) for s in specs),
        "masks": sum(len(s.masks) for s in specs),
        "models": sum(len(s.models) for s in specs),
        "entries": [
            {
                "workshop_id": s.workshop_id,
                "mod": s.mod_name,
                "versions": s.version_dirs,
                "skins": [str(p) for p in s.skins],
                "masks": [str(p) for p in s.masks],
                "models": [str(p) for p in s.models],
            }
            for s in specs
        ],
    }


def save_manifest(specs: list[VehicleSpec], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as fh:
        json.dump(manifest(specs), fh, indent=1)


def fbx_hash(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while chunk := fh.read(1 << 16):
            h.update(chunk)
    return h.hexdigest()[:16]
