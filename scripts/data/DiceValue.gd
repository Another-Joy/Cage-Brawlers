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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Rolls the dice using the provided DiceRoller and returns the total.
func roll(dice_roller: DiceRoller, uses_reliability: bool = false, reliability: float = 0.0) -> int:
	return dice_roller.roll_dice(count, sides, uses_reliability, reliability)

## Returns the expected average value of one roll (count * (sides + 1) / 2).
func average() -> float:
	return count * (sides + 1) / 2.0

## Returns a human-readable label such as "2d6".
func get_label() -> String:
	return "%dd%d" % [count, sides]
