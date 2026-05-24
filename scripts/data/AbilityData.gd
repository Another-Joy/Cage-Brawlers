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
# Phase Flags
# ---------------------------------------------------------------------------

## Bit-flag constants matching CombatManager.ActionPhase values.
## Store the OR'd sum in the 'phases' export.
const PHASE_BEGINNING: int = 1
const PHASE_MAIN: int = 2
const PHASE_ENDING: int = 4

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
