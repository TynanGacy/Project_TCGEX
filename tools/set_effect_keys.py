"""Batch-sets effect_key on specific attacks across all card JSON files."""

import json
import os

BASE = r"C:\Users\tgsha\OneDrive\Desktop\Important Docs\Github\Project_TCGEX\data\cards"

# (relative_path, attack_name, effect_key)
# Skipped (need extra infrastructure):
#   Double-poison attacks (RS_6 Dustox Toxic, SS_29 Arbok Toxic) — need damage-counter multiplier
#   Optional-discard-then-status (SS_10, SS_11 Seviper, SS_51 Quilava, DR_12 Torkoal,
#     DR_57 Grimer, DR_12 Torkoal) — need "you may discard" UI prompt
#   Conditional-on-energy (RS_11 Sceptile Lizard Poison, DR_6 Grumpig Mind Trip) — need energy count check
#   Complex combos (RS_24 Poison Smog bench damage, RS_62 Trembler, DR_72 Slugma,
#     SS_3 Cradily, SS_11 Extra Poison ex-check) — need Group N/J infrastructure
#   Retreat lock (SS_99 Ring of Fire) — needs Group F flag
#   Self-heal + asleep (RS_48 Wailmer Rest) — needs Group G
#   Multi-coin + paralyzed if any heads (SS_68 Marill Double Bubble)
UPDATES = [
    # ── Group A — inflict_asleep ─────────────────────────────────────────────
    ("DR/DR_2_altaria.json",     "Dragon Song",        "inflict_asleep"),
    ("DR/DR_43_shuppet.json",    "Hypnosis",           "inflict_asleep"),
    ("DR/DR_44_snorunt.json",    "Powder Snow",        "inflict_asleep"),
    ("DR/DR_50_bagon.json",      "Dragon Eye",         "inflict_asleep"),
    ("DR/DR_75_swablu.json",     "Lullaby",            "inflict_asleep"),
    ("DR/DR_9_roselia.json",     "Sleep Powder",       "inflict_asleep"),
    ("RS/RS_13_swampert.json",   "Hypno Splash",       "inflict_asleep"),
    ("RS/RS_44_skitty.json",     "Lullaby",            "inflict_asleep"),
    ("RS/RS_67_ralts.json",      "Hypnoblast",         "inflict_asleep"),
    ("RS/RS_69_shroomish.json",  "Sleep Powder",       "inflict_asleep"),
    ("SS/SS_69_natu.json",       "Soothing Wave",      "inflict_asleep"),
    ("SS/SS_74_ralts.json",      "Hypnosis",           "inflict_asleep"),
    ("SS/SS_83_wailmer.json",    "Super Hypno Wave",   "inflict_asleep"),

    # ── Group A — inflict_poisoned ───────────────────────────────────────────
    ("DR/DR_54_corphish.json",   "Toxic Grip",         "inflict_poisoned"),
    ("DR/DR_96_muk_ex.json",     "Poison Breath",      "inflict_poisoned"),
    ("RS/RS_26_cascoon.json",    "Poison Thread",      "inflict_poisoned"),
    ("RS/RS_31_grovyle.json",    "Poison Breath",      "inflict_poisoned"),
    ("RS/RS_78_wurmple.json",    "Poison Barb",        "inflict_poisoned"),
    ("SS/SS_33_breloom.json",    "Super Poison Breath","inflict_poisoned"),
    ("SS/SS_78_shroomish.json",  "Poisonpowder",       "inflict_poisoned"),

    # ── Group A — inflict_confused ───────────────────────────────────────────
    ("RS/RS_24_weezing.json",    "Confusion Gas",      "inflict_confused"),
    ("RS/RS_99_lapras_ex.json",  "Confuse Ray",        "inflict_confused"),
    ("SS/SS_94_aerodactyl_ex.json", "Supersonic",      "inflict_confused"),

    # ── Group A — inflict_burned ─────────────────────────────────────────────
    ("RS/RS_100_magmar_ex.json", "Super Singe",        "inflict_burned"),

    # ── Group B — coin_paralyzed ─────────────────────────────────────────────
    ("DR/DR_23_bagon.json",      "Paralyzing Gaze",    "coin_paralyzed"),
    ("DR/DR_52_corphish.json",   "Bubble",             "coin_paralyzed"),
    ("DR/DR_58_horsea.json",     "Paralyzing Gaze",    "coin_paralyzed"),
    ("DR/DR_63_magnemite.json",  "Thundershock",       "coin_paralyzed"),
    ("DR/DR_64_mareep.json",     "Jolt",               "coin_paralyzed"),
    ("DR/DR_75_swablu.json",     "Stifling Fluff",     "coin_paralyzed"),
    ("DR/DR_79_trapinch.json",   "Bind",               "coin_paralyzed"),
    ("DR/DR_81_wurmple.json",    "String Shot",        "coin_paralyzed"),
    ("RS/RS_2_beautifly.json",   "Stun Spore",         "coin_paralyzed"),
    ("RS/RS_33_hariyama.json",   "Shove",              "coin_paralyzed"),
    ("RS/RS_39_manectric.json",  "Thundershock",       "coin_paralyzed"),
    ("RS/RS_40_marshtomp.json",  "Bubble",             "coin_paralyzed"),
    ("RS/RS_53_electrike.json",  "Super Thunder Wave", "coin_paralyzed"),
    ("RS/RS_58_makuhita.json",   "Fake Out",           "coin_paralyzed"),
    ("RS/RS_59_mudkip.json",     "Bubble",             "coin_paralyzed"),
    ("RS/RS_97_electabuzz_ex.json", "Thundershock",    "coin_paralyzed"),
    ("SS/SS_40_kirlia.json",     "Psyshock",           "coin_paralyzed"),
    ("SS/SS_49_nuzleaf.json",    "Stun Spore",         "coin_paralyzed"),
    ("SS/SS_60_dunsparce.json",  "Sudden Flash",       "coin_paralyzed"),
    ("SS/SS_64_ekans.json",      "Bind",               "coin_paralyzed"),
    ("SS/SS_70_omanyte.json",    "Bind",               "coin_paralyzed"),
    ("SS/SS_71_onix.json",       "Bind",               "coin_paralyzed"),

    # ── Group B — coin_confused ──────────────────────────────────────────────
    ("DR/DR_14_dragonair.json",  "Dazzle Blast",       "coin_confused"),
    ("DR/DR_38_ninjask.json",    "Supersonic",         "coin_confused"),
    ("DR/DR_74_spoink.json",     "Psybeam",            "coin_confused"),
    ("RS/RS_35_kirlia.json",     "Dazzle Dance",       "coin_confused"),
    ("RS/RS_66_ralts.json",      "Confuse Ray",        "coin_confused"),
    ("SS/SS_16_espeon.json",     "Confuse Ray",        "coin_confused"),
    ("SS/SS_24_umbreon.json",    "Confuse Ray",        "coin_confused"),
    ("SS/SS_61_duskull.json",    "Confuse Ray",        "coin_confused"),
    ("SS/SS_84_wingull.json",    "Supersonic",         "coin_confused"),
    ("SS/SS_98_raichu_ex.json",  "Dazzle Blast",       "coin_confused"),

    # ── Group B — coin_poisoned ──────────────────────────────────────────────
    ("DR/DR_13_crawdaunt.json",  "Poison Claws",       "coin_poisoned"),
    ("DR/DR_52_corphish.json",   "Poison Claws",       "coin_poisoned"),
    ("DR/DR_66_nincada.json",    "Poison Breath",      "coin_poisoned"),
    ("RS/RS_75_treecko.json",    "Poison Breath",      "coin_poisoned"),
    ("SS/SS_58_cacnea.json",     "Poison Sting",       "coin_poisoned"),
    ("SS/SS_75_sandshrew.json",  "Poison Needle",      "coin_poisoned"),

    # ── Group B — coin_burned ────────────────────────────────────────────────
    ("DR/DR_24_camerupt.json",   "Super Singe",        "coin_burned"),
    ("RS/RS_61_numel.json",      "Burn Off",           "coin_burned"),
    ("RS/RS_74_torchic.json",    "Singe",              "coin_burned"),
    ("SS/SS_5_flareon.json",     "Super Singe",        "coin_burned"),
    ("SS/SS_59_cyndaquil.json",  "Singe",              "coin_burned"),

    # ── Group B — coin_asleep ────────────────────────────────────────────────
    ("DR/DR_93_latias_ex.json",  "Hypnoblast",         "coin_asleep"),

    # ── Group B — special two-outcome variants ───────────────────────────────
    ("SS/SS_38_illumise.json",   "Chaotic Noise",      "coin_confused_or_asleep"),
    ("SS/SS_53_volbeat.json",    "Toxic Vibration",    "coin_poisoned_or_asleep"),
    ("DR/DR_89_ampharos_ex.json","Gigavolt",           "coin_plus_30_or_paralyzed"),
]


def apply_updates(updates):
    ok = skipped = 0
    for rel_path, attack_name, effect_key in updates:
        full = os.path.join(BASE, rel_path.replace("/", os.sep))
        if not os.path.exists(full):
            print(f"MISSING  {rel_path}")
            skipped += 1
            continue
        with open(full, encoding="utf-8") as fh:
            data = json.load(fh)
        found = False
        for atk in data.get("attacks", []):
            if atk.get("name") == attack_name:
                atk["effect_key"] = effect_key
                found = True
                break
        if not found:
            print(f"NO MATCH {rel_path} — '{attack_name}'")
            skipped += 1
            continue
        with open(full, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        print(f"OK  {os.path.basename(rel_path):35s}  {attack_name:25s} -> {effect_key}")
        ok += 1
    print(f"\n{ok} updated, {skipped} skipped")


if __name__ == "__main__":
    apply_updates(UPDATES)
