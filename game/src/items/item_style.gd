class_name ItemStyle
extends RefCounted
## Shared presentation rules for authored items, so the pack screen, the HUD
## toasts, and the world pickups never disagree about what a "rare" thing looks
## like or what a category is called.
##
## Everything here reads a ContentDB item entry (see content/schemas/item.schema.json)
## and nothing here knows a single item id — categories and rarities are schema
## enums, which is the only item vocabulary the runtime is allowed to hardcode
## (docs/ARCHITECTURE.md: the runtime never hardcodes authored content).

const RARITY_COLOR: Dictionary = {
	"common": Color(0.84, 0.87, 0.80),
	"uncommon": Color(0.42, 0.78, 0.98),
	"rare": Color(0.99, 0.76, 0.30),
	"epic": Color(0.76, 0.52, 1.0),
	"golden": Color(1.0, 0.91, 0.45),
}

## Sort weight and forage frequency both key off this order.
const RARITY_RANK: Dictionary = {
	"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "golden": 4,
}

const CATEGORY_LABEL: Dictionary = {
	"weapon": "Weapon", "armor": "Armor", "material": "Material",
	"consumable": "Consumable", "key_item": "Key Item", "tool": "Tool",
	"furniture": "Furniture", "curio": "Curio", "flora": "Flora", "fish": "Fish",
}

## Display order for the pack's category tabs (schema categories only).
const CATEGORY_ORDER: Array[String] = [
	"consumable", "flora", "material", "tool", "curio", "fish",
	"weapon", "armor", "furniture", "key_item",
]

const FALLBACK_COLOR: Color = Color(0.84, 0.87, 0.80)


static func rarity_color(entry: Dictionary) -> Color:
	var c: Color = RARITY_COLOR.get(str(entry.get("rarity", "common")), FALLBACK_COLOR)
	return c


static func rarity_rank(entry: Dictionary) -> int:
	return int(RARITY_RANK.get(str(entry.get("rarity", "common")), 0))


static func rarity_label(entry: Dictionary) -> String:
	return str(entry.get("rarity", "common")).capitalize()


static func category_label(entry: Dictionary) -> String:
	return str(CATEGORY_LABEL.get(str(entry.get("category", "")), "Oddment"))


static func category_of(entry: Dictionary) -> String:
	return str(entry.get("category", ""))


## Falls back to the id so a stale save never shows a blank row.
static func display_name(item_id: String, entry: Dictionary) -> String:
	var n: String = str(entry.get("name", ""))
	return n if not n.is_empty() else item_id


## Hearts a consumable restores, or 0.0 when it restores nothing.
static func heal_amount(entry: Dictionary) -> float:
	var stats: Dictionary = entry.get("stats", {})
	return float(stats.get("hearts_restored", 0.0))


## Only healing consumables can be used from the pack today. Tools, curios, and
## materials are inert until the crafting and vendor milestones give them jobs.
static func is_usable(entry: Dictionary) -> bool:
	return str(entry.get("category", "")) == "consumable" and heal_amount(entry) > 0.0


## Sort key for a pack listing: category order, then rarity, then name.
static func sort_entries(a: Dictionary, b: Dictionary) -> bool:
	var ca: int = _category_index(a)
	var cb: int = _category_index(b)
	if ca != cb:
		return ca < cb
	var ra: int = rarity_rank(a)
	var rb: int = rarity_rank(b)
	if ra != rb:
		return ra > rb
	return str(a.get("name", "")) < str(b.get("name", ""))


## Unknown categories sort last rather than first (find() returns -1).
static func _category_index(entry: Dictionary) -> int:
	var i: int = CATEGORY_ORDER.find(category_of(entry))
	return i if i >= 0 else CATEGORY_ORDER.size()
