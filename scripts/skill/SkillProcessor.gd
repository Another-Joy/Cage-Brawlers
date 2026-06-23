## SkillProcessor.gd
## Evaluates passive SkillData entries against a combat context and returns
## the aggregate bonuses they grant.
##
## Call the static helper methods at the relevant points in the combat loop:
##
##   var extra_dmg := SkillProcessor.get_damage_bonus(attacker, target, weapon)
##   var extra_acc := SkillProcessor.get_accuracy_bonus(attacker, target, weapon)
##   var extra_eva := SkillProcessor.get_evasion_bonus(defender, attacker, weapon)
##
## The processor reads all SkillData entries from the character's three skill
## trees, evaluates their SkillCondition triggers against the context, and sums
## the relevant SkillEffect values.
class_name SkillProcessor
extends RefCounted

# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------

## Snapshot of the relevant combat state passed to trigger checks.
## Construct one before calling evaluation methods.
class SkillContext:
	## The character whose skills are being evaluated.
	var owner: CharacterData = null
	## Who is making or receiving the attack (may equal owner).
	var attacker: CharacterData = null
	## Who the attack is aimed at.
	var target: CharacterData = null
	## Weapon used in the attack (may be null for non-attack triggers).
	var weapon: WeaponData = null
	## Which major event is currently happening.
	var major_event: SkillCondition.MajorCondition = SkillCondition.MajorCondition.ALWAYS

	func _init(
			p_owner: CharacterData,
			p_major: SkillCondition.MajorCondition,
			p_attacker: CharacterData = null,
			p_target: CharacterData = null,
			p_weapon: WeaponData = null) -> void:
		owner    = p_owner
		major_event = p_major
		attacker = p_attacker
		target   = p_target
		weapon   = p_weapon

# ---------------------------------------------------------------------------
# Public Evaluation API
# ---------------------------------------------------------------------------

## Returns the total extra damage bonus from passive skills for the given context.
## Only counts FLAT and STAT_MODIFIER effects; DICE effects are handled separately
## via collect_bonus_damage_dice so they can be rolled as part of the attack bundle.
static func get_damage_bonus(ctx: SkillContext, dice_roller: DiceRoller = null) -> int:
	return _sum_non_dice_effects(ctx, SkillEffect.EffectType.ADD_DAMAGE, dice_roller)

## Returns the total extra accuracy bonus from passive skills.
static func get_accuracy_bonus(ctx: SkillContext, dice_roller: DiceRoller = null) -> int:
	return _sum_effects(ctx, SkillEffect.EffectType.ADD_ATTACK_ACCURACY, dice_roller)

## Returns the total accuracy penalty imposed on attackers targeting this character.
static func get_accuracy_reduction(ctx: SkillContext, dice_roller: DiceRoller = null) -> int:
	return _sum_effects(ctx, SkillEffect.EffectType.REDUCE_ACCURACY, dice_roller)

## Returns the total extra evasion bonus from passive skills.
static func get_evasion_bonus(ctx: SkillContext, dice_roller: DiceRoller = null) -> int:
	return _sum_effects(ctx, SkillEffect.EffectType.ADD_EVASION, dice_roller)

## Returns the total incoming damage reduction from passive skills.
static func get_damage_reduction(ctx: SkillContext, dice_roller: DiceRoller = null) -> int:
	return _sum_effects(ctx, SkillEffect.EffectType.REDUCE_INCOMING_DAMAGE, dice_roller)

## Returns the total movement modifier from passive skills.
static func get_movement_modifier(ctx: SkillContext, dice_roller: DiceRoller = null) -> int:
	return _sum_effects(ctx, SkillEffect.EffectType.MODIFY_MOVEMENT, dice_roller)

## Returns the total reliability bonus from passive skills (percentage points).
## Example: +30 means +30% reliability.
static func get_reliability_bonus(ctx: SkillContext, dice_roller: DiceRoller = null) -> int:
	return _sum_effects(ctx, SkillEffect.EffectType.ADD_RELIABILITY, dice_roller)

## Returns the total range bonus from passive skills (tiles).
static func get_range_bonus(ctx: SkillContext, dice_roller: DiceRoller = null) -> int:
	return _sum_effects(ctx, SkillEffect.EffectType.ADD_RANGE, dice_roller)

## Returns the total burden reduction granted by passive skills.
static func get_weight_reduction(ctx: SkillContext, dice_roller: DiceRoller = null) -> int:
	return _sum_effects(ctx, SkillEffect.EffectType.REDUCE_WEIGHT, dice_roller)

## Collects all DICE-type ADD_DAMAGE SkillEffects from triggered passive skills.
## These are returned as an Array[SkillEffect] so the caller can roll each one
## as a separate DiceValue in the attack bundle (rather than pre-summing them).
static func collect_bonus_damage_dice(ctx: SkillContext) -> Array:
	var effects: Array = []
	if ctx.owner == null:
		return effects
	for entry in ctx.owner.get_effective_skill_entries():
		if not entry is SkillData:
			continue
		var skill: SkillData = entry as SkillData
		if _skill_triggers(skill, ctx):
			for effect in skill.effects:
				if effect.effect_type == SkillEffect.EffectType.ADD_DAMAGE \
						and effect.value_type == SkillEffect.ValueType.DICE \
						and effect.dice != null:
					effects.append(effect)
	return effects

# ---------------------------------------------------------------------------
# Internal: trigger evaluation
# ---------------------------------------------------------------------------

## Iterates all SkillData entries in owner's trees, checks triggers, and sums
## effects of the requested type.
static func _sum_effects(
		ctx: SkillContext,
		effect_type: SkillEffect.EffectType,
		dice_roller: DiceRoller) -> int:

	if ctx.owner == null:
		return 0

	var total: int = 0
	for entry in ctx.owner.get_effective_skill_entries():
		if not entry is SkillData:
			continue  # AbilityData entries are not passive; skip.
		var skill: SkillData = entry as SkillData
		if _skill_triggers(skill, ctx):
			total += _sum_skill_effects(skill, effect_type, ctx, dice_roller)

	return total

## Iterates all SkillData entries in owner's trees, checks triggers, and sums
## effects of the requested type, excluding DICE-type effects.
## Used for ADD_DAMAGE so that DICE bonuses are collected separately for bundling.
static func _sum_non_dice_effects(
		ctx: SkillContext,
		effect_type: SkillEffect.EffectType,
		dice_roller: DiceRoller) -> int:

	if ctx.owner == null:
		return 0

	var total: int = 0
	for entry in ctx.owner.get_effective_skill_entries():
		if not entry is SkillData:
			continue
		var skill: SkillData = entry as SkillData
		if _skill_triggers(skill, ctx):
			for effect in skill.effects:
				if effect.effect_type == effect_type \
						and effect.value_type != SkillEffect.ValueType.DICE:
					total += _resolve_effect_value(effect, ctx, dice_roller)
	return total

## Returns true if any of the skill's SkillCondition triggers matches ctx.
static func _skill_triggers(skill: SkillData, ctx: SkillContext) -> bool:
	# No triggers means "always active".
	if skill.triggers.is_empty():
		return true

	for trigger in skill.triggers:
		if _condition_matches(trigger, ctx):
			return true

	return false

## Evaluates one SkillCondition pair (major + optional minor) against ctx.
static func _condition_matches(cond: SkillCondition, ctx: SkillContext) -> bool:
	# Major condition must match the current event.
	if cond.major != SkillCondition.MajorCondition.ALWAYS and cond.major != ctx.major_event:
		return false

	# If there is no minor condition, the major match is sufficient.
	if cond.minor == SkillCondition.MinorCondition.NONE:
		return true

	# Evaluate the minor condition.
	return _minor_matches(cond, ctx)

## Evaluates the minor condition part of a SkillCondition against ctx.
static func _minor_matches(cond: SkillCondition, ctx: SkillContext) -> bool:
	match cond.minor:
		SkillCondition.MinorCondition.TARGET_WEARING_HEAVY_ARMOR:
			return _target_armor_type(ctx) == ArmorData.ArmorType.HEAVY
		SkillCondition.MinorCondition.TARGET_WEARING_MEDIUM_ARMOR:
			return _target_armor_type(ctx) == ArmorData.ArmorType.MEDIUM
		SkillCondition.MinorCondition.TARGET_WEARING_LIGHT_ARMOR:
			return _target_armor_type(ctx) == ArmorData.ArmorType.LIGHT
		SkillCondition.MinorCondition.TARGET_CROUCHED:
			return ctx.target != null and ctx.target.is_crouched
		SkillCondition.MinorCondition.TARGET_STANDING:
			return ctx.target != null and not ctx.target.is_crouched
		SkillCondition.MinorCondition.ATTACKER_USING_PHYSICAL:
			return ctx.weapon != null and ctx.weapon.damage_type == WeaponData.DamageType.PHYSICAL
		SkillCondition.MinorCondition.ATTACKER_USING_RANGED:
			return ctx.weapon != null and ctx.weapon.damage_type == WeaponData.DamageType.RANGED
		SkillCondition.MinorCondition.ATTACKER_USING_MAGICAL:
			return ctx.weapon != null and ctx.weapon.damage_type == WeaponData.DamageType.MAGICAL
		SkillCondition.MinorCondition.SELF_CROUCHED:
			return ctx.owner != null and ctx.owner.is_crouched
		SkillCondition.MinorCondition.SELF_NOT_CROUCHED:
			return ctx.owner != null and not ctx.owner.is_crouched
		SkillCondition.MinorCondition.SELF_WEARING_HEAVY_ARMOR:
			return _self_armor_type(ctx) == ArmorData.ArmorType.HEAVY
		SkillCondition.MinorCondition.SELF_WEARING_MEDIUM_ARMOR:
			return _self_armor_type(ctx) == ArmorData.ArmorType.MEDIUM
		SkillCondition.MinorCondition.SELF_WEARING_LIGHT_ARMOR:
			return _self_armor_type(ctx) == ArmorData.ArmorType.LIGHT
		SkillCondition.MinorCondition.SELF_WEAPON_HAS_KEYWORD:
			return ctx.weapon != null and ctx.weapon.has_keyword(cond.string_param)
		SkillCondition.MinorCondition.SELF_WEAPON_TYPE_IS:
			return ctx.weapon != null and ctx.weapon.get_weapon_type_name() == cond.string_param.to_lower()
	return false

## Returns the ArmorType of the target's equipped armor, or LIGHT if none.
static func _target_armor_type(ctx: SkillContext) -> ArmorData.ArmorType:
	if ctx.target == null or ctx.target.armor_slot == null:
		return ArmorData.ArmorType.LIGHT
	return ctx.target.armor_slot.armor_type

static func _self_armor_type(ctx: SkillContext) -> ArmorData.ArmorType:
	if ctx.owner == null or ctx.owner.armor_slot == null:
		return ArmorData.ArmorType.LIGHT
	return ctx.owner.armor_slot.armor_type

# ---------------------------------------------------------------------------
# Internal: effect value resolution
# ---------------------------------------------------------------------------

## Sums effects of the requested type on a triggered skill.
static func _sum_skill_effects(
		skill: SkillData,
		effect_type: SkillEffect.EffectType,
		ctx: SkillContext,
		dice_roller: DiceRoller) -> int:

	var total: int = 0
	for effect in skill.effects:
		if effect.effect_type != effect_type:
			continue
		total += _resolve_effect_value(effect, ctx, dice_roller)
	return total

## Resolves the numeric value of a SkillEffect based on its ValueType.
static func _resolve_effect_value(
		effect: SkillEffect,
		ctx: SkillContext,
		dice_roller: DiceRoller) -> int:

	match effect.value_type:
		SkillEffect.ValueType.FLAT:
			return effect.flat_value
		SkillEffect.ValueType.DICE:
			if effect.dice == null or dice_roller == null:
				return 0
			return effect.dice.roll(dice_roller, effect.uses_reliability)
		SkillEffect.ValueType.STAT_MODIFIER:
			if ctx.owner == null or effect.modifier_divisor <= 0:
				return 0
			var stat_val: int = _read_stat(ctx.owner, effect.modifier_stat)
			return int(stat_val / effect.modifier_divisor)
	return 0

## Reads a named stat from a CharacterData instance.
static func _read_stat(char_data: CharacterData, stat_name: String) -> int:
	match stat_name.to_lower():
		"strength":     return char_data.strength
		"dexterity":    return char_data.dexterity
		"constitution": return char_data.constitution
		"wisdom":       return char_data.wisdom
		"intelligence": return char_data.intelligence
	return 0
