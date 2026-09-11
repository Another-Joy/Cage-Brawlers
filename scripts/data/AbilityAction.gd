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
	RELOAD,       ## Reload the equipped magazine weapon from reserve ammo.
	AREA_DAMAGE,  ## Deal direct damage to tiles/units in an area.
	SUMMON_WATCHER_EYE, ## Create a fragile observer unit on a target tile.
	BREAK_SEGMENT, ## Break the next active health segment on the target.
	MEND_BROKEN_SEGMENT, ## Mend the most recent broken segment on the target.
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

## Per-action accuracy modifier (percentage points, e.g. -20.0 = -20% accuracy).
## Stacks with the parent AbilityData.accuracy_modifier_percent for this action.
@export var accuracy_modifier_percent: float = 0.0

## Per-action reliability modifier (percentage points, e.g. -50.0 = -50% reliability).
## Stacks with the parent AbilityData.reliability_modifier_percent for this action.
@export var reliability_modifier_percent: float = 0.0

## When true and action_type == ATTACK, the attack always hits.
@export var force_hit: bool = false

## When true and action_type == ATTACK, the attack cannot critically hit.
@export var cannot_crit: bool = false

## When true and action_type == ATTACK, damage bypasses armor HP and is dealt
## directly to health segments.
@export var ignore_armor: bool = false

## Extra string parameter:
##   APPLY_BUFF/APPLY_DEBUFF → buff/debuff identifier.
##   GRANT_BONUS             → name of the stat to temporarily boost
##                             (e.g. "strength", "dexterity").
@export var string_param: String = ""

## When true and action_type == HEAL, the heal amount is derived from
## the acting character's equipped weapon damage dice (times weapon_dice_multiplier),
## instead of rolling bonus_dice. Ability-level dice_count_modifier /
## dice_tier_modifier are applied to the weapon roll first.
@export var uses_weapon_dice: bool = false

## Multiplier for the weapon dice roll when uses_weapon_dice is true.
## E.g. 2.0 = heal for twice the weapon damage roll. Default: 1.0.
@export var weapon_dice_multiplier: float = 1.0

## When > 0 and action_type == HEAL, adds this fraction of the damage dealt
## by the most recent ATTACK action in the same ability sequence.
## E.g. 0.5 = heal for 50% of the last attack's damage. Stacks additively
## with bonus_dice and flat_bonus.
@export var heal_from_attack_fraction: float = 0.0

## Index into the ability's target list for multi-target abilities.
## 0 = primary target (always the first selected / declared target).
## 1 = secondary target (second selected, e.g. ally for Drain Life heal).
## This is only meaningful when AbilityData.target_count > 1.
@export var target_index: int = 0

## Radius in tiles for area actions centered on the chosen tile.
## Used by AREA_DAMAGE.
@export var area_radius: int = 0

## Number of random tiles selected within the area. 0 means affect all valid targets.
## Used by AREA_DAMAGE abilities like Lightning Strike.
@export var random_tile_count: int = 0
