## LobbyScene.gd
## Client lobby — shown before connecting to a server.
## Tabs: Play (IP + connect), Roster (character management), Merchant (WIP).
## All roster changes are saved immediately to local storage via RosterManager.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player clicks Connect with a valid party.
signal connect_requested(ip: String)

# ---------------------------------------------------------------------------
# Resource manifests (same hardcoded paths as ServerGame)
# ---------------------------------------------------------------------------

const WEAPON_FILES: Array[String] = [
	"res://resources/weapons/longsword.tres",
	"res://resources/weapons/sword.tres",
	"res://resources/weapons/battleaxe.tres",
	"res://resources/weapons/greataxe.tres",
	"res://resources/weapons/handaxe.tres",
	"res://resources/weapons/dagger.tres",
	"res://resources/weapons/greatsword.tres",
	"res://resources/weapons/longbow.tres",
	"res://resources/weapons/shortbow.tres",
	"res://resources/weapons/hand_crossbow.tres",
	"res://resources/weapons/light_crossbow.tres",
	"res://resources/weapons/heavy_crossbow.tres",
	"res://resources/weapons/rifle.tres",
	"res://resources/weapons/ancient_tome.tres",
	"res://resources/weapons/crystal_ball.tres",
]
const ARMOR_FILES: Array[String] = [
	"res://resources/armor/full_plate.tres",
	"res://resources/armor/chain_mail.tres",
	"res://resources/armor/breastplate.tres",
	"res://resources/armor/ring_mail.tres",
	"res://resources/armor/studded_leather.tres",
	"res://resources/armor/hide.tres",
	"res://resources/armor/bandit_outfit.tres",
	"res://resources/armor/rangers_robes.tres",
	"res://resources/armor/mages_kefta.tres",
	"res://resources/armor/simple_gabardine.tres",
]
const SHIELD_FILES: Array[String] = [
	"res://resources/shields/round_shield.tres",
	"res://resources/shields/tower_shield.tres",
]
const BUFF_FILES: Array[String] = [
	"res://resources/buffs/chained_censer.tres",
	"res://resources/buffs/crypt_candle.tres",
	"res://resources/buffs/dream_catcher.tres",
]
const ABILITY_FILES: Array[String] = [
	"res://resources/abilities/achiles_bane.tres",
	"res://resources/abilities/drain_life.tres",
	"res://resources/abilities/hip_shot.tres",
	"res://resources/abilities/peek_shot.tres",
	"res://resources/abilities/reckless_assault.tres",
	"res://resources/abilities/regenerate.tres",
	"res://resources/abilities/riposte.tres",
]
## class_int matches CharacterData.CharacterClass enum values.
const CLASS_ENTRIES: Array = [
	{"label": "Fighter",  "char_class": 5, "path": "res://resources/classes/fighter.tres"},
	{"label": "Marksman", "char_class": 6, "path": "res://resources/classes/marksman.tres"},
	{"label": "Mage",     "char_class": 2, "path": "res://resources/classes/mage.tres"},
	{"label": "Cleric",   "char_class": 4, "path": "res://resources/classes/cleric.tres"},
	{"label": "Brawler",  "char_class": 7, "path": "res://resources/classes/brawler.tres"},
	{"label": "Ranger",   "char_class": 1, "path": "res://resources/classes/ranger.tres"},
	{"label": "Rogue",    "char_class": 3, "path": "res://resources/classes/rogue.tres"},
]

# ---------------------------------------------------------------------------
# Loaded resources
# ---------------------------------------------------------------------------

var _weapons:      Array = []   # WeaponData
var _armors:       Array = []   # ArmorData
var _off_hands:    Array = []   # EquipmentData (shields + buffs + light weapons)
var _abilities:    Array = []   # AbilityData

# ---------------------------------------------------------------------------
# UI node references — Play tab
# ---------------------------------------------------------------------------

var _play_ip:          LineEdit
var _play_connect_btn: Button
var _play_status:      Label

# ---------------------------------------------------------------------------
# UI node references — Roster tab
# ---------------------------------------------------------------------------

var _party_count_lbl:  Label
var _char_list_vbox:   VBoxContainer
var _editor_root:      Control   # scrollable editor area
var _editor_inner:     VBoxContainer  # inside the scroll
var _btn_new_char:     Button
var _btn_save_char:    Button

var _ed_name:          LineEdit
var _ed_class:         OptionButton
var _ed_stats:         Array = []   # Array[SpinBox], ordered [STR, DEX, CON, WIS, INT]
var _ed_derived:       Label
var _ed_main:          OptionButton
var _ed_off:           OptionButton
var _ed_armor:         OptionButton
var _ed_equip_err:     Label
var _ed_skills:        Array = []   # Array[CheckBox]
var _ed_skill_err:     Label
var _delete_dialog:    ConfirmationDialog
var _delete_target_idx: int = -1
var _result_dialog:    AcceptDialog

# ---------------------------------------------------------------------------
# Editor state
# ---------------------------------------------------------------------------

var _editor_idx: int  = -1
var _loading:    bool = false   # suppresses signals while programmatically loading

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_resources()
	_build_ui()
	RosterManager.roster_changed.connect(_on_roster_changed)
	_refresh_char_list()

# ---------------------------------------------------------------------------
# Resource loading
# ---------------------------------------------------------------------------

func _load_resources() -> void:
	for path in WEAPON_FILES:
		var r: Resource = load(path)
		if r is WeaponData:
			_weapons.append(r as WeaponData)
		else:
			push_warning("LobbyScene: could not load weapon: %s" % path)

	for path in ARMOR_FILES:
		var r: Resource = load(path)
		if r is ArmorData:
			_armors.append(r as ArmorData)

	# Off-hand: shields first, then buffs, then light weapons.
	for path in SHIELD_FILES:
		var r: Resource = load(path)
		if r != null:
			_off_hands.append(r)
	for path in BUFF_FILES:
		var r: Resource = load(path)
		if r != null:
			_off_hands.append(r)
	for w in _weapons:
		if (w as WeaponData).is_light_weapon():
			_off_hands.append(w)

	for path in ABILITY_FILES:
		var r: Resource = load(path)
		if r is AbilityData:
			_abilities.append(r as AbilityData)

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Delete Character"
	_delete_dialog.dialog_text = "Delete this character from your local roster?"
	_delete_dialog.confirmed.connect(_on_delete_char_confirmed)
	layer.add_child(_delete_dialog)

	_result_dialog = AcceptDialog.new()
	_result_dialog.title = "Match Result"
	layer.add_child(_result_dialog)

	var root_panel := PanelContainer.new()
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	root_panel.add_child(margin)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(outer_vbox)

	var title := Label.new()
	title.text = "Cage Brawlers"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(title)

	var tab := TabContainer.new()
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("side_margin", 6)
	outer_vbox.add_child(tab)

	tab.add_child(_build_play_tab())
	tab.add_child(_build_roster_tab())
	tab.add_child(_build_merchant_tab())

# ---------------------------------------------------------------------------
# Play tab
# ---------------------------------------------------------------------------

func _build_play_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "Play"
	vbox.add_theme_constant_override("separation", 10)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	vbox.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	margin.add_child(inner)

	var lbl_server := Label.new()
	lbl_server.text = "Server IP Address"
	lbl_server.add_theme_font_size_override("font_size", 14)
	inner.add_child(lbl_server)

	var hbox_ip := HBoxContainer.new()
	hbox_ip.add_theme_constant_override("separation", 8)
	inner.add_child(hbox_ip)

	_play_ip = LineEdit.new()
	_play_ip.placeholder_text = "127.0.0.1"
	_play_ip.text = "127.0.0.1"
	_play_ip.custom_minimum_size = Vector2(260.0, 0.0)
	_play_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_ip.add_child(_play_ip)

	_play_connect_btn = Button.new()
	_play_connect_btn.text = "Connect"
	_play_connect_btn.custom_minimum_size = Vector2(100.0, 0.0)
	_play_connect_btn.pressed.connect(_on_connect_pressed)
	hbox_ip.add_child(_play_connect_btn)

	_play_status = Label.new()
	_play_status.text = ""
	_play_status.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	inner.add_child(_play_status)

	var hint := Label.new()
	hint.text = (
		"Make sure your party of 3 characters is selected in the Roster tab.\n"
		+ "Port: %d" % NetworkManager.DEFAULT_PORT
	)
	hint.modulate = Color(0.75, 0.75, 0.75)
	hint.add_theme_font_size_override("font_size", 12)
	inner.add_child(hint)

	return vbox

# ---------------------------------------------------------------------------
# Roster tab
# ---------------------------------------------------------------------------

func _build_roster_tab() -> Control:
	var hbox := HBoxContainer.new()
	hbox.name = "Roster"
	hbox.add_theme_constant_override("separation", 0)

	# --- Left panel: character list ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260.0, 0.0)
	left.add_theme_constant_override("separation", 4)
	hbox.add_child(left)

	var roster_hdr := HBoxContainer.new()
	roster_hdr.add_theme_constant_override("separation", 8)
	left.add_child(roster_hdr)

	var lbl_roster := Label.new()
	lbl_roster.text = "Roster"
	lbl_roster.add_theme_font_size_override("font_size", 14)
	lbl_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_hdr.add_child(lbl_roster)

	_btn_new_char = Button.new()
	_btn_new_char.text = "New"
	_btn_new_char.tooltip_text = "Create a new local character"
	_btn_new_char.pressed.connect(_on_new_char_pressed)
	roster_hdr.add_child(_btn_new_char)

	_party_count_lbl = Label.new()
	_party_count_lbl.text = "Party: 0/3"
	_party_count_lbl.add_theme_font_size_override("font_size", 12)
	roster_hdr.add_child(_party_count_lbl)

	left.add_child(HSeparator.new())

	var scroll_chars := ScrollContainer.new()
	scroll_chars.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_chars.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll_chars)

	_char_list_vbox = VBoxContainer.new()
	_char_list_vbox.add_theme_constant_override("separation", 4)
	_char_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_chars.add_child(_char_list_vbox)

	# --- Separator ---
	var sep := VSeparator.new()
	hbox.add_child(sep)

	# --- Right panel: editor ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	hbox.add_child(right)

	var scroll_editor := ScrollContainer.new()
	scroll_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_editor.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll_editor)

	_editor_inner = VBoxContainer.new()
	_editor_inner.add_theme_constant_override("separation", 6)
	_editor_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_editor.add_child(_editor_inner)

	_show_editor_placeholder()

	return hbox

func _show_editor_placeholder() -> void:
	for c in _editor_inner.get_children():
		c.queue_free()
	var lbl := Label.new()
	lbl.text = "Select a character from the roster to edit."
	lbl.modulate = Color(0.7, 0.7, 0.7)
	lbl.add_theme_font_size_override("font_size", 13)
	_editor_inner.add_child(lbl)

# ---------------------------------------------------------------------------
# Editor population
# ---------------------------------------------------------------------------

func _select_char(idx: int) -> void:
	_editor_idx = idx
	_load_editor(RosterManager.roster[idx])

func _load_editor(cd: Dictionary) -> void:
	_loading = true

	for c in _editor_inner.get_children():
		c.queue_free()

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 4)
	_editor_inner.add_child(m)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	m.add_child(vbox)

	# -- Name ---------------------------------------------------------------
	var name_hbox := HBoxContainer.new()
	name_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(name_hbox)

	var lbl_name := Label.new()
	lbl_name.text = "Name:"
	lbl_name.custom_minimum_size = Vector2(72.0, 0.0)
	name_hbox.add_child(lbl_name)

	_ed_name = LineEdit.new()
	_ed_name.text = cd.get("character_name", "")
	_ed_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ed_name.text_changed.connect(_on_name_changed)
	name_hbox.add_child(_ed_name)

	_btn_save_char = Button.new()
	_btn_save_char.text = "Save"
	_btn_save_char.tooltip_text = "Save all changes for this character"
	_btn_save_char.pressed.connect(_on_save_char_pressed)
	name_hbox.add_child(_btn_save_char)

	# -- Class --------------------------------------------------------------
	var class_hbox := HBoxContainer.new()
	class_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(class_hbox)

	var lbl_class := Label.new()
	lbl_class.text = "Class:"
	lbl_class.custom_minimum_size = Vector2(72.0, 0.0)
	class_hbox.add_child(lbl_class)

	_ed_class = OptionButton.new()
	_ed_class.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current_class: int = int(cd.get("character_class", 5))
	var class_sel_idx: int = 0
	for i in CLASS_ENTRIES.size():
		var entry: Dictionary = CLASS_ENTRIES[i]
		_ed_class.add_item(entry["label"])
		_ed_class.set_item_metadata(i, entry)
		if entry["char_class"] == current_class:
			class_sel_idx = i
	_ed_class.select(class_sel_idx)
	_ed_class.item_selected.connect(_on_class_changed)
	class_hbox.add_child(_ed_class)

	vbox.add_child(HSeparator.new())

	# -- Stats --------------------------------------------------------------
	var lbl_stats := Label.new()
	lbl_stats.text = "Stats"
	lbl_stats.add_theme_font_size_override("font_size", 13)
	vbox.add_child(lbl_stats)

	var stat_grid := GridContainer.new()
	stat_grid.columns = 4
	stat_grid.add_theme_constant_override("h_separation", 8)
	stat_grid.add_theme_constant_override("v_separation", 3)
	vbox.add_child(stat_grid)

	var stat_defs: Array = [
		{"label": "STR", "key": "strength"},
		{"label": "DEX", "key": "dexterity"},
		{"label": "CON", "key": "constitution"},
		{"label": "WIS", "key": "wisdom"},
		{"label": "INT", "key": "intelligence"},
	]
	_ed_stats.clear()
	for i in stat_defs.size():
		var stat_def: Dictionary = stat_defs[i]
		var lbl := Label.new()
		lbl.text = stat_def["label"] + ":"
		lbl.custom_minimum_size = Vector2(40.0, 0.0)
		stat_grid.add_child(lbl)

		var sp := SpinBox.new()
		sp.min_value = 1
		sp.max_value = 30
		sp.value = int(cd.get(stat_def["key"], 10))
		sp.custom_minimum_size = Vector2(72.0, 0.0)
		sp.value_changed.connect(_on_stat_changed.bind(i))
		stat_grid.add_child(sp)
		_ed_stats.append(sp)

	vbox.add_child(HSeparator.new())

	# -- Derived stats display ---------------------------------------------
	var lbl_derived_hdr := Label.new()
	lbl_derived_hdr.text = "Derived Stats"
	lbl_derived_hdr.add_theme_font_size_override("font_size", 13)
	vbox.add_child(lbl_derived_hdr)

	_ed_derived = Label.new()
	_ed_derived.add_theme_font_size_override("font_size", 11)
	_ed_derived.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_ed_derived)

	vbox.add_child(HSeparator.new())

	# -- Equipment and Skills sub-tabs ------------------------------------
	var subtab := TabContainer.new()
	subtab.custom_minimum_size = Vector2(0.0, 280.0)
	vbox.add_child(subtab)

	subtab.add_child(_build_equipment_tab(cd))
	subtab.add_child(_build_skills_tab(cd))

	_loading = false
	_refresh_derived_stats()

# ---------------------------------------------------------------------------
# Equipment sub-tab
# ---------------------------------------------------------------------------

func _build_equipment_tab(cd: Dictionary) -> Control:
	var vb := VBoxContainer.new()
	vb.name = "Equipment"
	vb.add_theme_constant_override("separation", 6)

	var inner_m := MarginContainer.new()
	inner_m.add_theme_constant_override("margin_left", 6)
	inner_m.add_theme_constant_override("margin_top", 6)
	vb.add_child(inner_m)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	inner_m.add_child(inner)

	# Main hand
	var mh_row := _make_equip_row("Main Hand:")
	_ed_main = _make_weapon_option()
	_set_option_to_path(_ed_main, cd.get("main_hand_path", null))
	_ed_main.item_selected.connect(_on_main_hand_changed)
	mh_row.add_child(_ed_main)
	inner.add_child(mh_row)

	# Off hand
	var oh_row := _make_equip_row("Off Hand:")
	_ed_off = _make_off_hand_option()
	_set_option_to_path(_ed_off, cd.get("off_hand_path", null))
	_ed_off.item_selected.connect(_on_off_hand_changed)
	oh_row.add_child(_ed_off)
	inner.add_child(oh_row)

	# Armor
	var ar_row := _make_equip_row("Armor:")
	_ed_armor = _make_armor_option()
	_set_option_to_path(_ed_armor, cd.get("armor_path", null))
	_ed_armor.item_selected.connect(_on_armor_changed)
	ar_row.add_child(_ed_armor)
	inner.add_child(ar_row)

	# Equipment error label
	_ed_equip_err = Label.new()
	_ed_equip_err.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_ed_equip_err.add_theme_font_size_override("font_size", 11)
	_ed_equip_err.text = ""
	inner.add_child(_ed_equip_err)

	inner.add_child(HSeparator.new())

	# Ammo counts
	var lbl_ammo := Label.new()
	lbl_ammo.text = "Ammo & Consumables"
	lbl_ammo.add_theme_font_size_override("font_size", 12)
	inner.add_child(lbl_ammo)

	var ammo_grid := GridContainer.new()
	ammo_grid.columns = 4
	ammo_grid.add_theme_constant_override("h_separation", 8)
	ammo_grid.add_theme_constant_override("v_separation", 3)
	inner.add_child(ammo_grid)

	var ammo_defs: Array = [
		{"label": "Bullets:", "key": "bullets_count"},
		{"label": "Bolts:",   "key": "bolts_count"},
		{"label": "Arrows:",  "key": "arrows_count"},
		{"label": "Potions:", "key": "potions_count"},
	]
	for ammo_def in ammo_defs:
		var lbl := Label.new()
		lbl.text = ammo_def["label"]
		ammo_grid.add_child(lbl)
		var sp := SpinBox.new()
		sp.min_value = 0
		sp.max_value = 20
		sp.value = int(cd.get(ammo_def["key"], 0))
		sp.custom_minimum_size = Vector2(72.0, 0.0)
		sp.value_changed.connect(_on_ammo_changed.bind(ammo_def["key"]))
		ammo_grid.add_child(sp)

	_update_off_hand_availability()
	return vb

func _make_equip_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(84.0, 0.0)
	row.add_child(lbl)
	return row

func _make_weapon_option() -> OptionButton:
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_item("(none)")
	ob.set_item_metadata(0, null)
	for w in _weapons:
		var idx: int = ob.get_item_count()
		ob.add_item(w.item_name)
		ob.set_item_metadata(idx, w.resource_path)
	return ob

func _make_off_hand_option() -> OptionButton:
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_item("(none)")
	ob.set_item_metadata(0, null)
	for item in _off_hands:
		var idx: int = ob.get_item_count()
		var prefix: String = ""
		if item is WeaponData:
			prefix = "[Light] "
		elif item.get_class() == "ShieldData" or item is ShieldData:
			prefix = "[Shield] "
		else:
			prefix = "[Buff] "
		ob.add_item(prefix + item.item_name)
		ob.set_item_metadata(idx, item.resource_path)
	return ob

func _make_armor_option() -> OptionButton:
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_item("(none)")
	ob.set_item_metadata(0, null)
	for a in _armors:
		var idx: int = ob.get_item_count()
		ob.add_item(a.item_name)
		ob.set_item_metadata(idx, a.resource_path)
	return ob

func _set_option_to_path(ob: OptionButton, path: Variant) -> void:
	if path == null or path == "":
		ob.select(0)
		return
	for i in ob.get_item_count():
		if ob.get_item_metadata(i) == path:
			ob.select(i)
			return
	ob.select(0)

func _get_option_path(ob: OptionButton) -> Variant:
	if ob.selected < 0:
		return null
	return ob.get_item_metadata(ob.selected)

# ---------------------------------------------------------------------------
# Skills sub-tab
# ---------------------------------------------------------------------------

func _build_skills_tab(cd: Dictionary) -> Control:
	var vb := VBoxContainer.new()
	vb.name = "Skills"
	vb.add_theme_constant_override("separation", 5)

	var inner_m := MarginContainer.new()
	inner_m.add_theme_constant_override("margin_left", 6)
	inner_m.add_theme_constant_override("margin_top", 6)
	vb.add_child(inner_m)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner_m.add_child(inner)

	var lbl := Label.new()
	lbl.text = "Active Abilities (max 4)"
	lbl.add_theme_font_size_override("font_size", 12)
	inner.add_child(lbl)

	var hint := Label.new()
	hint.text = "Selected abilities will be available in battle."
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.75, 0.75, 0.75)
	inner.add_child(hint)

	var active_ids: Array = cd.get("ability_ids", [])
	_ed_skills.clear()
	for ab in _abilities:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		inner.add_child(row)

		var cb := CheckBox.new()
		cb.text = ab.entry_name
		cb.button_pressed = active_ids.has(ab.entry_id)
		cb.toggled.connect(_on_skill_toggled.bind(_ed_skills.size()))
		row.add_child(cb)
		_ed_skills.append(cb)

		var desc := Label.new()
		desc.text = "(%s)" % ab.entry_id
		desc.add_theme_font_size_override("font_size", 10)
		desc.modulate = Color(0.7, 0.7, 0.7)
		row.add_child(desc)

	_ed_skill_err = Label.new()
	_ed_skill_err.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_ed_skill_err.add_theme_font_size_override("font_size", 11)
	_ed_skill_err.text = ""
	inner.add_child(_ed_skill_err)

	return vb

# ---------------------------------------------------------------------------
# Merchant tab
# ---------------------------------------------------------------------------

func _build_merchant_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "Merchant"

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	vbox.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	margin.add_child(inner)

	var lbl := Label.new()
	lbl.text = "Merchant"
	lbl.add_theme_font_size_override("font_size", 18)
	inner.add_child(lbl)

	var wip := Label.new()
	wip.text = "🚧 Work in Progress — not yet available."
	wip.modulate = Color(0.7, 0.7, 0.7)
	wip.add_theme_font_size_override("font_size", 14)
	inner.add_child(wip)

	return vbox

# ---------------------------------------------------------------------------
# Char list refresh
# ---------------------------------------------------------------------------

func _refresh_char_list() -> void:
	if not _char_list_vbox:
		return
	for c in _char_list_vbox.get_children():
		c.queue_free()

	var party_count: int = RosterManager.party_indices.size()
	if _party_count_lbl:
		_party_count_lbl.text = "Party: %d/3" % party_count

	for i in RosterManager.roster.size():
		var cd: Dictionary = RosterManager.roster[i]
		var card := _make_char_card(i, cd)
		_char_list_vbox.add_child(card)

func _make_char_card(idx: int, cd: Dictionary) -> Control:
	var outer := PanelContainer.new()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	outer.add_child(hbox)

	# Party checkbox
	var cb := CheckBox.new()
	cb.button_pressed = RosterManager.is_in_party(idx)
	cb.tooltip_text = "Add/remove from party (max 3)"
	cb.toggled.connect(_on_party_toggle.bind(idx, cb))
	hbox.add_child(cb)

	# Name + class info
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 1)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_lbl := Label.new()
	name_lbl.text = cd.get("character_name", "Unknown")
	name_lbl.add_theme_font_size_override("font_size", 13)
	info_vbox.add_child(name_lbl)

	var class_lbl := Label.new()
	class_lbl.text = _class_label(int(cd.get("character_class", 5))) + "  Lv.%d" % int(cd.get("level", 1))
	class_lbl.add_theme_font_size_override("font_size", 11)
	class_lbl.modulate = Color(0.8, 0.8, 0.8)
	info_vbox.add_child(class_lbl)

	# Edit button
	var edit_btn := Button.new()
	edit_btn.text = "Edit"
	edit_btn.custom_minimum_size = Vector2(48.0, 0.0)
	if _editor_idx == idx:
		edit_btn.modulate = Color(0.6, 1.0, 0.6)
	edit_btn.pressed.connect(_select_char.bind(idx))
	hbox.add_child(edit_btn)

	# Delete button
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.custom_minimum_size = Vector2(62.0, 0.0)
	del_btn.pressed.connect(_on_delete_char_pressed.bind(idx))
	hbox.add_child(del_btn)

	return outer

func _class_label(char_class_int: int) -> String:
	for entry in CLASS_ENTRIES:
		if entry["char_class"] == char_class_int:
			return entry["label"]
	return "Class %d" % char_class_int

# ---------------------------------------------------------------------------
# Derived stats
# ---------------------------------------------------------------------------

func _refresh_derived_stats() -> void:
	if not _ed_derived or _editor_idx < 0 or _editor_idx >= RosterManager.roster.size():
		return
	var cd: CharacterData = RosterManager.dict_to_char(RosterManager.roster[_editor_idx])
	var lines: Array = []

	# Movement
	lines.append("Move: %d tiles/turn" % cd.get_base_movement_speed())

	# Max HP
	lines.append("Max HP: %.0f" % cd.get_max_hp())

	# Evasion
	var ev_char: int = cd.get_character_evasion()
	var ev_equip: int = cd.get_equipment_evasion()
	lines.append("Evasion: %d (char) + %d (equip) = %d total" % [ev_char, ev_equip, ev_char + ev_equip])

	# Attack info for each equipped weapon
	_append_weapon_stats(lines, cd, cd.main_hand_slot, "Main")

	if cd.off_hand_slot is WeaponData:
		_append_weapon_stats(lines, cd, cd.off_hand_slot as WeaponData, "Off")

	# Encumbrance
	var burden: float = cd.get_total_burden_weight()
	var cap: float = cd.get_max_carry_weight()
	if burden > cap:
		lines.append("⚠ Overencumbered! (%.1f/%.1f kg)" % [burden, cap])
	else:
		lines.append("Carry: %.1f / %.1f kg" % [burden, cap])

	_ed_derived.text = "\n".join(lines)

func _append_weapon_stats(lines: Array, cd: CharacterData, weapon: WeaponData, label: String) -> void:
	if weapon == null:
		return
	const BASE_ACC: int = 80
	var acc_bonus: int = _calc_accuracy_bonus(cd, weapon)
	var dmg_bonus: int = _calc_damage_bonus(cd, weapon)
	var accuracy: int = BASE_ACC + acc_bonus
	var crit_pct: int = maxi(0, accuracy - 100)
	var is_two_handed_grip: bool = weapon.is_versatile() and cd.off_hand_slot == null
	var dice: Array[int] = weapon.get_effective_damage_dice(is_two_handed_grip)
	var dice_str: String = "%dd%d" % [dice[0], dice[1]]
	var dmg_str: String = "%s%+d" % [dice_str, dmg_bonus] if dmg_bonus != 0 else dice_str
	var rel: float = weapon.base_reliability
	var rel_str: String = (" rel:+%d%%" % int(rel * 100.0)) if rel > 0.0 else ""
	var crit_str: String = (" crit:%d%%" % crit_pct) if crit_pct > 0 else ""
	lines.append(
		"%s Atk: %s  acc:%d%%%s%s  (%s)" % [
			label, weapon.item_name, accuracy, crit_str, rel_str, weapon.get_damage_type_name()
		]
	)
	lines.append("  Dmg: %s" % dmg_str)

func _calc_accuracy_bonus(cd: CharacterData, weapon: WeaponData) -> int:
	match weapon.damage_type:
		WeaponData.DamageType.PHYSICAL:
			if weapon.is_finesse():
				return cd.stat_bonus(cd.dexterity) * 10  # finesse doubles DEX bonus
			return cd.stat_bonus(cd.dexterity) * 5
		WeaponData.DamageType.RANGED:
			return cd.stat_bonus(cd.intelligence) * 5
		WeaponData.DamageType.MAGICAL:
			return ((cd.stat_bonus(cd.intelligence) + cd.stat_bonus(cd.wisdom)) / 2) * 5
	return 0

func _calc_damage_bonus(cd: CharacterData, weapon: WeaponData) -> int:
	match weapon.damage_type:
		WeaponData.DamageType.PHYSICAL:
			if weapon.is_finesse():
				return cd.stat_bonus(cd.wisdom)
			return cd.stat_bonus(cd.strength)
		WeaponData.DamageType.RANGED:
			return cd.stat_bonus(cd.wisdom)
		WeaponData.DamageType.MAGICAL:
			return (cd.stat_bonus(cd.wisdom) + cd.stat_bonus(cd.intelligence)) / 2
	return 0

# ---------------------------------------------------------------------------
# Off-hand availability (disable if 2H weapon in main hand)
# ---------------------------------------------------------------------------

func _update_off_hand_availability() -> void:
	if not _ed_off or not _ed_main:
		return
	var main_path: Variant = _get_option_path(_ed_main)
	var is_two_handed: bool = false
	if main_path is String and main_path != "":
		var w: Resource = load(main_path)
		if w is WeaponData:
			is_two_handed = (w as WeaponData).is_two_handed()
	_ed_off.disabled = is_two_handed
	if is_two_handed:
		_ed_off.select(0)

# ---------------------------------------------------------------------------
# Signals — Play tab
# ---------------------------------------------------------------------------

func _on_connect_pressed() -> void:
	if not RosterManager.party_is_valid():
		_play_status.text = "⚠ Select exactly 3 characters in the Roster tab."
		return
	var ip: String = _play_ip.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	_play_status.text = "Connecting to %s…" % ip
	_play_connect_btn.disabled = true
	emit_signal("connect_requested", ip)

## Called by Main.gd when the connection fails so the player can retry.
func on_connection_failed() -> void:
	_play_status.text = "⚠ Connection failed. Check IP and try again."
	_play_connect_btn.disabled = false

## Called by Main.gd after both players have sent their rosters but before
## the server has started the match.
func on_waiting_for_opponent() -> void:
	_play_status.text = "Connected. Waiting for opponent…"

# ---------------------------------------------------------------------------
# Signals — Party toggle
# ---------------------------------------------------------------------------

func _on_party_toggle(_pressed: bool, idx: int, cb: CheckBox) -> void:
	var err: String = RosterManager.toggle_party_member(idx)
	if err != "":
		# Revert the checkbox
		cb.button_pressed = RosterManager.is_in_party(idx)
		_play_status.text = "⚠ " + err

# ---------------------------------------------------------------------------
# Signals — Editor name / class / stats
# ---------------------------------------------------------------------------

func _on_name_changed(new_text: String) -> void:
	if _loading or _editor_idx < 0:
		return
	var cd: Dictionary = RosterManager.roster[_editor_idx].duplicate()
	cd["character_name"] = new_text
	RosterManager.update_char(_editor_idx, cd)

func _on_class_changed(option_idx: int) -> void:
	if _loading or _editor_idx < 0:
		return
	var entry: Dictionary = _ed_class.get_item_metadata(option_idx)
	var cd: Dictionary = RosterManager.roster[_editor_idx].duplicate()
	cd["character_class"] = entry["char_class"]
	cd["class_data_path"] = entry["path"]
	RosterManager.update_char(_editor_idx, cd)
	_refresh_derived_stats()

func _on_stat_changed(_value: float, stat_idx: int) -> void:
	if _loading or _editor_idx < 0:
		return
	var stat_keys: Array[String] = ["strength", "dexterity", "constitution", "wisdom", "intelligence"]
	var cd: Dictionary = RosterManager.roster[_editor_idx].duplicate()
	cd[stat_keys[stat_idx]] = int(_ed_stats[stat_idx].value)
	RosterManager.update_char(_editor_idx, cd)
	_refresh_derived_stats()

# ---------------------------------------------------------------------------
# Signals — Editor equipment
# ---------------------------------------------------------------------------

func _on_main_hand_changed(_idx: int) -> void:
	if _loading or _editor_idx < 0:
		return
	_update_off_hand_availability()
	var cd: Dictionary = RosterManager.roster[_editor_idx].duplicate()
	cd["main_hand_path"] = _get_option_path(_ed_main)
	# If two-handed, clear off-hand in the dict too.
	var main_path: Variant = cd["main_hand_path"]
	if main_path is String and main_path != "":
		var w: Resource = load(main_path)
		if w is WeaponData and (w as WeaponData).is_two_handed():
			cd["off_hand_path"] = null
	var err: String = RosterManager.validate_equipment(cd.get("main_hand_path"), cd.get("off_hand_path"))
	_ed_equip_err.text = err
	RosterManager.update_char(_editor_idx, cd)
	_refresh_derived_stats()

func _on_off_hand_changed(_idx: int) -> void:
	if _loading or _editor_idx < 0:
		return
	var cd: Dictionary = RosterManager.roster[_editor_idx].duplicate()
	cd["off_hand_path"] = _get_option_path(_ed_off)
	var err: String = RosterManager.validate_equipment(cd.get("main_hand_path"), cd.get("off_hand_path"))
	_ed_equip_err.text = err
	if err != "":
		# Revert off-hand selection to none.
		_ed_off.select(0)
		cd["off_hand_path"] = null
	RosterManager.update_char(_editor_idx, cd)
	_refresh_derived_stats()

func _on_armor_changed(_idx: int) -> void:
	if _loading or _editor_idx < 0:
		return
	var cd: Dictionary = RosterManager.roster[_editor_idx].duplicate()
	cd["armor_path"] = _get_option_path(_ed_armor)
	RosterManager.update_char(_editor_idx, cd)
	_refresh_derived_stats()

func _on_ammo_changed(value: float, key: String) -> void:
	if _loading or _editor_idx < 0:
		return
	var cd: Dictionary = RosterManager.roster[_editor_idx].duplicate()
	cd[key] = int(value)
	RosterManager.update_char(_editor_idx, cd)

# ---------------------------------------------------------------------------
# Signals — Editor skills
# ---------------------------------------------------------------------------

func _on_skill_toggled(pressed: bool, skill_idx: int) -> void:
	if _loading or _editor_idx < 0:
		return
	var cd: Dictionary = RosterManager.roster[_editor_idx].duplicate()
	var ids: Array = Array(cd.get("ability_ids", []))

	if pressed:
		# Count currently selected
		var count: int = 0
		for cb in _ed_skills:
			if cb.button_pressed:
				count += 1
		if count > 4:
			_ed_skill_err.text = "⚠ Max 4 active abilities."
			_ed_skills[skill_idx].button_pressed = false
			return
		_ed_skill_err.text = ""
		var ab: AbilityData = _abilities[skill_idx]
		if not ids.has(ab.entry_id):
			ids.append(ab.entry_id)
	else:
		_ed_skill_err.text = ""
		if skill_idx < _abilities.size():
			ids.erase(_abilities[skill_idx].entry_id)

	cd["ability_ids"] = ids
	RosterManager.update_char(_editor_idx, cd)

# ---------------------------------------------------------------------------
# Signals — Editor save/new
# ---------------------------------------------------------------------------

func _on_save_char_pressed() -> void:
	_save_current_character()

func _on_new_char_pressed() -> void:
	var new_idx: int = RosterManager.create_new_char()
	_editor_idx = new_idx
	_refresh_char_list()
	if new_idx >= 0 and new_idx < RosterManager.roster.size():
		_load_editor(RosterManager.roster[new_idx])
		_play_status.text = "Created new character. Edit and save as needed."

func _on_delete_char_pressed(idx: int) -> void:
	if idx < 0 or idx >= RosterManager.roster.size():
		return
	_delete_target_idx = idx
	var char_name: String = str(RosterManager.roster[idx].get("character_name", "this character"))
	_delete_dialog.dialog_text = "Delete '%s' from your local roster?" % char_name
	_delete_dialog.popup_centered()

func _on_delete_char_confirmed() -> void:
	if _delete_target_idx < 0:
		return
	var err: String = RosterManager.remove_char(_delete_target_idx)
	if err != "":
		_play_status.text = "⚠ " + err
		_delete_target_idx = -1
		return

	if RosterManager.roster.is_empty():
		_editor_idx = -1
		_show_editor_placeholder()
		_play_status.text = "Character deleted."
		_delete_target_idx = -1
		return

	if _editor_idx == _delete_target_idx:
		_editor_idx = mini(_delete_target_idx, RosterManager.roster.size() - 1)
		_load_editor(RosterManager.roster[_editor_idx])
	elif _editor_idx > _delete_target_idx:
		_editor_idx -= 1

	_play_status.text = "Character deleted."
	_delete_target_idx = -1

func _save_current_character() -> void:
	if _editor_idx < 0 or _editor_idx >= RosterManager.roster.size():
		return
	var cd: Dictionary = RosterManager.roster[_editor_idx].duplicate(true)

	if _ed_name:
		cd["character_name"] = _ed_name.text.strip_edges()
	if str(cd.get("character_name", "")) == "":
		cd["character_name"] = "Unnamed"

	if _ed_class and _ed_class.selected >= 0:
		var class_entry: Dictionary = _ed_class.get_item_metadata(_ed_class.selected)
		cd["character_class"] = int(class_entry["char_class"])
		cd["class_data_path"] = class_entry["path"]

	var stat_keys: Array[String] = ["strength", "dexterity", "constitution", "wisdom", "intelligence"]
	for i in min(_ed_stats.size(), stat_keys.size()):
		cd[stat_keys[i]] = int(_ed_stats[i].value)

	if _ed_main:
		cd["main_hand_path"] = _get_option_path(_ed_main)
	if _ed_off:
		cd["off_hand_path"] = _get_option_path(_ed_off)
	if _ed_armor:
		cd["armor_path"] = _get_option_path(_ed_armor)

	var ids: Array[String] = []
	for i in min(_ed_skills.size(), _abilities.size()):
		if _ed_skills[i].button_pressed:
			ids.append((_abilities[i] as AbilityData).entry_id)
	cd["ability_ids"] = ids

	var equip_err: String = RosterManager.validate_equipment(cd.get("main_hand_path"), cd.get("off_hand_path"))
	if _ed_equip_err:
		_ed_equip_err.text = equip_err
	if equip_err != "":
		_play_status.text = "⚠ " + equip_err
		return

	if ids.size() > 4:
		if _ed_skill_err:
			_ed_skill_err.text = "⚠ Max 4 active abilities."
		_play_status.text = "⚠ Max 4 active abilities."
		return
	if _ed_skill_err:
		_ed_skill_err.text = ""

	RosterManager.update_char(_editor_idx, cd)
	_refresh_derived_stats()
	_play_status.text = "Character saved locally."

# ---------------------------------------------------------------------------
# Roster change (external)
# ---------------------------------------------------------------------------

func _on_roster_changed() -> void:
	_refresh_char_list()
	# Re-load editor content if the selected char was changed externally.
	if _editor_idx >= 0 and _editor_idx < RosterManager.roster.size():
		_refresh_derived_stats()
	elif RosterManager.roster.is_empty():
		_editor_idx = -1
		_show_editor_placeholder()

# ---------------------------------------------------------------------------
# Public — called by Main.gd when server disconnects mid-lobby
# ---------------------------------------------------------------------------

func on_disconnected() -> void:
	_play_status.text = "Disconnected from server."
	_play_connect_btn.disabled = false

func on_match_result(won: bool, winner_player_id: String, summary: Dictionary = {}) -> void:
	_play_connect_btn.disabled = false
	var outcome: String = "Victory" if won else "Defeat"
	var gold_line: String = ""
	if summary.has("gold_earned"):
		gold_line = "\nGold earned: %d" % int(summary.get("gold_earned", 0))
	_result_dialog.dialog_text = "%s\nWinner: %s%s" % [outcome, winner_player_id, gold_line]
	_result_dialog.popup_centered()
