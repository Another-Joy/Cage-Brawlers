## SkillEffect.gd
## Sub-resource describing what a passive skill does when it triggers.
## Holds the effect type, who it applies to, and the value (flat, dice, or
## stat-modifier). SkillData stores an array of these so one trigger can
## produce multiple simultaneous effects.
class_name SkillEffect
extends Resource

# ---------------------------------------------------------------------------
# Effect Type
# ---------------------------------------------------------------------------

enum EffectType {
	ADD_DAMAGE,              ## Add extra damage to the attack being resolved.
	REDUCE_INCOMING_DAMAGE,  ## Reduce damage received by the target of the effect.
	ADD_ATTACK_ACCURACY,     ## Add bonus (flat integer) to the attacker's accuracy roll.
	REDUCE_ACCURACY,         ## Reduce the attacker's accuracy roll.
	ADD_EVASION,             ## Add to the character's evasion for this hit.
	MODIFY_MOVEMENT,         ## Change movement tiles for this turn.
	HEAL,                    ## Restore HP equal to the value.
	APPLY_BUFF,              ## Apply a named buff status (see string_param).
	APPLY_DEBUFF,            ## Apply a named debuff status (see string_param).
	ADD_RELIABILITY,         ## Add percentage points to this attack's reliability.
	                         ## flat_value is in whole percentage points
	                         ## (e.g. flat_value = 30 means +30%).
	ADD_RANGE,               ## Add flat tiles to the attack's effective range.
	                         ## flat_value is the tile count (can be negative).
}

# ---------------------------------------------------------------------------
# Effect Target
# ---------------------------------------------------------------------------

enum EffectTarget {
	SELF,        ## Applies to the skill's owner.
	ATTACKER,    ## Applies to whoever triggered the event (useful for ON_TAKE_DAMAGE).
	TARGET,      ## Applies to the skill's attack target.
	ALL_ALLIES,  ## Applies to every ally of the skill's owner.
	ALL_ENEMIES, ## Applies to every enemy of the skill's owner.
}

# ---------------------------------------------------------------------------
# Value Type
# ---------------------------------------------------------------------------

enum ValueType {
	FLAT,          ## Static integer (flat_value).
	DICE,          ## Roll the dice sub-resource.
	STAT_MODIFIER, ## floor(character_stat / modifier_divisor).
}

# ---------------------------------------------------------------------------
# Exported Properties
# ---------------------------------------------------------------------------

@export var effect_type: EffectType = EffectType.ADD_DAMAGE
@export var target: EffectTarget = EffectTarget.TARGET
@export var value_type: ValueType = ValueType.FLAT

## Used when value_type == FLAT.
@export var flat_value: int = 0

## Used when value_type == DICE. Set count and sides on the sub-resource.
@export var dice: DiceValue = null
## Whether the dice roll uses the character's Reliability modifier.
@export var uses_reliability: bool = false

## Used when value_type == STAT_MODIFIER: name of the stat to read
## (e.g. "strength", "dexterity", "wisdom", "intelligence", "constitution").
@export var modifier_stat: String = ""
## Divisor applied to the stat (floor(stat / divisor)).
@export var modifier_divisor: int = 2

## Extra string parameter used by some effect types.
## For APPLY_BUFF / APPLY_DEBUFF: the buff/debuff identifier.
@export var string_param: String = ""
