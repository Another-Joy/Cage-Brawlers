## SkillTreeManager.gd
## Handles procedural, seeded generation of skill trees for a character.
## Each character receives three trees: Class, Attribute, and Weapon.
## Skills within each tree are randomly shuffled while respecting level
## requirement groupings so high-tier skills never appear early.
class_name SkillTreeManager
extends RefCounted

# ---------------------------------------------------------------------------
# Tree index constants matching CharacterData.skill_trees layout
# ---------------------------------------------------------------------------

const TREE_CLASS: int = 0
const TREE_ATTRIBUTE: int = 1
const TREE_WEAPON: int = 2

# ---------------------------------------------------------------------------
# Skill Pool Registries
# Registry maps: key -> Array[SkillData] (populated via register_* calls)
# ---------------------------------------------------------------------------

## Maps CharacterClass enum value -> Array[SkillData]
var _class_skill_pools: Dictionary = {}
## Maps stat name string -> Array[SkillData]
var _attribute_skill_pools: Dictionary = {}
## Maps weapon category string -> Array[SkillData]
var _weapon_skill_pools: Dictionary = {}
## Maps CharacterClass enum value -> Array[String] (allowed weapon categories)
var _class_weapon_categories: Dictionary = {}

# ---------------------------------------------------------------------------
# Registration API (call during game initialisation to populate pools)
# ---------------------------------------------------------------------------

func register_class_skills(char_class: CharacterData.CharacterClass, skills: Array[SkillData]) -> void:
	_class_skill_pools[char_class] = skills

func register_attribute_skills(stat_name: String, skills: Array[SkillData]) -> void:
	_attribute_skill_pools[stat_name] = skills

func register_weapon_skills(weapon_category: String, skills: Array[SkillData]) -> void:
	_weapon_skill_pools[weapon_category] = skills

func register_class_weapon_categories(char_class: CharacterData.CharacterClass, categories: Array[String]) -> void:
	_class_weapon_categories[char_class] = categories

# ---------------------------------------------------------------------------
# Tree Generation
# ---------------------------------------------------------------------------

## Generates all three skill trees for a character and writes them into
## char_data.skill_trees. Uses the character's class and highest stat.
## seed_value controls reproducibility; pass 0 for a random seed.
func generate_skill_trees(char_data: CharacterData, seed_value: int = 0) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	# --- Class Tree ---
	var class_pool: Array[SkillData] = _class_skill_pools.get(char_data.character_class, [])
	char_data.skill_trees[TREE_CLASS] = _build_tree(class_pool, rng)

	# --- Attribute Tree ---
	var highest_stat: String = char_data.get_highest_stat_name()
	var attr_pool: Array[SkillData] = _attribute_skill_pools.get(highest_stat, [])
	char_data.skill_trees[TREE_ATTRIBUTE] = _build_tree(attr_pool, rng)

	# --- Weapon Tree ---
	var weapon_categories: Array[String] = _class_weapon_categories.get(char_data.character_class, [])
	var weapon_pool: Array[SkillData] = _pick_random_weapon_pool(weapon_categories, rng)
	char_data.skill_trees[TREE_WEAPON] = _build_tree(weapon_pool, rng)

# ---------------------------------------------------------------------------
# Internal Helpers
# ---------------------------------------------------------------------------

## Builds a shuffled skill tree from a pool while maintaining level-tier ordering.
## Skills are grouped by required_level tiers, each tier is internally shuffled,
## then tiers are concatenated in ascending level order.
func _build_tree(pool: Array[SkillData], rng: RandomNumberGenerator) -> Array:
	if pool.is_empty():
		return []

	# Group skills by required_level.
	var tiers: Dictionary = {}
	for skill in pool:
		var tier_key: int = skill.required_level
		if not tiers.has(tier_key):
			tiers[tier_key] = []
		tiers[tier_key].append(skill)

	# Sort tier keys ascending.
	var sorted_tiers: Array = tiers.keys()
	sorted_tiers.sort()

	# Shuffle within each tier, then flatten.
	var result: Array = []
	for tier_key in sorted_tiers:
		var tier_skills: Array = tiers[tier_key].duplicate()
		_shuffle_array(tier_skills, rng)
		result.append_array(tier_skills)

	return result

## Picks a random weapon skill pool from the categories allowed for a class.
func _pick_random_weapon_pool(categories: Array[String], rng: RandomNumberGenerator) -> Array[SkillData]:
	if categories.is_empty():
		return []
	var chosen_category: String = categories[rng.randi() % categories.size()]
	return _weapon_skill_pools.get(chosen_category, [])

## Fisher-Yates shuffle using the provided RNG.
func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
