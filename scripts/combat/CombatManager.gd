## CombatManager.gd
## Server-side combat loop controller.
## Manages the per-turn action phase container architecture
## (Beginning → Main → Ending) and coordinates all combat subsystems.
##
## Signals are emitted to notify clients of state changes via RPC.
class_name CombatManager
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when a new round starts. Carries the ordered initiative list.
signal round_started(turn_order: Array)
## Emitted when a character's turn begins, indicating the active phase.
signal turn_started(character: CharacterData, phase: ActionPhase)
## Emitted when the server requests the player to pick a facing direction.
signal facing_selection_required(character: CharacterData)
## Emitted when a character's turn ends.
signal turn_ended(character: CharacterData)
## Emitted when a character is knocked down.
signal character_knocked_down(character: CharacterData)
## Emitted when a character dies permanently.
signal character_died(character: CharacterData)
## Emitted when the match ends.
signal match_ended(winner_player_id: String)
## Emitted for notable combat events not covered by other signals (riposte, ability attacks, etc.).
signal combat_event(message: String)

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum ActionPhase {
	BEGINNING,
	PENDING_ROTATION,  # Sub-state: waiting for facing direction input.
	MAIN,
	ENDING,
	DONE,
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _map_data: MapData = null
var _initiative_manager: InitiativeManager = null
var _attack_resolver: AttackResolver = null
var _los_manager: LineOfSightManager = null
var _dice_roller: DiceRoller = null
var _pathfinding: PathfindingManager = null

## All characters currently in the match (both teams).
var _all_characters: Array[CharacterData] = []
## Maps player_id String -> Array[CharacterData] (their team).
var _team_map: Dictionary = {}

var _current_phase: ActionPhase = ActionPhase.BEGINNING
var _active_character: CharacterData = null
var _round_number: int = 0

## Flag set when a player surrenders.
var _surrender_requested: bool = false
var _surrender_player_id: String = ""

# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

func initialise(
		map_data: MapData,
		team_map: Dictionary,
		dice_roller: DiceRoller) -> void:

	_map_data = map_data
	_team_map = team_map
	_dice_roller = dice_roller

	_all_characters.clear()
	for player_id in team_map:
		for char_data in team_map[player_id]:
			_all_characters.append(char_data)

	_los_manager = LineOfSightManager.new()
	_attack_resolver = AttackResolver.new(_dice_roller, _los_manager, _map_data)
	_initiative_manager = InitiativeManager.new()
	_pathfinding = PathfindingManager.new()
	_pathfinding.build_from_map(_map_data)

# ---------------------------------------------------------------------------
# Match Flow
# ---------------------------------------------------------------------------

## Starts the match: resolves initiative and begins the first round.
func start_match() -> void:
	_round_number = 0
	_start_new_round()

## Starts a new round: resolves initiative for all living characters.
func _start_new_round() -> void:
	_round_number += 1
	var living: Array[CharacterData] = _get_living_characters()
	_initiative_manager.resolve_initiative(living, _dice_roller)
	emit_signal("round_started", _initiative_manager.turn_order.duplicate())
	_begin_next_turn()

## Begins the turn of the next character in the initiative order.
func _begin_next_turn() -> void:
	if _check_match_end():
		return

	_active_character = _initiative_manager.get_next_active_character()
	if _active_character == null:
		_start_new_round()
		return

	# Tick timed buffs/debuffs at the start of this character's turn.
	_tick_buffs(_active_character)

	# Reset per-turn combat state for the incoming active character.
	_active_character.moved_this_turn = false
	_active_character.stood_up_this_turn = false

	_current_phase = ActionPhase.BEGINNING
	emit_signal("turn_started", _active_character, _current_phase)

# ---------------------------------------------------------------------------
# Action Phase Processing
# ---------------------------------------------------------------------------

## Called by the server when a movement action is submitted for the active character.
## Returns false if the action is rejected.
func process_move_action(character: CharacterData, destination: Vector3i) -> bool:
	if character != _active_character:
		return false
	if _current_phase != ActionPhase.BEGINNING:
		return false

	var speed: int = character.get_base_movement_speed()
	if character.is_crouched:
		# Crouched characters cannot move — they must stand up first.
		return false
	if character.stood_up_this_turn:
		# Standing up this turn halves movement speed.
		speed = int(ceil(speed / 2.0))

	var can_vault: bool = _character_can_vault(character)
	var path: Array[Vector3i] = _pathfinding.find_path(character.grid_position, destination, can_vault)

	if path.is_empty():
		return false
	if _pathfinding.get_path_cost(path, can_vault) > speed:
		return false

	# Reject if the destination tile is already occupied by a living character.
	for other in _all_characters:
		if other == character:
			continue
		if other.grid_position == destination and other.state_flag != CharacterData.StateFlag.DEAD:
			return false

	# Apply movement.
	character.grid_position = destination
	character.moved_this_turn = true
	# After movement, enter PENDING_ROTATION sub-state.
	_current_phase = ActionPhase.PENDING_ROTATION
	emit_signal("facing_selection_required", character)
	return true

## Called when the player selects a facing direction after moving.
## direction_index must be in range [0, 7].
func process_facing_selection(character: CharacterData, direction_index: int) -> bool:
	if character != _active_character:
		return false
	if _current_phase != ActionPhase.PENDING_ROTATION:
		return false
	if direction_index < 0 or direction_index > 7:
		return false

	character.facing_direction = direction_index
	_current_phase = ActionPhase.MAIN
	emit_signal("turn_started", _active_character, _current_phase)
	return true

## Called when the active character skips their Beginning Action (no movement).
## Transitions directly to Main phase.
func process_skip_beginning(character: CharacterData) -> bool:
	if character != _active_character:
		return false
	if _current_phase != ActionPhase.BEGINNING:
		return false
	_current_phase = ActionPhase.MAIN
	emit_signal("turn_started", _active_character, _current_phase)
	return true

## Called when the player declares a standard attack or skill in the Main phase.
## Returns an Array[AttackResult]: one entry per attack (two for dual wield).
func process_attack_action(
		attacker: CharacterData,
		target: CharacterData,
		weapon: WeaponData = null,
		skill_or_ability: SkillTreeEntry = null) -> Array:

	var dummy_result: AttackResolver.AttackResult = AttackResolver.AttackResult.new()
	if attacker != _active_character:
		dummy_result.rejection_reason = "Not the active character."
		return [dummy_result]
	if _current_phase != ActionPhase.MAIN:
		dummy_result.rejection_reason = "Not in Main phase."
		return [dummy_result]

	if weapon == null:
		weapon = attacker.main_hand_slot
	if weapon == null:
		dummy_result.rejection_reason = "No weapon equipped."
		return [dummy_result]

	# Enforce the Aiming keyword: weapon cannot be fired after moving unless
	# the triggering ability explicitly ignores this restriction.
	if weapon.requires_aiming() and attacker.moved_this_turn:
		var ignore_aiming: bool = false
		if skill_or_ability != null and skill_or_ability is AbilityData:
			ignore_aiming = (skill_or_ability as AbilityData).ignore_aiming_restriction
		if not ignore_aiming:
			dummy_result.rejection_reason = "Aiming weapon cannot be fired after moving."
			return [dummy_result]

	if attacker.is_dual_wielding():
		# Fire each weapon individually so hit/miss and riposte apply per-attack.
		var results: Array = []
		var weapons: Array = [attacker.main_hand_slot, attacker.off_hand_slot as WeaponData]
		for w in weapons:
			if w == null:
				continue
			var r: AttackResolver.AttackResult = _attack_resolver.resolve_attack(
					attacker, target, w, skill_or_ability)
			_apply_attack_result_with_riposte(r, attacker, target, w)
			results.append(r)
			# Stop if attacker was killed or knocked down by a riposte counter-attack.
			if attacker.state_flag == CharacterData.StateFlag.DEAD \
					or attacker.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
				break
		return results
	else:
		var result: AttackResolver.AttackResult = _attack_resolver.resolve_attack(attacker, target, weapon, skill_or_ability)
		_apply_attack_result_with_riposte(result, attacker, target, weapon)
		return [result]

## Called when the active character passes or performs an Ending phase action.
func process_end_turn(character: CharacterData) -> bool:
	if character != _active_character:
		return false
	if _current_phase == ActionPhase.BEGINNING or _current_phase == ActionPhase.MAIN:
		# Skip remaining phases and end the turn.
		pass
	# Tick cooldowns at the end of this character's turn (per spec).
	_tick_cooldowns(character)
	_current_phase = ActionPhase.DONE
	emit_signal("turn_ended", character)
	_initiative_manager.advance_turn()
	_begin_next_turn()
	return true

## Called during Ending phase to crouch behind an adjacent barricade.
func process_crouch_action(character: CharacterData) -> bool:
	if character != _active_character:
		return false
	if _current_phase != ActionPhase.ENDING:
		return false

	# Verify at least one adjacent boundary has a barricade.
	var adjacent: Array[Vector3i] = _map_data.get_adjacent_tiles(character.grid_position)
	var found_barricade: bool = false
	for neighbour in adjacent:
		var boundary: BoundaryData = _map_data.get_boundary(character.grid_position, neighbour)
		if boundary != null and boundary.has_barricade:
			found_barricade = true
			break

	if not found_barricade:
		return false  # No adjacent barricade; action rejected.

	character.is_crouched = true
	return true

## Stand up is a free action (no phase slot consumed).
## The character may stand up during the Beginning phase only.
## After standing, movement speed is halved for the remainder of this turn.
func process_stand_up(character: CharacterData) -> bool:
	if character != _active_character:
		return false
	if _current_phase != ActionPhase.BEGINNING:
		return false
	if not character.is_crouched:
		return false
	character.is_crouched = false
	character.stood_up_this_turn = true
	return true

## Called when a player surrenders.
func process_surrender(player_id: String) -> void:
	_surrender_requested = true
	_surrender_player_id = player_id
	_end_match(_get_opponent_player_id(player_id))

# ---------------------------------------------------------------------------
# Match End Logic
# ---------------------------------------------------------------------------

## Checks whether the match end conditions have been met.
## Returns true and triggers match end if so.
func _check_match_end() -> bool:
	if _surrender_requested:
		return true

	for player_id in _team_map:
		var team: Array = _team_map[player_id]
		var all_out: bool = true
		for char_data in team:
			if char_data.state_flag == CharacterData.StateFlag.LIVING \
					or char_data.state_flag == CharacterData.StateFlag.PENDING_LEVEL_UP:
				all_out = false
				break
		if all_out:
			_end_match(_get_opponent_player_id(player_id))
			return true

	return false

func _end_match(winner_player_id: String) -> void:
	emit_signal("match_ended", winner_player_id)

## Returns the player ID of the opponent of the given player.
func _get_opponent_player_id(player_id: String) -> String:
	for pid in _team_map:
		if pid != player_id:
			return pid
	return ""

# ---------------------------------------------------------------------------
# Knockdown / Death Handling
# ---------------------------------------------------------------------------

func _on_character_knocked_down(character: CharacterData) -> void:
	if character.state_flag == CharacterData.StateFlag.DEAD:
		emit_signal("character_died", character)
		_initiative_manager.remove_character(character)
	elif character.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
		emit_signal("character_knocked_down", character)
		_initiative_manager.remove_character(character)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns all characters that are alive and can act.
func _get_living_characters() -> Array[CharacterData]:
	var living: Array[CharacterData] = []
	for char_data in _all_characters:
		if char_data.state_flag == CharacterData.StateFlag.LIVING \
				or char_data.state_flag == CharacterData.StateFlag.PENDING_LEVEL_UP:
			living.append(char_data)
	return living

## Returns true if the character has a vault skill (stub; extend with real skill lookup).
func _character_can_vault(character: CharacterData) -> bool:
	for tree in character.skill_trees:
		for entry in tree:
			if (entry as SkillTreeEntry).has_keyword("Vault"):
				return true
	return false

## Transitions the current phase to Ending (called after Main phase action is used).
func advance_to_ending_phase() -> void:
	if _current_phase == ActionPhase.MAIN:
		_current_phase = ActionPhase.ENDING
		emit_signal("turn_started", _active_character, _current_phase)

# ---------------------------------------------------------------------------
# Riposte System
# ---------------------------------------------------------------------------

## Applies an attack result, checking for a riposte counter-attack first.
## For physical attacks against a character in riposte stance:
##   - The attack is negated (parried), stance is cleared, counter fires.
## For non-physical or no stance: normal damage application.
func _apply_attack_result_with_riposte(
		result: AttackResolver.AttackResult,
		attacker: CharacterData,
		target: CharacterData,
		weapon: WeaponData) -> void:

	if not result.valid:
		return

	# Only physical attacks can be parried by Riposte.
	if result.hit and weapon.damage_type == WeaponData.DamageType.PHYSICAL \
			and target.active_buffs.has("riposte_stance"):
		# Parry: cancel the hit and counter.
		target.active_buffs.erase("riposte_stance")
		result.riposte_triggered = true
		result.hit = false
		result.damage_dealt = 0.0
		emit_signal("combat_event",
				"%s parries %s's attack and ripostes!" % [target.character_id, attacker.character_id])
		_execute_riposte(target, attacker)
		return

	# Non-physical or no stance: clear stance if present (riposte expires).
	if target.active_buffs.has("riposte_stance") \
			and weapon.damage_type != WeaponData.DamageType.PHYSICAL:
		target.active_buffs.erase("riposte_stance")

	# Normal hit resolution.
	if result.hit:
		var knocked_down: bool = target.apply_damage(result.damage_dealt)
		if knocked_down:
			_on_character_knocked_down(target)

## Executes the Riposte counter-attack: the riposte user immediately strikes back
## at the original attacker with -50% reliability (reflecting a hasty parry-riposte).
func _execute_riposte(riposte_user: CharacterData, original_attacker: CharacterData) -> void:
	var weapon: WeaponData = riposte_user.main_hand_slot
	if weapon == null:
		return

	# Synthesise a one-shot AbilityAction to carry the reliability penalty.
	var counter_action: AbilityAction = AbilityAction.new()
	counter_action.action_type = AbilityAction.ActionType.ATTACK
	counter_action.reliability_modifier_percent = -50.0

	var result: AttackResolver.AttackResult = _attack_resolver.resolve_attack(
			riposte_user, original_attacker, weapon, null, counter_action)

	if result.valid and result.hit:
		var knocked_down: bool = original_attacker.apply_damage(result.damage_dealt)
		if knocked_down:
			_on_character_knocked_down(original_attacker)
		emit_signal("combat_event", _format_attack_event(riposte_user, original_attacker, result, "Riposte"))
	else:
		emit_signal("combat_event",
				"Riposte: %s misses %s" % [riposte_user.character_id, original_attacker.character_id])

# ---------------------------------------------------------------------------
# Ability Execution
# ---------------------------------------------------------------------------

## Attempts to execute an AbilityData for the active character.
## target is the primary target character (may be null for self-only abilities).
## Returns false if the ability is rejected (wrong phase, failed conditions, etc.).
func process_ability(
		character: CharacterData,
		ability: AbilityData,
		target: CharacterData = null,
		secondary_target: CharacterData = null) -> bool:

	if character != _active_character:
		return false

	# Phase check: ability must be usable in the current phase.
	# ActionPhase enum values don't map 1:1 to AbilityData phase indices:
	#   BEGINNING(0) / PENDING_ROTATION(1) → index 0 (PHASE_BEGINNING = 1)
	#   MAIN(2)                             → index 1 (PHASE_MAIN     = 2)
	#   ENDING(3)                           → index 2 (PHASE_ENDING   = 4)
	var phase_index: int
	match _current_phase:
		ActionPhase.BEGINNING, ActionPhase.PENDING_ROTATION:
			phase_index = 0
		ActionPhase.MAIN:
			phase_index = 1
		ActionPhase.ENDING:
			phase_index = 2
		_:
			return false
	if not ability.is_usable_in_phase(phase_index):
		return false

	# Cooldown check: ability must not be on cooldown.
	if character.ability_cooldowns.get(ability.entry_id, 0) > 0:
		return false

	# Weapon requirement check (OR: any matching type satisfies the requirement).
	if ability.weapon_requirements.size() > 0:
		var equipped: WeaponData = character.main_hand_slot
		if equipped == null:
			return false
		var type_name: String = equipped.get_weapon_type_name()
		var matched: bool = false
		for req in ability.weapon_requirements:
			if req.to_lower() == type_name:
				matched = true
				break
		if not matched:
			return false

	# Condition check: all AbilityConditions must pass.
	if not _check_ability_conditions(character, ability, target):
		return false

	# Context carries data shared across actions in the same ability sequence
	# (e.g. last_attack_damage for drain_life's heal fraction).
	var context: Dictionary = {}

	# Execute each action in order.
	for action in ability.actions:
		_execute_ability_action(character, action, target, ability, context, secondary_target)

	# Apply cooldown if this ability has one.
	if ability.cooldown_turns > 0:
		character.ability_cooldowns[ability.entry_id] = ability.cooldown_turns

	return true

## Evaluates all AbilityConditions on an ability.
## Returns true only if every condition is satisfied.
func _check_ability_conditions(
		character: CharacterData,
		ability: AbilityData,
		target: CharacterData) -> bool:

	for condition in ability.conditions:
		var satisfied: bool = _evaluate_ability_condition(character, condition, target)
		# If must_be_true is false, invert the result.
		if condition.must_be_true != satisfied:
			return false
	return true

## Evaluates a single AbilityCondition. Returns the raw (uninverted) truth value.
func _evaluate_ability_condition(
		character: CharacterData,
		condition: AbilityCondition,
		_target: CharacterData) -> bool:

	match condition.condition_type:
		AbilityCondition.ConditionType.SELF_CROUCHED:
			return character.is_crouched
		AbilityCondition.ConditionType.ADJACENT_BARRICADE:
			var adjacent: Array[Vector3i] = _map_data.get_adjacent_tiles(character.grid_position)
			for neighbour in adjacent:
				var boundary: BoundaryData = _map_data.get_boundary(character.grid_position, neighbour)
				if boundary != null and boundary.has_barricade:
					return true
			return false
		AbilityCondition.ConditionType.HAS_AMMO:
			match condition.string_param.to_lower():
				"bullets": return character.bullets_count > 0
				"bolts":   return character.bolts_count > 0
				"arrows":  return character.arrows_count > 0
			return false
		AbilityCondition.ConditionType.HAS_SKILL:
			for tree in character.skill_trees:
				for entry in tree:
					if (entry as SkillTreeEntry).entry_id == condition.string_param:
						return true
			return false
		AbilityCondition.ConditionType.TARGET_IN_RANGE:
			# Basic range check using target and active weapon range.
			if _target == null or character.main_hand_slot == null:
				return false
			var dist: int = _manhattan_distance(character.grid_position, _target.grid_position)
			return dist <= character.main_hand_slot.attack_range
		AbilityCondition.ConditionType.WEAPON_TYPE_EQUIPPED:
			if character.main_hand_slot == null:
				return false
			return character.main_hand_slot.get_weapon_type_name() == condition.string_param.to_lower()
		AbilityCondition.ConditionType.NOT_MOVED_THIS_TURN:
			return not character.moved_this_turn
	return true

## Executes a single AbilityAction for a character.
## parent_ability carries ability-level modifiers applied to attacks and heals.
## context is a shared Dictionary for intra-ability data (e.g. last_attack_damage).
## secondary_target is an optional second target (e.g. the ally to heal in Drain Life).
func _execute_ability_action(
		character: CharacterData,
		action: AbilityAction,
		target: CharacterData,
		parent_ability: AbilityData,
		context: Dictionary,
		secondary_target: CharacterData = null) -> void:

	match action.action_type:
		AbilityAction.ActionType.STAND_UP:
			character.is_crouched = false

		AbilityAction.ActionType.CROUCH:
			character.is_crouched = true

		AbilityAction.ActionType.MOVE:
			# MOVE actions are declared via process_move_action; this hook is for
			# abilities that grant bonus movement (e.g. a dash), not a full move phase.
			pass

		AbilityAction.ActionType.ATTACK:
			if target == null or character.main_hand_slot == null:
				return
			# Build the list of weapons to attack with.
			# For dual-wield characters every ATTACK action fires from both weapons
			# (e.g. 2 ATTACK actions × 2 axes = 4 total attacks for Reckless Assault).
			var attack_weapons: Array = [character.main_hand_slot]
			if character.is_dual_wielding():
				attack_weapons.append(character.off_hand_slot as WeaponData)
			var total_damage: float = 0.0
			for w in attack_weapons:
				var r: AttackResolver.AttackResult = _attack_resolver.resolve_attack(
						character, target, w, parent_ability, action)
				_apply_attack_result_with_riposte(r, character, target, w)
				if r.valid and r.hit:
					total_damage += r.damage_dealt
				# Announce result (riposte emits its own parry + counter messages).
				if r.valid and not r.riposte_triggered:
					emit_signal("combat_event", _format_attack_event(
							character, target, r, parent_ability.entry_name))
				# Stop if attacker was killed or knocked down by a riposte counter-attack.
				if character.state_flag == CharacterData.StateFlag.DEAD \
						or character.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
					break
			context["last_attack_damage"] = total_damage

		AbilityAction.ActionType.HEAL:
			var heal_target: CharacterData = _resolve_action_target(character, action, target, secondary_target)
			if heal_target == null:
				return
			var heal_amount: float = float(action.flat_bonus)
			# Weapon-dice-based heal (e.g. Regenerate: 2× weapon damage roll).
			if action.uses_weapon_dice and character.main_hand_slot != null:
				var weapon: WeaponData = character.main_hand_slot
				var is_two_handed_grip: bool = weapon.is_versatile() and character.off_hand_slot == null
				var dice: Array[int] = weapon.get_effective_damage_dice(is_two_handed_grip)
				# Apply ability-level dice modifiers.
				dice[0] = AbilityData.apply_dice_count_modifier(dice[0], parent_ability.dice_count_modifier)
				dice[1] = AbilityData.apply_dice_tier_modifier(dice[1], parent_ability.dice_tier_modifier)
				var rel_bonus: float = parent_ability.reliability_modifier_percent / 100.0
				var reliability: float = clampf(weapon.base_reliability + rel_bonus, 0.0, 1.0)
				var weapon_roll: float = float(_dice_roller.roll_dice(
						dice[0], dice[1], reliability > 0.0, reliability))
				heal_amount += weapon_roll * action.weapon_dice_multiplier
			elif action.bonus_dice != null:
				# Fallback: fixed bonus dice (legacy / non-weapon-derived heals).
				heal_amount += float(action.bonus_dice.roll(_dice_roller, action.uses_reliability, 0.0))
			# Fraction of last attack damage (e.g. Drain Life heals 50% of damage dealt).
			if action.heal_from_attack_fraction > 0.0:
				heal_amount += context.get("last_attack_damage", 0.0) * action.heal_from_attack_fraction
			heal_target.apply_damage(-heal_amount)
			if heal_amount > 0.0:
				emit_signal("combat_event", "%s heals %s for %.0f HP" % [
						character.character_id, heal_target.character_id, heal_amount])

		AbilityAction.ActionType.APPLY_BUFF:
			var buff_target: CharacterData = _resolve_action_target(character, action, target)
			if buff_target != null and action.string_param != "":
				buff_target.active_buffs[action.string_param] = 1

		AbilityAction.ActionType.APPLY_DEBUFF:
			var debuff_target: CharacterData = _resolve_action_target(character, action, target)
			if debuff_target != null and action.string_param != "":
				debuff_target.active_buffs[action.string_param] = 1

		_:
			pass  # GRANT_BONUS and other future action types remain stubs.

## Resolves the target CharacterData for an AbilityAction.
## Uses action.target_index to pick between primary_target (index 0) and
## secondary_target (index 1) for multi-target abilities such as Drain Life.
## Falls back gracefully: if the requested indexed target is null, returns
## the primary declared_target instead.
func _resolve_action_target(
		character: CharacterData,
		action: AbilityAction,
		declared_target: CharacterData,
		secondary_target: CharacterData = null) -> CharacterData:

	match action.target_type:
		AbilityAction.TargetType.SELF:
			return character
		AbilityAction.TargetType.ALLY, AbilityAction.TargetType.ENEMY, AbilityAction.TargetType.ANY:
			# For multi-target abilities, target_index selects which supplied target to use.
			if action.target_index == 1 and secondary_target != null:
				return secondary_target
			return declared_target
	return declared_target

## Simple Manhattan distance helper (ignores z/floor for range checks).
func _manhattan_distance(a: Vector3i, b: Vector3i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

## Formats a one-line combat event string for an attack result.
## Used by ability attacks and riposte so their output matches normal attack logs.
func _format_attack_event(
		attacker: CharacterData,
		target: CharacterData,
		r: AttackResolver.AttackResult,
		context_label: String = "") -> String:
	var label: String = r.weapon_name if r.weapon_name != "" else "weapon"
	if context_label != "":
		label = "%s/%s" % [label, context_label]
	if not r.hit:
		return "%s [%s] → %s: MISS (acc %d%%, roll %d)" % [
				attacker.character_id, label, target.character_id,
				r.final_accuracy, r.roll_d100]
	var hit_type: String = "CRIT!" if r.crit else "Hit"
	var rel_str: String = " [rel:%.0f%%]" % (r.reliability * 100.0) if r.reliability > 0.0 else ""
	var bonus_str: String = " +bonus>%.0f" % r.dmg_bonus_dice if r.dmg_bonus_dice != 0.0 else ""
	return "%s [%s] → %s: %s (acc %d%%, roll %d) → %.0f dmg (%dd%d%s>%.0f +%d stat%s)" % [
			attacker.character_id, label, target.character_id,
			hit_type, r.final_accuracy, r.roll_d100,
			r.damage_dealt, r.dmg_dice_count, r.dmg_dice_sides,
			rel_str, r.dmg_raw_roll, r.dmg_stat_bonus, bonus_str]

## Decrements all active ability cooldowns for the given character by 1.
## Called at the end of the character's turn so that a cooldown of 2 means
## "unavailable the next turn, available the turn after".
func _tick_cooldowns(character: CharacterData) -> void:
	var keys_to_remove: Array = []
	for key in character.ability_cooldowns:
		character.ability_cooldowns[key] -= 1
		if character.ability_cooldowns[key] <= 0:
			keys_to_remove.append(key)
	for key in keys_to_remove:
		character.ability_cooldowns.erase(key)

## Decrements all active timed buffs/debuffs for the given character by 1.
## Called at the START of the character's turn. A buff set to 1 expires
## when this character's next turn begins (lasts one full rotation of the order).
func _tick_buffs(character: CharacterData) -> void:
	var keys_to_remove: Array = []
	for key in character.active_buffs:
		character.active_buffs[key] -= 1
		if character.active_buffs[key] <= 0:
			keys_to_remove.append(key)
	for key in keys_to_remove:
		character.active_buffs.erase(key)

