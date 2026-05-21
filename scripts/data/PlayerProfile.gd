## PlayerProfile.gd
## Resource representing a player's persistent global account data.
class_name PlayerProfile
extends Resource

@export var player_id: String = ""
@export var display_name: String = ""

## Active squad roster: array of CharacterData resources (must be 1-3 living characters).
@export var roster: Array[CharacterData] = []

## Gold currency available for spending in the merchant tab.
@export var gold: int = 0

## Historical records of permanently dead characters.
@export var hall_of_fame: Array[HallOfFameEntry] = []

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TEAM_SIZE: int = 3

# ---------------------------------------------------------------------------
# Roster Helpers
# ---------------------------------------------------------------------------

## Returns an array of living characters (LIVING or PENDING_LEVEL_UP).
func get_living_roster() -> Array[CharacterData]:
	var living: Array[CharacterData] = []
	for c in roster:
		if c.state_flag == CharacterData.StateFlag.LIVING \
				or c.state_flag == CharacterData.StateFlag.PENDING_LEVEL_UP:
			living.append(c)
	return living

## Validates that the player has exactly TEAM_SIZE living characters available.
func is_team_valid() -> bool:
	return get_living_roster().size() == TEAM_SIZE

## Removes a permanently dead character from the roster and archives their record.
func process_character_death(char_data: CharacterData) -> void:
	if char_data.state_flag != CharacterData.StateFlag.DEAD:
		return
	# Archive to hall of fame.
	hall_of_fame.append(HallOfFameEntry.from_character(char_data))
	# Delete equipped gear (nullify references so they can be freed).
	char_data.main_hand_slot = null
	char_data.off_hand_slot = null
	char_data.armor_slot = null
	# Remove from roster.
	roster.erase(char_data)

## Awards gold to the player's account.
func award_gold(amount: int) -> void:
	gold = max(0, gold + amount)

## Deducts gold (returns false if insufficient funds).
func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	return true
