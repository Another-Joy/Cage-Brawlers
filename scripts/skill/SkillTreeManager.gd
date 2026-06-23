## SkillTreeManager.gd
## Builds deterministic, code-defined 3-tree loadouts for characters.
## Each character has exactly 3 trees (Class, Stat, Weapon), 9 nodes each,
## arranged in 5 tiers with the layout [2, 2, 2, 2, 1].
class_name SkillTreeManager
extends RefCounted

const TREE_CLASS: int = 0
const TREE_ATTRIBUTE: int = 1
const TREE_WEAPON: int = 2

const _ABILITY_FILES: Dictionary = {
	"achiles_bane": "res://resources/abilities/achiles_bane.tres",
	"drain_life": "res://resources/abilities/drain_life.tres",
	"hip_shot": "res://resources/abilities/hip_shot.tres",
	"peek_shot": "res://resources/abilities/peek_shot.tres",
	"reckless_assault": "res://resources/abilities/reckless_assault.tres",
	"regenerate": "res://resources/abilities/regenerate.tres",
	"riposte": "res://resources/abilities/riposte.tres",
}

static var _ability_cache: Dictionary = {}

static func ensure_character_skill_trees(char_data: CharacterData) -> void:
	if char_data == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if char_data.skill_tree_seed == 0:
		rng.randomize()
		char_data.skill_tree_seed = int(rng.randi())
	rng.seed = int(char_data.skill_tree_seed)
	if char_data.skill_tree_attribute == "":
		char_data.skill_tree_attribute = _choose_primary_stat_for_character(char_data, rng)
	if char_data.skill_tree_weapon_category < 0:
		char_data.skill_tree_weapon_category = _choose_weighted_weapon_category(
			ClassDefinitions.get_weapon_categories_for_character(char_data),
			rng)
	char_data.skill_trees = [
		_build_class_tree(char_data),
		_build_attribute_tree(char_data.skill_tree_attribute),
		_build_weapon_tree(char_data.skill_tree_weapon_category),
	]

static func get_tree_display_name(char_data: CharacterData, tree_index: int) -> String:
	match tree_index:
		TREE_CLASS:
			return "%s Tree" % _get_class_name(char_data)
		TREE_ATTRIBUTE:
			return "%s Tree" % _title_case(char_data.skill_tree_attribute)
		TREE_WEAPON:
			return "%s Tree" % _title_case(WeaponType.get_type_name(char_data.skill_tree_weapon_category))
	return "Tree"

static func get_unlock_error(char_data: CharacterData, tree_index: int, node_index: int) -> String:
	if char_data == null:
		return "Invalid character."
	ensure_character_skill_trees(char_data)
	if tree_index < 0 or tree_index >= char_data.skill_trees.size():
		return "Invalid tree."
	var tree: Array = char_data.skill_trees[tree_index]
	if node_index < 0 or node_index >= tree.size():
		return "Invalid node."
	var entry: SkillTreeEntry = tree[node_index] as SkillTreeEntry
	if entry == null:
		return "Invalid node."
	if char_data.has_unlocked_skill(entry.entry_id):
		return "Already unlocked."
	if char_data.get_skill_points_remaining() <= 0:
		return "No skill points remaining."
	if entry.required_level > char_data.level:
		return "Requires level %d." % entry.required_level
	if not char_data.can_unlock_skill_tree_tier(entry.node_tier):
		return "Spend %d total skill points to unlock tier %d." % [
			(entry.node_tier - 1) * 3,
			entry.node_tier,
		]
	for prereq_id in entry.prerequisites:
		if not char_data.has_unlocked_skill(prereq_id):
			return "Requires %s." % prereq_id
	return ""

static func unlock_entry(char_data: CharacterData, tree_index: int, node_index: int) -> String:
	var err: String = get_unlock_error(char_data, tree_index, node_index)
	if err != "":
		return err
	var entry: SkillTreeEntry = char_data.skill_trees[tree_index][node_index] as SkillTreeEntry
	char_data.unlocked_skill_ids.append(entry.entry_id)
	return ""

static func _choose_primary_stat_for_character(char_data: CharacterData, rng: RandomNumberGenerator) -> String:
	var primary_stats: Array[String] = _get_primary_stat_names(char_data)
	if primary_stats.is_empty():
		return char_data.get_highest_stat_name()
	return primary_stats[int(rng.randi() % primary_stats.size())]

static func _get_primary_stat_names(char_data: CharacterData) -> Array[String]:
	var out: Array[String] = []
	if char_data.class_data != null:
		for raw_stat in char_data.class_data.primary_stats:
			var stat_name: String = ClassData.get_stat_field_name(int(raw_stat))
			if not out.has(stat_name):
				out.append(stat_name)
	if not out.is_empty():
		return out
	match char_data.character_class:
		CharacterData.CharacterClass.FIGHTER:
			return ["strength"]
		CharacterData.CharacterClass.MARKSMAN:
			return ["intelligence"]
		CharacterData.CharacterClass.MAGE:
			return ["intelligence", "wisdom"]
		CharacterData.CharacterClass.CLERIC:
			return ["wisdom"]
		CharacterData.CharacterClass.BRAWLER:
			return ["constitution", "strength"]
		CharacterData.CharacterClass.RANGER:
			return ["dexterity", "wisdom"]
		CharacterData.CharacterClass.ROGUE:
			return ["dexterity"]
		_:
			return [char_data.get_highest_stat_name()]

static func _choose_weighted_weapon_category(categories: Array[WeaponType.Type], rng: RandomNumberGenerator) -> int:
	if categories.is_empty():
		return WeaponType.Type.SWORD
	var total_weight: int = 0
	for i in range(categories.size()):
		total_weight += 1 << (categories.size() - 1 - i)
	var roll: int = int(rng.randi() % total_weight)
	var accum: int = 0
	for i in range(categories.size()):
		accum += 1 << (categories.size() - 1 - i)
		if roll < accum:
			return int(categories[i])
	return int(categories[0])

static func _build_class_tree(char_data: CharacterData) -> Array:
	var damage_minor: SkillCondition.MinorCondition = _minor_for_damage_type(
		char_data.class_data.main_damage_type if char_data.class_data != null else WeaponData.DamageType.PHYSICAL)
	var class_id: String = _get_class_id(char_data)
	return [
		_make_skill("%s_class_training" % class_id, "Class Training", "Gain accuracy with your class's preferred style.", TREE_CLASS, 1, [_condition(SkillCondition.MajorCondition.ON_ATTACK, damage_minor)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 5)]),
		_make_skill("%s_fieldcraft" % class_id, "Fieldcraft", "Gain damage when your class's attacks connect.", TREE_CLASS, 1, [_condition(SkillCondition.MajorCondition.ON_DEAL_DAMAGE, damage_minor)], [_flat_effect(SkillEffect.EffectType.ADD_DAMAGE, 1)]),
		_make_skill("%s_battle_drill" % class_id, "Battle Drill", "Improve attack reliability in your class style.", TREE_CLASS, 2, [_condition(SkillCondition.MajorCondition.ON_ATTACK, damage_minor)], [_flat_effect(SkillEffect.EffectType.ADD_RELIABILITY, 10)]),
		_make_skill("%s_pack_discipline" % class_id, "Pack Discipline", "Carry your combat load more efficiently.", TREE_CLASS, 2, [], [_flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 1)]),
		_make_signature_ability(char_data, 3),
		_make_skill("%s_steady_guard" % class_id, "Steady Guard", "Reduce incoming damage while wearing armor suited to your class.", TREE_CLASS, 3, [_condition(SkillCondition.MajorCondition.ON_TAKE_DAMAGE, _preferred_armor_minor(char_data))], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 1)]),
		_make_skill("%s_rangecraft" % class_id, "Rangecraft", "Stretch the useful range of your attacks.", TREE_CLASS, 4, [_condition(SkillCondition.MajorCondition.ON_ATTACK, damage_minor)], [_flat_effect(SkillEffect.EffectType.ADD_RANGE, 1)]),
		_make_skill("%s_hardened_kit" % class_id, "Hardened Kit", "Further reduces the burden of your combat kit.", TREE_CLASS, 4, [], [_flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 2)]),
		_make_skill("%s_mastery" % class_id, "Class Mastery", "Capstone class bonuses.", TREE_CLASS, 5, [_condition(SkillCondition.MajorCondition.ON_ATTACK, damage_minor)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 10), _flat_effect(SkillEffect.EffectType.ADD_DAMAGE, 2)]),
	]

static func _build_attribute_tree(stat_name: String) -> Array:
	match stat_name.to_lower():
		"strength":
			return _build_strength_tree()
		"dexterity":
			return _build_dexterity_tree()
		"constitution":
			return _build_constitution_tree()
		"wisdom":
			return _build_wisdom_tree()
		_:
			return _build_intelligence_tree()

static func _build_weapon_tree(weapon_type: int) -> Array:
	var weapon_name: String = WeaponType.get_type_name(weapon_type)
	return [
		_make_skill("%s_weapon_accuracy" % weapon_name, "%s Familiarity" % _title_case(weapon_name), "Gain accuracy with this weapon type.", TREE_WEAPON, 1, [_condition(SkillCondition.MajorCondition.ON_ATTACK, SkillCondition.MinorCondition.SELF_WEAPON_TYPE_IS, weapon_name)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 5)]),
		_make_skill("%s_weapon_force" % weapon_name, "%s Force" % _title_case(weapon_name), "Gain damage with this weapon type.", TREE_WEAPON, 1, [_condition(SkillCondition.MajorCondition.ON_DEAL_DAMAGE, SkillCondition.MinorCondition.SELF_WEAPON_TYPE_IS, weapon_name)], [_flat_effect(SkillEffect.EffectType.ADD_DAMAGE, 1)]),
		_make_skill("%s_weapon_reliability" % weapon_name, "%s Rhythm" % _title_case(weapon_name), "Improve reliability with this weapon type.", TREE_WEAPON, 2, [_condition(SkillCondition.MajorCondition.ON_ATTACK, SkillCondition.MinorCondition.SELF_WEAPON_TYPE_IS, weapon_name)], [_flat_effect(SkillEffect.EffectType.ADD_RELIABILITY, 10)]),
		_make_skill("%s_weapon_range" % weapon_name, "%s Reach" % _title_case(weapon_name), "Improve the range band of this weapon type.", TREE_WEAPON, 2, [_condition(SkillCondition.MajorCondition.ON_ATTACK, SkillCondition.MinorCondition.SELF_WEAPON_TYPE_IS, weapon_name)], [_flat_effect(SkillEffect.EffectType.ADD_RANGE, _weapon_range_bonus(weapon_type))]),
		_make_weapon_signature_ability(weapon_type, 3),
		_make_skill("%s_weapon_guard" % weapon_name, "%s Guard" % _title_case(weapon_name), "Reduce damage taken while fighting in this weapon style.", TREE_WEAPON, 3, [_condition(SkillCondition.MajorCondition.ON_TAKE_DAMAGE, SkillCondition.MinorCondition.SELF_WEAPON_TYPE_IS, weapon_name)], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 1)]),
		_make_skill("%s_weapon_precision" % weapon_name, "%s Precision" % _title_case(weapon_name), "Further improve accuracy.", TREE_WEAPON, 4, [_condition(SkillCondition.MajorCondition.ON_ATTACK, SkillCondition.MinorCondition.SELF_WEAPON_TYPE_IS, weapon_name)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 5)]),
		_make_skill("%s_weapon_burden" % weapon_name, "%s Burden Relief" % _title_case(weapon_name), "Your training lowers the burden of this combat style.", TREE_WEAPON, 4, [], [_flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 1)]),
		_make_skill("%s_weapon_mastery" % weapon_name, "%s Mastery" % _title_case(weapon_name), "Capstone weapon bonuses.", TREE_WEAPON, 5, [_condition(SkillCondition.MajorCondition.ON_ATTACK, SkillCondition.MinorCondition.SELF_WEAPON_TYPE_IS, weapon_name)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 10), _flat_effect(SkillEffect.EffectType.ADD_DAMAGE, 2)]),
	]

static func _build_strength_tree() -> Array:
	return [
		_make_skill("str_power_1", "Power Build", "Increase damage on successful hits.", TREE_ATTRIBUTE, 1, [_condition(SkillCondition.MajorCondition.ON_DEAL_DAMAGE)], [_flat_effect(SkillEffect.EffectType.ADD_DAMAGE, 1)]),
		_make_skill("str_pack_1", "Pack Mule", "Carry weight more easily.", TREE_ATTRIBUTE, 1, [], [_flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 1)]),
		_make_skill("str_guard_1", "Braced Stance", "Reduce incoming damage in medium armor.", TREE_ATTRIBUTE, 2, [_condition(SkillCondition.MajorCondition.ON_TAKE_DAMAGE, SkillCondition.MinorCondition.SELF_WEARING_MEDIUM_ARMOR)], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 1)]),
		_make_skill("str_heavy_1", "Heavy Conditioning", "Further reduce carried burden.", TREE_ATTRIBUTE, 2, [], [_flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 2)]),
		_make_skill("str_power_2", "Crushing Blows", "Gain extra damage on successful hits.", TREE_ATTRIBUTE, 3, [_condition(SkillCondition.MajorCondition.ON_DEAL_DAMAGE)], [_flat_effect(SkillEffect.EffectType.ADD_DAMAGE, 1)]),
		_make_skill("str_anchor_1", "Anchor", "Take less damage in heavy gear.", TREE_ATTRIBUTE, 3, [_condition(SkillCondition.MajorCondition.ON_TAKE_DAMAGE, SkillCondition.MinorCondition.SELF_WEARING_HEAVY_ARMOR)], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 1)]),
		_make_skill("str_power_3", "Overpower", "Improve accuracy under pressure.", TREE_ATTRIBUTE, 4, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 5)]),
		_make_skill("str_surge", "Momentum Surge", "Stride farther under load.", TREE_ATTRIBUTE, 4, [], [_flat_effect(SkillEffect.EffectType.MODIFY_MOVEMENT, 1)]),
		_make_skill("str_mastery", "Titan Frame", "Capstone strength bonuses.", TREE_ATTRIBUTE, 5, [], [_flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 3), _flat_effect(SkillEffect.EffectType.ADD_DAMAGE, 2)]),
	]

static func _build_dexterity_tree() -> Array:
	return [
		_make_skill("dex_accuracy_1", "Quick Hands", "Improve attack accuracy.", TREE_ATTRIBUTE, 1, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 5)]),
		_make_skill("dex_evasion_1", "Footwork", "Improve evasion.", TREE_ATTRIBUTE, 1, [], [_flat_effect(SkillEffect.EffectType.ADD_EVASION, 5)]),
		_make_skill("dex_reliability_1", "Steady Grip", "Improve reliability.", TREE_ATTRIBUTE, 2, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_RELIABILITY, 10)]),
		_make_skill("dex_range_1", "Line Step", "Gain a little range on attacks.", TREE_ATTRIBUTE, 2, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_RANGE, 1)]),
		_make_skill("dex_evasion_2", "Slip Away", "Further improve evasion.", TREE_ATTRIBUTE, 3, [], [_flat_effect(SkillEffect.EffectType.ADD_EVASION, 5)]),
		_make_skill("dex_move_1", "Burst", "Gain movement.", TREE_ATTRIBUTE, 3, [], [_flat_effect(SkillEffect.EffectType.MODIFY_MOVEMENT, 1)]),
		_make_skill("dex_accuracy_2", "True Aim", "Further improve accuracy.", TREE_ATTRIBUTE, 4, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 5)]),
		_make_skill("dex_burden_1", "Light Load", "Reduce practical burden.", TREE_ATTRIBUTE, 4, [], [_flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 1)]),
		_make_skill("dex_mastery", "Windstep", "Capstone dexterity bonuses.", TREE_ATTRIBUTE, 5, [], [_flat_effect(SkillEffect.EffectType.ADD_EVASION, 10), _flat_effect(SkillEffect.EffectType.MODIFY_MOVEMENT, 1)]),
	]

static func _build_constitution_tree() -> Array:
	return [
		_make_skill("con_guard_1", "Hardy", "Reduce incoming damage.", TREE_ATTRIBUTE, 1, [_condition(SkillCondition.MajorCondition.ON_TAKE_DAMAGE)], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 1)]),
		_make_skill("con_load_1", "Shoulder the Weight", "Carry more efficiently.", TREE_ATTRIBUTE, 1, [], [_flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 1)]),
		_make_skill("con_guard_2", "Iron Flesh", "Further reduce incoming damage.", TREE_ATTRIBUTE, 2, [_condition(SkillCondition.MajorCondition.ON_TAKE_DAMAGE)], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 1)]),
		_make_skill("con_move_1", "Marching Pace", "Encumbrance hurts less.", TREE_ATTRIBUTE, 2, [], [_flat_effect(SkillEffect.EffectType.MODIFY_MOVEMENT, 1)]),
		_make_skill("con_rel_1", "Calm Pulse", "Improve attack reliability.", TREE_ATTRIBUTE, 3, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_RELIABILITY, 10)]),
		_make_skill("con_armor_1", "Armor Habit", "Gain extra protection in heavy armor.", TREE_ATTRIBUTE, 3, [_condition(SkillCondition.MajorCondition.ON_TAKE_DAMAGE, SkillCondition.MinorCondition.SELF_WEARING_HEAVY_ARMOR)], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 1)]),
		_make_skill("con_guard_3", "Stonewall", "Further improve toughness.", TREE_ATTRIBUTE, 4, [_condition(SkillCondition.MajorCondition.ON_TAKE_DAMAGE)], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 1)]),
		_make_skill("con_load_2", "Bearer's Back", "Further reduce burden.", TREE_ATTRIBUTE, 4, [], [_flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 2)]),
		_make_skill("con_mastery", "Unbroken", "Capstone constitution bonuses.", TREE_ATTRIBUTE, 5, [], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 2), _flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 2)]),
	]

static func _build_wisdom_tree() -> Array:
	return [
		_make_skill("wis_accuracy_1", "Guided Aim", "Improve attack accuracy.", TREE_ATTRIBUTE, 1, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 5)]),
		_make_skill("wis_reliability_1", "Measured Strike", "Improve reliability.", TREE_ATTRIBUTE, 1, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_RELIABILITY, 10)]),
		_make_skill("wis_range_1", "Far Sight", "Increase range.", TREE_ATTRIBUTE, 2, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_RANGE, 1)]),
		_make_skill("wis_evasion_1", "Awareness", "Improve evasion.", TREE_ATTRIBUTE, 2, [], [_flat_effect(SkillEffect.EffectType.ADD_EVASION, 5)]),
		_make_skill("wis_damage_1", "Read the Opening", "Gain damage on successful hits.", TREE_ATTRIBUTE, 3, [_condition(SkillCondition.MajorCondition.ON_DEAL_DAMAGE)], [_flat_effect(SkillEffect.EffectType.ADD_DAMAGE, 1)]),
		_make_skill("wis_guard_1", "Patient Guard", "Reduce damage taken.", TREE_ATTRIBUTE, 3, [_condition(SkillCondition.MajorCondition.ON_TAKE_DAMAGE)], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 1)]),
		_make_skill("wis_accuracy_2", "Perfect Read", "Further improve accuracy.", TREE_ATTRIBUTE, 4, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 5)]),
		_make_skill("wis_move_1", "Deliberate Advance", "Gain movement efficiency.", TREE_ATTRIBUTE, 4, [], [_flat_effect(SkillEffect.EffectType.MODIFY_MOVEMENT, 1)]),
		_make_skill("wis_mastery", "Inner Compass", "Capstone wisdom bonuses.", TREE_ATTRIBUTE, 5, [], [_flat_effect(SkillEffect.EffectType.ADD_RELIABILITY, 20), _flat_effect(SkillEffect.EffectType.ADD_RANGE, 1)]),
	]

static func _build_intelligence_tree() -> Array:
	return [
		_make_skill("int_accuracy_1", "Ballistics", "Improve attack accuracy.", TREE_ATTRIBUTE, 1, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 5)]),
		_make_skill("int_range_1", "Trajectory", "Increase attack range.", TREE_ATTRIBUTE, 1, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_RANGE, 1)]),
		_make_skill("int_reliability_1", "Calibrated Motion", "Improve reliability.", TREE_ATTRIBUTE, 2, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_RELIABILITY, 10)]),
		_make_skill("int_weight_1", "Efficient Packing", "Reduce equipment burden.", TREE_ATTRIBUTE, 2, [], [_flat_effect(SkillEffect.EffectType.REDUCE_WEIGHT, 1)]),
		_make_skill("int_damage_1", "Exploit Weakness", "Gain damage when attacks land.", TREE_ATTRIBUTE, 3, [_condition(SkillCondition.MajorCondition.ON_DEAL_DAMAGE)], [_flat_effect(SkillEffect.EffectType.ADD_DAMAGE, 1)]),
		_make_skill("int_guard_1", "Countermeasures", "Reduce incoming damage.", TREE_ATTRIBUTE, 3, [_condition(SkillCondition.MajorCondition.ON_TAKE_DAMAGE)], [_flat_effect(SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, 1)]),
		_make_skill("int_accuracy_2", "Precision Tables", "Further improve accuracy.", TREE_ATTRIBUTE, 4, [_condition(SkillCondition.MajorCondition.ON_ATTACK)], [_flat_effect(SkillEffect.EffectType.ADD_ATTACK_ACCURACY, 5)]),
		_make_skill("int_move_1", "Pathing", "Gain movement efficiency.", TREE_ATTRIBUTE, 4, [], [_flat_effect(SkillEffect.EffectType.MODIFY_MOVEMENT, 1)]),
		_make_skill("int_mastery", "Grand Calculation", "Capstone intelligence bonuses.", TREE_ATTRIBUTE, 5, [], [_flat_effect(SkillEffect.EffectType.ADD_RANGE, 1), _flat_effect(SkillEffect.EffectType.ADD_RELIABILITY, 20)]),
	]

static func _make_signature_ability(char_data: CharacterData, tier: int) -> SkillTreeEntry:
	var ability_id: String = "riposte"
	match char_data.character_class:
		CharacterData.CharacterClass.FIGHTER:
			ability_id = "riposte"
		CharacterData.CharacterClass.MARKSMAN:
			ability_id = "hip_shot"
		CharacterData.CharacterClass.MAGE:
			ability_id = "drain_life"
		CharacterData.CharacterClass.CLERIC:
			ability_id = "regenerate"
		CharacterData.CharacterClass.BRAWLER:
			ability_id = "reckless_assault"
		CharacterData.CharacterClass.RANGER:
			ability_id = "peek_shot"
		CharacterData.CharacterClass.ROGUE:
			ability_id = "achiles_bane"
		_:
			ability_id = "riposte"
	return _make_ability_node("%s_class_signature" % _get_class_id(char_data), ability_id, TREE_CLASS, tier)

static func _make_weapon_signature_ability(weapon_type: int, tier: int) -> SkillTreeEntry:
	var weapon_name: String = WeaponType.get_type_name(weapon_type)
	var ability_id: String = "riposte"
	match weapon_type:
		WeaponType.Type.BOW:
			ability_id = "peek_shot"
		WeaponType.Type.CROSSBOW, WeaponType.Type.RIFLE:
			ability_id = "hip_shot"
		WeaponType.Type.TOME, WeaponType.Type.BALL:
			ability_id = "drain_life"
		WeaponType.Type.DAGGER:
			ability_id = "achiles_bane"
		WeaponType.Type.AXE:
			ability_id = "reckless_assault"
		WeaponType.Type.SWORD:
			ability_id = "riposte"
	return _make_ability_node("%s_weapon_signature" % weapon_name, ability_id, TREE_WEAPON, tier)

static func _make_ability_node(node_id: String, ability_id: String, tree_type: int, tier: int) -> SkillTreeEntry:
	var base: AbilityData = _load_ability(ability_id)
	if base == null:
		return _make_skill(node_id, _title_case(node_id), "Missing ability data.", tree_type, tier, [], [])
	var ab: AbilityData = base.duplicate(true) as AbilityData
	ab.entry_id = node_id
	ab.node_tier = tier
	ab.tree_type = tree_type
	return ab

static func _load_ability(ability_id: String) -> AbilityData:
	if _ability_cache.has(ability_id):
		return _ability_cache[ability_id] as AbilityData
	var path: String = _ABILITY_FILES.get(ability_id, "")
	if path == "":
		return null
	var res: Resource = load(path)
	if res is AbilityData:
		_ability_cache[ability_id] = res
		return res as AbilityData
	return null

static func _make_skill(node_id: String, name: String, description: String, tree_type: int, tier: int, triggers: Array, effects: Array) -> SkillData:
	var skill: SkillData = SkillData.new()
	skill.entry_id = node_id
	skill.entry_name = name
	skill.description = description
	skill.tree_type = tree_type
	skill.node_tier = tier
	skill.required_level = 1
	skill.triggers = triggers
	skill.effects = effects
	return skill

static func _flat_effect(effect_type: SkillEffect.EffectType, value: int) -> SkillEffect:
	var effect: SkillEffect = SkillEffect.new()
	effect.effect_type = effect_type
	effect.target = SkillEffect.EffectTarget.SELF
	effect.value_type = SkillEffect.ValueType.FLAT
	effect.flat_value = value
	return effect

static func _condition(major: SkillCondition.MajorCondition, minor: SkillCondition.MinorCondition = SkillCondition.MinorCondition.NONE, string_param: String = "") -> SkillCondition:
	var cond: SkillCondition = SkillCondition.new()
	cond.major = major
	cond.minor = minor
	cond.string_param = string_param
	return cond

static func _minor_for_damage_type(damage_type: WeaponData.DamageType) -> SkillCondition.MinorCondition:
	match damage_type:
		WeaponData.DamageType.RANGED:
			return SkillCondition.MinorCondition.ATTACKER_USING_RANGED
		WeaponData.DamageType.MAGICAL:
			return SkillCondition.MinorCondition.ATTACKER_USING_MAGICAL
		_:
			return SkillCondition.MinorCondition.ATTACKER_USING_PHYSICAL

static func _preferred_armor_minor(char_data: CharacterData) -> SkillCondition.MinorCondition:
	match char_data.character_class:
		CharacterData.CharacterClass.FIGHTER, CharacterData.CharacterClass.BRAWLER:
			return SkillCondition.MinorCondition.SELF_WEARING_HEAVY_ARMOR
		CharacterData.CharacterClass.RANGER, CharacterData.CharacterClass.ROGUE, CharacterData.CharacterClass.MAGE:
			return SkillCondition.MinorCondition.SELF_WEARING_LIGHT_ARMOR
		_:
			return SkillCondition.MinorCondition.SELF_WEARING_MEDIUM_ARMOR

static func _weapon_range_bonus(weapon_type: int) -> int:
	match weapon_type:
		WeaponType.Type.BOW, WeaponType.Type.CROSSBOW, WeaponType.Type.RIFLE, WeaponType.Type.TOME, WeaponType.Type.BALL:
			return 1
		_:
			return 0

static func _get_class_id(char_data: CharacterData) -> String:
	if char_data.class_data != null and char_data.class_data.class_id != "":
		return char_data.class_data.class_id
	return _get_class_name(char_data).to_lower().replace(" ", "_")

static func _get_class_name(char_data: CharacterData) -> String:
	if char_data.class_data != null and char_data.class_data.display_name != "":
		return char_data.class_data.display_name
	match char_data.character_class:
		CharacterData.CharacterClass.FIGHTER:
			return "Fighter"
		CharacterData.CharacterClass.MARKSMAN:
			return "Marksman"
		CharacterData.CharacterClass.MAGE:
			return "Mage"
		CharacterData.CharacterClass.CLERIC:
			return "Cleric"
		CharacterData.CharacterClass.BRAWLER:
			return "Brawler"
		CharacterData.CharacterClass.RANGER:
			return "Ranger"
		CharacterData.CharacterClass.ROGUE:
			return "Rogue"
		_:
			return "Warrior"

static func _title_case(value: String) -> String:
	if value == "":
		return "Unknown"
	var words: PackedStringArray = value.replace("_", " ").split(" ", false)
	var out: Array[String] = []
	for word in words:
		if word == "":
			continue
		out.append(word.substr(0, 1).to_upper() + word.substr(1).to_lower())
	return " ".join(out)
