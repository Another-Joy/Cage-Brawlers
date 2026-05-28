## ServerWindow.gd
## A simple UI window displayed when the game runs as a dedicated server.
## Shows the server's IP addresses and the current player connection status.
extends Node

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _lbl_ip: Label
var _lbl_status: Label
var _lbl_port: Label

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	_refresh_ip()

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(20.0, 20.0)
	panel.custom_minimum_size = Vector2(460.0, 220.0)
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Cage Brawlers — Server"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Port
	_lbl_port = Label.new()
	_lbl_port.text = "Port: %d" % NetworkManager.DEFAULT_PORT
	vbox.add_child(_lbl_port)

	# IP addresses
	var ip_hdr := Label.new()
	ip_hdr.text = "IP Addresses:"
	ip_hdr.add_theme_font_size_override("font_size", 14)
	vbox.add_child(ip_hdr)

	_lbl_ip = Label.new()
	_lbl_ip.text = "Resolving…"
	vbox.add_child(_lbl_ip)

	vbox.add_child(HSeparator.new())

	# Status
	_lbl_status = Label.new()
	_lbl_status.text = "Waiting for players (0 / 2)"
	_lbl_status.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_lbl_status)

	var hint := Label.new()
	hint.text = "The battle begins automatically when 2 players connect\nand both send their roster."
	hint.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(hint)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Update the displayed player-count status (called by Main when a peer connects/disconnects).
func update_status(connected_count: int) -> void:
	if _lbl_status:
		_lbl_status.text = "Waiting for players (%d / 2)" % connected_count

## Called by ServerGame once the match has actually started.
func show_match_started() -> void:
	if _lbl_status:
		_lbl_status.text = "Match in progress!"

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _refresh_ip() -> void:
	var addresses: PackedStringArray = IP.get_local_addresses()
	var ip_lines: Array = []
	for addr in addresses:
		# Skip IPv6, loopback (127.x.x.x), and link-local (169.254.x.x).
		if ":" in addr:
			continue
		if addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		ip_lines.append(addr)
	if ip_lines.is_empty():
		ip_lines.append("127.0.0.1 (loopback only)")
	if _lbl_ip:
		_lbl_ip.text = "\n".join(ip_lines)
