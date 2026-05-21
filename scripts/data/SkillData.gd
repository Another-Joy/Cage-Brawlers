## SkillData.gd
## Resource representing a single learnable skill node within a skill tree.
class_name SkillData
extends Resource

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum SkillPhase {
	BEGINNING,   # Used during Beginning Action Phase
	MAIN,        # Used during Main Action Phase
	ENDING,      # Used during Ending Action Phase
	PASSIVE,     # Always active; no phase slot required
}

enum SkillTreeType {
	CLASS,
	ATTRIBUTE,
	WEAPON,
}

# ---------------------------------------------------------------------------
# Skill Properties
# ---------------------------------------------------------------------------

@export var skill_id: String = ""
@export var skill_name: String = ""
@export_multiline var description: String = ""

## Minimum character level required to learn this skill.
@export var required_level: int = 1

## Which action phase this skill is slotted into.
@export var skill_phase: SkillPhase = SkillPhase.MAIN

## Whether this is a passive ability (always active).
@export var is_passive: bool = false

## Which tree type this skill belongs to.
@export var tree_type: SkillTreeType = SkillTreeType.CLASS

## IDs of skills that must be learned before this one.
@export var prerequisites: Array[String] = []

## Keywords associated with this skill (e.g. "Direct" for magical line-of-sight spells).
@export var keywords: Array[String] = []

# ---------------------------------------------------------------------------
# Effect Parameters (generic; specific logic lives in CombatManager)
# ---------------------------------------------------------------------------

## Dice count for skill damage/healing rolls (0 = no roll).
@export var effect_dice_count: int = 0
## Dice sides for skill effect rolls.
@export var effect_dice_sides: int = 0
## Additional flat bonus added to the roll result.
@export var effect_flat_bonus: int = 0
## Range override in tiles (0 = use weapon range).
@export var range_override: int = 0
## Whether this skill uses the Reliability modifier.
@export var uses_reliability: bool = false

# ---------------------------------------------------------------------------
# Keyword Helper
# ---------------------------------------------------------------------------

func has_keyword(keyword: String) -> bool:
	var kw_lower: String = keyword.to_lower()
	for k in keywords:
		if k.to_lower() == kw_lower:
			return true
	return false
