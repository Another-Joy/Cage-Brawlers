## ClassDefinitions.gd
## Static utility providing class-specific data: health segment percentages
## and weapon category lists used for skill tree generation.
class_name ClassDefinitions
extends RefCounted

# ---------------------------------------------------------------------------
# Health Segment Percentages
# ---------------------------------------------------------------------------
# Three floats per class; must sum to exactly 1.0.
# Index 0 = leftmost (first segment lost), index 2 = rightmost (last segment lost).

static func get_segment_percentages(char_class: CharacterData.CharacterClass) -> Array[float]:
	match char_class:
		CharacterData.CharacterClass.WARRIOR:
			# Warriors are durable: evenly distributed health.
			return [0.35, 0.35, 0.30]
		CharacterData.CharacterClass.RANGER:
			# Rangers are mobile: slightly front-heavy distribution.
			return [0.40, 0.35, 0.25]
		CharacterData.CharacterClass.MAGE:
			# Mages are fragile: back-loaded health (last segment is smallest).
			return [0.40, 0.35, 0.25]
		CharacterData.CharacterClass.ROGUE:
			# Rogues rely on evasion: small but equal early segments.
			return [0.35, 0.35, 0.30]
		CharacterData.CharacterClass.CLERIC:
			# Clerics are support-oriented: balanced with a large final segment.
			return [0.30, 0.30, 0.40]
		_:
			return [0.34, 0.33, 0.33]

# ---------------------------------------------------------------------------
# Allowed Weapon Categories per Class (for Weapon Skill Tree generation)
# ---------------------------------------------------------------------------

static func get_weapon_categories(char_class: CharacterData.CharacterClass) -> Array[String]:
	match char_class:
		CharacterData.CharacterClass.WARRIOR:
			return ["sword", "axe", "mace"]
		CharacterData.CharacterClass.RANGER:
			return ["bow", "crossbow", "thrown"]
		CharacterData.CharacterClass.MAGE:
			return ["staff", "wand", "orb"]
		CharacterData.CharacterClass.ROGUE:
			return ["dagger", "shortsword", "thrown"]
		CharacterData.CharacterClass.CLERIC:
			return ["mace", "staff", "shield"]
		_:
			return ["sword"]

# ---------------------------------------------------------------------------
# Convenience: Initialise a Character's health segments from their class.
# ---------------------------------------------------------------------------

static func initialise_character_health(char_data: CharacterData) -> void:
	var percentages: Array[float] = get_segment_percentages(char_data.character_class)
	char_data.initialise_health_segments(percentages)
