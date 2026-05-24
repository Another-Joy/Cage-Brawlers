## ClassData.gd
## Resource defining all class-specific constants for a character archetype.
## Each class is stored as a .tres file under resources/classes/.
##
## Properties cover:
##   - Which stats are primary and secondary (scale class damage/abilities).
##   - The hit dice rolled each level-up to determine HP gain.
##   - A flat level_health_modifier added on top of the hit-dice roll.
##   - The main damage type this class deals (Physical, Ranged, or Magical).
##   - The 3-element health-segment percentage split (must sum to 1.0).
##   - The weapon categories available for this class's weapon skill tree.
class_name ClassData
extends Resource

# ---------------------------------------------------------------------------
# Stat Type Enum
# ---------------------------------------------------------------------------

## The five primary stats a character can have.
## Mirrors the five @export vars in CharacterData for clarity in class design.
enum StatType {
	STRENGTH,
	DEXTERITY,
	CONSTITUTION,
	WISDOM,
	INTELLIGENCE,
}

# ---------------------------------------------------------------------------
# Exported Identity
# ---------------------------------------------------------------------------

## Unique snake_case identifier (e.g. "warrior", "mage").
@export var class_id: String = ""
## Human-readable display name (e.g. "Warrior", "Mage").
@export var display_name: String = ""

# ---------------------------------------------------------------------------
# Stat Affinity
# ---------------------------------------------------------------------------

## The stat that most strongly defines this class's offensive output.
@export var primary_stat: StatType = StatType.STRENGTH
## The stat that provides secondary scaling (accuracy, defences, utility).
@export var secondary_stat: StatType = StatType.DEXTERITY

# ---------------------------------------------------------------------------
# Hit Dice & HP Growth
# ---------------------------------------------------------------------------

## Dice rolled per level-up to determine HP gained.
## E.g. a Warrior might roll 1d10; a Mage 1d6.
@export var hit_dice: DiceValue = null

## Flat HP added on top of the hit-dice roll each level-up.
## Allows fine-tuning HP growth independent of dice variance.
@export var level_health_modifier: int = 0

# ---------------------------------------------------------------------------
# Damage Identity
# ---------------------------------------------------------------------------

## The primary damage type this class outputs.
## Used to determine which stat bonuses apply by default and for skill-tree
## filtering (e.g. a Warrior's class tree focuses on Physical abilities).
@export var main_damage_type: WeaponData.DamageType = WeaponData.DamageType.PHYSICAL

# ---------------------------------------------------------------------------
# Health Segment Percentages
# ---------------------------------------------------------------------------

## Three-element array describing the proportional size of each health segment.
## Index 0 = leftmost (first segment lost); index 2 = rightmost (last lost).
## Values must sum to 1.0.
@export var health_segment_percentages: Array[float] = [0.34, 0.33, 0.33]

# ---------------------------------------------------------------------------
# Weapon Categories (for Weapon Skill Tree generation)
# ---------------------------------------------------------------------------

## List of weapon category strings this class can use for its weapon skill tree.
## E.g. ["sword", "axe", "mace"] for Warriors.
@export var weapon_categories: Array[String] = []

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns the character stat value from char_data for a given StatType.
## Useful for class-aware damage/accuracy calculations.
static func get_stat_value(char_data: CharacterData, stat: StatType) -> int:
	match stat:
		StatType.STRENGTH:     return char_data.strength
		StatType.DEXTERITY:    return char_data.dexterity
		StatType.CONSTITUTION: return char_data.constitution
		StatType.WISDOM:       return char_data.wisdom
		StatType.INTELLIGENCE: return char_data.intelligence
	return 0

## Returns the name string for a StatType (matches CharacterData field names).
static func get_stat_field_name(stat: StatType) -> String:
	match stat:
		StatType.STRENGTH:     return "strength"
		StatType.DEXTERITY:    return "dexterity"
		StatType.CONSTITUTION: return "constitution"
		StatType.WISDOM:       return "wisdom"
		StatType.INTELLIGENCE: return "intelligence"
	return "strength"
