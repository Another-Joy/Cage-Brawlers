# Cage Brawlers — Resources Guide

This guide explains how the game's data (characters, weapons, armor, classes, skills, abilities) is stored as Godot **Resource** (`.tres`) files, and how to add or customise them.

---

## Directory layout

```
resources/
├── classes/
│   ├── warrior.tres
│   ├── ranger.tres
│   ├── mage.tres
│   ├── rogue.tres
│   └── cleric.tres
├── weapons/
│   ├── sword.tres
│   ├── shortbow.tres
│   └── dagger.tres
├── armor/
│   ├── leather_armor.tres
│   └── cloth_armor.tres
└── characters/
    ├── team_a/
    │   ├── 01_warrior.tres
    │   ├── 02_ranger.tres
    │   └── 03_rogue.tres
    └── team_b/
        ├── 01_warrior.tres
        ├── 02_ranger.tres
        └── 03_rogue.tres
```

- Each `.tres` file is a plain-text serialised Godot Resource.  
- Characters are loaded alphabetically by filename — use a numeric prefix (`01_`, `02_`, `03_`) to control spawn-position order.  
- The server (`ServerGame.gd`) reads the `team_a` and `team_b` folders at match start; all `.tres` files found there become the roster.

---

## How to edit a `.tres` file

The easiest way is inside the **Godot Editor**:

1. Open the project.  
2. In the **FileSystem** dock, navigate to `resources/`.  
3. Double-click any `.tres` file — the **Inspector** opens with all exported properties editable.  
4. Change values and press **Ctrl+S** to save.

You can also edit `.tres` files in any plain-text editor (see formats below).

---

## Weapon files (`WeaponData`)

### Properties

| Property | Type | Description |
|---|---|---|
| `item_id` | String | Unique identifier used in code (snake_case). |
| `item_name` | String | Display name shown in the HUD. |
| `description` | String | Flavour text. |
| `equipment_type` | int | Always `0` for weapons. |
| `weight` | float | Kilograms; affects carry-weight and encumbrance. |
| `keywords` | Array[String] | Special rules. `"Light"` allows off-hand use; `"Two-Handed"` locks the off-hand slot. |
| `damage_type` | int | `0` = Physical, `1` = Ranged, `2` = Magical. |
| `damage_dice_count` | int | Number of dice rolled per attack (e.g. `2` for 2d6). |
| `damage_dice_sides` | int | Sides per die (e.g. `6` for d6). |
| `attack_range` | int | Tiles. `1` = melee (adjacent only). |
| `ammo_type` | int | Ammo consumed per attack. `0`=NONE, `1`=BULLETS, `2`=BOLTS, `3`=ARROWS. |

### Example — a heavy crossbow

```gdresource
[gd_resource type="WeaponData" format=3]

[resource]
item_id = "crossbow"
item_name = "Crossbow"
description = "A powerful bolt-firing weapon."
equipment_type = 0
weight = 3.5
keywords = ["Two-Handed"]
damage_type = 1
damage_dice_count = 2
damage_dice_sides = 6
attack_range = 8
ammo_type = 2
```

---

## Armor files (`ArmorData`)

### Properties

| Property | Type | Description |
|---|---|---|
| `item_id` | String | Unique identifier. |
| `item_name` | String | Display name. |
| `description` | String | Flavour text. |
| `equipment_type` | int | Always `3` for armor. |
| `weight` | float | Kilograms. |
| `armor_type` | int | `0` = Light, `1` = Medium, `2` = Heavy. |
| `armor_value` | int | Flat damage reduction per hit. |
| `evasion_modifier` | int | Added to character evasion (can be negative for heavy). |
| `movement_modifier` | int | Added to movement speed (can be negative). |
| `ammo_slots_capacity` | int | Total ammo-unit capacity (bullets/bolts = 1 unit; arrows = 2 units). |
| `allows_arrows` | bool | `false` blocks arrows from being carried with this armor. |
| `potion_slots` | int | Number of potions that can be carried. |

### Example — heavy plate armor

```gdresource
[gd_resource type="ArmorData" format=3]

[resource]
item_id = "plate_armor"
item_name = "Plate Armor"
description = "Heavy protection at the cost of mobility."
equipment_type = 3
weight = 15.0
armor_type = 2
armor_value = 5
evasion_modifier = -3
movement_modifier = -1
ammo_slots_capacity = 2
allows_arrows = false
potion_slots = 1
```

---

## Shield files (`ShieldData`)

| Property | Type | Description |
|---|---|---|
| `item_id` | String | Unique identifier. |
| `item_name` | String | Display name. |
| `equipment_type` | int | Always `1` for shields. |
| `weight` | float | Kilograms. |
| `evasion_bonus` | int | Added to equipment evasion. |
| `movement_modifier` | int | Usually `0` or negative for heavy shields. |

---

## Character files (`CharacterData`)

Character files reference weapon and armor files using `ext_resource` links.

### Enum reference

**`character_class`**

| Value | Class |
|---|---|
| `0` | Warrior |
| `1` | Ranger |
| `2` | Mage |
| `3` | Rogue |
| `4` | Cleric |

**`state_flag`** — always set to `0` (Living) in the resource file; the server manages the rest.

### Template — a new Mage character

Save this as e.g. `resources/characters/team_a/04_mage.tres`:

```gdresource
[gd_resource type="CharacterData" load_steps=2 format=3]

[ext_resource type="WeaponData" path="res://resources/weapons/staff.tres" id="1"]

[resource]
character_id = "char_a_mage"
character_name = "A-Mage"
level = 1
experience = 0
character_class = 2
state_flag = 0
strength = 6
dexterity = 10
constitution = 8
wisdom = 14
intelligence = 16
main_hand_slot = ExtResource("1")
bullets_count = 0
bolts_count = 0
arrows_count = 0
potions_count = 0
```

> **Tip:** if you set both `main_hand_slot` and `off_hand_slot` to the same light weapon (same `id=` value), the character dual-wields.

### `load_steps` value

Set `load_steps` to `1 + <number of ext_resource lines>`.

| Slots used | `load_steps` |
|---|---|
| no equipment | `1` |
| main hand only | `2` |
| main hand + armor | `3` |
| main + off-hand + armor | `4` |

---

## Adding a new character to a team

1. Create any required weapon or armor `.tres` files in `resources/weapons/` or `resources/armor/`.
2. Create a new character `.tres` file in `resources/characters/team_a/` or `team_b/` (name it with a numeric prefix to control spawn order).
3. Run the server — the roster is read from disk at match start; no code changes are needed.

> **Team size note:** The default test map has 3 spawn positions per side. Adding a 4th character file is harmless — that character simply won't be placed on the map until you extend the spawn arrays in `ServerGame.start_test_match()`.

---

## Adding a new class (stat profile only)

1. Add a new value to `CharacterData.CharacterClass` enum in `scripts/data/CharacterData.gd`.
2. Add health-segment percentages for the new class in `ClassDefinitions.get_segment_percentages()`.
3. Optionally add allowed weapon categories in `ClassDefinitions.get_weapon_categories()`.
4. Use the new enum integer value in character `.tres` files.

---

## Class files (`ClassData`)

Classes are stored as `.tres` files under `resources/classes/`. Each file fully defines
a character archetype and is linked into character files via the `class_data` field.

### Properties

| Property | Type | Description |
|---|---|---|
| `class_id` | String | Snake_case identifier (e.g. `"warrior"`). |
| `display_name` | String | Human-readable name shown in the UI. |
| `primary_stat` | int | `0`=STR, `1`=DEX, `2`=CON, `3`=WIS, `4`=INT. |
| `secondary_stat` | int | Same enum as `primary_stat`. |
| `hit_dice` | DiceValue | Sub-resource: `count` dice of `sides` sides rolled each level-up. |
| `level_health_modifier` | int | Flat HP added on top of the hit-dice roll each level. |
| `main_damage_type` | int | `0`=Physical, `1`=Ranged, `2`=Magical. |
| `health_segment_percentages` | PackedFloat32Array | Three floats summing to `1.0` (left→right segment sizes). |
| `weapon_categories` | Array[String] | Categories for the weapon skill tree (e.g. `["sword","axe"]`). |

### Example — Warrior class

```gdresource
[gd_resource type="Resource" script_class="ClassData" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/data/ClassData.gd" id="1"]
[ext_resource type="Script" path="res://scripts/data/DiceValue.gd" id="2"]

[sub_resource type="Resource" id="hit_dice"]
script = ExtResource("2")
count = 1
sides = 10

[resource]
script = ExtResource("1")
class_id = "warrior"
display_name = "Warrior"
primary_stat = 0
secondary_stat = 1
hit_dice = SubResource("hit_dice")
level_health_modifier = 2
main_damage_type = 0
health_segment_percentages = PackedFloat32Array(0.35, 0.35, 0.3)
weapon_categories = ["sword", "axe", "mace"]
```

To link a class resource to a character, add an `ext_resource` entry pointing at the
`.tres` file and set `class_data = ExtResource("<id>")` in the `[resource]` block.

---

## Skill files (`SkillData`) — passive skills

Passive skills fire automatically when their trigger conditions are met. They are stored
as `.tres` files and referenced from `SkillTreeManager` pools.

### Key Properties

| Property | Type | Description |
|---|---|---|
| `entry_id` | String | Unique snake_case ID. |
| `entry_name` | String | Display name. |
| `required_level` | int | Minimum level to learn. |
| `tree_type` | int | `0`=CLASS, `1`=ATTRIBUTE, `2`=WEAPON. |
| `triggers` | Array[SkillCondition] | OR list of (major + optional minor) trigger pairs. |
| `effects` | Array[SkillEffect] | Effects applied when any trigger fires. |

### SkillCondition sub-resource

| Property | Type | Values |
|---|---|---|
| `major` | int | `ALWAYS`=0, `ON_ATTACK`=1, `ON_DEAL_DAMAGE`=2, `ON_TAKE_DAMAGE`=3, `ON_ATTACKED`=4, `ON_MOVE`=5, `ON_CROUCH`=6, `ON_STAND_UP`=7, `ON_TURN_START`=8, `ON_TURN_END`=9 |
| `minor` | int | `NONE`=0, `TARGET_WEARING_HEAVY_ARMOR`=1, `TARGET_CROUCHED`=4, `ATTACKER_USING_RANGED`=6, `SELF_CROUCHED`=8, `SELF_WEAPON_HAS_KEYWORD`=10, … |
| `string_param` | String | Extra parameter for keyword-based minors. |

### SkillEffect sub-resource

| Property | Type | Description |
|---|---|---|
| `effect_type` | int | `ADD_DAMAGE`=0, `REDUCE_INCOMING_DAMAGE`=1, `ADD_ATTACK_ACCURACY`=2, `REDUCE_ACCURACY`=3, `ADD_EVASION`=4, `MODIFY_MOVEMENT`=5, `HEAL`=6, `APPLY_BUFF`=7, `APPLY_DEBUFF`=8 |
| `target` | int | `SELF`=0, `ATTACKER`=1, `TARGET`=2, `ALL_ALLIES`=3, `ALL_ENEMIES`=4 |
| `value_type` | int | `FLAT`=0, `DICE`=1, `STAT_MODIFIER`=2 |
| `flat_value` | int | Used when `value_type`=FLAT. |
| `dice` | DiceValue | Sub-resource used when `value_type`=DICE. |
| `modifier_stat` | String | Stat name used when `value_type`=STAT_MODIFIER. |
| `modifier_divisor` | int | Divisor for stat modifier. |

---

## Ability files (`AbilityData`) — active abilities

Active abilities are used by the player during a specific action phase. They are also
stored as `.tres` files and can appear in any of the three skill trees.

### Key Properties

| Property | Type | Description |
|---|---|---|
| `entry_id` | String | Unique snake_case ID. |
| `entry_name` | String | Display name. |
| `required_level` | int | Minimum level to learn. |
| `phases` | int | Bitmask: `1`=Beginning, `2`=Main, `4`=Ending. OR values together for multi-phase. |
| `conditions` | Array[AbilityCondition] | All must be true (AND) for the ability to be available. |
| `actions` | Array[AbilityAction] | Ordered actions performed when the ability is used. |

### AbilityCondition sub-resource

| Property | Type | Description |
|---|---|---|
| `condition_type` | int | `SELF_CROUCHED`=0, `ADJACENT_BARRICADE`=1, `HAS_AMMO`=2, `HAS_SKILL`=3, `TARGET_IN_RANGE`=4 |
| `must_be_true` | bool | `false` inverts the check (e.g. "must NOT be crouched"). |
| `string_param` | String | Ammo type name or skill entry_id for relevant conditions. |

### AbilityAction sub-resource

| Property | Type | Description |
|---|---|---|
| `action_type` | int | `ATTACK`=0, `MOVE`=1, `HEAL`=2, `APPLY_BUFF`=3, `APPLY_DEBUFF`=4, `CROUCH`=5, `STAND_UP`=6, `GRANT_BONUS`=7 |
| `target_type` | int | `SELF`=0, `ALLY`=1, `ENEMY`=2, `ANY`=3 |
| `range_override` | int | Override range (0=use weapon/movement default). |
| `bonus_dice` | DiceValue | Extra dice rolled for ATTACK/HEAL value. |
| `flat_bonus` | int | Flat value added to the action's result. |
| `string_param` | String | Buff ID (APPLY_BUFF/DEBUFF) or stat name (GRANT_BONUS). |

### Example — Stand Up ability

```gdresource
[gd_resource type="Resource" script_class="AbilityData" format=3]

[ext_resource type="Script" path="res://scripts/data/AbilityData.gd" id="1"]
[ext_resource type="Script" path="res://scripts/data/AbilityCondition.gd" id="2"]
[ext_resource type="Script" path="res://scripts/data/AbilityAction.gd" id="3"]

[sub_resource type="Resource" id="cond"]
script = ExtResource("2")
condition_type = 0
must_be_true = true

[sub_resource type="Resource" id="act"]
script = ExtResource("3")
action_type = 6
target_type = 0

[resource]
script = ExtResource("1")
entry_id = "stand_up"
entry_name = "Stand Up"
description = "Stand up from a crouched position."
required_level = 1
phases = 1
conditions = [SubResource("cond")]
actions = [SubResource("act")]
```

---

## Tips

- Always **open the project in the Godot editor at least once** after adding new `.tres` files — Godot generates import metadata (`.uid` entries) that makes loading faster and more reliable.  
- Property names in `.tres` files must match the `@export` variable names in the GDScript class exactly (case-sensitive).  
- Omitted properties use their default values from the GDScript class definition.  
- Use the Godot editor's Inspector for complex types (nested resources, typed arrays) to avoid syntax errors.
