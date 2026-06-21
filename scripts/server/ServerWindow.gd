## ServerWindow.gd
## A simple UI window displayed when the game runs as a dedicated server.
## Shows the server's IP addresses and the current player connection status.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the operator picks a different map from the dropdown.
signal map_selected(path: String)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _lbl_ip: Label
var _lbl_status: Label
var _lbl_port: Label
var _opt_map: OptionButton
var _lbl_map_hdr: Label
var _map_paths: Array[String] = []

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
	panel.custom_minimum_size = Vector2(480.0, 320.0)
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

	vbox.add_child(HSeparator.new())

	_lbl_map_hdr = Label.new()
	_lbl_map_hdr.text = "Map for next battle:"
	_lbl_map_hdr.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_lbl_map_hdr)

	_opt_map = OptionButton.new()
	_opt_map.add_item("(no maps found)")
	_opt_map.disabled = true
	_opt_map.item_selected.connect(_on_map_option_selected)
	vbox.add_child(_opt_map)

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
	if _opt_map:
		_opt_map.disabled = true

## Populate the map dropdown; called by Main after ServerGame is ready.
func set_maps(paths: Array, selected_path: String) -> void:
	_map_paths.clear()
	for p in paths:
		_map_paths.append(str(p))
	if _opt_map == null:
		return
	_opt_map.clear()
	if _map_paths.is_empty():
		_opt_map.add_item("(no maps found)")
		_opt_map.disabled = true
		return
	_opt_map.disabled = false
	var selected_idx: int = 0
	for i in range(_map_paths.size()):
		_opt_map.add_item(_map_paths[i].get_file())
		if _map_paths[i] == selected_path:
			selected_idx = i
	_opt_map.selected = selected_idx

## Called by Main when the selected map changes externally (e.g. via CLI or terminal).
func on_selected_map_changed(path: String) -> void:
	if _opt_map == null:
		return
	for i in range(_map_paths.size()):
		if _map_paths[i] == path:
			_opt_map.selected = i
			break

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_map_option_selected(index: int) -> void:
	if index < 0 or index >= _map_paths.size():
		return
	emit_signal("map_selected", _map_paths[index])

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
