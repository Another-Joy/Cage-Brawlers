# Items With Skills — Authoring Guide

This guide explains how to create equipment items (armor, buff items, weapons) that grant **passive skills** or **active abilities** to the character who equips them. Skill-granting equipment is used for flavor-rich items like *Mage's Kefta*, *Dream Catcher*, and *Crypt Candle*.

---

## Overview

Every equipment resource inherits from `EquipmentData`, which now carries:

```gdscript
@export var granted_skills: Array[SkillTreeEntry] = []
```

Items placed in this array are given to the character while the equipment is equipped. They function identically to skills learned from skill trees — there is no distinction at runtime. Passive `SkillData` entries fire automatically when their trigger conditions are met; `AbilityData` entries appear in the character's ability list and can be activated manually.

---

## Step 1 — Decide what the skill does

Before writing any .tres file, pin down three things:

| Question | Example (Dream Catcher) |
|---|---|
| **When** does it trigger? | At the beginning of the character's turn |
| **What** does it do? | Heal the owner for 2d4 HP |
| **Who** is affected? | Self |

---

## Step 2 — Create a SkillData .tres file

Each skill lives in `resources/skills/` as its own .tres file. A `SkillData` resource contains:

- **`triggers`** — An array of `SkillCondition` sub-resources. The skill fires when **any** trigger matches (OR semantics).
- **`effects`** — An array of `SkillEffect` sub-resources that execute when a trigger fires.

### SkillCondition fields

| Field | Type | Meaning |
|---|---|---|
| `major` | `MajorCondition` (int) | The broad event. See enum below. |
| `minor` | `MinorCondition` (int) | Optional narrowing. 0 = NONE. |
| `string_param` | String | Extra parameter for some minors (e.g. keyword name). |

**MajorCondition enum values:**

| Value | Int | Notes |
|---|---|---|
| ALWAYS | 0 | Always-on passive |
| ON_ATTACK | 1 | When making any attack |
| ON_DEAL_DAMAGE | 2 | When an attack hits and deals damage |
| ON_TAKE_DAMAGE | 3 | When receiving damage |
| ON_ATTACKED | 4 | When targeted by any attack |
| ON_MOVE | 5 | When moving |
| ON_CROUCH | 6 | When crouching |
| ON_STAND_UP | 7 | When standing up |
| ON_TURN_START | 8 | At the start of this character's turn |
| ON_TURN_END | 9 | At the end of this character's turn |
| ON_HEAL | 10 | When this character receives any healing |

**MinorCondition enum values (selection):**

| Value | Int | Notes |
|---|---|---|
| NONE | 0 | No narrowing |
| ATTACKER_USING_PHYSICAL | 6 | |
| ATTACKER_USING_RANGED | 7 | |
| ATTACKER_USING_MAGICAL | 8 | |
| SELF_WEAPON_HAS_KEYWORD | 11 | `string_param` = keyword name |
| ATTACK_IS_SURPRISE | 12 | Surprise attack (attacker unseen) |
| ATTACK_IS_ABILITY | 13 | Attack was made via an active Ability |

### SkillEffect fields

| Field | Type | Meaning |
|---|---|---|
| `effect_type` | `EffectType` (int) | What happens. See enum below. |
| `target` | `EffectTarget` (int) | Who it applies to (SELF=0, ATTACKER=1, TARGET=2, ALL_ALLIES=3, ALL_ENEMIES=4). |
| `value_type` | `ValueType` (int) | FLAT=0, DICE=1, STAT_MODIFIER=2 |
| `flat_value` | int | Used when value_type=FLAT |
| `dice` | DiceValue | Used when value_type=DICE |
| `uses_reliability` | bool | If true, the dice roll uses reliability |

**EffectType enum values:**

| Value | Int | Notes |
|---|---|---|
| ADD_DAMAGE | 0 | Extra damage added to the current attack |
| REDUCE_INCOMING_DAMAGE | 1 | Reduce damage taken |
| ADD_ATTACK_ACCURACY | 2 | Flat accuracy bonus to this attack. For %-based bonuses, `flat_value` is the percentage-point increase (e.g. 30 = +30%) |
| ADD_EVASION | 4 | Bonus evasion for this hit |
| MODIFY_MOVEMENT | 5 | Change movement tiles |
| HEAL | 6 | Restore HP |
| APPLY_BUFF | 7 | Apply named buff (`string_param` = buff id) |
| APPLY_DEBUFF | 8 | Apply named debuff |
| ADD_RELIABILITY | 9 | Add percentage points to attack reliability (`flat_value` = pp, e.g. 30 = +30%) |
| ADD_RANGE | 10 | Add flat tiles to attack range (`flat_value` = tiles) |

### Complete example — Dream Catcher skill

```
[gd_resource type="Resource" script_class="SkillData" format=3]

[ext_resource type="Script" path="res://scripts/data/SkillData.gd" id="1"]
[ext_resource type="Script" path="res://scripts/data/SkillCondition.gd" id="3"]
[ext_resource type="Script" path="res://scripts/data/SkillEffect.gd" id="4"]
[ext_resource type="Script" path="res://scripts/data/DiceValue.gd" id="5"]

[sub_resource type="Resource" id="trigger"]
script = ExtResource("3")
major = 8      # ON_TURN_START
minor = 0      # NONE

[sub_resource type="Resource" id="dice"]
script = ExtResource("5")
count = 2
sides = 4      # 2d4

[sub_resource type="Resource" id="effect"]
script = ExtResource("4")
effect_type = 6   # HEAL
target = 0        # SELF
value_type = 1    # DICE
dice = SubResource("dice")

[resource]
script = ExtResource("1")
entry_id = "dream_catcher_heal"
entry_name = "Dream Catcher: Healing Mist"
description = "At the beginning of your turn, heal 2d4 HP."
triggers = [SubResource("trigger")]
effects = [SubResource("effect")]
```

---

## Step 3 — Attach the skill to an equipment .tres file

Reference the skill's .tres as an `ExtResource` and add it to `granted_skills`:

```
[gd_resource type="Resource" script_class="BuffItemData" format=3]

[ext_resource type="Script" path="res://scripts/data/BuffItemData.gd" id="1"]
[ext_resource type="Resource" path="res://resources/skills/dream_catcher_skill.tres" id="2"]

[resource]
script = ExtResource("1")
item_id = "dream_catcher"
item_name = "Dream Catcher"
description = "At the beginning of your turn, heal 2d4 HP."
equipment_type = 2    # BUFF
weight = 0.5
granted_skills = [ExtResource("2")]
```

The `granted_skills` array accepts any mix of `SkillData` (passive) and `AbilityData` (active) resources.

---

## Step 4 — Multiple triggers or effects

Skills can have multiple triggers (OR) and multiple effects (all fire together):

```
# Crypt Candle — fires on Magical damage OR Ability damage
triggers = [SubResource("trigger_magical"), SubResource("trigger_ability")]
effects  = [SubResource("effect")]          # same +1d4 for both triggers
```

To produce two independent effects from one trigger, list both in `effects`:

```
# Mage's Kefta — +30% Reliability AND +2 Range
effects = [SubResource("effect_reliability"), SubResource("effect_range")]
```

---

## Step 5 — Equipment that grants active Abilities

`AbilityData` extends `SkillTreeEntry`, so it can also appear in `granted_skills`. This is used when an item unlocks an active ability the player can trigger on their turn.

Key `AbilityData` fields beyond the standard skill fields:

| Field | Purpose |
|---|---|
| `phases` | Bitmask: 1=Beginning, 2=Main, 4=Ending |
| `weapon_requirements` | OR list of weapon type names required (e.g. `["axe"]`) |
| `cooldown_turns` | Turns unavailable after use (0 = no cooldown) |
| `dice_count_modifier` | Delta applied to the weapon's dice count (min 1) |
| `dice_tier_modifier` | Steps up/down the dice tier chain: 2→4→6→8→10→12→16→20 |
| `accuracy_modifier_percent` | % bonus/penalty to this ability's accuracy |
| `reliability_modifier_percent` | % bonus/penalty to this ability's reliability |
| `range_modifier` | Flat tile change to this ability's range |
| `ignore_aiming_restriction` | Bypasses the Aiming keyword movement check |
| `prevents_stand_up` | User stays crouched after using this ability |

### Example — Hip Shot (ignores Aiming restriction)

```
[resource]
script = ExtResource("1")
entry_id = "hip_shot"
entry_name = "Hip Shot"
phases = 2                                          # PHASE_MAIN
weapon_requirements = Array[String](["crossbow", "rifle"])
dice_tier_modifier = -1                             # 0d-1 modifier
ignore_aiming_restriction = true
actions = [SubResource("action_attack")]
```

---

## Keyword Reference

These keywords are stored in `EquipmentData.keywords: Array[String]` and detected by the named helpers on `WeaponData`:

| Keyword | Helper | Behaviour |
|---|---|---|
| `Versatile` | `is_versatile()` | Can be wielded one- or two-handed. Two-handed dice stored in `versatile_two_handed_count`/`sides`. |
| `Finesse` | `is_finesse()` | Uses Wis for damage bonus, double Dex accuracy bonus, gains reliability from Dex. |
| `Light` | `is_light_weapon()` | Can be equipped in the off-hand. Each weapon makes one attack when dual-wielding. |
| `Two-Handed` | `is_two_handed()` | Locks the off-hand slot. |
| `Magazine` | `has_magazine()` | Weapon has a magazine. Capacity in `magazine_capacity`. Full reload is a Beginning action. |
| `Aiming` | `requires_aiming()` | Cannot be fired after moving (unless ability has `ignore_aiming_restriction = true`). Ignores accuracy fall-off. |
| `Inaccurate` | `is_inaccurate()` | Accuracy fall-off is doubled. |

---

## WeaponType Enum

Use the integer value in .tres `weapon_type` field:

| Name | Int |
|---|---|
| SWORD | 0 |
| AXE | 1 |
| DAGGER | 2 |
| BOW | 3 |
| CROSSBOW | 4 |
| RIFLE | 5 |
| TOME | 6 |
| BALL | 7 |

---

## Ability Damage Modifiers

Abilities can change the weapon's dice expression for that specific use:

- **`dice_count_modifier`** — delta on the number of dice (clamped to minimum 1). Example: `+0d-1` on a 2d6 weapon → still 2 dice.
- **`dice_tier_modifier`** — steps along the tier chain. Example: `-1` on a 1d10 weapon → 1d8.

The tier chain: **2 → 4 → 6 → 8 → 10 → 12 → 16 → 20**.

```gdscript
# Helper available on AbilityData
AbilityData.apply_dice_tier_modifier(10, -1)  # returns 8
AbilityData.apply_dice_count_modifier(2, -1)  # returns 1
```

These modifiers also apply to any dice bonuses added by skills/effects that contribute directly to that attack (not to follow-up attacks spawned by a skill).

---

## Cooldown Behaviour

- `cooldown_turns = 0` — no cooldown, ability can be used every turn.
- `cooldown_turns = 2` — after use, the ability is unavailable for 1 full turn; usable again on the turn after.
- `cooldown_turns = 3` — unavailable for 2 turns.
- `cooldown_turns = -1` — special/non-standard cooldown (handled in game logic, not by the standard tick system).

Cooldowns tick down at the **start** of the character's turn (via `CombatManager._tick_cooldowns`).

---

## Tips

- Keep each skill in its own .tres file under `resources/skills/` so it can be referenced by multiple items.
- Use `entry_id` values that clearly indicate their source item (e.g. `"dream_catcher_heal"`).
- For skills that modify attack rolls (reliability, accuracy, range) make sure the `SkillProcessor` reads `ADD_RELIABILITY` and `ADD_RANGE` before finalising the attack.
- Equipment skills are removed from the character's effective skill list when the item is unequipped — the equip/unequip logic must add/remove `granted_skills` entries accordingly.
