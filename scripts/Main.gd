## Main.gd
## Bootstrap entry point.
## Detects whether this instance should run as a dedicated server or as a
## game client, sets up the appropriate subsystems, and acts as the shared
## RPC bridge that both sides expose at the same node path (/root/Main).
extends Node

# ---------------------------------------------------------------------------
# Preloads
# ---------------------------------------------------------------------------

const _ServerGame = preload("res://scripts/server/ServerGame.gd")
const _TestMatchScene = preload("res://scenes/TestMatch.tscn")

# ---------------------------------------------------------------------------
# References (set in _boot_*)
# ---------------------------------------------------------------------------

## ServerGame instance — only valid on the server.
var _server_game: Node = null
## TestMatchScene instance — only valid on the client.
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
	# Compiled as a dedicated-server export.
	if OS.has_feature("dedicated_server"):
		return true
	# Running with --headless (no display window, e.g. CI or Linux server).
	if DisplayServer.get_name() == "headless":
		return true
	# Explicit user flag: pass "--server" after the scene path.
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

	_server_game = _ServerGame.new()
	_server_game.name = "ServerGame"
	add_child(_server_game)

	_server_game.state_updated.connect(_on_server_state_updated)
	_server_game.event_logged.connect(_on_server_event_logged)

	multiplayer.peer_connected.connect(_on_server_peer_connected)
	print("[SERVER] Listening. Waiting for a client…")

func _on_server_peer_connected(peer_id: int) -> void:
	print("[SERVER] Client %d connected — starting test match." % peer_id)
	_server_game.start_test_match()

func _on_server_state_updated(state: Dictionary) -> void:
	# Broadcast the updated state to all connected clients.
	rpc("rpc_sync_state", state)

func _on_server_event_logged(message: String) -> void:
	rpc("rpc_event", message)

# ---------------------------------------------------------------------------
# Client boot
# ---------------------------------------------------------------------------

func _boot_client() -> void:
	_test_match = _TestMatchScene.instantiate()
	_test_match.name = "TestMatch"
	add_child(_test_match)
	_test_match.action_submitted.connect(_on_client_action_submitted)

	print("[CLIENT] Connecting to 127.0.0.1:%d…" % NetworkManager.DEFAULT_PORT)
	var err: Error = NetworkManager.create_client("127.0.0.1", NetworkManager.DEFAULT_PORT)
	if err != OK:
		push_error("[CLIENT] Failed to initiate connection (err %d)." % err)

func _on_client_action_submitted(action: Dictionary) -> void:
	# Send the action to the server (peer ID 1 is always the server).
	rpc_id(1, "rpc_submit_action", action)

# ---------------------------------------------------------------------------
# RPC — Client → Server
# ---------------------------------------------------------------------------

## Receives an action packet from a client and forwards it to ServerGame.
@rpc("any_peer", "call_remote", "reliable")
func rpc_submit_action(action: Dictionary) -> void:
	if _server_game:
		var sender_id: int = multiplayer.get_remote_sender_id()
		_server_game.handle_action(sender_id, action)

# ---------------------------------------------------------------------------
# RPC — Server → Client
# ---------------------------------------------------------------------------

## Receives a full state snapshot pushed by the server.
@rpc("authority", "call_remote", "reliable")
func rpc_sync_state(state: Dictionary) -> void:
	if _test_match:
		_test_match.apply_state(state)

## Receives a game event log message from the server.
@rpc("authority", "call_remote", "reliable")
func rpc_event(message: String) -> void:
	if _test_match:
		_test_match.log_event(message)
