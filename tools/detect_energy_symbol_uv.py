"""
Detects the normalized UV center of the energy symbol in each energy card image.
Uses a saturation-weighted centroid: energy symbols are the most vibrant colored
region on the card, so high-saturation pixels vote for the center location.

Run from the project root:
    python3 tools/detect_energy_symbol_uv.py

Output is ready-to-paste GDScript for the ENERGY_SYMBOL_UV dict in attachment_display.gd.
"""

import colorsys
from pathlib import Path
from PIL import Image

PROJECT_ROOT = Path(__file__).parent.parent

CARDS = {
    "RS_104_grass_energy":     "assets/images/RS/RS_104_grass_energy.png",
    "RS_105_fighting_energy":  "assets/images/RS/RS_105_fighting_energy.png",
    "RS_106_water_energy":     "assets/images/RS/RS_106_water_energy.png",
    "RS_107_psychic_energy":   "assets/images/RS/RS_107_psychic_energy.png",
    "RS_108_fire_energy":      "assets/images/RS/RS_108_fire_energy.png",
    "RS_109_lightning_energy": "assets/images/RS/RS_109_lightning_energy.png",
    "RS_93_darkness_energy":   "assets/images/RS/RS_93_darkness_energy.png",
    "RS_94_metal_energy":      "assets/images/RS/RS_94_metal_energy.png",
    "RS_95_rainbow_energy":    "assets/images/RS/RS_95_rainbow_energy.png",
    "SS_93_multi_energy":      "assets/images/SS/SS_93_multi_energy.png",
}

SAT_THRESHOLD = 0.35


def find_symbol_center(path: Path) -> tuple[float, float] | None:
    img = Image.open(path).convert("RGB")
    w, h = img.size
    pixels = img.load()
    cx = cy = weight = 0.0
    for y in range(h):
        for x in range(w):
            r, g, b = (v / 255.0 for v in pixels[x, y])
            _, s, v = colorsys.rgb_to_hsv(r, g, b)
            if s >= SAT_THRESHOLD and 0.20 < v < 0.98:
                cx += x * s
                cy += y * s
                weight += s
    if weight == 0:
        return None
    return cx / weight / w, cy / weight / h


print("const ENERGY_SYMBOL_UV: Dictionary = {")
for card_id, rel_path in CARDS.items():
    full_path = PROJECT_ROOT / rel_path
    if not full_path.exists():
        print(f'    "{card_id}": Vector2(0.500, 0.500),  # file not found')
        continue
    result = find_symbol_center(full_path)
    if result is None:
        print(f'    "{card_id}": Vector2(0.500, 0.500),  # low saturation — using center')
    else:
        nx, ny = result
        print(f'    "{card_id}": Vector2({nx:.3f}, {ny:.3f}),')
print("}")
