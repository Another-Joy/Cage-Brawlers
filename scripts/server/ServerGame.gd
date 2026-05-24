## ServerGame.gd
## Server-side game orchestrator for test matches.
##
## Responsibilities:
##   - Build a reproducible test map and two pre-configured teams.
##   - Wire up and start a MatchManager / CombatManager session.
##   - Receive action packets from clients (via Main.rpc_submit_action) and
##     translate them into CombatManager calls.
##   - Serialize and broadcast game state after every state change.
extends Node

# ---------------------------------------------------------------------------
# Signals (consumed by Main.gd to broadcast RPCs)
# ---------------------------------------------------------------------------

## Emitted whenever the game state changes and clients need a full snapshot.
signal state_updated(state: Dictionary)
## Emitted whenever a log message should be forwarded to all clients.
signal event_logged(message: String)

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _match_manager: MatchManager = null
var _dice_roller: DiceRoller = DiceRoller.new()
var _map_data: MapData = null

## peer_id (int) → player_id (String)
var _peer_to_player: Dictionary = {}
## char_id (String) → CharacterData
var _char_lookup: Dictionary = {}
## player_id (String) → Array[CharacterData]
var _team_map: Dictionary = {}

var _match_running: bool = false

# ---------------------------------------------------------------------------
# Test match bootstrap
# ---------------------------------------------------------------------------

## Builds and starts a self-contained test match.
## Safe to call multiple times — subsequent calls are ignored.
func start_test_match() -> void:
	if _match_running:
		return
	_match_running = true
	print("[ServerGame] Building test match…")

	_build_test_map()

	var teams: Dictionary = _build_test_teams()
	_team_map = teams

	# Populate the fast character lookup.
	for player_id in teams:
		for char_data in teams[player_id]:
			_char_lookup[char_data.character_id] = char_data

	# Assign every connected client to player_a (solo test).
	# In a full two-player setup you would split by peer index.
	for peer_id in multiplayer.get_peers():
		_peer_to_player[peer_id] = "player_a"

	# Place characters on spawn tiles.
	var spawns_a: Array[Vector3i] = [
		Vector3i(0, 1, 0), Vector3i(0, 4, 0), Vector3i(0, 6, 0),
	]
	var spawns_b: Array[Vector3i] = [
		Vector3i(7, 1, 0), Vector3i(7, 4, 0), Vector3i(7, 6, 0),
	]
	for i in min(teams["player_a"].size(), spawns_a.size()):
		teams["player_a"][i].grid_position = spawns_a[i]
	for i in min(teams["player_b"].size(), spawns_b.size()):
		teams["player_b"][i].grid_position = spawns_b[i]

	# Build minimal PlayerProfile objects.
	var profile_a: PlayerProfile = PlayerProfile.new()
	profile_a.player_id = "player_a"
	profile_a.display_name = "Blue Team"
	profile_a.roster = teams["player_a"].duplicate()

	var profile_b: PlayerProfile = PlayerProfile.new()
	profile_b.player_id = "player_b"
	profile_b.display_name = "Red Team"
	profile_b.roster = teams["player_b"].duplicate()

	# Create, configure, and start the MatchManager.
	_match_manager = MatchManager.new()
	add_child(_match_manager)
	_match_manager.register_player(profile_a)
	_match_manager.register_player(profile_b)
	_match_manager.set_map(_map_data)
	_match_manager.match_ended_with_results.connect(_on_match_ended)
	_match_manager.lock_teams()
	_match_manager.start_match()

	print("[ServerGame] Match started!")
	emit_signal("event_logged", "=== TEST MATCH STARTED ===")
	_broadcast_state()

# ---------------------------------------------------------------------------
# Client action handler
# ---------------------------------------------------------------------------

## Called by Main.rpc_submit_action for every action packet received.
func handle_action(peer_id: int, action: Dictionary) -> void:
	if not _match_running:
		return
	var combat: CombatManager = _match_manager._combat_manager
	if combat == null:
		return

	var action_type: String = action.get("type", "")
	var char_id: String = action.get("char_id", "")
	var char_data: CharacterData = _char_lookup.get(char_id, null)
	if char_data == null:
		emit_signal("event_logged", "WARN: unknown char_id '%s'" % char_id)
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
				emit_signal("event_logged", "WARN: unknown target_id '%s'" % target_id)
				return
			var result: AttackResolver.AttackResult = combat.process_attack_action(char_data, target)
			if not result.valid:
				log_msg = "%s → %s: REJECTED (%s)" % [
					char_data.character_name, target.character_name, result.rejection_reason]
			elif result.hit:
				log_msg = "%s → %s: HIT! %.0f dmg%s%s" % [
					char_data.character_name, target.character_name, result.damage_dealt,
					" [cover]" if result.cover_penalty_applied else "",
					" [ammo]" if result.ammo_consumed else ""]
			else:
				log_msg = "%s → %s: MISS." % [char_data.character_name, target.character_name]
			if result.valid:
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

		_:
			emit_signal("event_logged", "WARN: unknown action type '%s'" % action_type)
			return

	if log_msg:
		emit_signal("event_logged", log_msg)
	_broadcast_state()

# ---------------------------------------------------------------------------
# State serialization & broadcast
# ---------------------------------------------------------------------------

func _broadcast_state() -> void:
	emit_signal("state_updated", _serialize_state())

func _serialize_state() -> Dictionary:
	var combat: CombatManager = _match_manager._combat_manager if _match_manager else null

	var chars_out: Array = []
	for player_id in _team_map:
		for char_data in _team_map[player_id]:
			chars_out.append(_serialize_char(char_data, player_id))

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

	return {
		"map": _serialize_map(),
		"characters": chars_out,
		"turn_order": turn_order,
		"active_char": active_char_id,
		"phase": phase_str,
		"round": round_num,
	}

func _serialize_char(char_data: CharacterData, player_id: String) -> Dictionary:
	var max_hp: float = char_data.get_max_hp()
	var pcts: Array[float] = ClassDefinitions.get_segment_percentages(char_data.character_class)
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

	return {
		"id":           char_data.character_id,
		"name":         char_data.character_name,
		"class":        char_data.character_class,
		"player_id":    player_id,
		"state":        char_data.state_flag,
		"pos":          {"x": char_data.grid_position.x, "y": char_data.grid_position.y, "z": char_data.grid_position.z},
		"facing":       char_data.facing_direction,
		"is_crouched":  char_data.is_crouched,
		"hp_segments":  seg_hp,
		"hp_seg_max":   seg_max,
		"hp_disabled":  seg_disabled,
		"equipment":    equip,
	}

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
# Match end handler
# ---------------------------------------------------------------------------

func _on_match_ended(winner_player_id: String, _results: Dictionary) -> void:
	_match_running = false
	emit_signal("event_logged", "=== MATCH OVER — Winner: %s ===" % winner_player_id)
	_broadcast_state()

# ---------------------------------------------------------------------------
# Test data factories
# ---------------------------------------------------------------------------

func _build_test_map() -> void:
	_map_data = MapData.new()
	# 8×8 flat grid at z = 0.
	for x in range(8):
		for y in range(8):
			_map_data.tiles.append(Vector3i(x, y, 0))

	# Vertical wall: between column 2 and column 3, rows 0–3.
	for y in range(4):
		var bd: BoundaryData = BoundaryData.new()
		bd.has_wall = true
		_map_data.set_boundary(Vector3i(2, y, 0), Vector3i(3, y, 0), bd)

	# Horizontal barricade: between row 3 and row 4, columns 3–6.
	for x in range(3, 7):
		var bd: BoundaryData = BoundaryData.new()
		bd.has_barricade = true
		_map_data.set_boundary(Vector3i(x, 3, 0), Vector3i(x, 4, 0), bd)

func _build_test_teams() -> Dictionary:
	return {
		"player_a": _load_roster("res://resources/characters/team_a"),
		"player_b": _load_roster("res://resources/characters/team_b"),
	}

## Loads all CharacterData `.tres` files from a folder, sorted by filename.
## Each character is a shallow duplicate of the cached base resource so that
## combat state (grid_position, hp arrays, etc.) is clean while the shared
## sub-resources (weapons, armor) remain cached and are not duplicated.
func _load_roster(folder_path: String) -> Array[CharacterData]:
	var team: Array[CharacterData] = []
	var dir := DirAccess.open(folder_path)
	if dir == null:
		push_error("[ServerGame] Cannot open roster folder: %s — falling back to empty team." % folder_path)
		return team
	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()  # ensures consistent ordering (01_, 02_, 03_ prefixes)

	for fname in files:
		var full_path: String = folder_path + "/" + fname
		# Load the cached base resource, then shallow-duplicate to get a fresh
		# CharacterData instance with independent non-exported combat-state vars
		# while weapon/armor sub-resources stay as shared cached references.
		var base_data := load(full_path) as CharacterData
		if base_data == null:
			push_error("[ServerGame] Failed to load character resource: %s" % full_path)
			continue
		var char_data := base_data.duplicate(false) as CharacterData
		ClassDefinitions.initialise_character_health(char_data)
		team.append(char_data)

	return team
