## SkillTreeEntry.gd
## Base resource shared by SkillData (passive) and AbilityData (active).
## Holds the identity, level requirement, and keyword fields that both types
## need so that SkillTreeManager can treat them uniformly.
class_name SkillTreeEntry
extends Resource

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum TreeType {
	CLASS,      ## Belongs to the class-specific tree.
	ATTRIBUTE,  ## Belongs to the highest-stat attribute tree.
	WEAPON,     ## Belongs to the randomly-selected weapon tree.
}

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

## Unique identifier used in code (snake_case, e.g. "power_strike").
@export var entry_id: String = ""
## Display name shown in skill tree UI.
@export var entry_name: String = ""
## Flavour / rules text shown to the player.
@export_multiline var description: String = ""

# ---------------------------------------------------------------------------
# Tree Placement
# ---------------------------------------------------------------------------

## Minimum character level required to learn this entry.
@export var required_level: int = 1
## Which of the three skill trees this entry belongs to.
@export var tree_type: TreeType = TreeType.CLASS
## IDs of entries that must be learned before this one can be unlocked.
@export var prerequisites: Array[String] = []

# ---------------------------------------------------------------------------
# Keywords
# ---------------------------------------------------------------------------

## Gameplay keywords (e.g. "Direct", "Vault", "Two-Handed").
## Checked by combat systems and pathfinding to apply special rules.
@export var keywords: Array[String] = []

## Returns true if this entry has the given keyword (case-insensitive).
func has_keyword(keyword: String) -> bool:
	var kw_lower: String = keyword.to_lower()
	for k in keywords:
		if k.to_lower() == kw_lower:
			return true
	return false
