## SkillData.gd
## Resource representing a single passive skill node in a skill tree.
## Passive skills are always-on modifiers that fire automatically when their
## trigger conditions are met — they are never manually activated by the player.
## Activatable abilities (things the player uses during a phase) are AbilityData.
##
## A skill triggers when ANY of its SkillCondition entries matches the current
## combat context (OR semantics between triggers). When triggered, ALL of its
## SkillEffect entries are applied simultaneously.
class_name SkillData
extends SkillTreeEntry

# ---------------------------------------------------------------------------
# Trigger Conditions (OR)
# ---------------------------------------------------------------------------

## One or more (Major + optional Minor) condition pairs.
## The skill fires if at least one pair matches the current combat context.
## Leave empty to mean "always active" (equivalent to a single ALWAYS trigger).
@export var triggers: Array[SkillCondition] = []

# ---------------------------------------------------------------------------
# Effects (all applied when any trigger fires)
# ---------------------------------------------------------------------------

## One or more effects applied when the skill triggers.
## Multiple effects allow a single trigger to do several things at once
## (e.g. "+1d6 damage AND reduce target evasion by 2").
@export var effects: Array[SkillEffect] = []
