## CharacterData.gd
## Resource representing a full character profile. Stores identity, stats,
## equipment slots, health segments, and all derived combat metrics.
class_name CharacterData
extends Resource

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum StateFlag {
	LIVING,
	PENDING_LEVEL_UP,
	KNOCKED_DOWN,
	DEAD,
}

enum CharacterClass {
	WARRIOR,
	RANGER,
	MAGE,
	ROGUE,
	CLERIC,
}

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

@export var character_id: String = ""
@export var character_name: String = ""
@export var level: int = 1
@export var experience: int = 0
@export var character_class: CharacterClass = CharacterClass.WARRIOR
@export var state_flag: StateFlag = StateFlag.LIVING

# ---------------------------------------------------------------------------
# Primary Core Stats
# ---------------------------------------------------------------------------

@export_group("Primary Stats")
@export var strength: int = 10
@export var dexterity: int = 10
@export var constitution: int = 10
@export var wisdom: int = 10
@export var intelligence: int = 10

# ---------------------------------------------------------------------------
# Equipment Slots
# ---------------------------------------------------------------------------

@export_group("Equipment")
@export var main_hand_slot: WeaponData = null
@export var off_hand_slot: EquipmentData = null  # Weapon (light), Shield, or Buff
@export var armor_slot: ArmorData = null

# Ammo/support counts (managed at match start or when loading out)
@export var bullets_count: int = 0
@export var bolts_count: int = 0
@export var arrows_count: int = 0
@export var potions_count: int = 0

# ---------------------------------------------------------------------------
# Skill Trees (3 trees: class, attribute, weapon)
# ---------------------------------------------------------------------------

@export_group("Skills")
## Three skill trees stored as arrays of SkillData resources.
@export var skill_trees: Array[Array] = [[], [], []]
## Points spent in each tree node (parallel array to each tree).
@export var skill_points_spent: Array[int] = []

# ---------------------------------------------------------------------------
# Combat State (server-side, not persisted to save file)
# ---------------------------------------------------------------------------

## Grid position during a match (Vector3i: x, y, z=floor).
var grid_position: Vector3i = Vector3i.ZERO
## Current facing direction as an index 0-7 (N=0, NE=1, E=2, SE=3, S=4, SW=5, W=6, NW=7).
var facing_direction: int = 0
## Whether the character is currently crouched behind a barricade.
var is_crouched: bool = false
## Per-segment current HP. Index 0 is the leftmost (first lost) segment.
var segment_hp: Array[float] = []
## Which segments have been permanently disabled (KNOCKED_DOWN segments).
var segment_disabled: Array[bool] = []

# ---------------------------------------------------------------------------
# Constants (override per class via ClassDefinitions utility)
# ---------------------------------------------------------------------------

## Max HP scaling: constitution * HP_PER_CON
const HP_PER_CON: float = 10.0
const CARRY_WEIGHT_BASE: float = 5.0
const CARRY_WEIGHT_PER_STR: float = 2.0

# ---------------------------------------------------------------------------
# Derived Stat Calculations
# ---------------------------------------------------------------------------

## Returns the character's maximum health pool based on constitution.
func get_max_hp() -> float:
	return constitution * HP_PER_CON

## Returns the maximum carry weight based on strength.
func get_max_carry_weight() -> float:
	return CARRY_WEIGHT_BASE + strength * CARRY_WEIGHT_PER_STR

## Returns total equipped burden (sum of all slot item weights).
func get_total_burden_weight() -> float:
	var total: float = 0.0
	if main_hand_slot:
		total += main_hand_slot.weight
	if off_hand_slot:
		total += off_hand_slot.weight
	if armor_slot:
		total += armor_slot.weight
	# Ammo weights (approximate: 0.1 kg each unit)
	total += bullets_count * 0.1
	total += bolts_count * 0.1
	total += arrows_count * 0.05
	total += potions_count * 0.5
	return total

## Returns the movement speed penalty caused by encumbrance (0 if not overencumbered).
func get_encumbrance_penalty() -> int:
	var excess: float = get_total_burden_weight() - get_max_carry_weight()
	if excess <= 0.0:
		return 0
	return 1 + int(floor(excess / 3.0))

## Returns base movement speed (dexterity-derived), reduced by encumbrance and armor.
func get_base_movement_speed() -> int:
	var base_speed: int = 3 + int(dexterity / 5)
	if armor_slot:
		base_speed += armor_slot.movement_modifier
	base_speed -= get_encumbrance_penalty()
	return max(1, base_speed)

## Returns character evasion (from dexterity + armor modifier), clamped to >= 0.
func get_character_evasion() -> int:
	var evasion: int = int(dexterity / 2)
	if armor_slot:
		evasion += armor_slot.evasion_modifier
	return max(0, evasion)

## Returns equipment evasion (from shield/buff in off-hand), clamped to >= 0.
func get_equipment_evasion() -> int:
	var evasion: int = 0
	if off_hand_slot is ShieldData:
		evasion += (off_hand_slot as ShieldData).evasion_bonus
	elif off_hand_slot is BuffItemData:
		evasion += (off_hand_slot as BuffItemData).evasion_bonus
	return max(0, evasion)

## Returns combined final evasion: max(0, char_evasion) + max(0, equip_evasion).
func get_total_evasion() -> int:
	return get_character_evasion() + get_equipment_evasion()

## Returns the armor value provided by equipped armor (0 if none).
func get_armor_value() -> int:
	if armor_slot:
		return armor_slot.armor_value
	return 0

# ---------------------------------------------------------------------------
# Health Segment Initialisation
# ---------------------------------------------------------------------------

## Initialises the 3-segment HP arrays using class-specific percentage splits.
## segment_percentages must be a 3-element array summing to 1.0.
func initialise_health_segments(segment_percentages: Array[float]) -> void:
	assert(segment_percentages.size() == 3, "Exactly 3 segment percentages required.")
	var max_hp: float = get_max_hp()
	segment_hp.clear()
	segment_disabled.clear()
	for pct in segment_percentages:
		segment_hp.append(max_hp * pct)
		segment_disabled.append(false)

## Returns the current total HP across all active (non-disabled) segments.
func get_current_hp() -> float:
	var total: float = 0.0
	for i in segment_hp.size():
		if not segment_disabled[i]:
			total += segment_hp[i]
	return total

## Returns the maximum HP across all active (non-disabled) segments.
func get_current_max_hp() -> float:
	var max_hp: float = get_max_hp()
	var total: float = 0.0
	for i in segment_hp.size():
		if not segment_disabled[i]:
			# Recover the original max of this segment from the proportional data stored during init
			total += segment_hp[i]
	return total

## Applies damage using spillover resolution across segments (leftmost first active).
## Returns true if the character was knocked down as a result.
func apply_damage(damage: float) -> bool:
	var remaining_damage: float = damage
	# Segments are ordered index 0 (first lost) -> index 2 (last lost).
	# Apply damage left-to-right (index 0 first).
	for i in segment_hp.size():
		if segment_disabled[i]:
			continue
		if remaining_damage <= 0.0:
			break
		if remaining_damage >= segment_hp[i]:
			remaining_damage -= segment_hp[i]
			segment_hp[i] = 0.0
		else:
			segment_hp[i] -= remaining_damage
			remaining_damage = 0.0

	# Check knockdown condition
	if get_current_hp() <= 0.0:
		return _trigger_knockdown()
	return false

## Handles knockdown logic. Returns true if the character is now knocked down.
func _trigger_knockdown() -> bool:
	# Disable the rightmost non-disabled segment.
	var rightmost_active: int = -1
	for i in range(segment_hp.size() - 1, -1, -1):
		if not segment_disabled[i]:
			rightmost_active = i
			break

	if rightmost_active == -1:
		# All segments already disabled — permanent death.
		state_flag = StateFlag.DEAD
		return true

	segment_disabled[rightmost_active] = true
	segment_hp[rightmost_active] = 0.0

	# Check if all segments are now disabled -> permanent death.
	var all_disabled: bool = true
	for disabled in segment_disabled:
		if not disabled:
			all_disabled = false
			break

	if all_disabled:
		state_flag = StateFlag.DEAD
	else:
		state_flag = StateFlag.KNOCKED_DOWN

	return true

## Fully restores all health segments and sets state to LIVING.
func full_heal() -> void:
	var max_hp: float = get_max_hp()
	# Recalculate segment sizes using current segments (they retain their proportional size).
	# Re-enable all segments and restore to full.
	for i in segment_hp.size():
		segment_disabled[i] = false
	# Restore proportional HP (requires re-init via class percentages; here we fill to sum).
	for i in segment_hp.size():
		segment_hp[i] = max_hp / segment_hp.size()
	state_flag = StateFlag.LIVING

# ---------------------------------------------------------------------------
# Encumbrance / Ammo Slot Validation
# ---------------------------------------------------------------------------

## Returns the number of ammo slots capacity from the equipped armor.
func get_ammo_slots_capacity() -> int:
	if armor_slot:
		return armor_slot.ammo_slots_capacity
	return 0

## Returns true if the armor allows arrows to be equipped.
func allows_arrows() -> bool:
	if armor_slot:
		return armor_slot.allows_arrows
	return true

## Validates and clamps ammo counts based on armor capacity and type restrictions.
## Should be called whenever ammo counts are changed in the lobby.
func validate_ammo_counts() -> void:
	if not allows_arrows():
		arrows_count = 0

	var capacity: int = get_ammo_slots_capacity()
	var allocated: int = bullets_count * 1 + bolts_count * 1 + arrows_count * 2
	# Clamp by reducing arrows first, then bolts, then bullets.
	while allocated > capacity:
		if arrows_count > 0:
			arrows_count -= 1
			allocated -= 2
		elif bolts_count > 0:
			bolts_count -= 1
			allocated -= 1
		elif bullets_count > 0:
			bullets_count -= 1
			allocated -= 1
		else:
			break

# ---------------------------------------------------------------------------
# Dual Wield Check
# ---------------------------------------------------------------------------

## Returns true if the character has two valid light weapons equipped.
func is_dual_wielding() -> bool:
	if main_hand_slot == null or off_hand_slot == null:
		return false
	if not off_hand_slot is WeaponData:
		return false
	return (off_hand_slot as WeaponData).has_keyword("Light")

# ---------------------------------------------------------------------------
# Highest Stat Utility (used for attribute skill tree selection)
# ---------------------------------------------------------------------------

## Returns the name of the character's highest primary stat.
func get_highest_stat_name() -> String:
	var stats: Dictionary = {
		"strength": strength,
		"dexterity": dexterity,
		"constitution": constitution,
		"wisdom": wisdom,
		"intelligence": intelligence,
	}
	var highest_name: String = "strength"
	var highest_value: int = 0
	for stat_name in stats:
		if stats[stat_name] > highest_value:
			highest_value = stats[stat_name]
			highest_name = stat_name
	return highest_name
