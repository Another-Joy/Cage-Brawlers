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
		speed = int(ceil(speed / 2.0))

	var can_vault: bool = _character_can_vault(character)
	var path: Array[Vector3i] = _pathfinding.find_path(character.grid_position, destination, can_vault)

	if path.is_empty():
		return false
	if _pathfinding.get_path_cost(path) > speed:
		return false

	# Reject if the destination tile is already occupied by a living character.
	for other in _all_characters:
		if other == character:
			continue
		if other.grid_position == destination and other.state_flag != CharacterData.StateFlag.DEAD:
			return false

	# Apply movement.
	character.grid_position = destination
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
func process_attack_action(
		attacker: CharacterData,
		target: CharacterData,
		weapon: WeaponData = null,
		skill_or_ability: SkillTreeEntry = null) -> AttackResolver.AttackResult:

	var dummy_result: AttackResolver.AttackResult = AttackResolver.AttackResult.new()
	if attacker != _active_character:
		dummy_result.rejection_reason = "Not the active character."
		return dummy_result
	if _current_phase != ActionPhase.MAIN:
		dummy_result.rejection_reason = "Not in Main phase."
		return dummy_result

	if weapon == null:
		weapon = attacker.main_hand_slot
	if weapon == null:
		dummy_result.rejection_reason = "No weapon equipped."
		return dummy_result

	var result: AttackResolver.AttackResult
	if attacker.is_dual_wielding():
		var dual_results: Array = _attack_resolver.resolve_dual_wield(attacker, target)
		# Apply damage from all valid hits.
		for r in dual_results:
			if r.valid and r.hit:
				var knocked_down: bool = target.apply_damage(r.damage_dealt)
				if knocked_down:
					_on_character_knocked_down(target)
		result = dual_results[0] if dual_results.size() > 0 else dummy_result
	else:
		result = _attack_resolver.resolve_attack(attacker, target, weapon, skill_or_ability)
		if result.valid and result.hit:
			var knocked_down: bool = target.apply_damage(result.damage_dealt)
			if knocked_down:
				_on_character_knocked_down(target)

	return result

## Called when the active character passes or performs an Ending phase action.
func process_end_turn(character: CharacterData) -> bool:
	if character != _active_character:
		return false
	if _current_phase == ActionPhase.BEGINNING or _current_phase == ActionPhase.MAIN:
		# Skip remaining phases and end the turn.
		pass
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

## Called during Beginning phase to stand up (free action, no phase slot consumed).
func process_stand_up(character: CharacterData) -> bool:
	if character != _active_character:
		return false
	if _current_phase != ActionPhase.BEGINNING:
		return false
	character.is_crouched = false
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
# Ability Execution
# ---------------------------------------------------------------------------

## Attempts to execute an AbilityData for the active character.
## target is the primary target character (may be null for self-only abilities).
## Returns false if the ability is rejected (wrong phase, failed conditions, etc.).
func process_ability(
		character: CharacterData,
		ability: AbilityData,
		target: CharacterData = null) -> bool:

	if character != _active_character:
		return false

	# Phase check: ability must be usable in the current phase.
	var phase_index: int = _current_phase as int
	if not ability.is_usable_in_phase(phase_index):
		return false

	# Condition check: all AbilityConditions must pass.
	if not _check_ability_conditions(character, ability, target):
		return false

	# Execute each action in order.
	for action in ability.actions:
		_execute_ability_action(character, action, target)

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
	return true

## Executes a single AbilityAction for a character.
## This is a thin dispatch layer; complex actions delegate to existing subsystems.
func _execute_ability_action(
		character: CharacterData,
		action: AbilityAction,
		target: CharacterData) -> void:

	match action.action_type:
		AbilityAction.ActionType.STAND_UP:
			character.is_crouched = false
		AbilityAction.ActionType.CROUCH:
			character.is_crouched = true
		AbilityAction.ActionType.MOVE:
			# MOVE actions are declared via process_move_action; this hook is for
			# abilities that grant bonus movement (e.g. a dash), not a full move phase.
			# Actual path resolution is left to the caller with the destination tile.
			pass
		AbilityAction.ActionType.ATTACK:
			if target == null or character.main_hand_slot == null:
				return
			var result: AttackResolver.AttackResult = _attack_resolver.resolve_attack(
					character, target, character.main_hand_slot)
			if result.valid and result.hit:
				var knocked_down: bool = target.apply_damage(result.damage_dealt)
				if knocked_down:
					_on_character_knocked_down(target)
		AbilityAction.ActionType.HEAL:
			var heal_amount: float = float(action.flat_bonus)
			if action.bonus_dice != null:
				heal_amount += float(action.bonus_dice.roll(_dice_roller, action.uses_reliability))
			var heal_target: CharacterData = _resolve_action_target(character, action, target)
			if heal_target != null:
				heal_target.apply_damage(-heal_amount)
		_:
			pass  # Other action types (APPLY_BUFF, GRANT_BONUS, etc.) are stubs for now.

## Resolves the target CharacterData for an AbilityAction given the ability's TargetType.
func _resolve_action_target(
		character: CharacterData,
		action: AbilityAction,
		declared_target: CharacterData) -> CharacterData:

	match action.target_type:
		AbilityAction.TargetType.SELF:
			return character
		AbilityAction.TargetType.ALLY, AbilityAction.TargetType.ENEMY, AbilityAction.TargetType.ANY:
			return declared_target
	return declared_target

## Simple Manhattan distance helper (ignores z/floor for range checks).
func _manhattan_distance(a: Vector3i, b: Vector3i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
