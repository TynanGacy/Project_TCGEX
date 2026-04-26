"""
Energy sphere UV profiles for attachment display.

Edit PROFILES and CARD_PROFILES below, then run:
    python3 tools/energy_sphere_profiles.py

Output is ready-to-paste GDScript for attachment_display.gd.

Profile fields
--------------
center : (x, y)  Normalised UV coordinates of the sphere centre on the card art.
                 (0, 0) = top-left corner of the card image,
                 (1, 1) = bottom-right corner.
radius : float   Fraction of card width that the sphere's radius occupies.
                 The disc will show a square crop of side (2 * radius) centred
                 on 'center', so a smaller radius zooms in further.
"""

# ── Profiles ──────────────────────────────────────────────────────────────────
# Add new profiles here as new card sets introduce different art layouts.

PROFILES: dict[str, dict] = {
    # Basic energies (Grass/Fire/Water/Lightning/Psychic/Fighting — RS set)
    # The large sphere sits in the lower portion of the art, below the
    # triangular glow burst.  All six cards share the same template.
    "basic": {
        "center": (0.500, 0.640),
        "radius": 0.250,
    },

    # Special energies with a rules-text box (Darkness/Metal — RS set)
    # Smaller, darker sphere centred in the compressed art area.
    "special_dark": {
        "center": (0.500, 0.380),
        "radius": 0.185,
    },

    # Special energies with a rules-text box (Rainbow/Multi — RS/SS sets)
    # Slightly smaller colourful sphere at a similar vertical position.
    "special_colorful": {
        "center": (0.500, 0.370),
        "radius": 0.175,
    },
}

# ── Card → profile mapping ────────────────────────────────────────────────────
# Link each card_id to one of the profiles defined above.

CARD_PROFILES: dict[str, str] = {
    "RS_104_grass_energy":     "basic",
    "RS_105_fighting_energy":  "basic",
    "RS_106_water_energy":     "basic",
    "RS_107_psychic_energy":   "basic",
    "RS_108_fire_energy":      "basic",
    "RS_109_lightning_energy": "basic",
    "RS_93_darkness_energy":   "special_dark",
    "RS_94_metal_energy":      "special_dark",
    "RS_95_rainbow_energy":    "special_colorful",
    "SS_93_multi_energy":      "special_colorful",
}


# ── Output ────────────────────────────────────────────────────────────────────

def _vec2(x: float, y: float) -> str:
    return f"Vector2({x:.3f}, {y:.3f})"


print("## Paste into attachment_display.gd\n")

print("const ENERGY_SPHERE_PROFILES: Dictionary = {")
for name, p in PROFILES.items():
    cx, cy = p["center"]
    r      = p["radius"]
    print(f'    "{name}": {{"center": {_vec2(cx, cy)}, "radius": {r:.3f}}},')
print("}\n")

print("const ENERGY_CARD_PROFILE: Dictionary = {")
for card_id, profile in CARD_PROFILES.items():
    print(f'    "{card_id}": "{profile}",')
print("}")
