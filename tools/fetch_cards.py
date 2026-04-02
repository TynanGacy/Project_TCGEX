#!/usr/bin/env python3
"""
fetch_cards.py — Download cards from the Pokémon TCG API (pokemontcg.io)
and write one JSON file per card into data/cards/.

Usage examples:
  # Fetch a single card by its API id
  python tools/fetch_cards.py --id base1-58

  # Fetch all cards whose name contains "Pikachu"
  python tools/fetch_cards.py --name "Pikachu"

  # Fetch every card in a set
  python tools/fetch_cards.py --set base1

  # Combine filters (AND)
  python tools/fetch_cards.py --name "Charmander" --set base1

  # Use an API key for higher rate limits (recommended for large fetches)
  python tools/fetch_cards.py --set base1 --api-key YOUR_KEY_HERE

Output goes to data/cards/<card_id>.json relative to the project root.
Run from the project root, or set --out-dir to a different path.

Requires: requests  (pip install requests)
"""

import argparse
import json
import os
import re
import sys
import time

try:
    import requests
except ImportError:
    sys.exit("Missing dependency: run  pip install requests")


API_BASE = "https://api.pokemontcg.io/v2"
DEFAULT_OUT = os.path.join(os.path.dirname(__file__), "..", "data", "cards")

# ---------------------------------------------------------------------------
# Energy type normalisation
# ---------------------------------------------------------------------------

TYPE_MAP = {
    "fire":      "FIRE",
    "water":     "WATER",
    "grass":     "GRASS",
    "lightning": "LIGHTNING",
    "psychic":   "PSYCHIC",
    "fighting":  "FIGHTING",
    "darkness":  "DARKNESS",
    "dark":      "DARKNESS",
    "metal":     "METAL",
    "steel":     "METAL",
    "dragon":    "DRAGON",
    "colorless": "COLORLESS",
    "fairy":     "COLORLESS",   # Fairy was retired; treat as Colorless
    "none":      "NONE",
}

def normalise_type(raw: str) -> str:
    return TYPE_MAP.get(raw.lower(), "COLORLESS")


# ---------------------------------------------------------------------------
# Attack cost array → per-type count fields
# ---------------------------------------------------------------------------

COST_FIELDS = {
    "FIRE":      "cost_fire",
    "WATER":     "cost_water",
    "GRASS":     "cost_grass",
    "LIGHTNING": "cost_lightning",
    "PSYCHIC":   "cost_psychic",
    "FIGHTING":  "cost_fighting",
    "DARKNESS":  "cost_darkness",
    "METAL":     "cost_metal",
    "COLORLESS": "cost_colorless",
}

def cost_array_to_fields(cost_list: list) -> dict:
    counts = {}
    for entry in cost_list:
        key = COST_FIELDS.get(normalise_type(entry), "cost_colorless")
        counts[key] = counts.get(key, 0) + 1
    return counts


# ---------------------------------------------------------------------------
# Name → card_id slug  (used for evolves_from lookup)
# ---------------------------------------------------------------------------

def slugify(name: str) -> str:
    s = name.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


# ---------------------------------------------------------------------------
# Damage string → int  ("60" → 60, "60+" → 60, "" → 0)
# ---------------------------------------------------------------------------

def parse_damage(raw: str) -> int:
    match = re.search(r"\d+", raw or "")
    return int(match.group()) if match else 0


# ---------------------------------------------------------------------------
# Transformers
# ---------------------------------------------------------------------------

def transform_pokemon(card: dict) -> dict:
    subtypes = [s.lower() for s in card.get("subtypes", [])]

    if "stage 2" in subtypes:
        stage = "STAGE2"
    elif "stage 1" in subtypes:
        stage = "STAGE1"
    else:
        stage = "BASIC"

    types = card.get("types") or []
    pokemon_type = normalise_type(types[0]) if types else "COLORLESS"

    weaknesses = card.get("weaknesses") or []
    weakness = normalise_type(weaknesses[0]["type"]) if weaknesses else "NONE"

    resistances = card.get("resistances") or []
    resistance = normalise_type(resistances[0]["type"]) if resistances else "NONE"

    evolves_from_name = card.get("evolvesFrom", "")
    evolves_from = slugify(evolves_from_name) if evolves_from_name else ""

    rules_parts = card.get("rules") or []
    rules_text = "\n".join(rules_parts)

    attacks_out = []
    for atk in card.get("attacks") or []:
        entry = {
            "name": atk.get("name", ""),
            "base_damage": parse_damage(atk.get("damage", "")),
            "text": atk.get("text", ""),
        }
        entry.update(cost_array_to_fields(atk.get("cost") or []))
        attacks_out.append(entry)

    name_slug = slugify(card["name"])
    set_id = card.get("set", {}).get("id", "unknown")

    return {
        "card_id":      f"{name_slug}_{set_id}",
        "name_slug":    name_slug,
        "display_name": card["name"],
        "card_type":    "POKEMON",
        "stage":        stage,
        "evolves_from": evolves_from,
        "pokemon_type": pokemon_type,
        "hp_max":       int(card.get("hp") or 0),
        "weakness":     weakness,
        "resistance":   resistance,
        "retreat_cost": int(card.get("convertedRetreatCost") or 0),
        "rules_text":   rules_text,
        "attacks":      attacks_out,
    }


def transform_trainer(card: dict) -> dict:
    subtypes = [s.lower() for s in card.get("subtypes", [])]

    if "supporter" in subtypes:
        trainer_kind = "SUPPORTER"
    elif "stadium" in subtypes:
        trainer_kind = "STADIUM"
    elif "pokémon tool" in subtypes or "pokemon tool" in subtypes or "tool" in subtypes:
        trainer_kind = "TOOL"
    else:
        trainer_kind = "ITEM"

    rules_parts = card.get("rules") or []
    rules_text = "\n".join(rules_parts)

    return {
        "card_id":      slugify(card["name"]),
        "display_name": card["name"],
        "card_type":    "TRAINER",
        "trainer_kind": trainer_kind,
        "rules_text":   rules_text,
    }


def transform_energy(card: dict) -> dict:
    subtypes = [s.lower() for s in card.get("subtypes", [])]
    types = card.get("types") or []

    # Basic energy: type is in the types array
    # Special energy: may have no types, fall back to COLORLESS
    if types:
        energy_type = normalise_type(types[0])
    elif "double" in " ".join(subtypes):
        energy_type = "COLORLESS"
    else:
        energy_type = "COLORLESS"

    rules_parts = card.get("rules") or []
    rules_text = "\n".join(rules_parts)

    return {
        "card_id":      slugify(card["name"]),
        "display_name": card["name"],
        "card_type":    "ENERGY",
        "energy_type":  energy_type,
        "provides":     1,
        "rules_text":   rules_text,
    }


def transform(card: dict) -> dict | None:
    supertype = card.get("supertype", "").lower()
    if supertype == "pokémon" or supertype == "pokemon":
        return transform_pokemon(card)
    elif supertype == "trainer":
        return transform_trainer(card)
    elif supertype == "energy":
        return transform_energy(card)
    else:
        print(f"  [skip] unknown supertype '{supertype}' for {card.get('name')}")
        return None


# ---------------------------------------------------------------------------
# API fetching
# ---------------------------------------------------------------------------

def build_headers(api_key: str | None) -> dict:
    if api_key:
        return {"X-Api-Key": api_key}
    return {}


def fetch_single(card_id: str, api_key: str | None) -> list:
    url = f"{API_BASE}/cards/{card_id}"
    resp = requests.get(url, headers=build_headers(api_key), timeout=10)
    resp.raise_for_status()
    return [resp.json()["data"]]


def fetch_search(query: str, api_key: str | None) -> list:
    results = []
    page = 1
    while True:
        resp = requests.get(
            f"{API_BASE}/cards",
            headers=build_headers(api_key),
            params={"q": query, "pageSize": 250, "page": page},
            timeout=10,
        )
        resp.raise_for_status()
        body = resp.json()
        results.extend(body["data"])
        if len(results) >= body["totalCount"]:
            break
        page += 1
        time.sleep(0.1)  # be polite
    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch Pokémon TCG cards into JSON files.")
    parser.add_argument("--id",      help="Fetch a single card by API id (e.g. base1-58)")
    parser.add_argument("--name",    help="Filter by card name (substring match)")
    parser.add_argument("--set",     help="Filter by set id (e.g. base1, xy1, sv1)")
    parser.add_argument("--api-key", help="pokemontcg.io API key (optional, increases rate limit)")
    parser.add_argument("--out-dir", default=DEFAULT_OUT,
                        help="Directory to write JSON files into (default: data/cards)")
    args = parser.parse_args()

    if not args.id and not args.name and not args.set:
        parser.error("Provide at least one of --id, --name, or --set")

    os.makedirs(args.out_dir, exist_ok=True)

    # --- Fetch ---
    print("Fetching from pokemontcg.io …")
    if args.id:
        cards = fetch_single(args.id, args.api_key)
    else:
        parts = []
        if args.name:
            parts.append(f'name:"{args.name}"')
        if args.set:
            parts.append(f"set.id:{args.set}")
        cards = fetch_search(" ".join(parts), args.api_key)

    print(f"  {len(cards)} card(s) returned")

    # --- Transform & write ---
    written = 0
    skipped = 0
    for raw in cards:
        result = transform(raw)
        if result is None:
            skipped += 1
            continue

        out_path = os.path.join(args.out_dir, f"{result['card_id']}.json")

        # Warn if a file already exists with a different API id (name collision)
        if os.path.exists(out_path):
            print(f"  [overwrite] {result['card_id']}.json")

        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
            f.write("\n")

        print(f"  [ok] {result['card_id']}.json")
        written += 1

    print(f"\nDone — {written} written, {skipped} skipped.")


if __name__ == "__main__":
    main()
