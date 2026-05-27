## ClassDefinitions.gd
## Static utility providing class-specific data: health segment percentages
## and weapon category lists used for skill tree generation.
## When a character has a class_data resource set, those values take precedence
## over the hardcoded fallbacks defined here.
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
		CharacterData.CharacterClass.FIGHTER:
			# Fighters are heavily armored front-liners: balanced distribution.
			return [0.50, 0.25, 0.25]
		CharacterData.CharacterClass.MARKSMAN:
			# Marksmanship-focused class: moderate health, spread evenly.
			return [0.34, 0.33, 0.33]
		CharacterData.CharacterClass.BRAWLER:
			# Brawlers are aggressive melee fighters: front-heavy pool.
			return [0.50, 0.30, 0.20]
		_:
			return [0.34, 0.33, 0.33]

# ---------------------------------------------------------------------------
# Allowed Weapon Categories per Class (for Weapon Skill Tree generation)
# ---------------------------------------------------------------------------

static func get_weapon_categories(char_class: CharacterData.CharacterClass) -> Array[WeaponType.Type]:
	match char_class:
		CharacterData.CharacterClass.WARRIOR:
			return [WeaponType.Type.SWORD, WeaponType.Type.AXE]
		CharacterData.CharacterClass.RANGER:
			return [WeaponType.Type.BOW, WeaponType.Type.CROSSBOW]
		CharacterData.CharacterClass.MAGE:
			return [WeaponType.Type.TOME, WeaponType.Type.BALL]
		CharacterData.CharacterClass.ROGUE:
			return [WeaponType.Type.DAGGER]
		CharacterData.CharacterClass.CLERIC:
			return [WeaponType.Type.TOME]
		CharacterData.CharacterClass.FIGHTER:
			return [WeaponType.Type.SWORD, WeaponType.Type.AXE]
		CharacterData.CharacterClass.MARKSMAN:
			return [WeaponType.Type.RIFLE, WeaponType.Type.CROSSBOW]
		CharacterData.CharacterClass.BRAWLER:
			return [WeaponType.Type.AXE, WeaponType.Type.SWORD]
		_:
			return [WeaponType.Type.SWORD]

# ---------------------------------------------------------------------------
# Convenience: Initialise a Character's health segments from their class.
# Prefers class_data resource when available; falls back to enum-based lookup.
# ---------------------------------------------------------------------------

static func initialise_character_health(char_data: CharacterData) -> void:
	var percentages: Array[float]
	if char_data.class_data != null and not char_data.class_data.health_segment_percentages.is_empty():
		percentages = char_data.class_data.health_segment_percentages
	else:
		percentages = get_segment_percentages(char_data.character_class)
	char_data.initialise_health_segments(percentages)

# ---------------------------------------------------------------------------
# Convenience: Get weapon categories, preferring class_data when available.
# ---------------------------------------------------------------------------

static func get_weapon_categories_for_character(char_data: CharacterData) -> Array[WeaponType.Type]:
	if char_data.class_data != null and not char_data.class_data.weapon_categories.is_empty():
		return char_data.class_data.weapon_categories
	return get_weapon_categories(char_data.character_class)
