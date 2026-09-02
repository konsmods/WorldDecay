from __future__ import annotations

from pathlib import Path
import zlib

import numpy as np
from PIL import Image, ImageFilter


def _boost_alpha(im: Image.Image, alpha_boost: float) -> Image.Image:
    """Push a texture's alpha channel toward opaque. 1.0 = unchanged, >1.0 = denser."""
    a = np.asarray(im.getchannel("A"), dtype=np.float32)
    if alpha_boost != 1.0:
        a = 255.0 * (a / 255.0) ** (1.0 / max(alpha_boost, 0.01))
    alpha = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    im = im.copy()
    im.putalpha(alpha)
    return im


def enhance(src: Path, alpha_boost: float = 3.5) -> Image.Image:
    """Same texture, just more opaque/visible. No hue/saturation change."""
    im = Image.open(src).convert("RGBA")
    return _boost_alpha(im, alpha_boost)


def mossify(src: Path, hue_shift: int = 70, sat_scale: float = 0.75,
            value_scale: float = 1.0, alpha_boost: float = 3.5) -> Image.Image:
    """Make a broken moss outline around an orange rust core.

    The inner and outer edge bands are derived from the rust alpha mask. The
    source rust RGB is retained in the center, while the edge uses a
    shader-compensated green that remains green after the vehicle rust tint.
    """
    im = Image.open(src).convert("RGBA")
    im = _boost_alpha(im, alpha_boost)
    alpha = im.getchannel("A")
    alpha_np = np.asarray(alpha, dtype=np.float32)

    # Morphological bands: moss hugs both sides of the rust boundary.
    dilated = np.asarray(alpha.filter(ImageFilter.MaxFilter(9)), dtype=np.float32)
    eroded = np.asarray(alpha.filter(ImageFilter.MinFilter(7)), dtype=np.float32)
    outer = np.clip(dilated - alpha_np, 0, 255)
    inner = np.clip(alpha_np - eroded, 0, 255)

    # Deterministic low-frequency breakup makes the outer growth patchy while
    # keeping every rebuild of the same source texture identical.
    seed = zlib.crc32(src.name.encode("utf-8"))
    rng = np.random.default_rng(seed)
    small = Image.fromarray((rng.random((24, 24)) * 255).astype(np.uint8), "L")
    noise = np.asarray(small.resize(im.size, Image.Resampling.BICUBIC)
                       .filter(ImageFilter.GaussianBlur(1.0)), dtype=np.float32) / 255.0
    breakup = np.clip((noise - 0.30) / 0.70, 0.0, 1.0)
    outer *= 0.25 + 0.75 * breakup
    outer = np.asarray(Image.fromarray(np.uint8(outer)).filter(
        ImageFilter.GaussianBlur(1.0)), dtype=np.float32)

    edge = np.clip((inner * 0.90 + outer * 0.72) / 255.0, 0.0, 1.0)
    output_alpha = np.maximum(alpha_np, outer * 0.72)

    # The shader multiplies textureRust RGB by (1.1, 0.7, 0.5). This cyan-
    # green pre-compensation renders as a readable moss green in-game.
    source_rgb = np.asarray(im.convert("RGB"), dtype=np.float32)
    hsv = im.convert("HSV")
    h, s, v = hsv.split()
    h = h.point(lambda x: (x + hue_shift) % 256)
    s = s.point(lambda x: min(255, int(x * sat_scale)))
    v = v.point(lambda x: min(255, int(x * value_scale)))
    shifted_rgb = np.asarray(Image.merge("HSV", (h, s, v)).convert("RGB"),
                             dtype=np.float32)
    brightness = 0.68 + 0.32 * (source_rgb.mean(axis=2) / 255.0)
    safe_green = np.stack((40.0 * brightness, 235.0 * brightness,
                           100.0 * brightness), axis=2)
    edge_rgb = safe_green * 0.65 + shifted_rgb * 0.35
    # Darken only the preserved rust core at rust=1; leave the moss edge
    # bright enough to remain visible against dark vehicle paint.
    rust_core = source_rgb * 0.82
    result = rust_core * (1.0 - edge[..., None]) + edge_rgb * edge[..., None]
    result = np.clip(result, 0, 255).astype(np.uint8)
    rgb = Image.fromarray(result, "RGB")
    rgb.putalpha(Image.fromarray(np.clip(output_alpha, 0, 255).astype(np.uint8)))
    return rgb


def snowify(src: Path, white_scale: float = 0.8, alpha_boost: float = 3.5) -> Image.Image:
    """Create a neutral snow mask for the vehicle shader.

    damn_vehicle_shader applies (1.1, 0.7, 0.5) to every textureRust RGB
    value, so literal white becomes orange. This inverse-compensated blue
    white produces a neutral gray/white result after that shader tint.
    """
    im = Image.open(src).convert("RGBA")
    im = _boost_alpha(im, alpha_boost)
    # Use the source alpha only as coverage. The vehicle rust value is the
    # single opacity control; retaining partial mask alpha lets paint bleed
    # through and tints snow on brightly colored modded vehicles.
    alpha = im.getchannel("A").point(lambda p: 255 if p > 0 else 0)
    gray = im.convert("RGB").convert("L")
    # Keep the maximum post-shader channel balanced: (116,182,255) *
    # (1.1,0.7,0.5) ~= (0.5,0.5,0.5).
    compensated_white = Image.new("L", gray.size, 255)
    graded = Image.blend(gray, compensated_white,
                         max(0.0, min(1.0, white_scale)))
    rgb = Image.merge("RGB", tuple(
        graded.point(lambda p, scale=scale: min(255, int(p * scale)))
        for scale in (116 / 255, 182 / 255, 1.0)
    ))
    rgb.putalpha(alpha)
    return rgb
