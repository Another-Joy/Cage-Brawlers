## EquipmentData.gd
## Base resource for all equippable items. Every specific equipment type
## (weapon, shield, buff, armor, support) extends this class.
class_name EquipmentData
extends Resource

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum EquipmentType {
	WEAPON,
	SHIELD,
	BUFF,
	ARMOR,
	SUPPORT,
}

# ---------------------------------------------------------------------------
# Base Properties
# ---------------------------------------------------------------------------

@export var item_id: String = ""
@export var item_name: String = ""
@export var description: String = ""
@export var equipment_type: EquipmentType = EquipmentType.WEAPON

## Weight in kilograms.
@export var weight: float = 1.0

## Keywords applied to this item (e.g. "Light", "Two-Handed", "Direct").
@export var keywords: Array[String] = []

# ---------------------------------------------------------------------------
# Keyword Helpers
# ---------------------------------------------------------------------------

## Returns true if this item has the specified keyword (case-insensitive).
func has_keyword(keyword: String) -> bool:
	var kw_lower: String = keyword.to_lower()
	for k in keywords:
		if k.to_lower() == kw_lower:
			return true
	return false
