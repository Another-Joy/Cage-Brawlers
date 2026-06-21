## Main.gd
## Bootstrap entry point.
## Detects whether this instance should run as a dedicated server or as a
## game client, sets up the appropriate subsystems, and acts as the shared
## RPC bridge that both sides expose at the same node path (/root/Main).
extends Node

# ---------------------------------------------------------------------------
# Preloads
# ---------------------------------------------------------------------------

const _ServerGame    = preload("res://scripts/server/ServerGame.gd")
const _ServerWindow  = preload("res://scripts/server/ServerWindow.gd")
const _LobbyScene    = preload("res://scripts/client/LobbyScene.gd")
const _TestMatchScene = preload("res://scenes/TestMatch.tscn")

# ---------------------------------------------------------------------------
# References (set in _boot_*)
# ---------------------------------------------------------------------------

## ServerGame instance — only valid on the server.
var _server_game: Node = null
## ServerWindow instance — only valid on the server.
var _server_window: Node = null
## LobbyScene instance — only valid on the client while in lobby.
var _lobby: Node = null
## TestMatchScene instance — only valid on the client during a match.
var _test_match: Node = null

## Optional terminal prompt thread used by server mode for map selection.
var _map_prompt_thread: Thread = null

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

func _ready() -> void:
	if _is_server_mode():
		_boot_server()
	else:
		_boot_client()

func _is_server_mode() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	if OS.has_feature("server"):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	return "--server" in OS.get_cmdline_args()

# ---------------------------------------------------------------------------
# Server boot
# ---------------------------------------------------------------------------

func _boot_server() -> void:
	print("[SERVER] Starting dedicated server on port %d…" % NetworkManager.DEFAULT_PORT)
	var err: Error = NetworkManager.create_server(NetworkManager.DEFAULT_PORT)
	if err != OK:
		push_error("[SERVER] Failed to create server (err %d)." % err)
		return

	# Show the server status window.
	_server_window = _ServerWindow.new()
	_server_window.name = "ServerWindow"
	add_child(_server_window)

	_server_game = _ServerGame.new()
	_server_game.name = "ServerGame"
	add_child(_server_game)

	_server_game.state_updated_for_peer.connect(_on_server_state_for_peer)
	_server_game.event_logged_for_peer.connect(_on_server_event_for_peer)
	_server_game.broadcast_event.connect(_on_broadcast_event)
	_server_game.battle_ready.connect(_on_battle_ready)
	_server_game.match_result_for_peer.connect(_on_server_match_result_for_peer)
	_server_game.selected_map_changed.connect(_on_server_selected_map_changed)

	NetworkManager.peer_connected.connect(_on_server_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_server_peer_disconnected)

	# Populate the map selector in the server window now that ServerGame is ready.
	if _server_window and _server_game:
		_server_window.set_maps(
			_server_game.get_available_map_paths(),
			_server_game.get_selected_map_path())
		_server_window.map_selected.connect(_on_server_window_map_selected)

	print("[SERVER] Listening. Waiting for 2 clients…")
	_print_server_map_options()
	_start_server_map_prompt_thread()

func _on_server_peer_connected(peer_id: int) -> void:
	print("[SERVER] Client %d connected." % peer_id)
	if _server_window:
		var count: int = multiplayer.get_peers().size()
		_server_window.update_status(count)

func _on_server_peer_disconnected(peer_id: int) -> void:
	print("[SERVER] Client %d disconnected." % peer_id)
	if _server_window:
		var count: int = multiplayer.get_peers().size()
		_server_window.update_status(count)

func _on_server_state_for_peer(peer_id: int, state: Dictionary) -> void:
	rpc_id(peer_id, "rpc_sync_state", state)

func _on_server_event_for_peer(peer_id: int, message: String) -> void:
	rpc_id(peer_id, "rpc_event", message)

func _on_broadcast_event(message: String) -> void:
	rpc("rpc_event", message)

func _on_battle_ready(peer_a_id: int, peer_b_id: int) -> void:
	print("[SERVER] Battle ready — peer_a=%d, peer_b=%d" % [peer_a_id, peer_b_id])
	if _server_window:
		_server_window.show_match_started()
	rpc_id(peer_a_id, "rpc_start_battle", "player_a")
	rpc_id(peer_b_id, "rpc_start_battle", "player_b")

func _on_server_match_result_for_peer(
		peer_id: int,
		won: bool,
		winner_player_id: String,
		summary: Dictionary) -> void:
	rpc_id(peer_id, "rpc_match_result", won, winner_player_id, summary)

func _on_server_selected_map_changed(path: String) -> void:
	print("[SERVER] Selected map: %s" % path)
	if _server_window:
		_server_window.on_selected_map_changed(path)

func _on_server_window_map_selected(path: String) -> void:
	if _server_game:
		_server_game.select_map_path(path)

func _print_server_map_options() -> void:
	if not _server_game:
		return
	var maps: Array = _server_game.get_available_map_paths()
	var selected: String = _server_game.get_selected_map_path()
	if maps.is_empty():
		print("[SERVER] No map files found in res://resources/maps (will use fallback map).")
		return
	print("[SERVER] Available maps:")
	for i in range(maps.size()):
		var full_path: String = str(maps[i])
		var marker: String = "*" if full_path == selected else " "
		print("  %s %d) %s" % [marker, i + 1, full_path.get_file()])
	print("[SERVER] Type a map number and press Enter to select it before both rosters are received.")

func _start_server_map_prompt_thread() -> void:
	if not _server_game:
		return
	if _map_prompt_thread and _map_prompt_thread.is_started():
		return
	var maps: Array = _server_game.get_available_map_paths()
	if maps.is_empty():
		return
	_map_prompt_thread = Thread.new()
	var err: Error = _map_prompt_thread.start(_map_prompt_loop.bind(maps))
	if err != OK:
		push_warning("[SERVER] Failed to start map prompt thread (err %d)." % err)

func _map_prompt_loop(maps: Array) -> void:
	while true:
		var line: String = OS.read_string_from_stdin().strip_edges()
		if line == "":
			# No interactive stdin available (or EOF); stop prompt loop.
			break
		call_deferred("_apply_server_map_input", line, maps)

func _apply_server_map_input(line: String, maps: Array) -> void:
	if not _server_game:
		return
	if not line.is_valid_int():
		print("[SERVER] Invalid map selection '%s' (use a number from the list)." % line)
		return
	var idx: int = int(line) - 1
	if idx < 0 or idx >= maps.size():
		print("[SERVER] Invalid map number %d." % (idx + 1))
		return
	var path: String = str(maps[idx])
	if not _server_game.select_map_path(path):
		print("[SERVER] Could not apply map '%s' (match may already be running)." % path)

# ---------------------------------------------------------------------------
# Client boot
# ---------------------------------------------------------------------------

func _boot_client() -> void:
	_ensure_lobby()

	NetworkManager.connected_to_server.connect(_on_client_connected)
	NetworkManager.disconnected_from_server.connect(_on_client_disconnected)

func _ensure_lobby() -> void:
	if _lobby:
		return
	_lobby = _LobbyScene.new()
	_lobby.name = "Lobby"
	add_child(_lobby)
	_lobby.connect_requested.connect(_on_client_connect_requested)

func _on_client_connect_requested(ip: String) -> void:
	var err: Error = NetworkManager.create_client(ip, NetworkManager.DEFAULT_PORT)
	if err != OK:
		push_error("[CLIENT] Failed to initiate connection (err %d)." % err)
		if _lobby:
			(_lobby as Node).call("on_connection_failed")

func _on_client_connected() -> void:
	print("[CLIENT] Connected to server. Sending roster…")
	if _lobby:
		(_lobby as Node).call("on_waiting_for_opponent")
	# Send our party roster to the server immediately upon connection.
	var party: Array = RosterManager.get_party_dicts()
	rpc_id(1, "rpc_send_roster", party)

func _on_client_disconnected() -> void:
	print("[CLIENT] Server disconnected.")
	_ensure_lobby()
	(_lobby as Node).call("on_disconnected")

func _on_client_action_submitted(action: Dictionary) -> void:
	rpc_id(1, "rpc_submit_action", action)

# ---------------------------------------------------------------------------
# RPC — Client → Server
# ---------------------------------------------------------------------------

## Receives the party roster from a connecting client and forwards it to ServerGame.
@rpc("any_peer", "call_remote", "reliable")
func rpc_send_roster(party_dicts: Array) -> void:
	if _server_game:
		var sender_id: int = multiplayer.get_remote_sender_id()
		_server_game.receive_client_roster(sender_id, party_dicts)

## Receives an action packet from a client and forwards it to ServerGame.
@rpc("any_peer", "call_remote", "reliable")
func rpc_submit_action(action: Dictionary) -> void:
	if _server_game:
		var sender_id: int = multiplayer.get_remote_sender_id()
		_server_game.handle_action(sender_id, action)

# ---------------------------------------------------------------------------
# RPC — Server → Client
# ---------------------------------------------------------------------------

## Tells a client which player_id they are and starts the battle scene.
@rpc("authority", "call_remote", "reliable")
func rpc_start_battle(player_id: String) -> void:
	print("[CLIENT] Battle starting as '%s'." % player_id)
	# Remove the lobby.
	if _lobby:
		_lobby.queue_free()
		_lobby = null
	# Instantiate and configure the match scene.
	_test_match = _TestMatchScene.instantiate()
	_test_match.name = "TestMatch"
	_test_match.set("local_player_id", player_id)
	add_child(_test_match)
	_test_match.action_submitted.connect(_on_client_action_submitted)

## Receives match result, returns client to lobby, and shows win/loss panel.
@rpc("authority", "call_remote", "reliable")
func rpc_match_result(won: bool, winner_player_id: String, summary: Dictionary) -> void:
	print("[CLIENT] Match ended. won=%s winner=%s" % [str(won), winner_player_id])
	if _test_match:
		_test_match.queue_free()
		_test_match = null

	# Return to normal lobby state (disconnected) after each independent match.
	NetworkManager.disconnect_peer()
	_ensure_lobby()
	(_lobby as Node).call("on_match_result", won, winner_player_id, summary)

## Receives a full per-player state snapshot pushed by the server.
@rpc("authority", "call_remote", "reliable")
func rpc_sync_state(state: Dictionary) -> void:
	if _test_match:
		_test_match.apply_state(state)

## Receives a game event log message from the server.
@rpc("authority", "call_remote", "reliable")
func rpc_event(message: String) -> void:
	if _test_match:
		_test_match.log_event(message)

