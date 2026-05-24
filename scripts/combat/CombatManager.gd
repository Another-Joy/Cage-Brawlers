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
		skill: SkillData = null) -> AttackResolver.AttackResult:

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
		result = _attack_resolver.resolve_attack(attacker, target, weapon, skill)
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
		for skill in tree:
			if (skill as SkillData).has_keyword("Vault"):
				return true
	return false

## Transitions the current phase to Ending (called after Main phase action is used).
func advance_to_ending_phase() -> void:
	if _current_phase == ActionPhase.MAIN:
		_current_phase = ActionPhase.ENDING
		emit_signal("turn_started", _active_character, _current_phase)
