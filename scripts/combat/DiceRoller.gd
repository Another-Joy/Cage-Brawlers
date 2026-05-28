## DiceRoller.gd
## Core utility for all dice rolling operations.
## Supports multi-die bundles and an optional Reliability modifier.
##
## Reliability Formula:
##   Reliability is a value in [0.0, 1.0] that biases the roll toward the
##   maximum possible result, NOT toward the mean.
##
##     adjusted = raw_roll + floor(reliability * (max_possible - raw_roll))
##       where max_possible = dice_count * dice_sides
##
##   A reliability of 0.0 applies no adjustment (fully random).
##   A reliability of 1.0 always returns the maximum roll.
##   A reliability of 0.5 moves the roll halfway toward the maximum.
##
##   The reliability bonus is applied after all other dice buffs but before
##   critical hit multipliers (per spec).
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
##   reliability_value - Reliability factor in range [0.0, 1.0].
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

## Applies the reliability adjustment to a raw roll total.
##
## Pushes the result toward the maximum possible value:
##   adjusted = raw_roll + floor(reliability * (max_possible - raw_roll))
##   where max_possible = dice_count * dice_sides
##
## This replaces the old mean-targeting formula and matches the spec:
## "the max and min roll of that attack (total of dices)".
func _apply_reliability(raw_roll: int, dice_count: int, dice_sides: int, reliability: float) -> int:
	var clamped_reliability: float = clampf(reliability, 0.0, 1.0)
	var max_possible: float = float(dice_count * dice_sides)
	var adjusted: float = raw_roll + floor(clamped_reliability * (max_possible - raw_roll))
	return int(adjusted)
