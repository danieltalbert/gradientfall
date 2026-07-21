#!/usr/bin/env python3
"""Gradientfall content validator.

Validates all content JSON against the schemas in content/schemas/ and checks
cross-references (item/npc/quest IDs must resolve) and ID uniqueness.

Usage:
    python tools/validate_content.py            # validate content/approved/
    python tools/validate_content.py --inbox    # validate content/inbox/ (against approved + inbox)
    python tools/validate_content.py --all      # validate both

Exit code 0 = everything valid. No third-party dependencies.

Supported JSON Schema subset: type, required, properties, additionalProperties
(boolean), items, enum, pattern, minimum, maximum, minLength, maxLength,
minItems, maxItems. Keep schemas within this subset.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content"
SCHEMAS = CONTENT / "schemas"

# content subdirectory -> schema file stem
DIR_TO_SCHEMA = {
    "quests": "quest",
    "npcs": "npc",
    "items": "item",
    "monsters": "mon",
    "quizzes": "quiz",
    "lore": "lore",
    "pois": "poi",
}

ID_PREFIX_TO_DIR = {
    "q_": "quests",
    "npc_": "npcs",
    "item_": "items",
    "mon_": "monsters",
    "quiz_": "quizzes",
    "lore_": "lore",
    "poi_": "pois",
}


def type_ok(value, expected: str) -> bool:
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    return False


def validate_node(value, schema: dict, path: str, errors: list[str]) -> None:
    expected_type = schema.get("type")
    if expected_type and not type_ok(value, expected_type):
        errors.append(f"{path}: expected {expected_type}, got {type(value).__name__}")
        return

    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} not in allowed values {schema['enum']}")

    if isinstance(value, str):
        if "pattern" in schema and not re.fullmatch(schema["pattern"].strip("^$"), value):
            errors.append(f"{path}: {value!r} does not match pattern {schema['pattern']}")
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(f"{path}: string shorter than minLength {schema['minLength']}")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(f"{path}: string longer than maxLength {schema['maxLength']}")

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: {value} below minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: {value} above maximum {schema['maximum']}")

    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(f"{path}: fewer than minItems {schema['minItems']}")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{path}: more than maxItems {schema['maxItems']}")
        if "items" in schema:
            for i, element in enumerate(value):
                validate_node(element, schema["items"], f"{path}[{i}]", errors)

    if isinstance(value, dict):
        props = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: missing required field '{key}'")
        if schema.get("additionalProperties") is False:
            for key in value:
                if key not in props:
                    errors.append(f"{path}: unknown field '{key}'")
        for key, subschema in props.items():
            if key in value:
                validate_node(value[key], subschema, f"{path}.{key}", errors)


def load_entries(file: Path, errors: list[str]) -> list[dict]:
    try:
        data = json.loads(file.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as exc:
        errors.append(f"invalid JSON: {exc}")
        return []
    entries = data if isinstance(data, list) else [data]
    bad = [e for e in entries if not isinstance(e, dict)]
    if bad:
        errors.append("file must contain an object or an array of objects")
        return []
    return entries


def collect_refs(entry: dict) -> list[tuple[str, str]]:
    """All (ref_id, where) pairs inside an entry that must resolve."""
    refs: list[tuple[str, str]] = []
    for item_id in entry.get("rewards", {}).get("items", []):
        refs.append((item_id, "rewards.items"))
    for q_id in entry.get("prerequisites", {}).get("quests", []):
        refs.append((q_id, "prerequisites.quests"))
    if "giver_npc" in entry:
        refs.append((entry["giver_npc"], "giver_npc"))
    for item_id in entry.get("vendor_stock", []):
        refs.append((item_id, "vendor_stock"))
    for ingredient in entry.get("recipe", []):
        refs.append((ingredient.get("item_id", "?"), "recipe"))
    for drop in entry.get("drops", []):
        refs.append((drop.get("item_id", "?"), "drops"))
    for item_id in entry.get("reward_items", []):
        refs.append((item_id, "reward_items"))
    return refs


def main() -> int:
    args = set(sys.argv[1:])
    check_dirs = []
    if "--all" in args or not (args & {"--inbox", "--all"}):
        check_dirs.append(CONTENT / "approved")
    if "--inbox" in args or "--all" in args:
        check_dirs.append(CONTENT / "inbox")

    schemas: dict[str, dict] = {}
    for stem in set(DIR_TO_SCHEMA.values()):
        schema_file = SCHEMAS / f"{stem}.schema.json"
        if not schema_file.exists():
            print(f"FATAL: missing schema {schema_file}")
            return 2
        schemas[stem] = json.loads(schema_file.read_text(encoding="utf-8-sig"))

    # The reference universe is always approved + whatever is being checked,
    # so an inbox batch may reference approved content and its own entries.
    universe_dirs = {CONTENT / "approved", *check_dirs}

    all_ids: dict[str, str] = {}  # id -> file it came from
    total_errors = 0
    file_count = 0
    entry_count = 0
    pending_refs: list[tuple[str, str, str]] = []  # (ref_id, where, file)
    dup_errors: list[str] = []

    # First pass: build the ID universe (approved always included).
    for base in sorted(universe_dirs):
        for subdir in DIR_TO_SCHEMA:
            for file in sorted((base / subdir).glob("*.json")):
                for entry in load_entries(file, []):
                    entry_id = entry.get("id")
                    if isinstance(entry_id, str):
                        if entry_id in all_ids and all_ids[entry_id] != str(file):
                            dup_errors.append(
                                f"{file.relative_to(ROOT)}: duplicate id '{entry_id}' "
                                f"(also in {all_ids[entry_id]})"
                            )
                        all_ids.setdefault(entry_id, str(file))

    # Second pass: schema-validate the requested dirs and collect refs.
    for base in check_dirs:
        for subdir, schema_stem in DIR_TO_SCHEMA.items():
            for file in sorted((base / subdir).glob("*.json")):
                file_count += 1
                errors: list[str] = []
                entries = load_entries(file, errors)
                for i, entry in enumerate(entries):
                    entry_count += 1
                    label = entry.get("id", f"entry[{i}]")
                    validate_node(entry, schemas[schema_stem], str(label), errors)
                    if entry.get("id"):
                        # id prefix must match its directory
                        prefix = next((p for p in ID_PREFIX_TO_DIR if str(entry["id"]).startswith(p)), None)
                        if prefix and ID_PREFIX_TO_DIR[prefix] != subdir:
                            errors.append(f"{label}: id prefix '{prefix}' does not belong in {subdir}/")
                    for ref_id, where in collect_refs(entry):
                        pending_refs.append((ref_id, f"{label}.{where}", str(file.relative_to(ROOT))))
                if errors:
                    total_errors += len(errors)
                    print(f"\nFAIL {file.relative_to(ROOT)}")
                    for err in errors:
                        print(f"  - {err}")

    for err in dup_errors:
        total_errors += 1
        print(f"\nFAIL {err}")

    for ref_id, where, file in pending_refs:
        if ref_id not in all_ids:
            total_errors += 1
            print(f"\nFAIL {file}\n  - {where}: reference '{ref_id}' does not exist")

    print(
        f"\n{'PASS' if total_errors == 0 else 'FAIL'}: "
        f"{entry_count} entries in {file_count} files, {total_errors} error(s)."
    )
    return 0 if total_errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
