# Skill Conditions and Effects Reference

Canonical reference for passive skill authoring based on:
- [scripts/data/SkillCondition.gd](scripts/data/SkillCondition.gd)
- [scripts/data/SkillEffect.gd](scripts/data/SkillEffect.gd)
- [scripts/data/SkillData.gd](scripts/data/SkillData.gd)

## Trigger Structure

A passive skill (`SkillData`) uses:
- `trigger_match_mode`: `ANY` (OR) or `ALL` (AND)
- `triggers`: array of `SkillCondition`
- `effects`: array of `SkillEffect`

`triggers` empty means always active.

## SkillCondition Fields

- `major`: `MajorCondition`
- `minor`: `MinorCondition`
- `string_param`: optional string used by some minor conditions

## MajorCondition Values

| Name | Int | Meaning |
|---|---:|---|
| ALWAYS | 0 | Passive is always active for relevant evaluation context |
| ON_ATTACK | 1 | When this character makes an attack |
| ON_DEAL_DAMAGE | 2 | When this character hits and deals damage |
| ON_TAKE_DAMAGE | 3 | When this character takes damage |
| ON_ATTACKED | 4 | When this character is targeted by an attack |
| ON_MOVE | 5 | When this character moves |
| ON_CROUCH | 6 | When this character crouches |
| ON_STAND_UP | 7 | When this character stands up |
| ON_TURN_START | 8 | Start of turn |
| ON_TURN_END | 9 | End of turn |
| ON_HEAL | 10 | When this character is healed |

## MinorCondition Values

| Name | Int | Uses string_param? | Notes |
|---|---:|---|---|
| NONE | 0 | No | No narrowing |
| TARGET_WEARING_HEAVY_ARMOR | 1 | No | Target armor check |
| TARGET_WEARING_MEDIUM_ARMOR | 2 | No | Target armor check |
| TARGET_WEARING_LIGHT_ARMOR | 3 | No | Target armor check |
| TARGET_CROUCHED | 4 | No | Target state |
| TARGET_STANDING | 5 | No | Target state |
| ATTACKER_USING_PHYSICAL | 6 | No | Incoming/outgoing context weapon damage type |
| ATTACKER_USING_RANGED | 7 | No | Incoming/outgoing context weapon damage type |
| ATTACKER_USING_MAGICAL | 8 | No | Incoming/outgoing context weapon damage type |
| SELF_CROUCHED | 9 | No | Owner state |
| SELF_NOT_CROUCHED | 10 | No | Owner state |
| SELF_WEARING_HEAVY_ARMOR | 11 | No | Owner armor check |
| SELF_WEARING_MEDIUM_ARMOR | 12 | No | Owner armor check |
| SELF_WEARING_LIGHT_ARMOR | 13 | No | Owner armor check |
| SELF_WEAPON_HAS_KEYWORD | 14 | Yes | `string_param` is keyword |
| SELF_WEAPON_TYPE_IS | 15 | Yes | `string_param` is weapon type name |
| ATTACK_IS_SURPRISE | 16 | No | Uses `SkillContext.is_surprise_attack` |
| ATTACK_IS_ABILITY | 17 | No | Uses `SkillContext.is_ability_attack` |
| ATTACKING_WEAPON_IS_MAIN_HAND | 18 | No | Uses `SkillContext.is_main_hand_attack` |
| ATTACKING_WEAPON_IS_OFF_HAND | 19 | No | Uses `SkillContext.is_off_hand_attack` |

## SkillEffect Fields

- `effect_type`: `EffectType`
- `target`: `EffectTarget`
- `value_type`: `ValueType`
- `flat_value`: integer value for `FLAT`
- `dice`: `DiceValue` for `DICE`
- `uses_reliability`: whether dice roll uses reliability
- `modifier_stat`: stat name for `STAT_MODIFIER`
- `modifier_divisor`: divisor for `STAT_MODIFIER`
- `string_param`: extra string for effect types that need it

## EffectType Values

| Name | Int | Typical value_type | Uses string_param? | Meaning |
|---|---:|---|---|---|
| ADD_DAMAGE | 0 | FLAT or DICE or STAT_MODIFIER | No | Adds damage to current attack |
| REDUCE_INCOMING_DAMAGE | 1 | FLAT or STAT_MODIFIER | No | Reduces incoming damage |
| ADD_ATTACK_ACCURACY | 2 | FLAT or STAT_MODIFIER | No | Adds accuracy |
| REDUCE_ACCURACY | 3 | FLAT or STAT_MODIFIER | No | Reduces accuracy |
| ADD_EVASION | 4 | FLAT or STAT_MODIFIER | No | Adds evasion |
| MODIFY_MOVEMENT | 5 | FLAT or STAT_MODIFIER | No | Modifies movement |
| HEAL | 6 | FLAT or DICE or STAT_MODIFIER | No | Restores HP |
| APPLY_BUFF | 7 | FLAT (usually 0) | Yes | `string_param` = buff id |
| APPLY_DEBUFF | 8 | FLAT (usually 0) | Yes | `string_param` = debuff id |
| ADD_RELIABILITY | 9 | FLAT or STAT_MODIFIER | No | Reliability percentage points |
| ADD_RANGE | 10 | FLAT or STAT_MODIFIER | No | Range in tiles |
| REDUCE_WEIGHT | 11 | FLAT or STAT_MODIFIER | No | Burden reduction |
| ADD_EXTRA_ATTACK | 12 | FLAT or STAT_MODIFIER | No | Adds extra attacks (non-recursive in current combat flow) |

## EffectTarget Values

| Name | Int |
|---|---:|
| SELF | 0 |
| ATTACKER | 1 |
| TARGET | 2 |
| ALL_ALLIES | 3 |
| ALL_ENEMIES | 4 |

## ValueType Values

| Name | Int | Parameters used |
|---|---:|---|
| FLAT | 0 | `flat_value` |
| DICE | 1 | `dice`, optional `uses_reliability` |
| STAT_MODIFIER | 2 | `modifier_stat`, `modifier_divisor` |

## Parameter Notes

- `string_param` (condition): required for `SELF_WEAPON_HAS_KEYWORD`, `SELF_WEAPON_TYPE_IS`.
- `string_param` (effect): required for `APPLY_BUFF`, `APPLY_DEBUFF`.
- `modifier_divisor` should be > 0 for `STAT_MODIFIER`.
- `trigger_match_mode = ALL` requires every trigger in the array to match.
