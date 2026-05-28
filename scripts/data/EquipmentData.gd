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

## Parameters for keywords that carry values.
## Key   = keyword name (must match an entry in 'keywords').
## Value = Dictionary of parameter name → value for that keyword.
##
## Examples:
##   {"Versatile": {"count": 1, "sides": 10}}
##   {"Magazine":  {"capacity": 5}}
##   {"Versatile": {"count": 2, "sides": 8}, "Magazine": {"capacity": 3}}
@export var keyword_params: Dictionary = {}

## Passive skills and active abilities granted to the character while this
## item is equipped. Use SkillData resources for always-on passive effects
## (e.g. "while wearing this armor, ranged attacks gain +30% reliability")
## and AbilityData resources for active abilities the player can trigger.
@export var granted_skills: Array[SkillTreeEntry] = []

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

## Returns the value of a named parameter for a parametric keyword.
## If the keyword is absent or the parameter is not set, returns default_value.
## Example: get_keyword_param("Magazine", "capacity", 0)  →  5 (or 0 if absent)
func get_keyword_param(keyword: String, param: String, default_value: Variant = null) -> Variant:
	if not keyword_params.has(keyword):
		return default_value
	var kw_dict: Dictionary = keyword_params[keyword]
	if not kw_dict.has(param):
		return default_value
	return kw_dict[param]
