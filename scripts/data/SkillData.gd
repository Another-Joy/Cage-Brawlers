## SkillData.gd
## Resource representing a single passive skill node in a skill tree.
## Passive skills are always-on modifiers that fire automatically when their
## trigger conditions are met — they are never manually activated by the player.
## Activatable abilities (things the player uses during a phase) are AbilityData.
##
## A skill triggers when its SkillCondition entries match the current
## combat context according to trigger_match_mode (ANY/OR by default).
## When triggered, ALL of its SkillEffect entries are applied simultaneously.
class_name SkillData
extends SkillTreeEntry

# ---------------------------------------------------------------------------
# Trigger Conditions (ANY/ALL)
# ---------------------------------------------------------------------------

enum TriggerMatchMode {
	ANY,
	ALL,
}

## Controls how trigger conditions are combined.
## ANY = OR semantics, ALL = AND semantics.
@export var trigger_match_mode: TriggerMatchMode = TriggerMatchMode.ANY

## One or more (Major + optional Minor) condition pairs.
## The skill fires according to trigger_match_mode.
## Leave empty to mean "always active" (equivalent to a single ALWAYS trigger).
@export var triggers: Array[SkillCondition] = []

# ---------------------------------------------------------------------------
# Effects (all applied when any trigger fires)
# ---------------------------------------------------------------------------

## One or more effects applied when the skill triggers.
## Multiple effects allow a single trigger to do several things at once
## (e.g. "+1d6 damage AND reduce target evasion by 2").
@export var effects: Array[SkillEffect] = []
