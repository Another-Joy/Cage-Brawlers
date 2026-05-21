## MatchManager.gd
## Controls the full lifecycle of a match session:
##   - Pre-match validation and roster locking
##   - Spawning CombatManager for active gameplay
##   - Post-match character recovery, permadeath processing, and XP/gold rewards
class_name MatchManager
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal match_ready(player_ids: Array)
signal match_ended_with_results(winner_player_id: String, results: Dictionary)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Gold awarded per completed match (win or participation).
const GOLD_PER_MATCH: int = 50
## Gold bonus for the winning team.
const GOLD_WIN_BONUS: int = 25
## XP awarded per surviving character after a match.
const XP_PER_MATCH: int = 100

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Maps player_id String -> PlayerProfile.
var _profiles: Dictionary = {}
## Maps player_id String -> Array[CharacterData] (locked match team).
var _locked_teams: Dictionary = {}

var _combat_manager: CombatManager = null
var _map_data: MapData = null
var _dice_roller: DiceRoller = DiceRoller.new()

var _winner_player_id: String = ""

# ---------------------------------------------------------------------------
# Pre-Match Setup
# ---------------------------------------------------------------------------

## Registers a player profile for this match session.
func register_player(profile: PlayerProfile) -> void:
	_profiles[profile.player_id] = profile

## Validates and locks both teams from their player profiles.
## Returns true if all checks pass; false if a team is invalid.
func lock_teams() -> bool:
	for player_id in _profiles:
		var profile: PlayerProfile = _profiles[player_id]
		if not profile.is_team_valid():
			push_error("MatchManager: player %s does not have a valid team of %d." % [
				player_id, PlayerProfile.TEAM_SIZE])
			return false
		# Clone active living roster as the locked match team.
		_locked_teams[player_id] = profile.get_living_roster().duplicate()
	return true

## Sets the map for this match.
func set_map(map_data: MapData) -> void:
	_map_data = map_data

## Starts the match after teams and map are locked in.
func start_match() -> void:
	assert(_map_data != null, "MatchManager: map must be set before starting.")
	assert(_locked_teams.size() == 2, "MatchManager: exactly 2 players required.")

	_combat_manager = CombatManager.new()
	add_child(_combat_manager)
	_combat_manager.initialise(_map_data, _locked_teams, _dice_roller)
	_combat_manager.match_ended.connect(_on_match_ended)
	_combat_manager.start_match()

	emit_signal("match_ready", _locked_teams.keys())

# ---------------------------------------------------------------------------
# Surrender / Disconnect Hook
# ---------------------------------------------------------------------------

## Called when a player surrenders or disconnects mid-match.
## Characters that are KNOCKED_DOWN (but not DEAD) are rescued from permadeath.
func handle_surrender(player_id: String) -> void:
	if _combat_manager:
		_combat_manager.process_surrender(player_id)

# ---------------------------------------------------------------------------
# Post-Match Processing
# ---------------------------------------------------------------------------

func _on_match_ended(winner_player_id: String) -> void:
	_winner_player_id = winner_player_id
	var results: Dictionary = {}

	for player_id in _locked_teams:
		var team: Array = _locked_teams[player_id]
		var is_winner: bool = (player_id == winner_player_id)
		var profile: PlayerProfile = _profiles[player_id]

		# Process each character's end-of-match state.
		for char_data in team:
			_process_character_post_match(char_data, profile, is_winner)

		# Award gold.
		var gold_earned: int = GOLD_PER_MATCH
		if is_winner:
			gold_earned += GOLD_WIN_BONUS
		profile.award_gold(gold_earned)

		results[player_id] = {
			"won": is_winner,
			"gold_earned": gold_earned,
		}

	emit_signal("match_ended_with_results", winner_player_id, results)

## Handles the post-match fate of a single character.
func _process_character_post_match(char_data: CharacterData, profile: PlayerProfile, is_winner: bool) -> void:
	match char_data.state_flag:
		CharacterData.StateFlag.DEAD:
			# Permanently remove from roster and archive to hall of fame.
			profile.process_character_death(char_data)

		CharacterData.StateFlag.KNOCKED_DOWN:
			# Safety net: restore to full health after surrender/disconnect.
			char_data.full_heal()
			char_data.state_flag = CharacterData.StateFlag.LIVING

		CharacterData.StateFlag.LIVING, CharacterData.StateFlag.PENDING_LEVEL_UP:
			# Award XP to surviving characters.
			char_data.experience += XP_PER_MATCH
			_check_level_up(char_data)

		_:
			pass

## Checks and applies a pending level-up flag if the character has enough XP.
func _check_level_up(char_data: CharacterData) -> void:
	var xp_to_next_level: int = char_data.level * 100
	if char_data.experience >= xp_to_next_level:
		char_data.state_flag = CharacterData.StateFlag.PENDING_LEVEL_UP
