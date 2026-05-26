## DiceValue.gd
## Sub-resource representing a dice expression (e.g. 2d6).
## Used anywhere a variable quantity is defined by a roll: class hit dice,
## skill bonus dice, ability damage dice, etc.
class_name DiceValue
extends Resource

## Number of dice to roll (e.g. 2 for 2d6).
@export var count: int = 1
## Number of sides on each die (e.g. 6 for d6, 8 for d8).
@export var sides: int = 6

## Baked-in reliability modifier for this dice expression (0.0 = none).
## Set this on hit dice that always benefit from reliability regardless of
## the caller — e.g. Fighter hit dice have +20% reliability built in.
## A value of 0.2 means +20 percentage points.
@export var reliability: float = 0.0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Rolls the dice using the provided DiceRoller and returns the total.
##
## uses_reliability — if true, the caller declares that reliability applies.
##   When true and reliability_override > 0, uses the override value.
##   When true and reliability_override == 0, falls back to self.reliability.
## reliability_override — explicit reliability value from the caller (e.g. a
##   character's current reliability score). Ignored unless uses_reliability
##   is true or self.reliability > 0.
##
## In all cases, self.reliability is added on top of any runtime value so that
## hit-dice baked-in reliability is always honoured.
func roll(dice_roller: DiceRoller, uses_reliability: bool = false, reliability_override: float = 0.0) -> int:
	var final_rel: float = 0.0
	if uses_reliability:
		final_rel = reliability_override if reliability_override > 0.0 else reliability
	else:
		final_rel = reliability  # baked-in (e.g. class hit dice); 0 if not set
	return dice_roller.roll_dice(count, sides, final_rel > 0.0, final_rel)

## Returns the expected average value of one roll (count * (sides + 1) / 2).
func average() -> float:
	return count * (sides + 1) / 2.0

## Returns a human-readable label such as "2d6".
func get_label() -> String:
	return "%dd%d" % [count, sides]
