## NetworkManager.gd
## Autoload singleton managing the ENet multiplayer peer for both the
## dedicated headless server and the dumb client.
##
## Architecture: strict server-authoritative. The client sends only input
## declarations; the server validates, processes, and broadcasts state
## updates via RPCs.
extends Node

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 2

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted on the server when a new peer connects.
signal peer_connected(peer_id: int)
## Emitted on the server when a peer disconnects.
signal peer_disconnected(peer_id: int)
## Emitted on the client when the connection to the server is established.
signal connected_to_server()
## Emitted on the client when the connection is dropped.
signal disconnected_from_server()

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _peer: ENetMultiplayerPeer = null
var is_server: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ---------------------------------------------------------------------------
# Server Setup
# ---------------------------------------------------------------------------

## Creates a dedicated server listening on the given port.
func create_server(port: int = DEFAULT_PORT) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("NetworkManager: failed to create server on port %d (error %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = _peer
	is_server = true
	print("NetworkManager: server started on port %d." % port)
	return OK

# ---------------------------------------------------------------------------
# Client Setup
# ---------------------------------------------------------------------------

## Connects a client to the server at the given address and port.
func create_client(address: String, port: int = DEFAULT_PORT) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_client(address, port)
	if err != OK:
		push_error("NetworkManager: failed to connect to %s:%d (error %d)" % [address, port, err])
		return err
	multiplayer.multiplayer_peer = _peer
	is_server = false
	return OK

# ---------------------------------------------------------------------------
# Connection Cleanup
# ---------------------------------------------------------------------------

func disconnect_peer() -> void:
	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null

# ---------------------------------------------------------------------------
# RPC Helpers
# ---------------------------------------------------------------------------

## Sends an RPC to all connected clients from the server.
## target_node must have the method registered as an RPC.
func broadcast_to_clients(target_node: Node, method: String, args: Array = []) -> void:
	if not is_server:
		return
	target_node.rpc(method, args)

## Sends an RPC to a specific client peer.
func send_to_peer(peer_id: int, target_node: Node, method: String, args: Array = []) -> void:
	if not is_server:
		return
	target_node.rpc_id(peer_id, method, args)

# ---------------------------------------------------------------------------
# Internal Callbacks
# ---------------------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: peer %d connected." % peer_id)
	emit_signal("peer_connected", peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: peer %d disconnected." % peer_id)
	emit_signal("peer_disconnected", peer_id)

func _on_connected_to_server() -> void:
	print("NetworkManager: connected to server.")
	emit_signal("connected_to_server")

func _on_connection_failed() -> void:
	push_error("NetworkManager: connection to server failed.")

func _on_server_disconnected() -> void:
	push_error("NetworkManager: server disconnected unexpectedly.")
	emit_signal("disconnected_from_server")
