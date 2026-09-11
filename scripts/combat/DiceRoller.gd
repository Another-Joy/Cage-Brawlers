## DiceRoller.gd
## Core utility for all dice rolling operations.
## Supports multi-die bundles and an optional Reliability modifier.
##
## Reliability Formula:
##   Reliability uses 1.0 = 100% and is evaluated with a piecewise formula
##   that supports values above 1.0 and below 0.0.
##
##   Let M = max roll, m = min roll, Rs = rolled result, Rl = reliability.
##
##   If Rl > 1.0:
##     M + apply_reliability(new roll, Rl - 2.0)
##   If Rl >= 0.0:
##     Rs + (Rl * (M - Rs))
##   If -1.0 <= Rl < 0.0:
##     Rs + (Rl * (Rs - m))
##   If -2.0 <= Rl < -1.0:
##     -(Rs + ((Rl + 1.0) * (Rs - m)))
##
##   The reliability adjustment is applied after all other dice buffs but
##   before critical hit multipliers (per spec).
class_name DiceRoller
extends RefCounted

## Shared RNG instance. Seed can be set for reproducible tests.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

## Seeds the internal RNG for deterministic rolls (useful for testing).
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value

# ---------------------------------------------------------------------------
# Core Roll Functions
# ---------------------------------------------------------------------------

## Rolls dice_count dice each with dice_sides faces and returns the total.
##
## Parameters:
##   dice_count        - Number of dice to roll (must be >= 1).
##   dice_sides        - Number of sides on each die (must be >= 2).
##   uses_reliability  - Whether to apply the reliability adjustment formula.
##   reliability_value - Reliability factor where 1.0 = 100%.
##
## Returns the bundled integer result after optional reliability adjustment.
func roll_dice(
		dice_count: int,
		dice_sides: int,
		uses_reliability: bool = false,
		reliability_value: float = 0.0) -> int:

	assert(dice_count >= 1, "dice_count must be at least 1.")
	assert(dice_sides >= 2, "dice_sides must be at least 2.")

	var total: int = 0
	for _i in dice_count:
		total += _rng.randi_range(1, dice_sides)

	if uses_reliability:
		total = _apply_reliability(total, dice_count, dice_sides, reliability_value)

	return total

## Rolls a single d100 (uniform 1–100). Used for the hit/crit check.
func roll_d100() -> int:
	return _rng.randi_range(1, 100)

# ---------------------------------------------------------------------------
# Initiative Roll
# ---------------------------------------------------------------------------

## Convenience wrapper: rolls a single d20 optionally modified by a flat bonus.
func roll_initiative(bonus: int = 0) -> int:
	return roll_dice(1, 20) + bonus

# ---------------------------------------------------------------------------
# Reliability Formula
# ---------------------------------------------------------------------------

## Applies the piecewise reliability adjustment to a raw roll total.
func _apply_reliability(raw_roll: int, dice_count: int, dice_sides: int, reliability: float) -> int:
	var min_possible: float = float(dice_count)
	var max_possible: float = float(dice_count * dice_sides)
	var rs: float = float(raw_roll)

	if reliability > 1.0:
		# Overflow reliability: guarantee max roll and recurse with reliability - 200%.
		var reroll: int = roll_dice(dice_count, dice_sides, false)
		return roundi(max_possible + _apply_reliability(reroll, dice_count, dice_sides, reliability - 2.0))

	if reliability >= 0.0:
		return roundi(rs + (reliability * (max_possible - rs)))

	if reliability >= -1.0:
		return roundi(rs + (reliability * (rs - min_possible)))

	if reliability >= -2.0:
		return roundi(-(rs + ((reliability + 1.0) * (rs - min_possible))))

	# For values below -200%, keep extending the pattern by adding minimum rolls.
	var reroll_negative: int = roll_dice(dice_count, dice_sides, false)
	return roundi(-min_possible + _apply_reliability(reroll_negative, dice_count, dice_sides, reliability + 2.0))
