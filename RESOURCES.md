# Cage Brawlers — Resources Guide

This guide explains how the game's data (characters, weapons, armor) is stored as Godot **Resource** (`.tres`) files, and how to add or customise them.

---

## Directory layout

```
resources/
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

## Tips

- Always **open the project in the Godot editor at least once** after adding new `.tres` files — Godot generates import metadata (`.uid` entries) that makes loading faster and more reliable.  
- Property names in `.tres` files must match the `@export` variable names in the GDScript class exactly (case-sensitive).  
- Omitted properties use their default values from the GDScript class definition.  
- Use the Godot editor's Inspector for complex types (nested resources, typed arrays) to avoid syntax errors.
