## InitiativeManager.gd
## Resolves combat turn order by rolling initiative for all participating
## characters and applying a recursive tie-breaker algorithm until every
## combatant holds a unique turn order index.
class_name InitiativeManager
extends RefCounted

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

## Ordered list of CharacterData after initiative resolution. Index 0 acts first.
var turn_order: Array[CharacterData] = []

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Maximum recursion depth for tie-breaking to prevent infinite loops.
const MAX_TIEBREAK_ITERATIONS: int = 100

# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------

## Computes and stores the full initiative order for a list of characters.
## Returns the resolved turn_order array.
func resolve_initiative(characters: Array[CharacterData], dice_roller: DiceRoller) -> Array[CharacterData]:
	# Map each character to their current initiative value.
	var initiatives: Dictionary = {}  # CharacterData -> int
	for char_data in characters:
		var bonus: int = int(char_data.dexterity / 4)
		initiatives[char_data] = dice_roller.roll_initiative(bonus)

	# Resolve all ties recursively.
	var iterations: int = 0
	while _has_ties(initiatives) and iterations < MAX_TIEBREAK_ITERATIONS:
		_resolve_ties(initiatives, dice_roller)
		iterations += 1

	# Sort descending by initiative value (highest acts first).
	var sorted_chars: Array[CharacterData] = characters.duplicate()
	sorted_chars.sort_custom(func(a, b): return initiatives[a] > initiatives[b])

	turn_order = sorted_chars
	return turn_order

# ---------------------------------------------------------------------------
# Internal Helpers
# ---------------------------------------------------------------------------

## Returns true if any two characters share the same initiative value.
func _has_ties(initiatives: Dictionary) -> bool:
	var seen: Array = []
	for char_data in initiatives:
		var value: int = initiatives[char_data]
		if value in seen:
			return true
		seen.append(value)
	return false

## Finds all groups of characters sharing the same initiative and resolves
## each group with a secondary roll. The winner gains +1 to their initiative.
## After adjustment the full array is checked again from the top.
func _resolve_ties(initiatives: Dictionary, dice_roller: DiceRoller) -> void:
	# Group characters by initiative value.
	var groups: Dictionary = {}  # int -> Array[CharacterData]
	for char_data in initiatives:
		var value: int = initiatives[char_data]
		if not groups.has(value):
			groups[value] = []
		groups[value].append(char_data)

	# Process each tied group.
	for value in groups:
		var group: Array = groups[value]
		if group.size() < 2:
			continue
		# Tie-breaker: each tied character rolls again.
		var secondary_rolls: Dictionary = {}  # CharacterData -> int
		for char_data in group:
			secondary_rolls[char_data] = dice_roller.roll_initiative()

		# Award +1 to the highest secondary roll winner(s).
		var max_roll: int = 0
		for char_data in secondary_rolls:
			if secondary_rolls[char_data] > max_roll:
				max_roll = secondary_rolls[char_data]

		# If multiple characters tied the secondary roll too, still award +1
		# to the first one found (subsequent outer iterations handle residual ties).
		for char_data in secondary_rolls:
			if secondary_rolls[char_data] == max_roll:
				initiatives[char_data] += 1
				break  # Only the first winner gets +1; remaining ties are resolved next iteration.

## Returns the next character in the turn order who is eligible to act
## (i.e. not KNOCKED_DOWN or DEAD).
func get_next_active_character() -> CharacterData:
	for char_data in turn_order:
		if char_data.state_flag == CharacterData.StateFlag.LIVING \
				or char_data.state_flag == CharacterData.StateFlag.PENDING_LEVEL_UP:
			return char_data
	return null

## Rotates the turn order array: moves the first element to the end.
## Call after each character's turn is complete.
func advance_turn() -> void:
	if turn_order.is_empty():
		return
	var current: CharacterData = turn_order.pop_front()
	turn_order.append(current)

## Removes a character from the turn order (e.g. when knocked down or dead).
func remove_character(char_data: CharacterData) -> void:
	turn_order.erase(char_data)
