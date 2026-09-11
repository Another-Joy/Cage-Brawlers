## AbilityData.gd
## Resource representing an active ability that a character can use during
## one of the three action phases (Beginning, Main, Ending).
##
## Abilities are the building blocks of a character's turn — from the default
## Move and Attack actions every character has, to learned special abilities
## from skill trees. They are manually activated by the player, unlike the
## always-on passive SkillData entries.
##
## All conditions must be satisfied simultaneously (AND) for the ability to be
## available. Actions are executed in array order when the ability is used.
class_name AbilityData
extends SkillTreeEntry

# ---------------------------------------------------------------------------
# Dice Tier Chain (used for damage modifiers)
# ---------------------------------------------------------------------------

## Ordered list of valid die sizes. Tier modifiers step through this chain.
## -1 tier: d6 → d4  |  +1 tier: d6 → d8
const DICE_TIERS: Array[int] = [2, 4, 6, 8, 10, 12, 16, 20]

# ---------------------------------------------------------------------------
# Phase Flags
# ---------------------------------------------------------------------------

## Bit-flag constants matching CombatManager.ActionPhase values.
## Store the OR'd sum in the 'phases' export.
const PHASE_BEGINNING: int = 1
const PHASE_MAIN: int = 2
const PHASE_ENDING: int = 4

enum TargetingMode {
	NONE,
	CHARACTER,
	TILE,
	TILE_AND_DIRECTION,
}

# ---------------------------------------------------------------------------
# Exported Properties
# ---------------------------------------------------------------------------

## Bitmask of action phases during which this ability may be used.
## E.g. PHASE_BEGINNING | PHASE_MAIN = 3 means it can be used in either phase.
## Build it in .tres as the integer sum (1=Beginning, 2=Main, 4=Ending).
@export var phases: int = PHASE_MAIN

## Pre-conditions that must all be true for the ability to be usable.
## Leave empty for no restrictions.
@export var conditions: Array[AbilityCondition] = []

## Ordered list of actions performed when this ability is activated.
@export var actions: Array[AbilityAction] = []

# ---------------------------------------------------------------------------
# Cooldown
# ---------------------------------------------------------------------------

## Number of turns this ability is unavailable after being used.
## 0 = no cooldown.  2 = cannot be used the next turn; usable again on the
## turn after that.  Cooldowns tick down at the end of each of the user's turns.
## A value of -1 marks a special/non-standard cooldown (see description).
@export var cooldown_turns: int = 0

# ---------------------------------------------------------------------------
# Weapon Requirements
# ---------------------------------------------------------------------------

## Weapon type names that satisfy this ability's equipment requirement.
## OR logic: any single match allows the ability to be used.
## Empty = no weapon restriction.
## Values should match WeaponData.WeaponType key names in lowercase
## (e.g. ["axe"] or ["sword", "axe", "dagger"]).
@export var weapon_requirements: Array[String] = []

# ---------------------------------------------------------------------------
# Damage Modifiers (applied to the weapon's damage dice)
# ---------------------------------------------------------------------------

## Delta applied to the number of dice in the weapon's damage roll.
## Result is clamped to a minimum of 1 die.
## Example: weapon does 2d6; count_modifier = -1 → 1d6.
@export var dice_count_modifier: int = 0

## Number of tier steps applied to the weapon's damage die size.
## Uses the DICE_TIERS chain: 2→4→6→8→10→12→16→20.
## A value of -1 on a d6 weapon yields d4. A value of +1 on a d8 yields d10.
@export var dice_tier_modifier: int = 0

# ---------------------------------------------------------------------------
# Stat Overrides
# ---------------------------------------------------------------------------

## Percentage-point bonus (or penalty) applied to this ability's accuracy roll.
## E.g. -20.0 means -20% accuracy. Does not affect other attacks this turn.
@export var accuracy_modifier_percent: float = 0.0

## Percentage-point bonus (or penalty) applied to this ability's reliability.
## E.g. -50.0 means -50% reliability. Does not affect other attacks this turn.
@export var reliability_modifier_percent: float = 0.0

## Flat tile bonus (or penalty) applied to this ability's effective range.
## E.g. -4 means the weapon's attack range is reduced by 4 for this ability.
@export var range_modifier: int = 0

# ---------------------------------------------------------------------------
# Special Flags
# ---------------------------------------------------------------------------

## When true, this ability bypasses the Aiming keyword movement restriction.
## (Used by Hip Shot, which explicitly ignores Aiming limitations.)
@export var ignore_aiming_restriction: bool = false

## When true, successfully using this ability does not cause the character to
## stand up from a crouch or become revealed (used by Peek Shot).
@export var prevents_stand_up: bool = false

## Number of external targets this ability requires.
## 1 = single target (default). 0 = no external target (self-only).
## Values above 1 allow multi-target selection in the UI.
@export var target_count: int = 1

## How the player supplies targets for this ability.
@export var targeting_mode: TargetingMode = TargetingMode.CHARACTER

# ---------------------------------------------------------------------------
# Phase Helpers
# ---------------------------------------------------------------------------

## Returns true if this ability can be used during the given phase index
## (0=Beginning, 1=Main, 2=Ending).
func is_usable_in_phase(phase_index: int) -> bool:
	var flag: int = 1 << phase_index
	return (phases & flag) != 0

## Returns true if this ability can be used during the Beginning phase.
func is_beginning_ability() -> bool:
	return (phases & PHASE_BEGINNING) != 0

## Returns true if this ability can be used during the Main phase.
func is_main_ability() -> bool:
	return (phases & PHASE_MAIN) != 0

## Returns true if this ability can be used during the Ending phase.
func is_ending_ability() -> bool:
	return (phases & PHASE_ENDING) != 0

func uses_character_targeting() -> bool:
	return targeting_mode == TargetingMode.CHARACTER

func uses_tile_targeting() -> bool:
	return targeting_mode == TargetingMode.TILE or targeting_mode == TargetingMode.TILE_AND_DIRECTION

func requires_direction_selection() -> bool:
	return targeting_mode == TargetingMode.TILE_AND_DIRECTION

# ---------------------------------------------------------------------------
# Damage Modifier Helpers
# ---------------------------------------------------------------------------

## Returns the effective die size after applying dice_tier_modifier to base_sides.
## Clamps within the DICE_TIERS chain.
static func apply_dice_tier_modifier(base_sides: int, tier_delta: int) -> int:
	if tier_delta == 0:
		return base_sides
	var idx: int = DICE_TIERS.find(base_sides)
	if idx == -1:
		# Snap to nearest tier below the given value.
		idx = 0
		for i in DICE_TIERS.size():
			if DICE_TIERS[i] <= base_sides:
				idx = i
	idx = clampi(idx + tier_delta, 0, DICE_TIERS.size() - 1)
	return DICE_TIERS[idx]

## Returns the effective dice count after applying dice_count_modifier.
## Minimum result is 1.
static func apply_dice_count_modifier(base_count: int, count_delta: int) -> int:
	return maxi(1, base_count + count_delta)
