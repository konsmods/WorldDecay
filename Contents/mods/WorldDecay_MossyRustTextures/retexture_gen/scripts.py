from __future__ import annotations

import re
from dataclasses import dataclass, field


@dataclass
class SkinInfo:
    texture: str = ""
    textureRust: str = ""


@dataclass
class VehicleInfo:
    name: str
    rust: str = ""
    skins: list[SkinInfo] = field(default_factory=list)
    templates: list[str] = field(default_factory=list)
    is_template: bool = False


_TEXTURE_RE = re.compile(r"^\s*texture\s*=\s*([^\s,]+)\s*,?\s*$")
_RUST_RE = re.compile(r"^\s*textureRust\s*=\s*([^\s,]+)\s*,?\s*$")


def parse_vehicle_scripts(files: list) -> dict[str, VehicleInfo]:
    parsed: list[VehicleInfo] = []
    for path in files:
        try:
            text = path.read_text(errors="replace")
        except Exception:
            continue
        for vi in _parse_text(text):
            parsed.append(vi)
    templates = {vi.name: vi for vi in parsed if vi.is_template}
    out: dict[str, VehicleInfo] = {}
    for vi in parsed:
        if not vi.is_template and vi.name not in out:
            out[vi.name] = vi
    for vi in out.values():
        if vi.is_template:
            continue
        for name in vi.templates:
            template = templates.get(name)
            if not template:
                continue
            if not vi.skins and template.skins:
                vi.skins = [SkinInfo(s.texture, s.textureRust) for s in template.skins]
            if not vi.rust:
                vi.rust = template.rust
            if vi.skins:
                break
    return {name: vi for name, vi in out.items() if not vi.is_template}


def _parse_text(text: str) -> list[VehicleInfo]:
    vehicles: list[VehicleInfo] = []
    lines = text.splitlines()
    i, n = 0, len(lines)
    while i < n:
        line = lines[i].strip()
        m = re.match(r"^(template\s+)?vehicle\s+(\S+)", line)
        if not m:
            i += 1
            continue
        vi = VehicleInfo(name=m.group(2), is_template=bool(m.group(1)))
        depth = line.count("{") - line.count("}")
        i += 1
        while i < n:
            s = lines[i].strip()
            if re.match(r"^skin\s*\{?", s):
                sk = _parse_skin(lines, i)
                if sk is not None:
                    skin, end_i, delta = sk
                    vi.skins.append(skin)
                    depth += delta
                    i = end_i
                    continue
            d = s.count("{") - s.count("}")
            tm = re.match(r"^template!?\s*=\s*([^,\s]+)", s)
            if tm:
                vi.templates.append(tm.group(1))
            if not vi.rust:
                rm = _RUST_RE.match(s)
                if rm:
                    vi.rust = rm.group(1)
            depth += d
            i += 1
            if depth <= 0:
                break
        vehicles.append(vi)
    return vehicles


def _parse_skin(lines: list, start: int):
    i = start
    depth = lines[i].count("{") - lines[i].count("}")
    n = len(lines)
    while i < n and depth < 1:
        i += 1
        if i >= n:
            return None
        depth += lines[i].count("{") - lines[i].count("}")
    if depth < 1:
        return None
    skin = SkinInfo()
    i += 1
    while i < n:
        s = lines[i].strip()
        if depth > 0:
            tm = _TEXTURE_RE.match(s)
            if tm and not skin.texture:
                skin.texture = tm.group(1)
            rm = _RUST_RE.match(s)
            if rm and not skin.textureRust:
                skin.textureRust = rm.group(1)
        depth += s.count("{") - s.count("}")
        i += 1
        if depth <= 0:
            break
    return skin, i, depth
