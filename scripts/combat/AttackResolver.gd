## AttackResolver.gd
## Validates and resolves all attack declarations on the server.
## Handles Physical (melee), Ranged, and Magical attack types with their
## respective boundary, line-of-sight, and keyword rules.
##
## Accuracy System (0–100+ percentage scale)
## ─────────────────────────────────────────
## Default hit chance is BASE_ACCURACY (80%).  Modifiers are flat %-point
## additions and subtractions, as is the target's Evasion value:
##
##   final_accuracy = BASE_ACCURACY + stat_bonus + situational_modifiers
##                    + ability_modifier − target_evasion
##
## A d100 is rolled:
##   roll ≤ min(100, final_accuracy)           → hit
##   roll ≤ max(0, final_accuracy − 100)       → critical hit  (always a hit too)
##
## Example: final_accuracy = 115 → always hits, 15 % crit chance.
##
## Critical Hits
## ─────────────
## A crit multiplies post-reliability, post-armor damage by
##   (1.0 + CRIT_DAMAGE_PERCENT / 100.0)
## Default: 50 % bonus → 1.5× damage.
##
## Reliability
## ───────────
## Applies after all additive bonuses but before the crit multiplier.
## DiceRoller pushes the raw dice roll toward the maximum possible value
## proportional to the reliability factor (0.0–1.0).
class_name AttackResolver
extends RefCounted

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

var _dice_roller: DiceRoller = null
var _los_manager: LineOfSightManager = null
var _map_data: MapData = null

func _init(dice_roller: DiceRoller, los_manager: LineOfSightManager, map_data: MapData) -> void:
	_dice_roller = dice_roller
	_los_manager = los_manager
	_map_data = map_data

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Default hit chance before any modifiers (percentage points).
const BASE_ACCURACY: int = 80

## Default critical damage bonus (percentage points).
## 50 → 1.5× damage on a crit.  100 → 2× damage.
const CRIT_DAMAGE_PERCENT: float = 50.0

## Accuracy penalty (%-pts) when the target is behind a barricade.
const COVER_ACCURACY_PENALTY: int = -20

# ---------------------------------------------------------------------------
# Attack Result Data
# ---------------------------------------------------------------------------

## Returned by resolve_attack to describe the full outcome.
class AttackResult:
	var valid: bool = false
	var rejection_reason: String = ""
	var hit: bool = false
	## True when the roll landed in the critical overflow zone (above 100% accuracy).
	var crit: bool = false
	## The computed accuracy value before clamping (can exceed 100 or go below 0).
	var final_accuracy: int = 0
	var damage_dealt: float = 0.0
	var cover_penalty_applied: bool = false
	var ammo_consumed: bool = false
	## True when a riposte stance intercepted this attack (hit cancelled).
	var riposte_triggered: bool = false
	## Name of the weapon used (for dual-wield log disambiguation).
	var weapon_name: String = ""
	# ── Debug breakdown fields ──────────────────────────────────────────────
	var roll_d100: int = 0
	var acc_base: int = 0
	var acc_stat_bonus: int = 0
	var acc_skill_bonus: int = 0
	var acc_context_mod: int = 0
	var acc_ability_mod: int = 0
	var acc_cover_mod: int = 0
	var acc_evasion: int = 0
	var dmg_dice_count: int = 0
	var dmg_dice_sides: int = 0
	var dmg_raw_roll: float = 0.0
	var dmg_stat_bonus: int = 0
	var dmg_bonus_dice: float = 0.0
	## Damage absorbed by the target's armor HP (for log only; deducted in apply_damage).
	var armor_absorbed: float = 0.0
	## Effective reliability factor applied to this damage roll (0.0 = none).
	var reliability: float = 0.0
	## Detailed per-bundle dice roll entries.
	## Each item contains: source, count, sides, roll, reliability.
	var dice_roll_details: Array = []

# ---------------------------------------------------------------------------
# Main Entry Point
# ---------------------------------------------------------------------------

## Validates and resolves a single attack from attacker targeting target using weapon.
## Returns an AttackResult describing validity, hit/crit/miss, and damage.
## skill_or_ability may be a SkillData or AbilityData; ability-level accuracy,
## reliability, and dice modifiers are read from it when present.
## action, if provided, supplies per-action overrides that stack on top of the
## ability-level modifiers, plus optional bonus_dice added to the damage roll.
func resolve_attack(
		attacker: CharacterData,
		target: CharacterData,
		weapon: WeaponData,
		skill_or_ability: SkillTreeEntry = null,
		action: AbilityAction = null,
		is_surprise_attack: bool = false) -> AttackResult:

	var result: AttackResult = AttackResult.new()
	result.weapon_name = weapon.item_name

	match weapon.damage_type:
		WeaponData.DamageType.PHYSICAL:
			return _resolve_physical(attacker, target, weapon, skill_or_ability, action, result, is_surprise_attack)
		WeaponData.DamageType.RANGED:
			return _resolve_ranged(attacker, target, weapon, skill_or_ability, action, result, is_surprise_attack)
		WeaponData.DamageType.MAGICAL:
			return _resolve_magical(attacker, target, weapon, skill_or_ability, action, result, is_surprise_attack)

	result.rejection_reason = "Unknown damage type."
	return result

# ---------------------------------------------------------------------------
# Physical (Melee) Attack Resolution
# ---------------------------------------------------------------------------

func _resolve_physical(
		attacker: CharacterData,
		target: CharacterData,
		weapon: WeaponData,
		skill_or_ability: SkillTreeEntry,
		action: AbilityAction,
		result: AttackResult,
		is_surprise_attack: bool) -> AttackResult:

	# Height equity check: attacker and target must be on the same floor.
	if attacker.grid_position.z != target.grid_position.z:
		result.rejection_reason = "Height mismatch: melee requires same floor level."
		return result

	# Range check: Manhattan distance must not exceed the weapon's attack range,
	# adjusted by any ability range modifier.
	var effective_range: int = weapon.attack_range
	var is_ability_attack: bool = skill_or_ability is AbilityData
	var is_main_hand_attack: bool = attacker != null and weapon == attacker.main_hand_slot
	var is_off_hand_attack: bool = attacker != null and weapon == attacker.off_hand_slot
	if skill_or_ability is AbilityData:
		effective_range += (skill_or_ability as AbilityData).range_modifier
	effective_range += _get_passive_range_bonus(attacker, target, weapon, is_ability_attack, is_main_hand_attack, is_off_hand_attack)
	var dist: int = abs(attacker.grid_position.x - target.grid_position.x) + abs(attacker.grid_position.y - target.grid_position.y)
	if dist > effective_range:
		result.rejection_reason = "Target out of melee range (%d > %d)." % [dist, effective_range]
		return result

	# Boundary obstruction check: wall between attacker and target blocks melee.
	var boundary: BoundaryData = _map_data.get_boundary(attacker.grid_position, target.grid_position)
	if boundary != null and boundary.has_wall:
		result.rejection_reason = "Wall blocks melee attack path."
		return result
	# Barricades do NOT block melee (they are physically bypassed).

	result.valid = true
	_roll_accuracy_and_damage(attacker, target, weapon, 0, skill_or_ability, action, result, is_surprise_attack)
	return result

# ---------------------------------------------------------------------------
# Ranged Attack Resolution
# ---------------------------------------------------------------------------

func _resolve_ranged(
		attacker: CharacterData,
		target: CharacterData,
		weapon: WeaponData,
		skill_or_ability: SkillTreeEntry,
		action: AbilityAction,
		result: AttackResult,
		is_surprise_attack: bool) -> AttackResult:

	# Check ammo availability.
	if weapon.requires_ammo():
		var consumed: bool = _consume_ammo(attacker, weapon)
		if not consumed:
			result.rejection_reason = "No ammo loaded: %s" % weapon.item_name if weapon.has_magazine() else "No ammo: %s" % (WeaponData.AmmoType.keys()[weapon.ammo_type] if weapon.ammo_type < WeaponData.AmmoType.size() else "UNKNOWN")
			return result
		result.ammo_consumed = true

	# Force stand-up if the attacker is crouched.
	if attacker.is_crouched:
		attacker.is_crouched = false

	# Range check: Manhattan distance must not exceed the weapon's attack range,
	# adjusted by any ability range modifier.
	var effective_range: int = weapon.attack_range
	var is_ability_attack: bool = skill_or_ability is AbilityData
	var is_main_hand_attack: bool = attacker != null and weapon == attacker.main_hand_slot
	var is_off_hand_attack: bool = attacker != null and weapon == attacker.off_hand_slot
	if skill_or_ability is AbilityData:
		effective_range += (skill_or_ability as AbilityData).range_modifier
	effective_range += _get_passive_range_bonus(attacker, target, weapon, is_ability_attack, is_main_hand_attack, is_off_hand_attack)
	var dist: int = abs(attacker.grid_position.x - target.grid_position.x) + abs(attacker.grid_position.y - target.grid_position.y)
	if dist > effective_range:
		result.rejection_reason = "Target out of ranged range (%d > %d)." % [dist, effective_range]
		return result

	# Ranged sight check.
	var los_result: Dictionary = _los_manager.check_ranged_target(attacker, target, _map_data)
	if not los_result["valid"]:
		result.rejection_reason = "Ranged target invalid: line of sight blocked."
		return result

	var accuracy_modifier: int = 0
	if los_result["cover_penalty"]:
		accuracy_modifier += COVER_ACCURACY_PENALTY
		result.cover_penalty_applied = true

	result.valid = true
	_roll_accuracy_and_damage(attacker, target, weapon, accuracy_modifier, skill_or_ability, action, result, is_surprise_attack)
	return result

# ---------------------------------------------------------------------------
# Magical Attack Resolution
# ---------------------------------------------------------------------------

func _resolve_magical(
		attacker: CharacterData,
		target: CharacterData,
		weapon: WeaponData,
		skill_or_ability: SkillTreeEntry,
		action: AbilityAction,
		result: AttackResult,
		is_surprise_attack: bool) -> AttackResult:

	# Force stand-up if the attacker is crouched.
	if attacker.is_crouched:
		attacker.is_crouched = false

	# Range check: Manhattan distance must not exceed the weapon's attack range,
	# adjusted by any ability range modifier.
	var effective_range: int = weapon.attack_range
	var is_ability_attack: bool = skill_or_ability is AbilityData
	var is_main_hand_attack: bool = attacker != null and weapon == attacker.main_hand_slot
	var is_off_hand_attack: bool = attacker != null and weapon == attacker.off_hand_slot
	if skill_or_ability is AbilityData:
		effective_range += (skill_or_ability as AbilityData).range_modifier
	effective_range += _get_passive_range_bonus(attacker, target, weapon, is_ability_attack, is_main_hand_attack, is_off_hand_attack)
	var dist: int = abs(attacker.grid_position.x - target.grid_position.x) + abs(attacker.grid_position.y - target.grid_position.y)
	if dist > effective_range:
		result.rejection_reason = "Target out of magical range (%d > %d)." % [dist, effective_range]
		return result

	# Check if the spell has the "Direct" keyword → treat as Ranged rules.
	var has_direct: bool = (weapon.has_keyword("Direct") or (skill_or_ability != null and skill_or_ability.has_keyword("Direct")))

	if has_direct:
		# Use strict ranged LoS rules.
		var los_result: Dictionary = _los_manager.check_ranged_target(attacker, target, _map_data)
		if not los_result["valid"]:
			result.rejection_reason = "Direct magical target invalid: line of sight blocked."
			return result
		var accuracy_modifier: int = 0
		if los_result["cover_penalty"]:
			accuracy_modifier += COVER_ACCURACY_PENALTY
			result.cover_penalty_applied = true
		result.valid = true
		_roll_accuracy_and_damage(attacker, target, weapon, accuracy_modifier, skill_or_ability, action, result, is_surprise_attack)
	else:
		# Default magic: unconditional targeting within range; no LoS required.
		result.valid = true
		_roll_accuracy_and_damage(attacker, target, weapon, 0, skill_or_ability, action, result, is_surprise_attack)

	return result

# ---------------------------------------------------------------------------
# Accuracy & Damage Rolling
# ---------------------------------------------------------------------------
#
# Bundled DiceValues system
# ─────────────────────────
# Each attack is a bundle of one or more DiceValue expressions that all hit
# or miss together.  The bundle consists of:
#
#   1. The weapon's base dice (from get_effective_damage_dice), converted to
#      a DiceValue with the weapon's base_reliability baked in.
#   2. Any DICE-type ADD_DAMAGE passive skill effects that fire for this
#      attacker/weapon combination (e.g. Crypt Candle's +1d4).
#   3. An optional per-action bonus DiceValue from AbilityAction.bonus_dice.
#
# General reliability comes from: weapon.base_reliability +
#   ability.reliability_modifier_percent/100 + action.reliability_modifier_percent/100.
#
# Each bundled DiceValue's effective reliability is clamped:
#   clampf(general_reliability + dv.reliability, 0.0, 1.0)
#
# The stat damage bonus is applied once (as an integer addend) after all
# dice have been summed.  A stat_bonus_multiplier float (default 1.0) is
# reserved for future skills that amplify the stat contribution.
#
# Flat passive skill bonuses are added last.

func _roll_accuracy_and_damage(
		attacker: CharacterData,
		target: CharacterData,
		weapon: WeaponData,
		base_accuracy_modifier: int,
		skill_or_ability: SkillTreeEntry,
		action: AbilityAction,
		result: AttackResult,
		is_surprise_attack: bool = false) -> void:

	# ── Collect ability-level modifiers ──────────────────────────────────────
	var ability_acc_modifier: int = 0
	var ability_reliability_bonus: float = 0.0
	if skill_or_ability is AbilityData:
		var ability: AbilityData = skill_or_ability as AbilityData
		ability_acc_modifier = int(ability.accuracy_modifier_percent)
		ability_reliability_bonus = ability.reliability_modifier_percent / 100.0

	# ── Per-action overrides (stack on top of ability-level modifiers) ────────
	if action != null:
		ability_acc_modifier += int(action.accuracy_modifier_percent)
		ability_reliability_bonus += action.reliability_modifier_percent / 100.0

	# ── Build SkillContext for passive skill evaluation ───────────────────────
	# For trigger matching: build a context with ON_ATTACK first (for accuracy
	# skills), then we switch to ON_DEAL_DAMAGE for damage skill dice.
	var is_ability_attack: bool = skill_or_ability is AbilityData
	var is_main_hand_attack: bool = attacker != null and weapon == attacker.main_hand_slot
	var is_off_hand_attack: bool = attacker != null and weapon == attacker.off_hand_slot
	var attack_ctx: SkillProcessor.SkillContext = SkillProcessor.SkillContext.new(
		attacker,
		SkillCondition.MajorCondition.ON_ATTACK,
		attacker,
		target,
		weapon,
		is_ability_attack,
		is_surprise_attack,
		is_main_hand_attack,
		is_off_hand_attack)

	var deal_ctx: SkillProcessor.SkillContext = SkillProcessor.SkillContext.new(
		attacker,
		SkillCondition.MajorCondition.ON_DEAL_DAMAGE,
		attacker,
		target,
		weapon,
		is_ability_attack,
		is_surprise_attack,
		is_main_hand_attack,
		is_off_hand_attack)

	# ── Accuracy formula ─────────────────────────────────────────────────────
	var accuracy_stat_bonus: int = _get_accuracy_bonus(attacker, weapon) * 5
	var skill_acc_bonus: int = SkillProcessor.get_accuracy_bonus(attack_ctx)
	var target_evasion: int = target.get_total_evasion()
	var final_accuracy: int = (BASE_ACCURACY
			+ accuracy_stat_bonus
			+ skill_acc_bonus
			+ base_accuracy_modifier
			+ ability_acc_modifier
			- target_evasion)
	result.final_accuracy = final_accuracy

	# Populate accuracy debug breakdown.
	result.acc_base = BASE_ACCURACY
	result.acc_stat_bonus = accuracy_stat_bonus
	result.acc_skill_bonus = skill_acc_bonus
	result.acc_context_mod = base_accuracy_modifier
	result.acc_ability_mod = ability_acc_modifier
	result.acc_cover_mod = base_accuracy_modifier if result.cover_penalty_applied else 0
	result.acc_evasion = target_evasion

	# ── Hit / crit determination (d100) ──────────────────────────────────────
	var force_hit: bool = action != null and action.force_hit
	var cannot_crit: bool = action != null and action.cannot_crit
	var roll: int = _dice_roller.roll_d100()
	result.roll_d100 = roll
	result.hit = force_hit or roll <= mini(100, maxi(0, final_accuracy))
	if final_accuracy > 100 and not cannot_crit and not force_hit:
		result.crit = roll <= (final_accuracy - 100)
	if cannot_crit:
		result.crit = false

	# ── Damage (only on hit) ──────────────────────────────────────────────────
	if result.hit:
		# General reliability factor shared by all bundled dice in this attack.
		var skill_reliability_bonus: float = _get_passive_reliability_bonus(attacker, target, weapon, is_ability_attack, is_main_hand_attack, is_off_hand_attack)
		var general_reliability: float = weapon.base_reliability + ability_reliability_bonus + _get_reliability_bonus(attacker, weapon) + skill_reliability_bonus

		# Build the dice bundle.
		# Slot 1: weapon base dice, converted to a temporary DiceValue.
		var is_two_handed_grip: bool = weapon.is_versatile() and attacker.off_hand_slot == null
		var raw_dice: Array[int] = weapon.get_effective_damage_dice(is_two_handed_grip)

		# Apply ability-level dice expression modifiers.
		if skill_or_ability is AbilityData:
			var ability: AbilityData = skill_or_ability as AbilityData
			raw_dice[0] = AbilityData.apply_dice_count_modifier(raw_dice[0], ability.dice_count_modifier)
			raw_dice[1] = AbilityData.apply_dice_tier_modifier(raw_dice[1], ability.dice_tier_modifier)

		var weapon_dv: DiceValue = DiceValue.new()
		weapon_dv.count = raw_dice[0]
		weapon_dv.sides = raw_dice[1]
		weapon_dv.reliability = 0.0  # general_reliability covers the weapon's base

		# Slot 2+: passive skill bonus dice (e.g. Crypt Candle +1d4).
		var skill_dice_effects: Array = SkillProcessor.collect_bonus_damage_dice(deal_ctx)

		# Slot last: per-action bonus_dice (e.g. Achilles Bane +1d4).
		var action_dv: DiceValue = null
		if action != null and action.bonus_dice != null:
			action_dv = action.bonus_dice

		# Roll each bundled DiceValue; they all benefit from general_reliability.
		var total_roll: float = 0.0
		result.dice_roll_details.clear()

		var weapon_eff_rel: float = general_reliability + weapon_dv.reliability
		var weapon_roll: float = float(_dice_roller.roll_dice(weapon_dv.count, weapon_dv.sides,
				weapon_eff_rel > 0.0, weapon_eff_rel))
		total_roll += weapon_roll
		result.dice_roll_details.append({
			"source": "weapon",
			"count": weapon_dv.count,
			"sides": weapon_dv.sides,
			"roll": weapon_roll,
			"reliability": weapon_eff_rel,
		})

		var bonus_dice_roll: float = 0.0
		for se in skill_dice_effects:
			var dv: DiceValue = (se as SkillEffect).dice
			var eff_rel: float = general_reliability + dv.reliability
			var r: float = float(_dice_roller.roll_dice(dv.count, dv.sides, eff_rel > 0.0, eff_rel))
			bonus_dice_roll += r
			total_roll += r
			result.dice_roll_details.append({
				"source": "skill",
				"count": dv.count,
				"sides": dv.sides,
				"roll": r,
				"reliability": eff_rel,
			})

		if action_dv != null:
			var eff_rel: float = general_reliability + action_dv.reliability
			var r: float = float(_dice_roller.roll_dice(action_dv.count, action_dv.sides,
					eff_rel > 0.0, eff_rel))
			bonus_dice_roll += r
			total_roll += r
			result.dice_roll_details.append({
				"source": "ability",
				"count": action_dv.count,
				"sides": action_dv.sides,
				"roll": r,
				"reliability": eff_rel,
			})

		# Stat damage bonus applied once (multiplier reserved for future skills).
		const STAT_BONUS_MULTIPLIER: float = 1.0
		var damage_stat_bonus: int = _get_damage_bonus(attacker, weapon)
		var flat_skill_bonus: int = SkillProcessor.get_damage_bonus(deal_ctx)

		var raw_damage: float = total_roll + int(damage_stat_bonus * STAT_BONUS_MULTIPLIER) + flat_skill_bonus

		# Apply critical hit multiplier after all other effects.
		if result.crit:
			raw_damage *= 1.0 + CRIT_DAMAGE_PERCENT / 100.0

		# Populate debug breakdown.
		result.dmg_dice_count = weapon_dv.count
		result.dmg_dice_sides = weapon_dv.sides
		result.dmg_raw_roll = total_roll
		result.dmg_stat_bonus = damage_stat_bonus
		result.dmg_bonus_dice = bonus_dice_roll
		result.reliability = general_reliability

		result.damage_dealt = raw_damage

# ---------------------------------------------------------------------------
# Stat Bonus Helpers
# ---------------------------------------------------------------------------

func _get_accuracy_bonus(attacker: CharacterData, weapon: WeaponData) -> int:
	match weapon.damage_type:
		WeaponData.DamageType.PHYSICAL:
			# Finesse weapons grant double the Dexterity accuracy bonus.
			if weapon.is_finesse():
				return attacker.stat_bonus(attacker.dexterity) * 2
			return attacker.stat_bonus(attacker.dexterity)
		WeaponData.DamageType.RANGED:
			return attacker.stat_bonus(attacker.intelligence)
		WeaponData.DamageType.MAGICAL:
			return (attacker.stat_bonus(attacker.intelligence) + attacker.stat_bonus(attacker.wisdom)) / 2
	return 0

func _get_damage_bonus(attacker: CharacterData, weapon: WeaponData) -> int:
	match weapon.damage_type:
		WeaponData.DamageType.PHYSICAL:
			# Finesse weapons use Wisdom for the damage bonus instead of Strength.
			if weapon.is_finesse():
				return attacker.stat_bonus(attacker.wisdom)
			return attacker.stat_bonus(attacker.strength)
		WeaponData.DamageType.RANGED:
			return attacker.stat_bonus(attacker.wisdom)
		WeaponData.DamageType.MAGICAL:
			return (attacker.stat_bonus(attacker.wisdom) + attacker.stat_bonus(attacker.intelligence)) / 2
	return 0

func _get_reliability_bonus(attacker: CharacterData, weapon: WeaponData) -> float:
	match weapon.damage_type:
		WeaponData.DamageType.PHYSICAL:
			# Finesse weapons use Dexterity for the reliability bonus.
			if weapon.is_finesse():
				return attacker.stat_bonus(attacker.dexterity) * 0.05
			return 0.0
		WeaponData.DamageType.RANGED:
			return 0.0
		WeaponData.DamageType.MAGICAL:
			return 0.0
	return 0.0

func _get_passive_reliability_bonus(attacker: CharacterData, target: CharacterData, weapon: WeaponData, is_ability_attack: bool = false, is_main_hand_attack: bool = false, is_off_hand_attack: bool = false) -> float:
	var ctx: SkillProcessor.SkillContext = SkillProcessor.SkillContext.new(
		attacker,
		SkillCondition.MajorCondition.ON_ATTACK,
		attacker,
		target,
		weapon,
		is_ability_attack,
		false,
		is_main_hand_attack,
		is_off_hand_attack)
	return SkillProcessor.get_reliability_bonus(ctx) / 100.0

func _get_passive_range_bonus(attacker: CharacterData, target: CharacterData, weapon: WeaponData, is_ability_attack: bool = false, is_main_hand_attack: bool = false, is_off_hand_attack: bool = false) -> int:
	var ctx: SkillProcessor.SkillContext = SkillProcessor.SkillContext.new(
		attacker,
		SkillCondition.MajorCondition.ON_ATTACK,
		attacker,
		target,
		weapon,
		is_ability_attack,
		false,
		is_main_hand_attack,
		is_off_hand_attack)
	return SkillProcessor.get_range_bonus(ctx)

# ---------------------------------------------------------------------------
# Ammo Consumption
# ---------------------------------------------------------------------------

## Attempts to consume one unit of the required ammo type.
## Returns true on success, false if no ammo remains.
func _consume_ammo(attacker: CharacterData, weapon: WeaponData) -> bool:
	if weapon == null:
		return false
	return attacker.consume_weapon_ammo(weapon)

# ---------------------------------------------------------------------------
# Dual Wield Sequence
# ---------------------------------------------------------------------------

## Resolves a dual-wield attack sequence: main-hand first, then off-hand.
## The off-hand attack is cancelled if ammo is exhausted after the main-hand.
## Returns an Array[AttackResult] with 1 or 2 entries.
func resolve_dual_wield(
		attacker: CharacterData,
		target: CharacterData) -> Array:

	var results: Array = []

	if not attacker.is_dual_wielding():
		return results

	var main_weapon: WeaponData = attacker.main_hand_slot
	var off_weapon: WeaponData = attacker.off_hand_slot as WeaponData

	# Attack 1: Main Hand.
	var main_result: AttackResult = resolve_attack(attacker, target, main_weapon)
	results.append(main_result)

	if not main_result.valid:
		return results  # Main hand failed; abort.

	# Attack 2: Off Hand — check ammo before rolling.
	if off_weapon.requires_ammo():
		var ammo_available: bool = attacker.can_fire_weapon(off_weapon)
		if not ammo_available:
			var no_ammo_result: AttackResult = AttackResult.new()
			no_ammo_result.rejection_reason = "No Ammo: off-hand attack cancelled."
			results.append(no_ammo_result)
			return results

	var off_result: AttackResult = resolve_attack(attacker, target, off_weapon)
	results.append(off_result)
	return results
