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

NOTE TO ME: retrieve via !python tools/fetch_cards.py --set ex1 --api-key fb809308-4a56-4099-a205-cba887d7edce
"""

import argparse
import json
import os
import re
import sys
import time


try:
    import requests
    from requests.adapters import HTTPAdapter
    from urllib3.util.retry import Retry

except ImportError:
    sys.exit("Missing dependency: run  pip install requests")


API_BASE = "https://api.pokemontcg.io/v2"
DEFAULT_OUT = os.path.join(os.path.dirname(__file__), "..", "data", "cards")
DEFAULT_IMG = os.path.join(os.path.dirname(__file__), "..", "assets", "images")

SET_ABBREVIATIONS = {
    # EX Era
    "ex1":  "RS",   # Ruby & Sapphire
    "ex2":  "SS",   # Sandstorm
    "ex3":  "DR",   # Dragon
    "ex4":  "MA",   # Team Magma vs Team Aqua
    "ex5":  "HL",   # Hidden Legends
    "ex6":  "FL",   # FireRed & LeafGreen
    "ex7":  "RR",   # Team Rocket Returns
    "ex8":  "DE",   # Deoxys
    "ex9":  "EM",   # Emerald
    "ex10": "UF",   # Unseen Forces
    "ex11": "DS",   # Delta Species
    "ex12": "LM",   # Legend Maker
    "ex13": "HP",   # Holon Phantoms
    "ex14": "CG",   # Crystal Guardians
    "ex15": "DF",   # Dragon Frontiers
    "ex16": "PK",   # Power Keepers
}

def set_abbrev(card: dict) -> str:
    set_id = card.get("set", {}).get("id", "unknown")
    return SET_ABBREVIATIONS.get(set_id, slugify(set_id))

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

def make_session(api_key: str | None) -> requests.Session:
    session = requests.Session()
    retry = Retry(
        total=3,                          # retry up to 3 times
        backoff_factor=1,                 # wait 1s, 2s, 4s between retries
        status_forcelist=[500, 502, 503, 504],  # retry on these HTTP errors
        allowed_methods=["GET"],
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    if api_key:
        session.headers.update({"X-Api-Key": api_key})
    return session

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
            "name":        atk.get("name", ""),
            "base_damage": parse_damage(atk.get("damage", "")),
            "text":        atk.get("text", ""),
        }
        entry.update(cost_array_to_fields(atk.get("cost") or []))
        attacks_out.append(entry)

    name_slug  = slugify(card["name"])
    abbrev      = set_abbrev(card)
    card_number = card.get("number", "0")
    
    return {
        "card_id": f"{abbrev}_{card_number}_{name_slug}",
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
    rules_text  = "\n".join(rules_parts)

    name_slug   = slugify(card["name"])
    abbrev      = set_abbrev(card)
    card_number = card.get("number", "0")

    return {
        "card_id": f"{abbrev}_{card_number}_{name_slug}",
        "display_name": card["name"],
        "card_type":    "TRAINER",
        "trainer_kind": trainer_kind,
        "rules_text":   rules_text,
    }


def transform_energy(card: dict) -> dict:
    subtypes = [s.lower() for s in card.get("subtypes", [])]
    types    = card.get("types") or []

    if types:
        energy_type = normalise_type(types[0])
    elif "double" in " ".join(subtypes):
        energy_type = "COLORLESS"
    else:
        energy_type = "COLORLESS"

    rules_parts = card.get("rules") or []
    rules_text  = "\n".join(rules_parts)

    name_slug   = slugify(card["name"])
    abbrev      = set_abbrev(card)
    card_number = card.get("number", "0")

    return {
        "card_id": f"{abbrev}_{card_number}_{name_slug}",
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

def download_image(url: str, out_path: str, session: requests.Session) -> bool:
    try:
        resp = session.get(url, timeout=30)
        resp.raise_for_status()
        with open(out_path, "wb") as f:
            f.write(resp.content)
        return True
    except Exception as e:
        print(f"  [warn] image download failed: {e}")
        return False
    
def fetch_single(card_id: str, session: requests.Session) -> list:
    url  = f"{API_BASE}/cards/{card_id}"
    resp = session.get(url, timeout=(10, 60))
    resp.raise_for_status()
    return [resp.json()["data"]]


def fetch_search(query: str, session: requests.Session) -> list:
    results = []
    page    = 1
    while True:
        try:
            resp = session.get(
                f"{API_BASE}/cards",
                params={"q": query, "pageSize": 250, "page": page},
                timeout=(10, 60),
            )
            resp.raise_for_status()
        except requests.exceptions.ReadTimeout:
            print(f"  [warn] Timeout on page {page}, retrying after 5s …")
            time.sleep(5)
            continue
        except requests.exceptions.HTTPError as e:
            sys.exit(f"  [error] HTTP error on page {page}: {e}")

        body = resp.json()
        results.extend(body["data"])
        print(f"  [page {page}] fetched {len(results)}/{body['totalCount']}")
        if len(results) >= body["totalCount"]:
            break
        page += 1
        time.sleep(0.2)
    return results

def process_cards(cards: list, set_id: str, out_dir: str, img_dir: str, session: requests.Session) -> tuple[int, int]:
    set_folder = SET_ABBREVIATIONS.get(set_id, slugify(set_id))  # fall back to slugified set id if not in table
    set_out = os.path.join(out_dir, set_folder)
    set_img = os.path.join(img_dir, set_folder)
    os.makedirs(set_out, exist_ok=True)
    os.makedirs(set_img, exist_ok=True)

    written = 0
    skipped = 0

    for raw in cards:
        result = transform(raw)
        if result is None:
            skipped += 1
            continue

        # Write JSON
        out_path = os.path.join(set_out, f"{result['card_id']}.json")
        if os.path.exists(out_path):
            print(f"  [overwrite] {set_folder}/{result['card_id']}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
            f.write("\n")

        # Download image
        img_url = raw.get("images", {}).get("large", "")
        if img_url:
            img_path = os.path.join(set_img, f"{result['card_id']}.png")
            img_ok   = download_image(img_url, img_path, session)
            print(f"  [ok] {set_folder}/{result['card_id']}.json" + (" + image" if img_ok else " (image failed)"))
        else:
            print(f"  [ok] {set_folder}/{result['card_id']}.json (no image url)")

        written += 1

    return written, skipped

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
    parser.add_argument("--img-dir", default=DEFAULT_IMG,
                        help="Directory to write images into (default: assets/images)")
    args = parser.parse_args()

    if not args.id and not args.name and not args.set:
        parser.error("Provide at least one of --id, --name, or --set")

    os.makedirs(args.out_dir, exist_ok=True)
    os.makedirs(args.img_dir, exist_ok=True)

    session = make_session(args.api_key)

    # --- Fetch ---
    print("Fetching from pokemontcg.io …")
    if args.id:
        cards  = fetch_single(args.id, session)
        set_id = cards[0].get("set", {}).get("id", "unknown") if cards else "unknown"
    else:
        parts = []
        if args.name:
            parts.append(f'name:"{args.name}"')
        if args.set:
            parts.append(f"set.id:{args.set}")
        cards  = fetch_search(" ".join(parts), session)
        set_id = args.set if args.set else (cards[0].get("set", {}).get("id", "unknown") if cards else "unknown")

    print(f"  {len(cards)} card(s) returned")
    written, skipped = process_cards(cards, set_id, args.out_dir, args.img_dir, session)

    print(f"\nDone — {written} written, {skipped} skipped.")


if __name__ == "__main__":
    main()
