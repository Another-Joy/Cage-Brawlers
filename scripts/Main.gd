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

	NetworkManager.peer_connected.connect(_on_server_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_server_peer_disconnected)

	print("[SERVER] Listening. Waiting for 2 clients…")

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

# ---------------------------------------------------------------------------
# Client boot
# ---------------------------------------------------------------------------

func _boot_client() -> void:
	_lobby = _LobbyScene.new()
	_lobby.name = "Lobby"
	add_child(_lobby)

	_lobby.connect_requested.connect(_on_client_connect_requested)

	NetworkManager.connected_to_server.connect(_on_client_connected)
	NetworkManager.disconnected_from_server.connect(_on_client_disconnected)

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
	if _lobby:
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

