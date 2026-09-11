## TestMatchScene.gd
## Client-side match view — HUD layout.
##
## The map fills the full viewport and can be panned with WASD.
## An overlay CanvasLayer contains:
##   - Top bar: Round / Phase / Active character info.
##   - Bottom bar: One slot per allied character: portrait + HP bars + action buttons.
##
## Hovering a portrait shows an equipment tooltip.
## Hovering an ability/action button previews its range (all tiles within range,
## regardless of occupancy) and shows a small description tooltip.
##
## Communicates with the server via the `action_submitted` signal.
extends Node2D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal action_submitted(action: Dictionary)

# ---------------------------------------------------------------------------
# Visual constants
# ---------------------------------------------------------------------------

const CHAR_PAD_BASE      : float = 6.0
const HP_BAR_H_BASE      : float = 5.0
const HP_BAR_MARGIN_BASE : float = 2.0

## Tile / map colours
const C_TILE          := Color(0.18, 0.18, 0.21)
const C_TILE_BORDER   := Color(0.30, 0.30, 0.34)
const C_HOVER         := Color(1.00, 1.00, 1.00, 0.10)
const C_SEL_MOVE      := Color(0.20, 0.90, 0.20, 0.22)
const C_SEL_ATTACK    := Color(0.95, 0.20, 0.20, 0.28)
const C_FOG           := Color(0.00, 0.00, 0.00, 0.55)
const C_RANGE_PREVIEW := Color(0.80, 0.60, 1.00, 0.20)

## Boundary colours
const C_WALL      := Color(1.00, 1.00, 1.00)
const C_BARRICADE := Color(0.90, 0.70, 0.10)
const C_LADDER    := Color(0.65, 0.40, 0.10)

## Character colours
const C_TEAM_A      := Color(0.25, 0.45, 1.00)
const C_TEAM_B      := Color(1.00, 0.25, 0.25)
const C_KNOCKED     := Color(0.45, 0.45, 0.45)
const C_DEAD        := Color(0.10, 0.10, 0.10)
const C_ACTIVE_RING := Color(1.00, 0.92, 0.10)
const C_CROUCHED    := Color(0.80, 0.80, 0.10, 0.50)
const C_FACING      := Color(1.00, 1.00, 1.00, 0.90)

const FACING_VECS: Array = [
	Vector2( 0,  1),  # 0 N
	Vector2( 1,  1),  # 1 NE
	Vector2( 1,  0),  # 2 E
	Vector2( 1, -1),  # 3 SE
	Vector2( 0, -1),  # 4 S
	Vector2(-1, -1),  # 5 SW
	Vector2(-1,  0),  # 6 W
	Vector2(-1,  1),  # 7 NW
]

## HP bar colours
const C_HP_FULL     := Color(0.15, 0.85, 0.15)
const C_HP_LOW      := Color(0.90, 0.10, 0.10)
const C_HP_BG       := Color(0.15, 0.08, 0.08)
const C_HP_DISABLED := Color(0.20, 0.20, 0.20, 0.50)
const C_HP_BROKEN   := Color(0.45, 0.18, 0.18, 0.75)
const C_HP_BORDER   := Color(0.50, 0.50, 0.50)

## Map panning speed (pixels per second)
const PAN_SPEED : float = 300.0

## Bottom HUD dimensions
const HUD_BOTTOM_H  : float = 120.0
const PORTRAIT_SIZE : float = 72.0
const BTN_SIZE      : float = 44.0
const BTN_GAP       : float = 4.0
const TOP_BAR_H     : float = 30.0

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _state       : Dictionary = {}
var _input_mode  : String     = "none"
var _hovered     : Vector2i   = Vector2i(-1, -1)
var _selected_ability_id  : String = ""
var _selected_ability_range: int = 0
var _selected_ability_targeting_mode: int = 0
var _pending_targets      : Array  = []
var _pending_target_count : int    = 0
var _pending_target_tile  : Vector2i = Vector2i(-1, -1)

var local_player_id  : String     = ""
var _visible_tiles   : Dictionary = {}
var _hover_char_dict : Dictionary = {}

# ---------------------------------------------------------------------------
# Map layout / camera
# ---------------------------------------------------------------------------

var _map_min_x   : int   = 0
var _map_min_y   : int   = 0
var _map_tiles_w : int   = 12
var _map_tiles_h : int   = 8
var _tile_size_px : float = 64.0

var _cam_offset : Vector2 = Vector2.ZERO
var _pan_left   : bool = false
var _pan_right  : bool = false
var _pan_up     : bool = false
var _pan_down   : bool = false

# ---------------------------------------------------------------------------
# HUD nodes
# ---------------------------------------------------------------------------

var _ui_layer      : CanvasLayer
var _ui_root       : Control
var _lbl_round     : Label
var _lbl_phase     : Label
var _lbl_active    : Label
var _btn_log       : Button
var _hud_hbox      : HBoxContainer
var _tooltip_panel : PanelContainer
var _tooltip_label : Label
var _grid_facing   : GridContainer
var _log_history   : Array[String] = []
var _log_popup     : PanelContainer
var _log_vbox      : VBoxContainer

## Array of { "char_id", "control": Control, "equip_lines": Array[String] }
var _portrait_slots : Array = []

## { "range": int, "char_pos": Vector2i } or empty when no hover.
var _ability_hover_range : Dictionary = {}

# ---------------------------------------------------------------------------
# _ready / _process
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if _pan_left  : dir.x -= 1.0
	if _pan_right : dir.x += 1.0
	if _pan_up    : dir.y -= 1.0
	if _pan_down  : dir.y += 1.0
	if dir != Vector2.ZERO:
		_cam_offset += dir * PAN_SPEED * delta
		_clamp_camera()
		queue_redraw()

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)

	# Root control that fills the entire viewport.
	# CanvasLayer is not a Control, so direct children can't anchor to it;
	# this node is the anchor reference for everything below.
	var ui_root := Control.new()
	_ui_root = ui_root
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(ui_root)

	# VBoxContainer: top bar | transparent spacer | bottom bar.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	ui_root.add_child(vbox)

	# ── Top bar ──────────────────────────────────────────────────
	var top_panel := PanelContainer.new()
	top_panel.custom_minimum_size = Vector2(0.0, TOP_BAR_H)
	top_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(top_panel)
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 16)
	top_panel.add_child(top_hbox)
	_lbl_round = Label.new()
	_lbl_round.text = "Connecting…"
	_lbl_round.add_theme_font_size_override("font_size", 13)
	top_hbox.add_child(_lbl_round)
	_lbl_phase = Label.new()
	_lbl_phase.text = ""
	_lbl_phase.add_theme_font_size_override("font_size", 13)
	top_hbox.add_child(_lbl_phase)
	_lbl_active = Label.new()
	_lbl_active.text = ""
	_lbl_active.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_active.add_theme_font_size_override("font_size", 13)
	top_hbox.add_child(_lbl_active)
	_btn_log = Button.new()
	_btn_log.text = "▼ Log"
	_btn_log.add_theme_font_size_override("font_size", 11)
	_btn_log.size_flags_horizontal = Control.SIZE_SHRINK_END
	_btn_log.flat = true
	_btn_log.pressed.connect(_on_log_toggle)
	top_hbox.add_child(_btn_log)

	# ── Spacer (map area — transparent, passes mouse through) ────
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	# ── Bottom bar ───────────────────────────────────────────────
	var bot_panel := PanelContainer.new()
	bot_panel.custom_minimum_size = Vector2(0.0, HUD_BOTTOM_H)
	bot_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(bot_panel)
	_hud_hbox = HBoxContainer.new()
	_hud_hbox.add_theme_constant_override("separation", 8)
	bot_panel.add_child(_hud_hbox)

	# ── Facing grid (absolutely positioned inside ui_root) ───────
	_grid_facing = GridContainer.new()
	_grid_facing.columns = 3
	_grid_facing.add_theme_constant_override("h_separation", 3)
	_grid_facing.add_theme_constant_override("v_separation", 3)
	_grid_facing.visible = false
	var facing_entries: Array = [
		["NW", 5], ["N", 4], ["NE", 3],
		["W",  6], ["·", -1], ["E",  2],
		["SW", 7], ["S", 0], ["SE",  1],
	]
	for entry in facing_entries:
		if entry[1] == -1:
			var pad := Control.new()
			pad.custom_minimum_size = Vector2(42.0, 30.0)
			_grid_facing.add_child(pad)
		else:
			var btn := Button.new()
			btn.text = entry[0]
			btn.custom_minimum_size = Vector2(42.0, 30.0)
			btn.pressed.connect(_on_facing_pressed.bind(entry[1]))
			_grid_facing.add_child(btn)
	ui_root.add_child(_grid_facing)

	# ── Tooltip panel (absolutely positioned inside ui_root) ─────
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 11)
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_label.custom_minimum_size = Vector2(180.0, 0.0)
	_tooltip_panel.add_child(_tooltip_label)
	ui_root.add_child(_tooltip_panel)

	# ── Log history popup (absolutely positioned, hidden by default) ──
	_log_popup = PanelContainer.new()
	_log_popup.visible = false
	var log_scroll := ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(360.0, 200.0)
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_vbox = VBoxContainer.new()
	_log_vbox.add_theme_constant_override("separation", 4)
	log_scroll.add_child(_log_vbox)
	_log_popup.add_child(log_scroll)
	ui_root.add_child(_log_popup)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func apply_state(state: Dictionary) -> void:
	_state = state
	_recompute_map_layout()
	var sid: String = state.get("my_player_id", "")
	if sid != "" and local_player_id == "":
		local_player_id = sid
	_visible_tiles.clear()
	for vt in state.get("visible_tiles", []):
		_visible_tiles["%d,%d" % [vt["x"], vt["y"]]] = true
	_hover_char_dict = _char_dict_at_tile(_hovered)
	_update_ui()
	queue_redraw()


func log_event(message: String) -> void:
	_log_history.append(message)
	if _btn_log:
		var preview: String = message.substr(0, 30) + ("…" if message.length() > 30 else "")
		_btn_log.text = "▼  " + preview
	if _log_popup and _log_popup.visible:
		_rebuild_log_popup()


func _on_log_toggle() -> void:
	if not _log_popup:
		return
	_log_popup.visible = not _log_popup.visible
	if _log_popup.visible:
		_rebuild_log_popup()
		var vp := get_viewport_rect().size
		_log_popup.position = Vector2(vp.x - 368.0, TOP_BAR_H + 2.0)


func _rebuild_log_popup() -> void:
	for c in _log_vbox.get_children():
		c.queue_free()
	for i in range(_log_history.size() - 1, -1, -1):
		var lbl := Label.new()
		lbl.text = _log_history[i]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(330.0, 0.0)
		_log_vbox.add_child(lbl)


# ---------------------------------------------------------------------------
# Map layout / camera
# ---------------------------------------------------------------------------

func _recompute_map_layout() -> void:
	var tiles: Array = _state.get("map", {}).get("tiles", [])
	if tiles.is_empty():
		_map_min_x = 0
		_map_min_y = 0
		_map_tiles_w = 12
		_map_tiles_h = 8
		_tile_size_px = 64.0
		return
	var min_x: int = int(tiles[0]["x"])
	var max_x: int = min_x
	var min_y: int = int(tiles[0]["y"])
	var max_y: int = min_y
	for t in tiles:
		var tx: int = int(t["x"])
		var ty: int = int(t["y"])
		min_x = mini(min_x, tx)
		max_x = maxi(max_x, tx)
		min_y = mini(min_y, ty)
		max_y = maxi(max_y, ty)
	_map_min_x = min_x
	_map_min_y = min_y
	_map_tiles_w = maxi(1, max_x - min_x + 1)
	_map_tiles_h = maxi(1, max_y - min_y + 1)
	var vp := get_viewport_rect().size
	var usable_h := vp.y - TOP_BAR_H - HUD_BOTTOM_H
	_tile_size_px = minf(
		(vp.x * 0.9) / float(_map_tiles_w),
		usable_h * 0.9 / float(_map_tiles_h)
	)
	_clamp_camera()


func _clamp_camera() -> void:
	var vp := get_viewport_rect().size
	var map_w := _tile_size_px * float(_map_tiles_w)
	var map_h := _tile_size_px * float(_map_tiles_h)
	_cam_offset.x = clampf(_cam_offset.x, -20.0, maxf(0.0, map_w - vp.x + 40.0))
	_cam_offset.y = clampf(_cam_offset.y, -20.0, maxf(0.0, map_h - (vp.y - TOP_BAR_H - HUD_BOTTOM_H) + 40.0))


func _tile_pos(tx: int, ty: int) -> Vector2:
	return Vector2(
		float(tx - _map_min_x) * _tile_size_px + 20.0 - _cam_offset.x,
		float(ty - _map_min_y) * _tile_size_px + TOP_BAR_H + 10.0 - _cam_offset.y
	)


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var rel := screen_pos - Vector2(20.0 - _cam_offset.x, TOP_BAR_H + 10.0 - _cam_offset.y)
	var tx: int = int(rel.x / _tile_size_px) + _map_min_x
	var ty: int = int(rel.y / _tile_size_px) + _map_min_y
	for t in _state.get("map", {}).get("tiles", []):
		if t["x"] == tx and t["y"] == ty:
			return Vector2i(tx, ty)
	return Vector2i(-1, -1)

# ---------------------------------------------------------------------------
# UI update
# ---------------------------------------------------------------------------

func _update_ui() -> void:
	var phase     : String = _state.get("phase", "none")
	var round_n   : int    = _state.get("round", 0)
	var active_id : String = _state.get("active_char", "")
	_lbl_round.text = "Round %d" % round_n
	var active_char: Dictionary = _find_char_dict(active_id)
	if not active_char.is_empty():
		var team_tag: String = "A" if active_char["player_id"] == "player_a" else "B"
		_lbl_active.text = "%s [Team %s]  –  %s" % [active_char["name"], team_tag, phase.capitalize()]
		_lbl_phase.text = ""
	else:
		_lbl_active.text = "—"
		_lbl_phase.text = phase
	var is_my_turn: bool = (not active_char.is_empty()) and (active_char.get("player_id","") == local_player_id)
	_rebuild_bottom_hud(phase if is_my_turn else "", active_id)
	var show_facing: bool = ((phase == "pending_rotation") or _input_mode == "select_ability_direction") and is_my_turn
	if show_facing:
		var vp := get_viewport_rect().size
		_grid_facing.position = Vector2(vp.x * 0.5 - 75.0, vp.y - HUD_BOTTOM_H - 120.0)
	_grid_facing.visible = show_facing


func _rebuild_bottom_hud(phase: String, active_id: String) -> void:
	for c in _hud_hbox.get_children():
		c.queue_free()
	_portrait_slots.clear()
	var my_chars: Array = []
	for cid in _state.get("turn_order", []):
		var cd: Dictionary = _find_char_dict(cid)
		if not cd.is_empty() and cd.get("player_id","") == local_player_id:
			my_chars.append(cd)
	if my_chars.is_empty():
		for cd in _state.get("characters", []):
			if cd.get("player_id","") == local_player_id:
				my_chars.append(cd)

	# Active char on the left (with action buttons).
	var active_cd: Dictionary = _find_char_dict(active_id)
	if not active_cd.is_empty() and active_cd.get("player_id","") == local_player_id:
		_build_char_slot(active_cd, phase, true)

	# Spacer pushes inactive chars to the right.
	var mid_spacer := Control.new()
	mid_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_hbox.add_child(mid_spacer)

	# Inactive chars on the right (portrait + HP only, no buttons).
	for cd in my_chars:
		if cd["id"] == active_id:
			continue
		_build_char_slot(cd, "", false)


func _build_char_slot(cd: Dictionary, phase: String, is_active: bool) -> void:
	var slot_hbox := HBoxContainer.new()
	slot_hbox.add_theme_constant_override("separation", 4)
	slot_hbox.custom_minimum_size = Vector2(0.0, HUD_BOTTOM_H - 8.0)
	_hud_hbox.add_child(slot_hbox)

	# Portrait.
	var portrait := ColorRect.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var team_col: Color = C_TEAM_A if cd.get("player_id","") == "player_a" else C_TEAM_B
	portrait.color = team_col.darkened(0.1 if is_active else 0.4)
	var port_lbl := Label.new()
	port_lbl.text = cd.get("name","?").substr(0,1).to_upper()
	port_lbl.add_theme_font_size_override("font_size", 28)
	port_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	port_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	port_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.add_child(port_lbl)
	var name_lbl := Label.new()
	name_lbl.text = cd.get("name","?")
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.add_child(name_lbl)
	if is_active:
		var ring := ColorRect.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.TRANSPARENT
		sb.border_color = C_ACTIVE_RING
		sb.border_width_left   = 3
		sb.border_width_right  = 3
		sb.border_width_top    = 3
		sb.border_width_bottom = 3
		ring.add_theme_stylebox_override("panel", sb)
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait.add_child(ring)
	slot_hbox.add_child(portrait)
	_portrait_slots.append({"char_id": cd["id"], "control": portrait, "equip_lines": _build_equip_lines(cd)})

	# HP column.
	var hp_vbox := VBoxContainer.new()
	hp_vbox.add_theme_constant_override("separation", 2)
	hp_vbox.custom_minimum_size = Vector2(100.0, 0.0)
	hp_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot_hbox.add_child(hp_vbox)
	_fill_hp_vbox(hp_vbox, cd)

	var sep := VSeparator.new()
	sep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot_hbox.add_child(sep)

	# Action buttons — single horizontal row.
	if phase != "":
		var btns_hbox := HBoxContainer.new()
		btns_hbox.add_theme_constant_override("separation", BTN_GAP)
		btns_hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot_hbox.add_child(btns_hbox)
		_populate_action_buttons(btns_hbox, phase, cd)


func _fill_hp_vbox(container: VBoxContainer, cd: Dictionary) -> void:
	var segs     : Array = cd.get("hp_segments", [])
	var seg_maxs : Array = cd.get("hp_seg_max", [])
	var disabled : Array = cd.get("hp_disabled", [])
	var armor_hp : float = cd.get("armor_hp", 0.0)
	var armor_max: float = cd.get("armor_max_hp", 0.0)
	if segs.is_empty():
		var lbl := Label.new()
		lbl.text = cd.get("hp_state","?")
		lbl.add_theme_font_size_override("font_size", 11)
		container.add_child(lbl)
		return
	var cur: float = 0.0
	var mx: float  = 0.0
	for i in segs.size():
		cur += float(segs[i])
		mx  += float(seg_maxs[i]) if i < seg_maxs.size() else 0.0
	var total_lbl := Label.new()
	total_lbl.text = "%d / %d HP" % [int(cur), int(mx)]
	total_lbl.add_theme_font_size_override("font_size", 10)
	container.add_child(total_lbl)
	var bars_hbox := HBoxContainer.new()
	bars_hbox.add_theme_constant_override("separation", 1)
	container.add_child(bars_hbox)
	var seg_max_ints := _compute_int_seg_maxes(seg_maxs)
	for i in range(segs.size() - 1, -1, -1):
		var sm_i   : float = float(seg_maxs[i]) if i < seg_maxs.size() else 1.0
		var sm_int : int   = seg_max_ints[i] if i < seg_max_ints.size() else int(sm_i)
		var cur_int: int   = mini(int(segs[i]), sm_int) if segs[i] > 0.0 else 0
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 1)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(22.0, 12.0)
		bar.show_percentage = false
		bar.max_value = sm_i
		bar.value = float(segs[i]) if segs[i] > 0.0 else 0.0
		if i < disabled.size() and disabled[i]:
			bar.value = 0.0
			bar.modulate = Color(0.35, 0.35, 0.35)
		sv.add_child(bar)
		var lbl := Label.new()
		lbl.text = "%d" % cur_int
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(lbl)
		bars_hbox.add_child(sv)
	if armor_max > 0.0:
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 1)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(22.0, 12.0)
		bar.show_percentage = false
		bar.max_value = armor_max
		bar.value = armor_hp
		bar.modulate = Color(1.0, 0.85, 0.2)
		sv.add_child(bar)
		var lbl := Label.new()
		lbl.text = "%d" % int(armor_hp)
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(lbl)
		bars_hbox.add_child(sv)


func _populate_action_buttons(container: HBoxContainer, phase: String, cd: Dictionary) -> void:
	match phase:
		"beginning":
			_sq_btn(container, "Skip",  _on_skip_beginning)
			_sq_btn(container, "Move",  _on_move_mode)
			_sq_btn(container, "Stand", _on_stand_up)
			_sq_btn(container, "End",   _on_end_turn)
			_add_ability_buttons(container, 1, cd)
		"main":
			_sq_btn(container, "Attack", _on_attack_mode)
			_sq_btn(container, "Skip",   _on_skip_main)
			_sq_btn(container, "End",    _on_end_turn)
			_add_ability_buttons(container, 2, cd)
		"ending":
			_sq_btn(container, "Crouch", _on_crouch)
			_sq_btn(container, "End",    _on_end_turn)
			_add_ability_buttons(container, 4, cd)
		_:
			_sq_btn(container, "End", _on_end_turn)
	if _input_mode != "none":
		_sq_btn(container, "X", _on_cancel)


func _add_ability_buttons(container: HBoxContainer, phase_flag: int, cd: Dictionary) -> void:
	for ab in cd.get("abilities", []):
		if ab.get("phases", 0) & phase_flag == 0:
			continue
		var cooldown    : int    = ab.get("cooldown_remaining", 0)
		var label       : String = ab.get("name","?")
		if cooldown > 0:
			label = "%s\n(%d)" % [label, cooldown]
		var ab_id        : String = ab.get("id","")
		var needs_target : bool   = ab.get("needs_target", false)
		var target_count : int    = ab.get("target_count", 1)
		var targeting_mode: int   = ab.get("targeting_mode", 0)
		var ab_range     : int    = ab.get("range", 0)
		var desc         : String = ab.get("description","")
		var btn := Button.new()
		btn.text = label
		btn.disabled = cooldown > 0
		btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
		btn.pressed.connect(_on_ability_pressed.bind(ab_id, needs_target, target_count, targeting_mode, ab_range))
		btn.mouse_entered.connect(_on_ability_btn_hover.bind(ab_range, desc, btn))
		btn.mouse_exited.connect(_on_ability_btn_exit)
		container.add_child(btn)


func _sq_btn(container: HBoxContainer, label: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	btn.pressed.connect(callback)
	container.add_child(btn)

# ---------------------------------------------------------------------------
# Button callbacks
# ---------------------------------------------------------------------------

func _on_skip_beginning() -> void:
	_submit({"type": "skip_beginning", "char_id": _active_id()})


func _on_move_mode() -> void:
	_input_mode = "select_move"
	_update_ui()
	queue_redraw()


func _on_attack_mode() -> void:
	_input_mode = "select_attack"
	_update_ui()
	queue_redraw()


func _on_stand_up() -> void:
	_submit({"type": "stand_up", "char_id": _active_id()})


func _on_end_turn() -> void:
	_submit({"type": "end_turn", "char_id": _active_id()})


func _on_skip_main() -> void:
	_submit({"type": "skip_main", "char_id": _active_id()})


func _on_crouch() -> void:
	_submit({"type": "crouch", "char_id": _active_id()})


func _on_cancel() -> void:
	_input_mode = "none"
	_selected_ability_id = ""
	_selected_ability_range = 0
	_selected_ability_targeting_mode = 0
	_pending_targets = []
	_pending_target_count = 0
	_pending_target_tile = Vector2i(-1, -1)
	_ability_hover_range = {}
	_update_ui()
	queue_redraw()


func _on_facing_pressed(direction: int) -> void:
	if _input_mode == "select_ability_direction":
		var tile := _pending_target_tile
		_input_mode = "none"
		_submit({
			"type": "ability",
			"char_id": _active_id(),
			"ability_id": _selected_ability_id,
			"target_tile": {"x": tile.x, "y": tile.y, "z": 0},
			"direction": direction,
		})
		_selected_ability_id = ""
		_selected_ability_range = 0
		_selected_ability_targeting_mode = 0
		_pending_target_tile = Vector2i(-1, -1)
		_ability_hover_range = {}
		_update_ui()
		queue_redraw()
		return
	_submit({"type": "facing", "char_id": _active_id(), "direction": direction})


func _on_ability_pressed(ability_id: String, needs_target: bool, target_count: int = 1, targeting_mode: int = 0, ab_range: int = 0) -> void:
	_ability_hover_range = {}
	_selected_ability_range = ab_range
	_selected_ability_targeting_mode = targeting_mode
	var active_char: Dictionary = _find_char_dict(_active_id())
	if not active_char.is_empty() and ab_range > 0:
		_ability_hover_range = {
			"range": ab_range,
			"char_pos": Vector2i(int(active_char["pos"]["x"]), int(active_char["pos"]["y"])),
		}
	if needs_target:
		_selected_ability_id = ability_id
		_pending_targets = []
		_pending_target_count = maxi(1, target_count)
		_pending_target_tile = Vector2i(-1, -1)
		match targeting_mode:
			AbilityData.TargetingMode.CHARACTER:
				_input_mode = "select_ability_target"
			AbilityData.TargetingMode.TILE, AbilityData.TargetingMode.TILE_AND_DIRECTION:
				_input_mode = "select_ability_tile"
			_:
				_input_mode = "select_ability_target"
		_update_ui()
		queue_redraw()
	else:
		_selected_ability_id = ""
		_selected_ability_range = 0
		_selected_ability_targeting_mode = 0
		_ability_hover_range = {}
		_submit({"type": "ability", "char_id": _active_id(), "ability_id": ability_id})


func _on_ability_btn_hover(ab_range: int, desc: String, btn: Button) -> void:
	var active_char: Dictionary = _find_char_dict(_active_id())
	if not active_char.is_empty() and ab_range > 0:
		_ability_hover_range = {
			"range"    : ab_range,
			"char_pos" : Vector2i(int(active_char["pos"]["x"]), int(active_char["pos"]["y"])),
		}
	if desc != "":
		_tooltip_label.text = desc
		_tooltip_panel.visible = true
		var gp : Vector2 = btn.get_screen_position()
		var vp := get_viewport_rect().size
		_tooltip_panel.reset_size()
		_tooltip_panel.position = Vector2(
			clampf(gp.x, 0.0, vp.x - _tooltip_panel.size.x),
			maxf(0.0, gp.y - _tooltip_panel.size.y - 4.0)
		)
	queue_redraw()


func _on_ability_btn_exit() -> void:
	_ability_hover_range = {}
	_tooltip_panel.visible = false
	queue_redraw()


func _submit(action: Dictionary) -> void:
	emit_signal("action_submitted", action)


func _active_id() -> String:
	return _state.get("active_char", "")

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		match ke.keycode:
			KEY_A: _pan_left  = ke.pressed
			KEY_D: _pan_right = ke.pressed
			KEY_W: _pan_up    = ke.pressed
			KEY_S: _pan_down  = ke.pressed
		return

	if event is InputEventMouseMotion:
		var mm   := event as InputEventMouseMotion
		var tile := _screen_to_tile(mm.position)
		if tile != _hovered:
			_hovered = tile
			_hover_char_dict = _char_dict_at_tile(tile)
			queue_redraw()
		_check_portrait_hover(mm.position)
		return

	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var tile := _screen_to_tile(mb.position)
	if tile.x < 0 or tile.y < 0:
		return
	var aid := _active_id()
	match _input_mode:
		"select_move":
			_input_mode = "none"
			_submit({"type": "move", "char_id": aid, "dest": {"x": tile.x, "y": tile.y, "z": 0}})
			_update_ui()
			queue_redraw()
		"select_attack":
			var tid := _char_id_at_tile(tile)
			if not tid.is_empty():
				_input_mode = "none"
				_submit({"type": "attack", "char_id": aid, "target_id": tid})
				_update_ui()
				queue_redraw()
		"select_ability_target":
			var tid := _char_id_at_tile(tile)
			if not tid.is_empty() and not _pending_targets.has(tid):
				_pending_targets.append(tid)
				if _pending_targets.size() >= _pending_target_count:
					_input_mode = "none"
					_submit({"type": "ability", "char_id": aid,
						"ability_id"  : _selected_ability_id,
						"target_id"   : _pending_targets[0],
						"target_ids"  : _pending_targets.duplicate()})
					_selected_ability_id = ""
					_selected_ability_range = 0
					_selected_ability_targeting_mode = 0
					_pending_targets = []
					_pending_target_count = 0
					_ability_hover_range = {}
					_update_ui()
					queue_redraw()
		"select_ability_tile":
			if _selected_ability_targeting_mode == AbilityData.TargetingMode.TILE_AND_DIRECTION:
				_pending_target_tile = tile
				_input_mode = "select_ability_direction"
				_update_ui()
				queue_redraw()
			else:
				_input_mode = "none"
				_submit({
					"type": "ability",
					"char_id": aid,
					"ability_id": _selected_ability_id,
					"target_tile": {"x": tile.x, "y": tile.y, "z": 0},
				})
				_selected_ability_id = ""
				_selected_ability_range = 0
				_selected_ability_targeting_mode = 0
				_pending_target_tile = Vector2i(-1, -1)
				_ability_hover_range = {}
				_update_ui()
				queue_redraw()


func _check_portrait_hover(mouse_pos: Vector2) -> void:
	for slot in _portrait_slots:
		var ctrl: Control = slot["control"]
		if not is_instance_valid(ctrl):
			continue
		var gr: Rect2 = Rect2(ctrl.get_global_rect().position, ctrl.size)
		if gr.has_point(mouse_pos):
			var lines: Array = slot["equip_lines"]
			if lines.size() > 0:
				_tooltip_label.text = "\n".join(lines)
				_tooltip_panel.visible = true
				var vp := get_viewport_rect().size
				_tooltip_panel.reset_size()
				_tooltip_panel.position = Vector2(
					clampf(mouse_pos.x + 8.0, 0.0, vp.x - _tooltip_panel.size.x),
					maxf(0.0, mouse_pos.y - _tooltip_panel.size.y - 4.0)
				)
			return
	if _ability_hover_range.is_empty():
		_tooltip_panel.visible = false


func _build_equip_lines(cd: Dictionary) -> Array[String]:
	var lines : Array[String] = []
	var equip : Dictionary    = cd.get("equipment", {})
	if equip.has("main_hand"):
		var mh : Dictionary = equip["main_hand"]
		var kw : String     = ", ".join(mh.get("keywords", []))
		lines.append("Main: %s  %s %s  r%d" % [
			mh.get("name","?"), mh.get("damage","?"), mh.get("damage_type","?"), int(mh.get("range",1))
		])
		if int(mh.get("mag_capacity", 0)) > 0:
			lines.append("  Mag: %d/%d" % [int(mh.get("loaded_ammo", 0)), int(mh.get("mag_capacity", 0))])
		if kw != "":
			lines.append("  [%s]" % kw)
	if equip.has("off_hand"):
		var oh : Dictionary = equip["off_hand"]
		match oh.get("kind","item"):
			"weapon":
				lines.append("Off:  %s  %s" % [oh.get("name","?"), oh.get("damage","?")])
				if int(oh.get("mag_capacity", 0)) > 0:
					lines.append("  Mag: %d/%d" % [int(oh.get("loaded_ammo", 0)), int(oh.get("mag_capacity", 0))])
			"shield": lines.append("Off:  %s  Ev+%d" % [oh.get("name","?"), int(oh.get("evasion_bonus",0))])
			_:        lines.append("Off:  %s" % oh.get("name","?"))
	if equip.has("armor"):
		var ar : Dictionary = equip["armor"]
		lines.append("Armor: %s  AV:%d  Ev:%+d  Mv:%+d" % [
			ar.get("name","?"), int(ar.get("av",0)), int(ar.get("evasion",0)), int(ar.get("movement",0))
		])
	var buffs: Array = cd.get("active_buffs", [])
	if buffs.size() > 0:
		lines.append("Buffs: %s" % ", ".join(buffs))
	return lines

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _state.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(40.0, 100.0), "Waiting for server…",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		return

	var map_d              : Dictionary = _state.get("map", {})
	var tiles              : Array      = map_d.get("tiles", [])
	var boundaries         : Array      = map_d.get("boundaries", [])
	var chars              : Array      = _state.get("characters", [])
	var active_id          : String     = _state.get("active_char", "")
	var movable_tiles      : Array      = _state.get("movable_tiles", [])
	var attackable_targets : Array      = _state.get("attackable_targets", [])

	# Ability range preview tiles (manhattan distance from active char).
	var range_tiles: Dictionary = {}
	if not _ability_hover_range.is_empty():
		var rng    : int      = _ability_hover_range.get("range", 0)
		var origin : Vector2i = _ability_hover_range.get("char_pos", Vector2i(-999,-999))
		if rng > 0:
			for t in tiles:
				if abs(int(t["x"]) - origin.x) + abs(int(t["y"]) - origin.y) <= rng:
					range_tiles["%d,%d" % [int(t["x"]), int(t["y"])]] = true

	for t in tiles:
		var tpos := _tile_pos(t["x"], t["y"])
		var rect  := Rect2(tpos, Vector2(_tile_size_px, _tile_size_px))
		draw_rect(rect, C_TILE, true)
		draw_rect(rect, C_TILE_BORDER, false, 1.0)
		if _hovered.x == t["x"] and _hovered.y == t["y"]:
			draw_rect(rect, C_HOVER, true)
		var tkey: String = "%d,%d" % [int(t["x"]), int(t["y"])]
		if range_tiles.has(tkey):
			draw_rect(rect, C_RANGE_PREVIEW, true)
		if _input_mode == "select_move":
			for mt in movable_tiles:
				if mt["x"] == t["x"] and mt["y"] == t["y"]:
					draw_rect(rect, C_SEL_MOVE, true)
					break
		elif _input_mode == "select_attack":
			for cdd in chars:
				if not attackable_targets.has(cdd["id"]):
					continue
				var cp: Dictionary = cdd["pos"]
				if cp["x"] == t["x"] and cp["y"] == t["y"]:
					draw_rect(rect, C_SEL_ATTACK, true)
		elif _input_mode == "select_ability_target":
			for cdd in chars:
				var cp: Dictionary = cdd["pos"]
				if cp["x"] == t["x"] and cp["y"] == t["y"]:
					var acd: Dictionary = _find_char_dict(active_id)
					if cdd["player_id"] == acd.get("player_id",""):
						draw_rect(rect, Color(0.20, 0.60, 1.00, 0.28), true)
					else:
						draw_rect(rect, C_SEL_ATTACK, true)
		if not _visible_tiles.is_empty() and not _visible_tiles.has("%d,%d" % [t["x"], t["y"]]):
			draw_rect(rect, C_FOG, true)

	for bd in boundaries:
		_draw_boundary(bd)
	for cd in chars:
		_draw_character(cd, active_id)
	if not _hover_char_dict.is_empty():
		_draw_hover_popup(_hover_char_dict)


func _draw_boundary(bd: Dictionary) -> void:
	var a  : Dictionary = bd["a"]
	var b  : Dictionary = bd["b"]
	var dx : int = int(b["x"]) - int(a["x"])
	var dy : int = int(b["y"]) - int(a["y"])
	if abs(dx) + abs(dy) != 1:
		return
	var color : Color
	var width : float
	if bd.get("wall", false):
		color = C_WALL
		width = maxf(2.0, _tile_size_px * 0.09)
	elif bd.get("barricade", false):
		color = C_BARRICADE
		width = maxf(2.0, _tile_size_px * 0.06)
	elif bd.get("ladder", false):
		color = C_LADDER
		width = maxf(1.5, _tile_size_px * 0.05)
	else:
		return
	var origin := _tile_pos(a["x"], a["y"])
	var p1 : Vector2
	var p2 : Vector2
	if dx == 1:
		p1 = origin + Vector2(_tile_size_px, 0.0)
		p2 = origin + Vector2(_tile_size_px, _tile_size_px)
	elif dx == -1:
		p1 = origin
		p2 = origin + Vector2(0.0, _tile_size_px)
	elif dy == 1:
		p1 = origin + Vector2(0.0, _tile_size_px)
		p2 = origin + Vector2(_tile_size_px, _tile_size_px)
	elif dy == -1:
		p1 = origin
		p2 = origin + Vector2(_tile_size_px, 0.0)
	else:
		return
	draw_line(p1, p2, color, width)


func _draw_character(cd: Dictionary, active_id: String) -> void:
	var state_int  : int        = int(cd["state"])
	var pos        : Dictionary = cd["pos"]
	var char_id    : String     = cd["id"]
	var player_id  : String     = cd["player_id"]
	var tile_origin := _tile_pos(pos["x"], pos["y"])
	var char_pad     : float = clampf(_tile_size_px * 0.10, 2.0, CHAR_PAD_BASE)
	var hp_bar_h     : float = clampf(_tile_size_px * 0.08, 2.0, HP_BAR_H_BASE)
	var hp_bar_margin: float = clampf(_tile_size_px * 0.03, 1.0, HP_BAR_MARGIN_BASE)
	var sq_w : float = maxf(6.0, _tile_size_px - char_pad * 2.0)
	var sq_h : float = maxf(6.0, _tile_size_px - char_pad * 2.0 - hp_bar_h - hp_bar_margin)
	var sq_rect := Rect2(tile_origin + Vector2(char_pad, char_pad), Vector2(sq_w, sq_h))
	var fill: Color
	match state_int:
		CharacterData.StateFlag.DEAD:         fill = C_DEAD
		CharacterData.StateFlag.KNOCKED_DOWN: fill = C_KNOCKED
		_: fill = C_TEAM_A if player_id == "player_a" else C_TEAM_B
	draw_rect(sq_rect, fill, true)
	if char_id == active_id:
		draw_rect(sq_rect, C_ACTIVE_RING, false, 2.5)
	else:
		draw_rect(sq_rect, fill.lightened(0.25), false, 1.0)
	if state_int == CharacterData.StateFlag.KNOCKED_DOWN:
		draw_line(sq_rect.position, sq_rect.end, Color.WHITE, 2.0)
		draw_line(sq_rect.position + Vector2(sq_w, 0.0), sq_rect.position + Vector2(0.0, sq_h), Color.WHITE, 2.0)
	if cd.get("is_crouched", false):
		draw_rect(sq_rect, C_CROUCHED, true)
	var font  := ThemeDB.fallback_font
	var fsize : int = clamp(int(_tile_size_px * 0.22), 9, 14)
	draw_string(font, sq_rect.get_center() + Vector2(-fsize * 0.3, fsize * 0.4),
		cd["name"].substr(0,1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.WHITE)
	if state_int != CharacterData.StateFlag.DEAD:
		var facing_idx : int     = int(cd.get("facing",0)) % FACING_VECS.size()
		var fv         : Vector2 = (FACING_VECS[facing_idx] as Vector2).normalized()
		var center     : Vector2 = sq_rect.get_center()
		var tip        : Vector2 = center + fv * sq_w * 0.30
		var perp       : Vector2 = Vector2(-fv.y, fv.x)
		draw_colored_polygon(PackedVector2Array([
			tip,
			center + perp * sq_w * 0.12,
			center - perp * sq_w * 0.12,
		]), C_FACING)
	_draw_hp_bars(cd, tile_origin)


func _draw_hp_bars(cd: Dictionary, tile_origin: Vector2) -> void:
	var char_pad     : float = clampf(_tile_size_px * 0.10, 2.0, CHAR_PAD_BASE)
	var hp_bar_h     : float = clampf(_tile_size_px * 0.08, 2.0, HP_BAR_H_BASE)
	var hp_bar_margin: float = clampf(_tile_size_px * 0.03, 1.0, HP_BAR_MARGIN_BASE)
	var bar_x     : float = tile_origin.x + char_pad
	var bar_y     : float = tile_origin.y + _tile_size_px - hp_bar_h - hp_bar_margin
	var bar_total : float = maxf(6.0, _tile_size_px - char_pad * 2.0)
	if cd.has("hp_state"):
		draw_string(ThemeDB.fallback_font, Vector2(bar_x, bar_y), cd.get("hp_state","?"),
			HORIZONTAL_ALIGNMENT_LEFT, bar_total, 8, Color(1.0, 0.8, 0.8))
		return
	var segs      : Array = cd.get("hp_segments",[])
	var seg_maxs  : Array = cd.get("hp_seg_max",[])
	var disabled  : Array = cd.get("hp_disabled",[])
	var seg_state  : Array = cd.get("hp_seg_state",[])
	var armor_hp  : float = cd.get("armor_hp",0.0)
	var armor_max : float = cd.get("armor_max_hp",0.0)
	if segs.is_empty():
		return
	var total_max: float = 0.0
	for m in seg_maxs:
		total_max += float(m)
	if armor_max > 0.0:
		total_max += armor_max
	if total_max <= 0.0:
		return
	var gap       : float = 1.0
	var draw_segs : Array = []
	for i in range(segs.size() - 1, -1, -1):
		draw_segs.append({
			"cur"     : float(segs[i]),
			"max"     : float(seg_maxs[i]) if i < seg_maxs.size() else 0.0,
			"disabled": (i < disabled.size() and disabled[i]),
			"state"   : int(seg_state[i]) if i < seg_state.size() else ((i < disabled.size() and disabled[i]) ? 2 : 0),
			"armor"   : false,
		})
	if armor_max > 0.0:
		draw_segs.append({"cur": armor_hp, "max": armor_max, "disabled": false, "armor": true})
	var seg_x: float = 0.0
	for seg in draw_segs:
		var sm : float = seg["max"]
		var sw : float = bar_total * (sm / total_max) - gap
		var sr := Rect2(bar_x + seg_x, bar_y, sw, hp_bar_h)
		if int(seg.get("state", 0)) == 2:
			draw_rect(sr, C_HP_DISABLED, true)
		elif int(seg.get("state", 0)) == 1:
			draw_rect(sr, C_HP_BROKEN, true)
		elif seg["armor"]:
			draw_rect(sr, Color(0.4, 0.3, 0.0), true)
			var ff: float = (seg["cur"] / sm) if sm > 0.0 else 0.0
			if ff > 0.0:
				draw_rect(Rect2(bar_x + seg_x, bar_y, sw * ff, hp_bar_h), Color(1.0, 0.85, 0.2), true)
		else:
			draw_rect(sr, C_HP_BG, true)
			var ff: float = (seg["cur"] / sm) if sm > 0.0 else 0.0
			if ff > 0.0:
				draw_rect(Rect2(bar_x + seg_x, bar_y, sw * ff, hp_bar_h), C_HP_FULL.lerp(C_HP_LOW, 1.0 - ff), true)
		draw_rect(sr, C_HP_BORDER, false, 0.8)
		seg_x += sw + gap


func _draw_hover_popup(cd: Dictionary) -> void:
	var font    := ThemeDB.fallback_font
	var fsize   : int   = 11
	var line_h  : float = float(fsize) + 3.0
	var padding : float = 6.0
	var is_mine : bool  = (cd.get("player_id","") == local_player_id)
	var lines   : Array[String] = []
	lines.append(cd.get("name","?"))
	var class_names: Array = ["Warrior","Ranger","Mage","Rogue","Cleric","Fighter","Marksman","Brawler"]
	var ci : int = int(cd.get("class",0))
	lines.append("Class: %s" % (class_names[ci] if ci < class_names.size() else "?"))
	if is_mine:
		var segs     : Array = cd.get("hp_segments",[])
		var seg_maxs : Array = cd.get("hp_seg_max",[])
		var seg_state: Array = cd.get("hp_seg_state",[])
		var cur : float = 0.0
		var mx  : float = 0.0
		for i in segs.size():
			cur += float(segs[i])
			if i < seg_maxs.size() and (i >= seg_state.size() or int(seg_state[i]) == 0):
				mx += float(seg_maxs[i])
		lines.append("HP: %d / %d" % [int(cur), int(mx)])
	else:
		lines.append("Status: %s" % cd.get("hp_state","?"))
	var equip: Dictionary = cd.get("equipment",{})
	if equip.has("main_hand"):
		lines.append("Main: %s (%s)" % [equip["main_hand"].get("name","?"), equip["main_hand"].get("damage","?")])
	if equip.has("off_hand"):
		lines.append("Off: %s" % equip["off_hand"].get("name","?"))
	if equip.has("armor"):
		lines.append("Armor: %s (AV %d)" % [equip["armor"].get("name","?"), equip["armor"].get("av",0)])
	var tile_origin : Vector2 = _tile_pos(_hovered.x, _hovered.y)
	var popup_w     : float   = 160.0
	var popup_h     : float   = padding * 2.0 + line_h * float(lines.size())
	var vp_size     : Vector2 = get_viewport_rect().size
	var px : float = tile_origin.x + _tile_size_px + 4.0
	var py : float = clampf(tile_origin.y, TOP_BAR_H, vp_size.y - HUD_BOTTOM_H - popup_h)
	if px + popup_w > vp_size.x:
		px = tile_origin.x - popup_w - 4.0
	draw_rect(Rect2(px, py, popup_w, popup_h), Color(0.0, 0.0, 0.0, 0.80), true)
	draw_rect(Rect2(px, py, popup_w, popup_h), Color(0.6, 0.6, 0.6, 0.60), false, 1.0)
	var team_color: Color = C_TEAM_A if cd.get("player_id","") == "player_a" else C_TEAM_B
	for i in lines.size():
		draw_string(font, Vector2(px + padding, py + padding + line_h * float(i) + float(fsize)),
			lines[i], HORIZONTAL_ALIGNMENT_LEFT, popup_w - padding * 2.0, fsize,
			team_color if i == 0 else Color.WHITE)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _compute_int_seg_maxes(seg_maxs: Array) -> Array:
	if seg_maxs.is_empty():
		return []
	var total_int : int = 0
	for m in seg_maxs:
		total_int += int(roundf(float(m)))
	var result    : Array = []
	var allocated : int   = 0
	for i in range(seg_maxs.size() - 1):
		var v: int = ceili(float(seg_maxs[i]))
		result.append(v)
		allocated += v
	result.append(maxi(0, total_int - allocated))
	return result


func _find_char_dict(char_id: String) -> Dictionary:
	for cd in _state.get("characters",[]):
		if cd["id"] == char_id:
			return cd
	return {}


func _char_id_at_tile(tile: Vector2i) -> String:
	for cd in _state.get("characters",[]):
		var p: Dictionary = cd["pos"]
		if p["x"] == tile.x and p["y"] == tile.y:
			return cd["id"]
	return ""


func _char_dict_at_tile(tile: Vector2i) -> Dictionary:
	if tile.x < 0 or tile.y < 0:
		return {}
	for cd in _state.get("characters",[]):
		var p: Dictionary = cd["pos"]
		if p["x"] == tile.x and p["y"] == tile.y:
			return cd
	return {}
