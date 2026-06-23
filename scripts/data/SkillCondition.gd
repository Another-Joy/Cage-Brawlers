## SkillCondition.gd
## Sub-resource pairing one Major Condition with an optional Minor Condition.
## A SkillData resource holds an array of these; the skill fires when ANY
## element in the array matches the current combat context (OR semantics).
##
## Major conditions describe the broad event ("when attacking").
## Minor conditions narrow it down ("…a target wearing heavy armor").
## Minor conditions are always linked to their paired Major condition —
## if there is no minor, the skill triggers on the major alone.
class_name SkillCondition
extends Resource

# ---------------------------------------------------------------------------
# Major Condition
# ---------------------------------------------------------------------------

enum MajorCondition {
	ALWAYS,          ## Permanent passive — always considered active.
	ON_ATTACK,       ## When this character makes any attack.
	ON_DEAL_DAMAGE,  ## When this character's attack hits and deals damage.
	ON_TAKE_DAMAGE,  ## When this character receives damage.
	ON_ATTACKED,     ## When this character is targeted by any attack.
	ON_MOVE,         ## When this character moves.
	ON_CROUCH,       ## When this character crouches.
	ON_STAND_UP,     ## When this character stands up.
	ON_TURN_START,   ## At the very start of this character's turn.
	ON_TURN_END,     ## At the very end of this character's turn.
	ON_HEAL,         ## When this character receives healing (any source).
}

# ---------------------------------------------------------------------------
# Minor Condition
# ---------------------------------------------------------------------------

enum MinorCondition {
	NONE,                      ## No additional narrowing; fires on major alone.

	## Target state
	TARGET_WEARING_HEAVY_ARMOR,
	TARGET_WEARING_MEDIUM_ARMOR,
	TARGET_WEARING_LIGHT_ARMOR,
	TARGET_CROUCHED,
	TARGET_STANDING,

	## Attack / attacker type (relevant for ON_TAKE_DAMAGE / ON_ATTACKED)
	ATTACKER_USING_PHYSICAL,
	ATTACKER_USING_RANGED,
	ATTACKER_USING_MAGICAL,

	## Self state
	SELF_CROUCHED,
	SELF_NOT_CROUCHED,
	SELF_WEARING_HEAVY_ARMOR,
	SELF_WEARING_MEDIUM_ARMOR,
	SELF_WEARING_LIGHT_ARMOR,

	## Weapon keyword on the active weapon
	SELF_WEAPON_HAS_KEYWORD,   ## Requires string_param to name the keyword.
	SELF_WEAPON_TYPE_IS,       ## Requires string_param to name the weapon type.

	## Attack classification (relevant for ON_ATTACK / ON_DEAL_DAMAGE)
	ATTACK_IS_SURPRISE,        ## The attack qualifies as a Surprise attack.
	ATTACK_IS_ABILITY,         ## The attack was made as part of an active Ability.
}

# ---------------------------------------------------------------------------
# Exported Properties
# ---------------------------------------------------------------------------

@export var major: MajorCondition = MajorCondition.ALWAYS
@export var minor: MinorCondition = MinorCondition.NONE

## Extra string parameter used by some minor conditions.
## For SELF_WEAPON_HAS_KEYWORD: name the keyword (e.g. "Two-Handed").
@export var string_param: String = ""
