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

## The stats that most strongly define this class's offensive output.
## More than one can be listed; the first is the dominant primary stat.
@export var primary_stats: Array[StatType] = []

## The stats that provide secondary scaling (accuracy, defences, utility).
## More than one can be listed.
@export var secondary_stats: Array[StatType] = []

# ---------------------------------------------------------------------------
# Hit Dice & HP Growth
# ---------------------------------------------------------------------------

## Dice rolled per level-up to determine HP gained.
## E.g. a Fighter rolls 3d6; a Mage rolls 1d8.
## Set the DiceValue.reliability field for classes whose hit dice always use
## reliability (e.g. Fighter +20%, Brawler +50%).
@export var hit_dice: DiceValue = null

## Flat HP added on top of the hit-dice roll each level-up.
## Allows fine-tuning HP growth independent of dice variance.
@export var level_health_modifier: int = 0

# ---------------------------------------------------------------------------
# Damage Identity
# ---------------------------------------------------------------------------

## The primary damage type this class outputs.
## Used to determine which stat bonuses apply by default and for skill-tree
## filtering (e.g. a Fighter's class tree focuses on Physical abilities).
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

## List of weapon types this class can use for its weapon skill tree.
## Values should be WeaponType constants (e.g. [WeaponType.SWORD, WeaponType.AXE]).
@export var weapon_categories: Array[WeaponType.Type] = []

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns the dominant primary stat (first entry), or STRENGTH if none set.
func get_primary_stat() -> StatType:
	return primary_stats[0] if primary_stats.size() > 0 else StatType.STRENGTH

## Returns the dominant secondary stat (first entry), or DEXTERITY if none set.
func get_secondary_stat() -> StatType:
	return secondary_stats[0] if secondary_stats.size() > 0 else StatType.DEXTERITY

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
