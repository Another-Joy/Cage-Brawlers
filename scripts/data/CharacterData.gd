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
	WARRIOR,    ## Legacy value — kept for backward compatibility with saved .tres files.
	RANGER,
	MAGE,
	ROGUE,
	CLERIC,
	FIGHTER,    ## Melee/Tank damage class (Str primary, Dex/Con secondary).
	MARKSMAN,   ## Ranged precision class (Int primary, Wis secondary).
	BRAWLER,    ## Heavy tank class (Con primary, Str secondary).
}

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

@export var character_id: String = ""
@export var character_name: String = ""
@export var level: int = 1
@export var experience: int = 0
@export var character_class: CharacterClass = CharacterClass.WARRIOR
## Full class resource. When set, class-specific values (hit dice, stat
## affinities, segment percentages, weapon categories) are read from here
## rather than from the ClassDefinitions utility. Kept optional so that
## existing character files without a class_data reference continue to work.
@export var class_data: ClassData = null
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
## Three skill trees stored as arrays of SkillTreeEntry resources
## (either SkillData for passive skills or AbilityData for active abilities).
@export var skill_trees: Array[Array] = [[], [], []]
## Random seed used to generate the character's 3 trees deterministically.
@export var skill_tree_seed: int = 0
## Which attribute was selected for the attribute tree.
@export var skill_tree_attribute: String = ""
## Which weapon category was selected for the weapon tree.
@export var skill_tree_weapon_category: int = -1
## IDs of skill nodes that the character has unlocked.
@export var unlocked_skill_ids: Array[String] = []

# ---------------------------------------------------------------------------
# Combat State (server-side, not persisted to save file)
# ---------------------------------------------------------------------------

## Grid position during a match (Vector3i: x, y, z=floor).
var grid_position: Vector3i = Vector3i.ZERO
## Current facing direction as an index 0-7 (N=0, NE=1, E=2, SE=3, S=4, SW=5, W=6, NW=7).
var facing_direction: int = 0
## Whether the character is currently crouched behind a barricade.
var is_crouched: bool = false
## Whether the character has moved during the current turn's Beginning phase.
## Set to true by CombatManager when a move action succeeds.
## Cleared at the start of each of this character's turns.
## Used to enforce the Aiming keyword restriction and NOT_MOVED_THIS_TURN conditions.
var moved_this_turn: bool = false
## Whether the character used Stand Up this turn.
## When true, movement speed is halved for this turn.
## Cleared at the start of each of this character's turns.
var stood_up_this_turn: bool = false
## Current armor HP (separate bar depleted before regular HP; cannot be healed).
## Initialised from equipped armor's AV × character level.
var armor_hp: float = 0.0
## Maximum armor HP (AV × character level).  0 when no armor is equipped.
var armor_max_hp: float = 0.0
## Per-segment current HP. Index 0 is the first segment to drain.
var segment_hp: Array[float] = []
## Which segments have been permanently disabled (KNOCKED_DOWN segments).
var segment_disabled: Array[bool] = []
## The original class-specific percentage split used at initialisation.
## Stored so that full_heal() and get_current_max_hp() can restore correctly.
var _segment_percentages: Array[float] = []
## Tracks remaining cooldown (in turns) for each ability by entry_id.
## Managed by CombatManager: decremented at turn end, set on ability use.
var ability_cooldowns: Dictionary = {}
## Active timed buffs and debuffs on this character.
## Key: buff/debuff identifier (String). Value: turns remaining (int).
## Ticked down at the start of each of this character's turns by CombatManager.
## Not exported — reset on each match load via duplicate(false).
var active_buffs: Dictionary = {}

# ---------------------------------------------------------------------------
# Constants (override per class via ClassDefinitions utility)
# ---------------------------------------------------------------------------

## Max HP scaling: constitution * HP_PER_CON
const HP_PER_CON: float = 10.0
const CARRY_WEIGHT_BASE: float = 0.0
const CARRY_WEIGHT_PER_STR: float = 1.0

# ---------------------------------------------------------------------------
# Derived Stat Calculations
# ---------------------------------------------------------------------------

## Returns the DnD-style stat bonus: (stat_value - 10) / 2 (integer division, can be negative).
func stat_bonus(stat_value: int) -> int:
	return (stat_value - 10) / 2

## Returns the character's maximum health pool.
## When class_data is set, uses level-based hit dice:
##   Level 1: max dice roll (count × sides) + CON_bonus × level_health_modifier
##   Level N (N>1): average dice per additional level + same bonus
## Falls back to constitution × HP_PER_CON for characters without class data.
func get_max_hp() -> float:
	if class_data == null or class_data.hit_dice == null:
		return constitution * HP_PER_CON
	var dice: DiceValue = class_data.hit_dice
	var con_bonus: int = stat_bonus(constitution)
	var health_mod: int = class_data.level_health_modifier
	var hp: float = 0.0
	# Level 1 uses the maximum possible dice result.
	hp += float(dice.count * dice.sides) + float(con_bonus * health_mod)
	# Each additional level uses the average dice result.
	for _lv in range(2, level + 1):
		hp += float(dice.count) * float(dice.sides + 1) / 2.0 + float(con_bonus * health_mod)
	return maxf(1.0, hp)

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
	var ctx: SkillProcessor.SkillContext = SkillProcessor.SkillContext.new(
		self,
		SkillCondition.MajorCondition.ALWAYS,
		self,
		null,
		null)
	total = maxf(0.0, total - float(SkillProcessor.get_weight_reduction(ctx)))
	return total

## Returns the movement speed penalty caused by encumbrance (0 if not overencumbered).
func get_encumbrance_penalty() -> int:
	var excess: float = get_total_burden_weight() - get_max_carry_weight()
	if excess <= 0.0:
		return 0
	return 1 + int(floor(excess / 3.0))

## Returns base movement speed: 4 + max(0, DEX_bonus) − encumbrance + armor modifier.
func get_base_movement_speed() -> int:
	var base_speed: int = 4 + maxi(0, stat_bonus(dexterity))
	if armor_slot:
		base_speed += armor_slot.movement_modifier
	base_speed -= get_encumbrance_penalty()
	return max(1, base_speed)

## Returns character evasion: DEX_bonus + armor modifier, clamped to >= 0.
func get_character_evasion() -> int:
	var evasion: int = stat_bonus(dexterity)*5
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

## Initialises armor HP from equipped armor: AV × character level.
## Must be called after health segments are initialised (at match load time).
func initialise_armor_hp() -> void:
	var av: int = get_armor_value()
	armor_max_hp = float(av * level)
	armor_hp = armor_max_hp

## Initialises the 3-segment HP arrays using class-specific percentage splits.
## segment_percentages must be a 3-element array summing to 1.0.
func initialise_health_segments(segment_percentages: Array[float]) -> void:
	assert(segment_percentages.size() == 3, "Exactly 3 segment percentages required.")
	_segment_percentages = segment_percentages.duplicate()
	var max_hp: float = get_max_hp()
	segment_hp.clear()
	segment_disabled.clear()

	segment_hp.append(ceil(max_hp * segment_percentages[0]))
	segment_hp.append(ceil(max_hp * segment_percentages[1]))
	segment_hp.append(max_hp - segment_hp[0] - segment_hp[1])  # Ensure total HP matches max_hp, avoiding rounding issues.
	segment_disabled = [false, false, false]

## Returns the current total HP across all active (non-disabled) segments.
func get_current_hp() -> float:
	var total: float = 0.0
	for i in segment_hp.size():
		if not segment_disabled[i]:
			total += segment_hp[i]
	return total

## Returns the maximum HP across all active (non-disabled) segments.
func get_current_max_hp() -> float:
	if _segment_percentages.is_empty():
		return get_max_hp()
	var max_hp: float = get_max_hp()
	var total: float = 0.0
	for i in _segment_percentages.size():
		if i < segment_disabled.size() and not segment_disabled[i]:
			total += max_hp * _segment_percentages[i]
	return total

## Applies damage (positive) or healing (negative) to the character.
## Damage depletes armor HP first, then spills into HP segments (index 0 first).
## Healing restores HP segments from the last segment backwards; armor is NOT healed.
## Returns true if the character was knocked down as a result.
func apply_damage(damage: float) -> bool:
	# ── Healing (negative damage) ──────────────────────────────────────────────
	if damage < 0.0:
		var heal: float = -damage
		var max_hp: float = get_max_hp()
		for i in range(segment_hp.size() - 1, -1, -1):
			if segment_disabled[i]:
				continue
			var seg_max: float
			if i < _segment_percentages.size():
				seg_max = max_hp * _segment_percentages[i]
			else:
				seg_max = max_hp / float(segment_hp.size())
			var space: float = maxf(0.0, seg_max - segment_hp[i])
			var applied: float = minf(heal, space)
			segment_hp[i] += applied
			heal -= applied
			if heal <= 0.0:
				break
		# Revive from KNOCKED_DOWN if HP is restored.
		if get_current_hp() > 0.0 and state_flag == StateFlag.KNOCKED_DOWN:
			state_flag = StateFlag.LIVING
		return false

	# ── Damage (positive) ─────────────────────────────────────────────────────
	var remaining_damage: float = damage

	# Armor HP is depleted before regular HP (cannot be healed back).
	if armor_hp > 0.0 and remaining_damage > 0.0:
		var absorbed: float = minf(remaining_damage, armor_hp)
		armor_hp -= absorbed
		remaining_damage -= absorbed

	# Apply remaining damage to HP segments (index 0 first).
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
## Armor HP is intentionally NOT restored — armor cannot be healed.
## Uses the stored class-specific percentages to restore correct proportional HP.
func full_heal() -> void:
	var max_hp: float = get_max_hp()
	for i in segment_hp.size():
		segment_disabled[i] = false
		if i < _segment_percentages.size():
			segment_hp[i] = max_hp * _segment_percentages[i]
		else:
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

## Returns the total skill points available from level progression.
func get_skill_points_available() -> int:
	return max(0, (level - 1) * 2)

## Returns the number of points already spent in the three trees.
func get_skill_points_spent() -> int:
	return unlocked_skill_ids.size()

## Returns how many unspent skill points remain.
func get_skill_points_remaining() -> int:
	return max(0, get_skill_points_available() - get_skill_points_spent())

## Returns true if the character has unlocked the given skill/ability id.
func has_unlocked_skill(entry_id: String) -> bool:
	return unlocked_skill_ids.has(entry_id)

## Returns true if the requested tier is globally unlocked.
func can_unlock_skill_tree_tier(tier: int) -> bool:
	if tier <= 1:
		return true
	return get_skill_points_spent() >= (tier - 1) * 3

## Finds the generated tree entry by id, or null when absent.
func find_skill_tree_entry(entry_id: String) -> SkillTreeEntry:
	for tree in skill_trees:
		for raw_entry in tree:
			var entry: SkillTreeEntry = raw_entry as SkillTreeEntry
			if entry != null and entry.entry_id == entry_id:
				return entry
	return null

## Returns only the unlocked tree entries plus all equipment-granted entries.
func get_effective_skill_entries() -> Array[SkillTreeEntry]:
	var out: Array[SkillTreeEntry] = []
	var seen: Dictionary = {}
	for tree in skill_trees:
		for raw_entry in tree:
			var entry: SkillTreeEntry = raw_entry as SkillTreeEntry
			if entry == null:
				continue
			if not has_unlocked_skill(entry.entry_id):
				continue
			if seen.has(entry.entry_id):
				continue
			seen[entry.entry_id] = true
			out.append(entry)
	for slot in [main_hand_slot, off_hand_slot, armor_slot]:
		var equip: EquipmentData = slot as EquipmentData
		if equip == null:
			continue
		for raw_entry in equip.granted_skills:
			var entry: SkillTreeEntry = raw_entry as SkillTreeEntry
			if entry == null:
				continue
			var key: String = entry.entry_id if entry.entry_id != "" else entry.resource_path
			if seen.has(key):
				continue
			seen[key] = true
			out.append(entry)
	return out

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
