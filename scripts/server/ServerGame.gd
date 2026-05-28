## ServerGame.gd
## Server-side game orchestrator.
##
## Responsibilities:
##   - Receive party rosters from both clients, build teams from the supplied
##     CharacterData dictionaries, then start a match.
##   - Handle action packets from clients.
##   - Serialise and broadcast per-player game state (with fog-of-war) after
##     every state change.
##   - Filter event-log messages so players only see what they should.
extends Node

# ---------------------------------------------------------------------------
# Signals (consumed by Main.gd to dispatch RPCs)
# ---------------------------------------------------------------------------

## Per-player state snapshot (fog-of-war applied).
signal state_updated_for_peer(peer_id: int, state: Dictionary)
## Per-player event log (only events visible to that player).
signal event_logged_for_peer(peer_id: int, message: String)
## Event visible to all players (e.g. match start).
signal broadcast_event(message: String)
## Emitted once both rosters are received and the match is ready to start.
## Main.gd uses this to send rpc_start_battle to each peer.
signal battle_ready(peer_a_id: int, peer_b_id: int)

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _match_manager: MatchManager = null
var _dice_roller: DiceRoller = DiceRoller.new()
var _map_data: MapData = null
var _los_manager: LineOfSightManager = LineOfSightManager.new()

## peer_id (int) → player_id (String)
var _peer_to_player: Dictionary = {}
## player_id (String) → peer_id (int)
var _player_to_peer: Dictionary = {}
## char_id (String) → CharacterData
var _char_lookup: Dictionary = {}
## player_id (String) → Array[CharacterData]
var _team_map: Dictionary = {}
## ability_id (String) → AbilityData: loaded once at match start.
var _ability_registry: Dictionary = {}

var _match_running: bool = false

## Rosters waiting: peer_id → Array of char dicts (received but not yet started)
var _pending_rosters: Dictionary = {}

# ---------------------------------------------------------------------------
# Roster reception & match start
# ---------------------------------------------------------------------------

## Called by Main.rpc_send_roster when a client sends their party data.
func receive_client_roster(peer_id: int, party_dicts: Array) -> void:
	if _match_running:
		push_warning("[ServerGame] Roster from peer %d ignored (match already running)." % peer_id)
		return
	print("[ServerGame] Received roster from peer %d (%d chars)." % [peer_id, party_dicts.size()])
	_pending_rosters[peer_id] = party_dicts

	if _pending_rosters.size() >= 2:
		_start_match_from_rosters()

func _start_match_from_rosters() -> void:
	if _match_running:
		return
	_match_running = true
	print("[ServerGame] Both rosters received — building match…")

	_load_ability_registry()
	_build_test_map()

	var peer_ids: Array = _pending_rosters.keys()
	var peer_a: int = peer_ids[0]
	var peer_b: int = peer_ids[1]

	_peer_to_player[peer_a] = "player_a"
	_peer_to_player[peer_b] = "player_b"
	_player_to_peer["player_a"] = peer_a
	_player_to_peer["player_b"] = peer_b

	var team_a: Array[CharacterData] = _build_team_from_roster(_pending_rosters[peer_a], "player_a")
	var team_b: Array[CharacterData] = _build_team_from_roster(_pending_rosters[peer_b], "player_b")
	_pending_rosters.clear()

	_team_map["player_a"] = team_a
	_team_map["player_b"] = team_b

	for player_id in _team_map:
		for char_data in _team_map[player_id]:
			_char_lookup[char_data.character_id] = char_data

	# Place characters on spawn tiles.
	var spawns_a: Array[Vector3i] = [
		Vector3i(0, 1, 0), Vector3i(0, 4, 0), Vector3i(0, 6, 0),
	]
	var spawns_b: Array[Vector3i] = [
		Vector3i(11, 1, 0), Vector3i(11, 4, 0), Vector3i(11, 6, 0),
	]
	for i in mini(team_a.size(), spawns_a.size()):
		team_a[i].grid_position = spawns_a[i]
	for i in mini(team_b.size(), spawns_b.size()):
		team_b[i].grid_position = spawns_b[i]

	# Build PlayerProfile objects.
	var profile_a: PlayerProfile = PlayerProfile.new()
	profile_a.player_id = "player_a"
	profile_a.display_name = "Player A"
	profile_a.roster = team_a.duplicate()

	var profile_b: PlayerProfile = PlayerProfile.new()
	profile_b.player_id = "player_b"
	profile_b.display_name = "Player B"
	profile_b.roster = team_b.duplicate()

	_match_manager = MatchManager.new()
	add_child(_match_manager)
	_match_manager.register_player(profile_a)
	_match_manager.register_player(profile_b)
	_match_manager.set_map(_map_data)
	_match_manager.match_ended_with_results.connect(_on_match_ended)
	_match_manager.lock_teams()
	_match_manager.start_match()

	_match_manager._combat_manager.combat_event.connect(_on_combat_event)

	print("[ServerGame] Match started!")
	emit_signal("broadcast_event", "=== MATCH STARTED ===")
	emit_signal("battle_ready", peer_a, peer_b)
	_broadcast_state_all()

## Builds an Array[CharacterData] from a list of serialised party dicts.
## Prefixes each char_id with player_id to prevent cross-player ID collisions.
func _build_team_from_roster(dicts: Array, player_id: String) -> Array[CharacterData]:
	var team: Array[CharacterData] = []
	for d in dicts:
		var dict: Dictionary = d as Dictionary
		var cd: CharacterData = RosterManager.dict_to_char(dict)
		# Prefix the ID to ensure uniqueness across both teams.
		cd.character_id = "%s_%s" % [player_id, cd.character_id]
		ClassDefinitions.initialise_character_health(cd)
		cd.initialise_armor_hp()
		# Inject the abilities the player selected in the lobby.
		var ability_ids: Array = dict.get("ability_ids", [])
		_inject_abilities(cd, ability_ids)
		team.append(cd)
	return team

# ---------------------------------------------------------------------------
# Client action handler
# ---------------------------------------------------------------------------

func handle_action(peer_id: int, action: Dictionary) -> void:
	if not _match_running:
		return
	var combat: CombatManager = _match_manager._combat_manager
	if combat == null:
		return

	var player_id: String = _peer_to_player.get(peer_id, "")
	var action_type: String = action.get("type", "")
	var char_id: String = action.get("char_id", "")
	var char_data: CharacterData = _char_lookup.get(char_id, null)
	if char_data == null:
		_send_event(peer_id, "WARN: unknown char_id '%s'" % char_id)
		return

	# Only allow controlling own characters.
	if _get_player_id_for_char(char_data) != player_id:
		_send_event(peer_id, "WARN: you do not control '%s'." % char_id)
		return

	var log_msg: String = ""

	match action_type:
		"move":
			var d: Dictionary = action.get("dest", {})
			var dest: Vector3i = Vector3i(d.get("x", 0), d.get("y", 0), d.get("z", 0))
			if combat.process_move_action(char_data, dest):
				log_msg = "%s moved to (%d,%d)." % [char_data.character_name, dest.x, dest.y]
			else:
				log_msg = "%s: move to (%d,%d) rejected." % [char_data.character_name, dest.x, dest.y]

		"facing":
			var dir: int = action.get("direction", 0)
			if combat.process_facing_selection(char_data, dir):
				var dir_names: Array = ["N","NE","E","SE","S","SW","W","NW"]
				log_msg = "%s now faces %s." % [char_data.character_name, dir_names[dir]]
			else:
				log_msg = "%s: facing rejected." % char_data.character_name

		"skip_beginning":
			if combat.process_skip_beginning(char_data):
				log_msg = "%s skipped Beginning phase." % char_data.character_name
			else:
				log_msg = "%s: skip beginning rejected." % char_data.character_name

		"attack":
			var target_id: String = action.get("target_id", "")
			var target: CharacterData = _char_lookup.get(target_id, null)
			if target == null:
				_send_event(peer_id, "WARN: unknown target_id '%s'" % target_id)
				return
			var results: Array = combat.process_attack_action(char_data, target)
			var any_valid: bool = false
			for res in results:
				var r: AttackResolver.AttackResult = res as AttackResolver.AttackResult
				if not r.valid:
					_send_event(peer_id, "%s → %s: REJECTED (%s)" % [
						char_data.character_name, target.character_name, r.rejection_reason])
				else:
					any_valid = true
					var msg: String = _format_attack_log(char_data, target, r)
					_emit_event_for_action(msg, char_data, target)
			if any_valid:
				combat.advance_to_ending_phase()

		"skip_main":
			if combat._current_phase == CombatManager.ActionPhase.MAIN:
				combat.advance_to_ending_phase()
				log_msg = "%s skipped Main phase." % char_data.character_name
			else:
				log_msg = "%s: skip main rejected (not in Main phase)." % char_data.character_name

		"crouch":
			if combat.process_crouch_action(char_data):
				log_msg = "%s crouched." % char_data.character_name
			else:
				log_msg = "%s: crouch rejected (no adjacent barricade)." % char_data.character_name

		"stand_up":
			if combat.process_stand_up(char_data):
				log_msg = "%s stood up." % char_data.character_name
			else:
				log_msg = "%s: stand-up rejected." % char_data.character_name

		"end_turn":
			if combat.process_end_turn(char_data):
				log_msg = "%s ended their turn." % char_data.character_name
			else:
				log_msg = "%s: end turn rejected." % char_data.character_name

		"ability":
			var ability_id: String = action.get("ability_id", "")
			var ability: AbilityData = _ability_registry.get(ability_id, null)
			if ability == null:
				_send_event(peer_id, "WARN: unknown ability_id '%s'" % ability_id)
				return
			var target_id: String = action.get("target_id", "")
			var target: CharacterData = _char_lookup.get(target_id, null) if target_id != "" else null
			if combat.process_ability(char_data, ability, target):
				log_msg = "%s used %s." % [char_data.character_name, ability.entry_name]
				if ability.is_main_ability():
					combat.advance_to_ending_phase()
			else:
				log_msg = "%s: ability '%s' rejected." % [char_data.character_name, ability.entry_name]

		_:
			_send_event(peer_id, "WARN: unknown action type '%s'" % action_type)
			return

	if log_msg:
		_emit_event_for_action(log_msg, char_data, null)
	_broadcast_state_all()

# ---------------------------------------------------------------------------
# Combat event passthrough (from CombatManager)
# ---------------------------------------------------------------------------

func _on_combat_event(msg: String) -> void:
	# Broadcast all internal combat events to all players for now.
	# Event log filtering for ability-triggered attacks is handled here.
	emit_signal("broadcast_event", msg)

# ---------------------------------------------------------------------------
# Event log routing
# ---------------------------------------------------------------------------

## Sends an event message to a single peer.
func _send_event(peer_id: int, message: String) -> void:
	emit_signal("event_logged_for_peer", peer_id, message)

## Routes an event to the correct set of players.
##   - If acting_char is null: broadcast to everyone.
##   - If target is null: only visible to players who can see acting_char.
##   - If target is not null: visible to the acting_char's player and to the
##     target's player (regardless of visibility — being attacked always informs you).
func _emit_event_for_action(message: String, acting_char: CharacterData, target: CharacterData) -> void:
	if acting_char == null:
		emit_signal("broadcast_event", message)
		return

	var acting_player: String = _get_player_id_for_char(acting_char)
	for player_id in _team_map:
		var peer_id: int = _player_to_peer.get(player_id, -1)
		if peer_id < 0:
			continue
		# Always show to the player whose char is acting.
		if player_id == acting_player:
			emit_signal("event_logged_for_peer", peer_id, message)
			continue
		# If there is a target owned by this player, always show (you know you were attacked).
		if target != null and _get_player_id_for_char(target) == player_id:
			emit_signal("event_logged_for_peer", peer_id, message)
			continue
		# Otherwise only show if the acting char is in a visible tile.
		var visible: Dictionary = _compute_player_visible_tiles(player_id)
		if visible.has(acting_char.grid_position):
			emit_signal("event_logged_for_peer", peer_id, message)

# ---------------------------------------------------------------------------
# Per-player state broadcast
# ---------------------------------------------------------------------------

func _broadcast_state_all() -> void:
	for player_id in _team_map:
		var peer_id: int = _player_to_peer.get(player_id, -1)
		if peer_id < 0:
			continue
		var state: Dictionary = _serialize_state_for_player(player_id)
		emit_signal("state_updated_for_peer", peer_id, state)

# ---------------------------------------------------------------------------
# State serialization (per-player, with fog of war)
# ---------------------------------------------------------------------------

func _serialize_state_for_player(player_id: String) -> Dictionary:
	var combat: CombatManager = _match_manager._combat_manager if _match_manager else null
	var visible_tiles: Dictionary = _compute_player_visible_tiles(player_id)

	var chars_out: Array = []
	for pid in _team_map:
		for char_data in _team_map[pid]:
			# For the owning player, always include with full info.
			var is_mine: bool = (pid == player_id)
			# For enemies, only include if their tile is visible.
			if not is_mine and not visible_tiles.has(char_data.grid_position):
				continue
			chars_out.append(_serialize_char(char_data, pid, is_mine))

	# Visible tile list for the client to darken non-visible tiles.
	var vis_array: Array = []
	for tile in visible_tiles:
		vis_array.append({"x": tile.x, "y": tile.y})

	var turn_order: Array = []
	var active_char_id: String = ""
	var phase_str: String = "none"
	var round_num: int = 0

	if combat:
		for cd in combat._initiative_manager.turn_order:
			turn_order.append(cd.character_id)
		if combat._active_character:
			active_char_id = combat._active_character.character_id
		phase_str = _phase_name(combat._current_phase)
		round_num = combat._round_number

	var movable_tiles: Array = []
	var attackable_targets: Array = []
	if combat and active_char_id != "":
		var active_char: CharacterData = _char_lookup.get(active_char_id, null)
		var active_player_id: String = _get_player_id_for_char(active_char)
		# Only show movable/attackable info for the requesting player's active char.
		if active_char != null and active_player_id == player_id:
			if phase_str == "beginning" and not active_char.moved_this_turn and not active_char.is_crouched:
				var speed: int = active_char.get_base_movement_speed()
				if active_char.stood_up_this_turn:
					speed = int(ceil(speed / 2.0))
				var can_vault: bool = _char_can_vault(active_char)
				var reachable: Dictionary = combat._pathfinding.get_reachable_tiles(active_char.grid_position, speed, can_vault)
				for tile in reachable:
					if tile == active_char.grid_position:
						continue
					var occupied: bool = false
					for other in combat._all_characters:
						if other.character_id != active_char_id \
								and other.grid_position == tile \
								and other.state_flag != CharacterData.StateFlag.DEAD:
							occupied = true
							break
					if not occupied:
						movable_tiles.append({"x": tile.x, "y": tile.y})
			if phase_str == "main" and active_char.main_hand_slot != null:
				var atk_range: int = active_char.main_hand_slot.attack_range
				for other in combat._all_characters:
					if other.character_id == active_char_id:
						continue
					if other.state_flag == CharacterData.StateFlag.DEAD:
						continue
					var dist: int = abs(active_char.grid_position.x - other.grid_position.x) \
							+ abs(active_char.grid_position.y - other.grid_position.y)
					if dist <= atk_range:
						if _get_player_id_for_char(other) != active_player_id:
							attackable_targets.append(other.character_id)

	return {
		"my_player_id":      player_id,
		"map":               _serialize_map(),
		"characters":        chars_out,
		"turn_order":        turn_order,
		"active_char":       active_char_id,
		"phase":             phase_str,
		"round":             round_num,
		"movable_tiles":     movable_tiles,
		"attackable_targets": attackable_targets,
		"visible_tiles":     vis_array,
	}

## Computes the union of visible tiles for all of player_id's living characters.
func _compute_player_visible_tiles(player_id: String) -> Dictionary:
	if not _map_data or not _team_map.has(player_id):
		return {}
	var all_chars: Array[CharacterData] = []
	for pid in _team_map:
		for cd in _team_map[pid]:
			all_chars.append(cd)
	var union: Dictionary = {}
	for cd in _team_map[player_id]:
		if cd.state_flag == CharacterData.StateFlag.DEAD:
			continue
		var tiles: Dictionary = _los_manager.compute_visible_tiles(cd, _map_data, all_chars)
		for tile in tiles:
			union[tile] = true
	return union

func _serialize_char(char_data: CharacterData, player_id: String, full_info: bool) -> Dictionary:
	var max_hp: float = char_data.get_max_hp()
	var pcts: Array[float]
	if char_data.class_data != null and not char_data.class_data.health_segment_percentages.is_empty():
		pcts = char_data.class_data.health_segment_percentages
	else:
		pcts = ClassDefinitions.get_segment_percentages(char_data.character_class)
	var seg_hp: Array = []
	var seg_max: Array = []
	var seg_disabled: Array = []
	for i in char_data.segment_hp.size():
		seg_hp.append(char_data.segment_hp[i])
		seg_max.append(max_hp * (pcts[i] if i < pcts.size() else 0.33))
		seg_disabled.append(char_data.segment_disabled[i])

	# ── Equipment snapshot ─────────────────────────────────────────────────
	var equip: Dictionary = {}
	if char_data.main_hand_slot:
		var w: WeaponData = char_data.main_hand_slot
		equip["main_hand"] = {
			"name":        w.item_name,
			"damage":      "%dd%d" % [w.damage_dice_count, w.damage_dice_sides],
			"range":       w.attack_range,
			"damage_type": w.get_damage_type_name(),
			"keywords":    w.keywords.duplicate(),
			"reliability": w.base_reliability,
		}
	if char_data.off_hand_slot:
		var e: EquipmentData = char_data.off_hand_slot
		var ohd: Dictionary = {"name": e.item_name}
		if e is WeaponData:
			var woff: WeaponData = e as WeaponData
			ohd["kind"]     = "weapon"
			ohd["damage"]   = "%dd%d" % [woff.damage_dice_count, woff.damage_dice_sides]
			ohd["range"]    = woff.attack_range
			ohd["keywords"] = woff.keywords.duplicate()
		elif e is ShieldData:
			ohd["kind"]          = "shield"
			ohd["evasion_bonus"] = (e as ShieldData).evasion_bonus
		else:
			ohd["kind"] = "item"
		equip["off_hand"] = ohd
	if char_data.armor_slot:
		var a: ArmorData = char_data.armor_slot
		equip["armor"] = {
			"name":     a.item_name,
			"av":       a.armor_value,
			"evasion":  a.evasion_modifier,
			"movement": a.movement_modifier,
		}

	# ── Abilities ──────────────────────────────────────────────────────────
	var abilities_out: Array = []
	for tree in char_data.skill_trees:
		for entry in tree:
			if entry is AbilityData:
				var ab: AbilityData = entry as AbilityData
				abilities_out.append({
					"id":       ab.entry_id,
					"name":     ab.entry_name,
					"phases":   ab.phases,
					"cooldown_turns": ab.cooldown_turns,
					"cooldown_remaining": char_data.ability_cooldowns.get(ab.entry_id, 0),
					"needs_target": _ability_needs_target(ab),
					"target_count": ab.target_count,
				})

	var base: Dictionary = {
		"id":           char_data.character_id,
		"name":         char_data.character_name,
		"class":        char_data.character_class,
		"player_id":    player_id,
		"state":        char_data.state_flag,
		"pos":          {"x": char_data.grid_position.x, "y": char_data.grid_position.y, "z": char_data.grid_position.z},
		"facing":       char_data.facing_direction,
		"is_crouched":  char_data.is_crouched,
		"equipment":    equip,
		"abilities":    abilities_out,
		"active_buffs": char_data.active_buffs.keys(),
	}

	if full_info:
		# Owner: full numeric HP.
		base["hp_segments"]  = seg_hp
		base["hp_seg_max"]   = seg_max
		base["hp_disabled"]  = seg_disabled
		base["armor_hp"]     = char_data.armor_hp
		base["armor_max_hp"] = char_data.armor_max_hp
	else:
		# Opponent: only a health state label.
		base["hp_state"] = _get_hp_state_label(char_data)

	return base

## Returns a coarse health descriptor for enemy characters.
func _get_hp_state_label(cd: CharacterData) -> String:
	if cd.state_flag == CharacterData.StateFlag.DEAD:
		return "Dead"
	if cd.state_flag == CharacterData.StateFlag.KNOCKED_DOWN:
		return "Knocked Down"
	var current: float = cd.get_current_hp()
	var max_hp: float = cd.get_max_hp()
	if max_hp <= 0.0:
		return "Unknown"
	var ratio: float = current / max_hp
	if ratio > 0.75:
		return "Unscathed"
	elif ratio > 0.50:
		return "Bruised"
	elif ratio > 0.25:
		return "Bloodied"
	else:
		return "Heavily Bloodied"

func _serialize_map() -> Dictionary:
	var tile_list: Array = []
	for t in _map_data.tiles:
		tile_list.append({"x": t.x, "y": t.y, "z": t.z})

	var boundary_list: Array = []
	var seen: Dictionary = {}
	for tile in _map_data.tiles:
		for nb in _map_data.get_adjacent_tiles(tile):
			var key: String = _bd_key(tile, nb)
			if seen.has(key):
				continue
			seen[key] = true
			var bd: BoundaryData = _map_data.get_boundary(tile, nb)
			if bd == null:
				continue
			boundary_list.append({
				"a":         {"x": tile.x, "y": tile.y, "z": tile.z},
				"b":         {"x": nb.x,   "y": nb.y,   "z": nb.z},
				"wall":      bd.has_wall,
				"barricade": bd.has_barricade,
				"ladder":    bd.has_ladder,
			})

	return {"tiles": tile_list, "boundaries": boundary_list}

func _bd_key(a: Vector3i, b: Vector3i) -> String:
	var sa: String = "%d,%d,%d" % [a.x, a.y, a.z]
	var sb: String = "%d,%d,%d" % [b.x, b.y, b.z]
	return (sa + "|" + sb) if sa < sb else (sb + "|" + sa)

func _phase_name(phase: CombatManager.ActionPhase) -> String:
	match phase:
		CombatManager.ActionPhase.BEGINNING:         return "beginning"
		CombatManager.ActionPhase.PENDING_ROTATION:  return "pending_rotation"
		CombatManager.ActionPhase.MAIN:              return "main"
		CombatManager.ActionPhase.ENDING:            return "ending"
		CombatManager.ActionPhase.DONE:              return "done"
	return "unknown"

# ---------------------------------------------------------------------------
# Attack log formatting
# ---------------------------------------------------------------------------

func _format_attack_log(attacker: CharacterData, target: CharacterData, r: AttackResolver.AttackResult) -> String:
	var weapon_label: String = r.weapon_name if r.weapon_name != "" else "weapon"
	if not r.hit:
		return "%s [%s] → %s: MISS (%d base +%d acc %d cover -%d evasion = %d%%, roll %d)" % [
			attacker.character_name, weapon_label, target.character_name,
			r.acc_base, r.acc_stat_bonus, r.acc_ability_mod, r.acc_evasion,
			r.final_accuracy, r.roll_d100]

	var hit_type: String = "CRIT!" if r.crit else "Hit"
	var rel_str: String = " [rel:%.0f%%]" % (r.reliability * 100.0) if r.reliability > 0.0 else ""
	var dice_str: String = "%dd%d%s>%.0f" % [r.dmg_dice_count, r.dmg_dice_sides, rel_str, r.dmg_raw_roll]
	var stat_str: String = ("+%d stat" % r.dmg_stat_bonus) if r.dmg_stat_bonus >= 0 else ("%d stat" % r.dmg_stat_bonus)
	var bonus_str: String = ""
	if r.dmg_bonus_dice != 0.0:
		bonus_str = " +bonus>%.0f" % r.dmg_bonus_dice
	var extras: String = ""
	if r.cover_penalty_applied:
		extras += " [cover]"
	if r.ammo_consumed:
		extras += " [ammo]"
	return "%s [%s] → %s: %s (%d base +%d acc %d cover -%d evasion = %d%%, roll %d)\n  %.0f dmg (%s %s%s)%s" % [
		attacker.character_name, weapon_label, target.character_name,
		hit_type,
		r.acc_base, r.acc_stat_bonus, r.acc_ability_mod, r.acc_evasion,
		r.final_accuracy, r.roll_d100,
		r.damage_dealt, dice_str, stat_str, bonus_str, extras]

# ---------------------------------------------------------------------------
# Match end
# ---------------------------------------------------------------------------

func _on_match_ended(winner_player_id: String, _results: Dictionary) -> void:
	_match_running = false
	emit_signal("broadcast_event", "=== MATCH OVER — Winner: %s ===" % winner_player_id)
	_broadcast_state_all()

# ---------------------------------------------------------------------------
# Test map
# ---------------------------------------------------------------------------

func _build_test_map() -> void:
	_map_data = MapData.new()
	for x in range(12):
		for y in range(8):
			_map_data.tiles.append(Vector3i(x, y, 0))

	for y in range(1, 6):
		var bd: BoundaryData = BoundaryData.new()
		bd.has_wall = true
		_map_data.set_boundary(Vector3i(2, y, 0), Vector3i(3, y, 0), bd)

	for y in range(1, 6):
		var bd: BoundaryData = BoundaryData.new()
		bd.has_wall = true
		_map_data.set_boundary(Vector3i(8, y, 0), Vector3i(9, y, 0), bd)

	for x in range(3, 6):
		var bd: BoundaryData = BoundaryData.new()
		bd.has_barricade = true
		_map_data.set_boundary(Vector3i(x, 3, 0), Vector3i(x, 4, 0), bd)

	for x in range(6, 9):
		var bd: BoundaryData = BoundaryData.new()
		bd.has_barricade = true
		_map_data.set_boundary(Vector3i(x, 3, 0), Vector3i(x, 4, 0), bd)

# ---------------------------------------------------------------------------
# Ability registry
# ---------------------------------------------------------------------------

const _ABILITY_FILES: Array[String] = [
	"res://resources/abilities/achiles_bane.tres",
	"res://resources/abilities/drain_life.tres",
	"res://resources/abilities/hip_shot.tres",
	"res://resources/abilities/peek_shot.tres",
	"res://resources/abilities/reckless_assault.tres",
	"res://resources/abilities/regenerate.tres",
	"res://resources/abilities/riposte.tres",
]

func _load_ability_registry() -> void:
	_ability_registry.clear()
	for full_path in _ABILITY_FILES:
		var res: Resource = load(full_path)
		if res is AbilityData:
			var ab: AbilityData = res as AbilityData
			_ability_registry[ab.entry_id] = ab
		else:
			push_error("[ServerGame] Failed to load ability: %s" % full_path)
	print("[ServerGame] Loaded %d abilities." % _ability_registry.size())

## Injects abilities into char_data from the given ability_ids list.
## Falls back to a class-based default if the list is empty.
func _inject_abilities(char_data: CharacterData, ability_ids: Array) -> void:
	char_data.skill_trees = [[], [], []]
	for aid in ability_ids:
		if _ability_registry.has(aid):
			char_data.skill_trees[0].append(_ability_registry[aid])
	# Fall back to a class default when no abilities were selected.
	if char_data.skill_trees[0].is_empty():
		_inject_class_defaults(char_data)

func _inject_class_defaults(char_data: CharacterData) -> void:
	var ability_id: String = ""
	match char_data.character_class:
		CharacterData.CharacterClass.FIGHTER:
			ability_id = "riposte"
		CharacterData.CharacterClass.BRAWLER:
			ability_id = "reckless_assault"
		CharacterData.CharacterClass.MAGE:
			ability_id = "drain_life"
		CharacterData.CharacterClass.MARKSMAN:
			ability_id = "hip_shot"
		CharacterData.CharacterClass.CLERIC:
			ability_id = "regenerate"
	if ability_id != "" and _ability_registry.has(ability_id):
		char_data.skill_trees[0].append(_ability_registry[ability_id])

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _ability_needs_target(ability: AbilityData) -> bool:
	for action in ability.actions:
		if action.action_type == AbilityAction.ActionType.ATTACK:
			return true
		if action.target_type != AbilityAction.TargetType.SELF:
			return true
	return false

func _get_player_id_for_char(char_data: CharacterData) -> String:
	if char_data == null:
		return ""
	for pid in _team_map:
		if _team_map[pid].has(char_data):
			return pid
	return ""

func _char_can_vault(char_data: CharacterData) -> bool:
	for tree in char_data.skill_trees:
		for entry in tree:
			if (entry as SkillTreeEntry).has_keyword("Vault"):
				return true
	return false

