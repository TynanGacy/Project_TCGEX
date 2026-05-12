#!/usr/bin/env python3
"""
restore_card_fields.py — one-off recovery script.

Commit 06beb76 ("feat: deck-builder rarity + multi-typed energy filtering")
regenerated every card JSON via fetch_cards.py, which mirrors the
pokemontcg.io API faithfully and therefore stripped our hand-authored
game-logic fields (effect_key, effect_params — both at the top level for
trainers and nested inside attacks[] for Pokemon).

This script walks data/cards/**/*.json, pulls each file's pre-06beb76 copy
from git, and merges back the missing hand-authored fields. Current file
wins on every field that exists in both — we only fill what the regen
deleted. Run once from the repo root:

    python tools/restore_card_fields.py

Pass --dry-run to print a summary without writing.
"""

import argparse
import json
import os
import subprocess
import sys

PRE_COMMIT = "06beb76^"
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CARDS_DIR = os.path.join(REPO_ROOT, "data", "cards")

HAND_AUTHORED_TOP_LEVEL = ("effect_key", "effect_params")
# Fields the author writes onto a Pokemon attack. effect_chain composes extra
# handlers alongside the primary effect; base_damage is normally API-derived
# but is intentionally overridden (typically to 0) when damage is scaled by a
# handler — see commit 33d523e Tier 3 attacks. We treat base_damage as an
# override only when the old attack also had an effect_key, signalling intent.
HAND_AUTHORED_ATTACK_FILL     = ("effect_key", "effect_params", "effect_chain")
HAND_AUTHORED_ATTACK_OVERRIDE = ("base_damage",)


def git_show(rel_path: str) -> dict | None:
    """Return the JSON contents of rel_path at PRE_COMMIT, or None if missing."""
    rel_posix = rel_path.replace(os.sep, "/")
    try:
        out = subprocess.check_output(
            ["git", "show", f"{PRE_COMMIT}:{rel_posix}"],
            cwd=REPO_ROOT,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return None
    try:
        return json.loads(out.decode("utf-8"))
    except json.JSONDecodeError:
        return None


def merge_attacks(old_attacks: list, new_attacks: list) -> int:
    """Copy missing effect_key / effect_params onto new_attacks by name. Returns count restored."""
    if not isinstance(old_attacks, list) or not isinstance(new_attacks, list):
        return 0
    by_name = {a.get("name"): a for a in old_attacks if isinstance(a, dict)}
    restored = 0
    for attack in new_attacks:
        if not isinstance(attack, dict):
            continue
        old = by_name.get(attack.get("name"))
        if old is None:
            continue
        for key in HAND_AUTHORED_ATTACK_FILL:
            if key not in attack and key in old:
                attack[key] = old[key]
                restored += 1
        # Override fields apply only when the author also wired an effect_key
        # in the old version — that signals the value was a deliberate gameplay
        # override paired with the handler, not just stale API data.
        if "effect_key" in old:
            for key in HAND_AUTHORED_ATTACK_OVERRIDE:
                if key in old and attack.get(key) != old[key]:
                    attack[key] = old[key]
                    restored += 1
    return restored


def merge_card(old: dict, new: dict) -> tuple[int, int]:
    """Merge old hand-authored fields into new. Returns (top_level_restored, attack_fields_restored)."""
    top = 0
    for key in HAND_AUTHORED_TOP_LEVEL:
        if key not in new and key in old:
            new[key] = old[key]
            top += 1
    attack_fields = merge_attacks(old.get("attacks", []), new.get("attacks", []))
    return top, attack_fields


def iter_card_files() -> list[str]:
    paths = []
    for root, _dirs, files in os.walk(CARDS_DIR):
        for name in files:
            if name.endswith(".json"):
                paths.append(os.path.join(root, name))
    return sorted(paths)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Report changes without writing.")
    args = parser.parse_args()

    total_files = 0
    files_changed = 0
    top_restored = 0
    attack_restored = 0
    missing_old = 0

    for path in iter_card_files():
        total_files += 1
        rel = os.path.relpath(path, REPO_ROOT)

        with open(path, "r", encoding="utf-8") as f:
            new = json.load(f)

        old = git_show(rel)
        if old is None:
            missing_old += 1
            continue

        top, attacks = merge_card(old, new)
        if top == 0 and attacks == 0:
            continue

        top_restored += top
        attack_restored += attacks
        files_changed += 1

        if not args.dry_run:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(new, f, indent=2, ensure_ascii=False)
                f.write("\n")

        print(f"  [restored] {rel}  (top={top}, attacks={attacks})")

    print()
    print(f"Scanned:               {total_files}")
    print(f"No pre-{PRE_COMMIT} version: {missing_old}")
    print(f"Files updated:         {files_changed}")
    print(f"Top-level fields:      {top_restored}")
    print(f"Attack-level fields:   {attack_restored}")
    if args.dry_run:
        print("(dry-run — no files written)")


if __name__ == "__main__":
    main()
