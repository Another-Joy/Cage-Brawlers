## RosterManager.gd
## Autoload singleton that manages the player's local character roster.
## Persists all roster data to user://roster.json as plain JSON.
## Provides party selection (up to 3 characters) for use in battle.
extends Node

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SAVE_PATH: String = "user://roster.json"
const DEFAULT_NEW_CLASS: int = 5  # Fighter
const DEFAULT_NEW_CLASS_PATH: String = "res://resources/classes/fighter.tres"

## Hardcoded manifest of default character .tres files used when no save
## exists (team_a + team_b characters from the repository resources).
const DEFAULT_CHAR_FILES: Array[String] = [
	"res://resources/characters/team_a/01_phys.tres",
	"res://resources/characters/team_a/02_ranged.tres",
	"res://resources/characters/team_a/03_magic.tres",
	"res://resources/characters/team_b/01_phys.tres",
	"res://resources/characters/team_b/02_ranged.tres",
	"res://resources/characters/team_b/03_magic.tres",
]

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted whenever the roster or party selection changes.
signal roster_changed()

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Full roster as an array of character Dictionaries (serialised CharacterData).
var roster: Array = []
## Indices into roster[] that form the active party (max 3).
var party_indices: Array = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	load_roster()

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func load_roster() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var text: String = f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary and parsed.has("roster"):
				roster = []
				for raw_char in parsed["roster"]:
					if raw_char is Dictionary:
						roster.append(_normalise_char_dict(raw_char as Dictionary))
				party_indices = []
				for idx in parsed.get("party_indices", []):
					var clean_idx: int = int(idx)
					if clean_idx >= 0 and clean_idx < roster.size() and not party_indices.has(clean_idx):
						party_indices.append(clean_idx)
				roster_changed.emit()
				return
	_create_defaults()
	save_roster()

func save_roster() -> void:
	var data: Dictionary = {
		"roster": roster,
		"party_indices": party_indices,
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

# ---------------------------------------------------------------------------
# Default creation — load from bundled .tres files
# ---------------------------------------------------------------------------

func _create_defaults() -> void:
	roster = []
	party_indices = []
	for path in DEFAULT_CHAR_FILES:
		var res: Resource = load(path)
		if res is CharacterData:
			roster.append(char_to_dict(res as CharacterData))
		else:
			push_error("RosterManager: failed to load default character: %s" % path)
	# Select first 3 as default party.
	for i in mini(3, roster.size()):
		party_indices.append(i)

# ---------------------------------------------------------------------------
# Party management
# ---------------------------------------------------------------------------

func is_in_party(roster_idx: int) -> bool:
	return party_indices.has(roster_idx)

## Adds or removes a character from the party.
## Returns an error string if the party is full, or "" on success.
func toggle_party_member(roster_idx: int) -> String:
	if roster_idx < 0 or roster_idx >= roster.size():
		return "Invalid roster index."
	if party_indices.has(roster_idx):
		party_indices.erase(roster_idx)
		save_roster()
		roster_changed.emit()
		return ""
	if party_indices.size() >= 3:
		return "Party is full (max 3). Remove a character first."
	party_indices.append(roster_idx)
	save_roster()
	roster_changed.emit()
	return ""

func get_party_dicts() -> Array:
	var result: Array = []
	for idx in party_indices:
		if idx < roster.size():
			result.append(roster[idx].duplicate())
	return result

func party_is_valid() -> bool:
	return party_indices.size() == 3

# ---------------------------------------------------------------------------
# Roster editing helpers
# ---------------------------------------------------------------------------

func update_char(roster_idx: int, char_dict: Dictionary) -> void:
	if roster_idx < 0 or roster_idx >= roster.size():
		return
	roster[roster_idx] = _normalise_char_dict(char_dict)
	save_roster()
	roster_changed.emit()

func add_char(char_dict: Dictionary) -> void:
	roster.append(_normalise_char_dict(char_dict))
	save_roster()
	roster_changed.emit()

func create_new_char(character_name: String = "") -> int:
	var next_index: int = roster.size() + 1
	var id_suffix: String = str(Time.get_unix_time_from_system())
	var new_dict: Dictionary = {
		"character_id": "custom_%s_%d" % [id_suffix, next_index],
		"character_name": character_name if character_name != "" else "New Brawler %d" % next_index,
		"character_class": DEFAULT_NEW_CLASS,
		"class_data_path": DEFAULT_NEW_CLASS_PATH,
		"level": 1,
		"experience": 0,
		"strength": 10,
		"dexterity": 10,
		"constitution": 10,
		"wisdom": 10,
		"intelligence": 10,
		"main_hand_path": null,
		"off_hand_path": null,
		"armor_path": null,
		"bullets_count": 0,
		"bolts_count": 0,
		"arrows_count": 0,
		"potions_count": 0,
		"ability_ids": [],
	}
	roster.append(new_dict)
	save_roster()
	roster_changed.emit()
	return roster.size() - 1

func remove_char(roster_idx: int) -> String:
	if roster_idx < 0 or roster_idx >= roster.size():
		return "Invalid roster index."
	roster.remove_at(roster_idx)

	# Rebuild party indices after removal.
	var updated_party: Array = []
	for idx in party_indices:
		var p: int = int(idx)
		if p == roster_idx:
			continue
		if p > roster_idx:
			p -= 1
		if p >= 0 and p < roster.size() and not updated_party.has(p):
			updated_party.append(p)
	party_indices = updated_party

	save_roster()
	roster_changed.emit()
	return ""

# ---------------------------------------------------------------------------
# Serialisation helpers (CharacterData ↔ Dictionary)
# ---------------------------------------------------------------------------

## Converts a CharacterData resource to a JSON-safe Dictionary.
func char_to_dict(cd: CharacterData) -> Dictionary:
	var ab_ids: Array = []
	for tree in cd.skill_trees:
		for entry in tree:
			if entry is AbilityData:
				ab_ids.append((entry as AbilityData).entry_id)
	return {
		"character_id":    cd.character_id,
		"character_name":  cd.character_name,
		"character_class": int(cd.character_class),
		"class_data_path": _res_path(cd.class_data),
		"level":           cd.level,
		"experience":      cd.experience,
		"strength":        cd.strength,
		"dexterity":       cd.dexterity,
		"constitution":    cd.constitution,
		"wisdom":          cd.wisdom,
		"intelligence":    cd.intelligence,
		"main_hand_path":  _res_path(cd.main_hand_slot),
		"off_hand_path":   _res_path(cd.off_hand_slot),
		"armor_path":      _res_path(cd.armor_slot),
		"bullets_count":   cd.bullets_count,
		"bolts_count":     cd.bolts_count,
		"arrows_count":    cd.arrows_count,
		"potions_count":   cd.potions_count,
		"ability_ids":     ab_ids,
	}

## Reconstructs a CharacterData resource from a saved Dictionary.
## Loads sub-resources (weapons, armor, class) from their stored paths.
func dict_to_char(d: Dictionary) -> CharacterData:
	var cd: CharacterData = CharacterData.new()
	cd.character_id    = d.get("character_id", "")
	cd.character_name  = d.get("character_name", "Unknown")
	cd.character_class = int(d.get("character_class", 0))
	cd.level           = int(d.get("level", 1))
	cd.experience      = int(d.get("experience", 0))
	cd.strength        = int(d.get("strength", 10))
	cd.dexterity       = int(d.get("dexterity", 10))
	cd.constitution    = int(d.get("constitution", 10))
	cd.wisdom          = int(d.get("wisdom", 10))
	cd.intelligence    = int(d.get("intelligence", 10))
	cd.bullets_count   = int(d.get("bullets_count", 0))
	cd.bolts_count     = int(d.get("bolts_count", 0))
	cd.arrows_count    = int(d.get("arrows_count", 0))
	cd.potions_count   = int(d.get("potions_count", 0))

	var class_path: Variant = d.get("class_data_path", null)
	if class_path is String and class_path != "":
		cd.class_data = load(class_path) as ClassData

	var mh: Variant = d.get("main_hand_path", null)
	if mh is String and mh != "":
		cd.main_hand_slot = load(mh) as WeaponData

	var oh: Variant = d.get("off_hand_path", null)
	if oh is String and oh != "":
		cd.off_hand_slot = load(oh) as EquipmentData

	var ar: Variant = d.get("armor_path", null)
	if ar is String and ar != "":
		cd.armor_slot = load(ar) as ArmorData

	cd.skill_trees = [[], [], []]
	return cd

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

## Checks if a proposed equipment combination is legal.
## Returns "" if legal, or an error string describing the violation.
static func validate_equipment(
		main_hand_path: Variant,
		off_hand_path: Variant) -> String:

	if main_hand_path == null or main_hand_path == "":
		return ""  # No main hand — always valid.

	var main_hand: Resource = load(main_hand_path)
	if not (main_hand is WeaponData):
		return ""

	var weapon: WeaponData = main_hand as WeaponData

	# Two-handed lockout: cannot equip anything in off-hand.
	if weapon.is_two_handed() and off_hand_path != null and off_hand_path != "":
		return "Cannot equip an off-hand item with a two-handed weapon."

	if off_hand_path == null or off_hand_path == "":
		return ""

	var off_item: Resource = load(off_hand_path)
	if off_item == null:
		return ""

	# Off-hand weapons must have the Light keyword.
	if off_item is WeaponData:
		var off_weapon: WeaponData = off_item as WeaponData
		if not off_weapon.is_light_weapon():
			return "Off-hand weapons must have the Light keyword."

	return ""

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

static func _res_path(res: Resource) -> Variant:
	if res == null:
		return null
	return res.resource_path

func _normalise_char_dict(raw: Dictionary) -> Dictionary:
	var clean: Dictionary = raw.duplicate(true)
	if clean.get("character_id", "") == "":
		clean["character_id"] = "char_%s" % str(Time.get_unix_time_from_system())
	clean["character_name"] = str(clean.get("character_name", "Unknown"))
	clean["character_class"] = int(clean.get("character_class", DEFAULT_NEW_CLASS))
	clean["class_data_path"] = clean.get("class_data_path", DEFAULT_NEW_CLASS_PATH)
	clean["level"] = int(clean.get("level", 1))
	clean["experience"] = int(clean.get("experience", 0))
	clean["strength"] = int(clean.get("strength", 10))
	clean["dexterity"] = int(clean.get("dexterity", 10))
	clean["constitution"] = int(clean.get("constitution", 10))
	clean["wisdom"] = int(clean.get("wisdom", 10))
	clean["intelligence"] = int(clean.get("intelligence", 10))
	clean["bullets_count"] = int(clean.get("bullets_count", 0))
	clean["bolts_count"] = int(clean.get("bolts_count", 0))
	clean["arrows_count"] = int(clean.get("arrows_count", 0))
	clean["potions_count"] = int(clean.get("potions_count", 0))
	var raw_ids: Array = Array(clean.get("ability_ids", []))
	var ids: Array[String] = []
	for v in raw_ids:
		var id: String = str(v)
		if id != "" and not ids.has(id):
			ids.append(id)
	clean["ability_ids"] = ids
	return clean
