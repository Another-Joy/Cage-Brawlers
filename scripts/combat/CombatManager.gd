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
var _summoned_units: Array[CharacterData] = []

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
	_summoned_units.clear()

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
	_active_character.visible_to_enemy_ids_at_turn_start = _compute_enemy_visibility_at_turn_start(_active_character)

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
	if get_path_cost_for_character(character, path) > speed:
		return false

	# Reject if the destination tile is already occupied by a living character.
	for other in _all_characters:
		if other == character:
			continue
		if other.grid_position == destination and other.state_flag != CharacterData.StateFlag.DEAD:
			return false

	# Apply movement step-by-step so opportunity attacks can interrupt it.
	var triggered_opportunity_ids: Dictionary = {}
	for i in range(1, path.size()):
		var from_tile: Vector3i = path[i - 1]
		var to_tile: Vector3i = path[i]
		character.grid_position = from_tile
		if not _process_opportunity_attacks(character, from_tile, triggered_opportunity_ids):
			return false
		character.grid_position = to_tile
	character.moved_this_turn = true
	# After movement, enter PENDING_ROTATION sub-state.
	_current_phase = ActionPhase.PENDING_ROTATION
	emit_signal("facing_selection_required", character)
	return true

func get_path_cost_for_character(character: CharacterData, path: Array[Vector3i]) -> int:
	var can_vault: bool = _character_can_vault(character)
	var total_cost: int = _pathfinding.get_path_cost(path, can_vault)
	for i in range(1, path.size()):
		total_cost += _enemy_movement_aura_cost(character, path[i])
	return total_cost

func get_reachable_tiles_for_character(character: CharacterData, movement_budget: int) -> Dictionary:
	var can_vault: bool = _character_can_vault(character)
	var candidates: Dictionary = _pathfinding.get_reachable_tiles(character.grid_position, movement_budget, can_vault)
	var reachable: Dictionary = {}
	for tile in candidates:
		var path: Array[Vector3i] = _pathfinding.find_path(character.grid_position, tile, can_vault)
		if path.is_empty():
			continue
		var cost: int = get_path_cost_for_character(character, path)
		if cost <= movement_budget:
			reachable[tile] = cost
	return reachable

func _enemy_movement_aura_cost(mover: CharacterData, tile: Vector3i) -> int:
	var total: int = 0
	for other in _all_characters:
		if other == null or other == mover:
			continue
		if other.state_flag == CharacterData.StateFlag.DEAD or other.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
			continue
		if _get_owner_player_id(other) == _get_owner_player_id(mover):
			continue
		for entry in other.get_effective_skill_entries():
			if entry != null and entry.has_keyword("EnemyMoveCostAura2"):
				var dist: int = abs(other.grid_position.x - tile.x) + abs(other.grid_position.y - tile.y)
				if dist <= 2:
					total += 1
	return total

func _process_opportunity_attacks(mover: CharacterData, from_tile: Vector3i, triggered_ids: Dictionary) -> bool:
	for other in _all_characters:
		if other == null or other == mover:
			continue
		if other.state_flag == CharacterData.StateFlag.DEAD or other.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
			continue
		if _get_owner_player_id(other) == _get_owner_player_id(mover):
			continue
		if triggered_ids.has(other.character_id):
			continue
		var weapon: WeaponData = other.main_hand_slot
		if weapon == null or weapon.damage_type != WeaponData.DamageType.PHYSICAL:
			continue
		if not _get_opportunity_tiles(other).has(from_tile):
			continue
		triggered_ids[other.character_id] = true
		var results: Array = _resolve_attack_with_passive_extras(other, mover, weapon, null, null, false)
		for r in results:
			if r.valid and not r.riposte_triggered:
				emit_signal("combat_event", _format_attack_event(other, mover, r, "Opportunity Attack"))
		if mover.state_flag == CharacterData.StateFlag.DEAD or mover.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
			return false
	return true

func _get_opportunity_tiles(character: CharacterData) -> Dictionary:
	var tiles: Dictionary = {}
	var p: Vector3i = character.grid_position
	match character.facing_direction % 8:
		0:
			tiles[Vector3i(p.x - 1, p.y + 1, p.z)] = true
			tiles[Vector3i(p.x, p.y + 1, p.z)] = true
			tiles[Vector3i(p.x + 1, p.y + 1, p.z)] = true
		1:
			tiles[Vector3i(p.x, p.y + 1, p.z)] = true
			tiles[Vector3i(p.x + 1, p.y, p.z)] = true
		2:
			tiles[Vector3i(p.x + 1, p.y + 1, p.z)] = true
			tiles[Vector3i(p.x + 1, p.y, p.z)] = true
			tiles[Vector3i(p.x + 1, p.y - 1, p.z)] = true
		3:
			tiles[Vector3i(p.x + 1, p.y, p.z)] = true
			tiles[Vector3i(p.x, p.y - 1, p.z)] = true
		4:
			tiles[Vector3i(p.x + 1, p.y - 1, p.z)] = true
			tiles[Vector3i(p.x, p.y - 1, p.z)] = true
			tiles[Vector3i(p.x - 1, p.y - 1, p.z)] = true
		5:
			tiles[Vector3i(p.x, p.y - 1, p.z)] = true
			tiles[Vector3i(p.x - 1, p.y, p.z)] = true
		6:
			tiles[Vector3i(p.x - 1, p.y - 1, p.z)] = true
			tiles[Vector3i(p.x - 1, p.y, p.z)] = true
			tiles[Vector3i(p.x - 1, p.y + 1, p.z)] = true
		7:
			tiles[Vector3i(p.x - 1, p.y, p.z)] = true
			tiles[Vector3i(p.x, p.y + 1, p.z)] = true
	return tiles

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
			var is_surprise_attack: bool = _is_surprise_attack(attacker, target)
		for w in weapons:
			if w == null:
				continue
				results.append_array(_resolve_attack_with_passive_extras(attacker, target, w, skill_or_ability, null, is_surprise_attack))
			# Stop if attacker was killed or knocked down by a riposte counter-attack.
			if attacker.state_flag == CharacterData.StateFlag.DEAD \
					or attacker.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
				break
		return results
	else:
		return _resolve_attack_with_passive_extras(attacker, target, weapon, skill_or_ability, null, _is_surprise_attack(attacker, target))

func _resolve_attack_with_passive_extras(
		attacker: CharacterData,
		target: CharacterData,
		weapon: WeaponData,
		skill_or_ability: SkillTreeEntry = null,
		action: AbilityAction = null,
		is_surprise_attack: bool = false) -> Array:
	var out: Array = []
	if weapon == null:
		return out
	var primary: AttackResolver.AttackResult = _attack_resolver.resolve_attack(
			attacker, target, weapon, skill_or_ability, action, is_surprise_attack)
	_apply_attack_result_with_riposte(primary, attacker, target, weapon)
	out.append(primary)
	if not primary.valid:
		return out
	var is_ability_attack: bool = skill_or_ability is AbilityData
	var is_main_hand_attack: bool = attacker != null and weapon == attacker.main_hand_slot
	var is_off_hand_attack: bool = attacker != null and weapon == attacker.off_hand_slot
	var extra_ctx: SkillProcessor.SkillContext = SkillProcessor.SkillContext.new(
		attacker,
		SkillCondition.MajorCondition.ON_ATTACK,
		attacker,
		target,
		weapon,
		is_ability_attack,
		false,
		is_main_hand_attack,
		is_off_hand_attack)
	var extra_attacks: int = SkillProcessor.get_extra_attack_count(extra_ctx)
	for _i in range(extra_attacks):
		if attacker.state_flag == CharacterData.StateFlag.DEAD \
				or attacker.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
			break
		var extra: AttackResolver.AttackResult = _attack_resolver.resolve_attack(
				attacker, target, weapon, skill_or_ability, action, is_surprise_attack)
		_apply_attack_result_with_riposte(extra, attacker, target, weapon)
		out.append(extra)
	return out

func _compute_enemy_visibility_at_turn_start(character: CharacterData) -> Dictionary:
	var visible_to: Dictionary = {}
	if character == null:
		return visible_to
	for other in _all_characters:
		if other == null or other == character:
			continue
		if other.state_flag == CharacterData.StateFlag.DEAD or other.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
			continue
		if _get_owner_player_id(other) == _get_owner_player_id(character):
			continue
		var tiles: Dictionary = _los_manager.compute_visible_tiles(other, _map_data, _all_characters)
		if tiles.has(character.grid_position):
			visible_to[other.character_id] = true
	return visible_to

func _is_surprise_attack(attacker: CharacterData, target: CharacterData) -> bool:
	if attacker == null or target == null:
		return false
	if target.state_flag == CharacterData.StateFlag.DEAD:
		return false
	if attacker.visible_to_enemy_ids_at_turn_start.get(target.character_id, false):
		return false
	var facing_vec: Vector2 = (LineOfSightManager.DIRECTION_VECTORS[target.facing_direction] as Vector2).normalized()
	var to_attacker: Vector2 = Vector2(
		attacker.grid_position.x - target.grid_position.x,
		attacker.grid_position.y - target.grid_position.y)
	if to_attacker.length_squared() == 0.0:
		return false
	return facing_vec.dot(to_attacker.normalized()) < 0.0

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
	for entry in character.get_effective_skill_entries():
		if entry.has_keyword("Vault"):
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
		var is_main_hand_attack: bool = attacker != null and weapon == attacker.main_hand_slot
		var is_off_hand_attack: bool = attacker != null and weapon == attacker.off_hand_slot
		var reduction_ctx: SkillProcessor.SkillContext = SkillProcessor.SkillContext.new(
			target,
			SkillCondition.MajorCondition.ON_TAKE_DAMAGE,
			attacker,
			target,
			weapon,
			false,
			false,
			is_main_hand_attack,
			is_off_hand_attack)
		var passive_reduction: int = SkillProcessor.get_damage_reduction(reduction_ctx)
		result.damage_dealt = maxf(0.0, result.damage_dealt - float(passive_reduction))
		var knocked_down: bool = action != null and action.ignore_armor \
				? target.apply_direct_hp_damage(result.damage_dealt) \
				: target.apply_damage(result.damage_dealt)
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
			riposte_user, original_attacker, weapon, null, counter_action, false)

	if result.valid and result.hit:
		var is_main_hand_attack: bool = riposte_user != null and weapon == riposte_user.main_hand_slot
		var is_off_hand_attack: bool = riposte_user != null and weapon == riposte_user.off_hand_slot
		var reduction_ctx: SkillProcessor.SkillContext = SkillProcessor.SkillContext.new(
			original_attacker,
			SkillCondition.MajorCondition.ON_TAKE_DAMAGE,
			riposte_user,
			original_attacker,
			weapon,
			false,
			false,
			is_main_hand_attack,
			is_off_hand_attack)
		var passive_reduction: int = SkillProcessor.get_damage_reduction(reduction_ctx)
		result.damage_dealt = maxf(0.0, result.damage_dealt - float(passive_reduction))
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
		secondary_target: CharacterData = null,
		target_tile: Vector3i = Vector3i(-1, -1, -1),
		facing_direction: int = -1) -> bool:

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
		if not _execute_ability_action(character, action, target, ability, context, secondary_target, target_tile, facing_direction):
			return false

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
			for entry in character.get_effective_skill_entries():
				if entry.entry_id == condition.string_param:
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
		AbilityCondition.ConditionType.TARGET_IS_SURPRISE_ELIGIBLE:
			return _target != null and _is_surprise_attack(character, _target)
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
		secondary_target: CharacterData = null,
		target_tile: Vector3i = Vector3i(-1, -1, -1),
		facing_direction: int = -1) -> bool:

	match action.action_type:
		AbilityAction.ActionType.STAND_UP:
			character.is_crouched = false
			return true

		AbilityAction.ActionType.CROUCH:
			character.is_crouched = true
			return true

		AbilityAction.ActionType.MOVE:
			return _execute_ability_move(character, action, parent_ability, target_tile)

		AbilityAction.ActionType.ATTACK:
			if target == null or character.main_hand_slot == null:
				return false
			# Build the list of weapons to attack with.
			# For dual-wield characters every ATTACK action fires from both weapons
			# (e.g. 2 ATTACK actions × 2 axes = 4 total attacks for Reckless Assault).
			var attack_weapons: Array = [character.main_hand_slot]
			if character.is_dual_wielding():
				attack_weapons.append(character.off_hand_slot as WeaponData)
			var total_damage: float = 0.0
			var total_hits: int = 0
			var is_surprise_attack: bool = _is_surprise_attack(character, target)
			for w in attack_weapons:
				var action_results: Array = _resolve_attack_with_passive_extras(
						character, target, w, parent_ability, action, is_surprise_attack)
				for r in action_results:
					if r.valid and r.hit:
						total_damage += r.damage_dealt
						total_hits += 1
					# Announce result (riposte emits its own parry + counter messages).
					if r.valid and not r.riposte_triggered:
						emit_signal("combat_event", _format_attack_event(
								character, target, r, parent_ability.entry_name))
				if character.state_flag == CharacterData.StateFlag.DEAD \
						or character.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
					break
			context["last_attack_damage"] = total_damage
			context["last_attack_hits"] = total_hits
			return true

		AbilityAction.ActionType.HEAL:
			var heal_target: CharacterData = _resolve_action_target(character, action, target, secondary_target)
			if heal_target == null:
				return false
			var heal_amount: float = float(action.flat_bonus)
			var heal_dice_logs: Array[String] = []
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
				heal_dice_logs.append("weapon %dd%d=%.0f rel:%d%%" % [
					dice[0], dice[1], weapon_roll, int(roundf(reliability * 100.0))])
				heal_amount += weapon_roll * action.weapon_dice_multiplier
			elif action.bonus_dice != null:
				# Fallback: fixed bonus dice (legacy / non-weapon-derived heals).
				var bonus_roll: float = float(action.bonus_dice.roll(_dice_roller, action.uses_reliability, 0.0))
				heal_dice_logs.append("ability %dd%d=%.0f rel:%d%%" % [
					action.bonus_dice.count,
					action.bonus_dice.sides,
					bonus_roll,
					int(roundf(action.bonus_dice.reliability * 100.0)),
				])
				heal_amount += bonus_roll
			# Fraction of last attack damage (e.g. Drain Life heals 50% of damage dealt).
			if action.heal_from_attack_fraction > 0.0:
				heal_amount += context.get("last_attack_damage", 0.0) * action.heal_from_attack_fraction
			heal_target.apply_damage(-heal_amount)
			if heal_amount > 0.0:
				var dice_log: String = " | dice[%s]" % ", ".join(heal_dice_logs) if not heal_dice_logs.is_empty() else ""
				emit_signal("combat_event", "%s [%s] -> %s: HEAL%s => final_heal=%.0f" % [
						character.character_id,
						parent_ability.entry_name,
						heal_target.character_id,
						dice_log,
						heal_amount])
			return true

		AbilityAction.ActionType.APPLY_BUFF:
			var buff_target: CharacterData = _resolve_action_target(character, action, target)
			if buff_target != null and action.string_param != "":
				buff_target.active_buffs[action.string_param] = 1
			return buff_target != null

		AbilityAction.ActionType.APPLY_DEBUFF:
			var debuff_target: CharacterData = _resolve_action_target(character, action, target)
			if debuff_target != null and action.string_param != "":
				debuff_target.active_buffs[action.string_param] = 1
			return debuff_target != null

		AbilityAction.ActionType.RELOAD:
			return _execute_reload_action(character)

		AbilityAction.ActionType.AREA_DAMAGE:
			return _execute_area_damage(character, action, parent_ability, target_tile)

		AbilityAction.ActionType.SUMMON_WATCHER_EYE:
			return _summon_watcher_eye(character, parent_ability, target_tile, facing_direction)

		AbilityAction.ActionType.BREAK_SEGMENT:
			var break_target: CharacterData = _resolve_action_target(character, action, target, secondary_target)
			if break_target == null:
				return false
			if int(context.get("last_attack_hits", 0)) <= 0:
				return false
			if not break_target.has_empty_segment():
				return false
			if not break_target.break_next_segment():
				return false
			emit_signal("combat_event", "%s [%s] breaks one of %s's health segments." % [
					character.character_id,
					parent_ability.entry_name,
					break_target.character_id])
			return true

		AbilityAction.ActionType.MEND_BROKEN_SEGMENT:
			var mend_target: CharacterData = _resolve_action_target(character, action, target, secondary_target)
			if mend_target == null:
				return false
			if not mend_target.mend_broken_segment():
				return false
			emit_signal("combat_event", "%s [%s] mends one of %s's broken health segments." % [
					character.character_id,
					parent_ability.entry_name,
					mend_target.character_id])
			return true

		_:
			return false  # GRANT_BONUS and other future action types remain stubs.

func _execute_ability_move(character: CharacterData, action: AbilityAction, parent_ability: AbilityData, target_tile: Vector3i) -> bool:
	if not _map_data.is_valid_tile(target_tile):
		return false
	var max_range: int = action.range_override if action.range_override > 0 else character.get_base_movement_speed()
	max_range = mini(max_range, character.get_base_movement_speed())
	if _manhattan_distance(character.grid_position, target_tile) > max_range:
		return false
	var can_vault: bool = _character_can_vault(character)
	var path: Array[Vector3i] = _pathfinding.find_path(character.grid_position, target_tile, can_vault)
	if path.is_empty():
		return false
	if get_path_cost_for_character(character, path) > max_range:
		return false
	var triggered_opportunity_ids: Dictionary = {}
	for i in range(1, path.size()):
		var from_tile: Vector3i = path[i - 1]
		var to_tile: Vector3i = path[i]
		character.grid_position = from_tile
		if not _process_opportunity_attacks(character, from_tile, triggered_opportunity_ids):
			return false
		character.grid_position = to_tile
	for other in _all_characters:
		if other == character:
			continue
		if other.state_flag != CharacterData.StateFlag.DEAD and other.grid_position == target_tile:
			return false
	character.moved_this_turn = true
	if not parent_ability.prevents_stand_up and character.is_crouched:
		character.is_crouched = false
	return true

func _execute_reload_action(character: CharacterData) -> bool:
	if character.main_hand_slot == null or not character.main_hand_slot.has_magazine():
		return false
	var loaded: int = character.reload_weapon(character.main_hand_slot)
	if loaded <= 0:
		return false
	emit_signal("combat_event", "%s reloads %s (+%d)." % [
		character.character_id,
		character.main_hand_slot.item_name,
		loaded])
	return true

func _execute_area_damage(character: CharacterData, action: AbilityAction, parent_ability: AbilityData, target_tile: Vector3i) -> bool:
	if not _map_data.is_valid_tile(target_tile):
		return false
	var effective_range: int = _get_ability_action_range(character, parent_ability, action)
	if effective_range > 0 and _manhattan_distance(character.grid_position, target_tile) > effective_range:
		return false
	var candidate_tiles: Array[Vector3i] = _tiles_in_radius(target_tile, maxi(0, action.area_radius))
	if candidate_tiles.is_empty():
		return false
	var affected_tiles: Array[Vector3i] = candidate_tiles
	if action.random_tile_count > 0:
		affected_tiles = _pick_priority_random_tiles(character, candidate_tiles, action.random_tile_count)
	var hit_any: bool = false
	for tile in affected_tiles:
		var victim: CharacterData = _living_character_at_tile(tile)
		if victim == null:
			continue
		var damage: float = _roll_ability_direct_damage(character, parent_ability, action)
		_apply_direct_damage(character, victim, damage)
		emit_signal("combat_event", "%s [%s] hits %s at (%d,%d) for %.0f." % [
			character.character_id,
			parent_ability.entry_name,
			victim.character_id,
			tile.x,
			tile.y,
			damage])
		hit_any = true
	if not hit_any:
		emit_signal("combat_event", "%s [%s] strikes empty tiles." % [character.character_id, parent_ability.entry_name])
	return true

func _summon_watcher_eye(character: CharacterData, parent_ability: AbilityData, target_tile: Vector3i, facing_direction: int) -> bool:
	if not _map_data.is_valid_tile(target_tile):
		return false
	if facing_direction < 0 or facing_direction > 7:
		return false
	var effective_range: int = _get_ability_action_range(character, parent_ability, null)
	if effective_range > 0 and _manhattan_distance(character.grid_position, target_tile) > effective_range:
		return false
	for other in _all_characters:
		if other.state_flag != CharacterData.StateFlag.DEAD and other.grid_position == target_tile:
			return false
	var eye: CharacterData = CharacterData.new()
	eye.character_id = "%s_watchers_eye_%d" % [character.character_id, Time.get_unix_time_from_system()]
	eye.character_name = "Watcher's Eye"
	eye.level = 1
	eye.grid_position = target_tile
	eye.facing_direction = facing_direction
	eye.segment_hp = [1.0]
	eye.segment_disabled = [false]
	eye.armor_hp = 0.0
	eye.armor_max_hp = 0.0
	eye.state_flag = CharacterData.StateFlag.KNOCKED_DOWN
	eye.summoned_owner_player_id = _get_owner_player_id(character)
	eye.is_summoned_watcher_eye = true
	_all_characters.append(eye)
	_summoned_units.append(eye)
	emit_signal("combat_event", "%s conjures a Watcher's Eye at (%d,%d)." % [
		character.character_id,
		target_tile.x,
		target_tile.y])
	return true

func _get_ability_action_range(character: CharacterData, parent_ability: AbilityData, action: AbilityAction) -> int:
	if action != null and action.range_override > 0:
		return action.range_override
	if parent_ability != null and parent_ability.range_modifier != 0:
		var base_range: int = character.main_hand_slot.attack_range if character.main_hand_slot != null else 0
		return maxi(0, base_range + parent_ability.range_modifier)
	if parent_ability != null and parent_ability.uses_tile_targeting() and character.main_hand_slot != null:
		return character.main_hand_slot.attack_range
	return 0

func _tiles_in_radius(center: Vector3i, radius: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for tile in _map_data.tiles:
		if tile.z != center.z:
			continue
		if maxi(abs(tile.x - center.x), abs(tile.y - center.y)) <= radius:
			out.append(tile)
	return out

func _pick_priority_random_tiles(character: CharacterData, candidate_tiles: Array[Vector3i], count: int) -> Array[Vector3i]:
	var enemies: Array[Vector3i] = []
	var allies: Array[Vector3i] = []
	var empties: Array[Vector3i] = []
	var owner_player: String = _get_owner_player_id(character)
	for tile in candidate_tiles:
		var occupant: CharacterData = _living_character_at_tile(tile)
		if occupant == null:
			empties.append(tile)
		elif _get_owner_player_id(occupant) == owner_player:
			allies.append(tile)
		else:
			enemies.append(tile)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	_shuffle_tiles(enemies, rng)
	_shuffle_tiles(allies, rng)
	_shuffle_tiles(empties, rng)
	var out: Array[Vector3i] = []
	for bucket in [enemies, allies, empties]:
		for tile in bucket:
			if out.size() >= count:
				return out
			out.append(tile)
	return out

func _shuffle_tiles(tiles: Array[Vector3i], rng: RandomNumberGenerator) -> void:
	for i in range(tiles.size() - 1, 0, -1):
		var j: int = int(rng.randi_range(0, i))
		var tmp: Vector3i = tiles[i]
		tiles[i] = tiles[j]
		tiles[j] = tmp

func _living_character_at_tile(tile: Vector3i) -> CharacterData:
	for other in _all_characters:
		if other.state_flag == CharacterData.StateFlag.DEAD:
			continue
		if other.grid_position == tile:
			return other
	return null

func _roll_ability_direct_damage(character: CharacterData, parent_ability: AbilityData, action: AbilityAction) -> float:
	var damage: float = float(action.flat_bonus)
	var reliability_bonus: float = 0.0
	if parent_ability != null:
		reliability_bonus += parent_ability.reliability_modifier_percent / 100.0
	reliability_bonus += action.reliability_modifier_percent / 100.0
	if action.uses_weapon_dice and character.main_hand_slot != null:
		var weapon: WeaponData = character.main_hand_slot
		var is_two_handed_grip: bool = weapon.is_versatile() and character.off_hand_slot == null
		var dice: Array[int] = weapon.get_effective_damage_dice(is_two_handed_grip)
		if parent_ability != null:
			dice[0] = AbilityData.apply_dice_count_modifier(dice[0], parent_ability.dice_count_modifier)
			dice[1] = AbilityData.apply_dice_tier_modifier(dice[1], parent_ability.dice_tier_modifier)
		var reliability: float = clampf(weapon.base_reliability + reliability_bonus, 0.0, 1.0)
		damage += float(_dice_roller.roll_dice(dice[0], dice[1], reliability > 0.0, reliability))
	if action.bonus_dice != null:
		damage += float(action.bonus_dice.roll(_dice_roller, action.uses_reliability, reliability_bonus))
	return damage

func _apply_direct_damage(attacker: CharacterData, target: CharacterData, damage: float) -> void:
	var weapon: WeaponData = attacker.main_hand_slot
	var is_main_hand_attack: bool = attacker != null and weapon == attacker.main_hand_slot
	var is_off_hand_attack: bool = attacker != null and weapon == attacker.off_hand_slot
	var reduction_ctx: SkillProcessor.SkillContext = SkillProcessor.SkillContext.new(
		target,
		SkillCondition.MajorCondition.ON_TAKE_DAMAGE,
		attacker,
		target,
		weapon,
		false,
		false,
		is_main_hand_attack,
		is_off_hand_attack)
	var passive_reduction: int = SkillProcessor.get_damage_reduction(reduction_ctx)
	var final_damage: float = maxf(0.0, damage - float(passive_reduction))
	var knocked_down: bool = target.apply_damage(final_damage)
	if knocked_down:
		_on_character_knocked_down(target)

func _get_owner_player_id(character: CharacterData) -> String:
	if character == null:
		return ""
	if character.summoned_owner_player_id != "":
		return character.summoned_owner_player_id
	for player_id in _team_map:
		if _team_map[player_id].has(character):
			return player_id
	return ""

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
	var acc_breakdown: String = (
		"acc %d = base %d + stat %d + skill %d + ctx %d + ability %d - evasion %d"
		% [
			r.final_accuracy,
			r.acc_base,
			r.acc_stat_bonus,
			r.acc_skill_bonus,
			r.acc_context_mod,
			r.acc_ability_mod,
			r.acc_evasion,
		]
	)
	var dice_parts: Array[String] = []
	for d in r.dice_roll_details:
		dice_parts.append("%s %dd%d=%.0f rel:%d%%" % [
			str(d.get("source", "dice")),
			int(d.get("count", 0)),
			int(d.get("sides", 0)),
			float(d.get("roll", 0.0)),
			int(roundf(float(d.get("reliability", 0.0)) * 100.0)),
		])
	var dice_log: String = " | dice[%s]" % ", ".join(dice_parts) if not dice_parts.is_empty() else ""
	if not r.hit:
		return "%s [%s] -> %s: MISS (%s, d100=%d)%s" % [
				attacker.character_id, label, target.character_id,
				acc_breakdown, r.roll_d100, dice_log]
	var hit_type: String = "CRIT!" if r.crit else "Hit"
	var crit_tag: String = " crit" if r.crit else ""
	var armor_str: String = " armor_absorb=%.0f" % r.armor_absorbed if r.armor_absorbed > 0.0 else ""
	return "%s [%s] -> %s: %s%s (%s, d100=%d)%s | total_dice=%.0f + stat=%d + flat_bonus=%.0f%s => final_damage=%.0f" % [
			attacker.character_id, label, target.character_id,
			hit_type, crit_tag, acc_breakdown, r.roll_d100,
			dice_log, r.dmg_raw_roll, r.dmg_stat_bonus, r.dmg_bonus_dice, armor_str, r.damage_dealt]

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

