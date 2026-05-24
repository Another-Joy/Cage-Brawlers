## AbilityAction.gd
## Sub-resource representing a single action performed when an ability is used.
## AbilityData holds an ordered array of these; they execute sequentially.
##
## Examples:
##   ActionType.MOVE          → character moves up to range_override tiles
##                               (0 = full movement speed).
##   ActionType.ATTACK        → make an attack; dice adds extra damage on top of weapon.
##   ActionType.HEAL          → restore HP equal to the resolved value.
##   ActionType.APPLY_BUFF    → apply a named buff to the resolved target.
##   ActionType.CROUCH        → crouch the character (requires adjacent barricade).
##   ActionType.STAND_UP      → stand the character up.
class_name AbilityAction
extends Resource

# ---------------------------------------------------------------------------
# Action Types
# ---------------------------------------------------------------------------

enum ActionType {
	ATTACK,       ## Make one attack using the equipped weapon (+ optional bonus dice).
	MOVE,         ## Move up to range_override tiles (0 = character movement speed).
	HEAL,         ## Restore HP equal to the resolved value.
	APPLY_BUFF,   ## Apply named buff to the action target (string_param = buff id).
	APPLY_DEBUFF, ## Apply named debuff to the action target (string_param = debuff id).
	CROUCH,       ## Crouch the character.
	STAND_UP,     ## Stand the character up.
	GRANT_BONUS,  ## Temporarily add flat_bonus to the stat named in string_param.
}

# ---------------------------------------------------------------------------
# Target Types
# ---------------------------------------------------------------------------

enum TargetType {
	SELF,   ## The ability owner.
	ALLY,   ## A chosen allied character.
	ENEMY,  ## A chosen enemy character.
	ANY,    ## Any character (ally or enemy).
}

# ---------------------------------------------------------------------------
# Exported Properties
# ---------------------------------------------------------------------------

@export var action_type: ActionType = ActionType.ATTACK
@export var target_type: TargetType = TargetType.ENEMY

## Range override in tiles. 0 = use equipped weapon range (for ATTACK) or
## full movement speed (for MOVE).
@export var range_override: int = 0

## Bonus dice added on top of the base weapon roll (for ATTACK) or used as
## the heal/grant amount (for HEAL, GRANT_BONUS). null = no extra dice.
@export var bonus_dice: DiceValue = null

## Flat bonus added to the resolved value.
@export var flat_bonus: int = 0

## Whether this action uses the Reliability modifier when rolling dice.
@export var uses_reliability: bool = false

## Extra string parameter:
##   APPLY_BUFF/APPLY_DEBUFF → buff/debuff identifier.
##   GRANT_BONUS             → name of the stat to temporarily boost
##                             (e.g. "strength", "dexterity").
@export var string_param: String = ""
