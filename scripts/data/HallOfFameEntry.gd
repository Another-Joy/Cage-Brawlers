## HallOfFameEntry.gd
## Read-only record created when a character permanently dies.
## Appended to the player's global profile for historical tracking.
class_name HallOfFameEntry
extends Resource

@export var character_name: String = ""
@export var character_class: CharacterData.CharacterClass = CharacterData.CharacterClass.WARRIOR
@export var achieved_level: int = 1
@export var final_strength: int = 0
@export var final_dexterity: int = 0
@export var final_constitution: int = 0
@export var final_wisdom: int = 0
@export var final_intelligence: int = 0
@export var date_of_death: String = ""  # ISO-8601 date string

## Creates a HallOfFameEntry from a CharacterData resource.
static func from_character(char_data: CharacterData) -> HallOfFameEntry:
	var entry: HallOfFameEntry = HallOfFameEntry.new()
	entry.character_name = char_data.character_name
	entry.character_class = char_data.character_class
	entry.achieved_level = char_data.level
	entry.final_strength = char_data.strength
	entry.final_dexterity = char_data.dexterity
	entry.final_constitution = char_data.constitution
	entry.final_wisdom = char_data.wisdom
	entry.final_intelligence = char_data.intelligence
	entry.date_of_death = Time.get_date_string_from_system()
	return entry
