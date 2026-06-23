# Skill System Extension Guide

This guide explains how the current skill tree system works and how to add new skill triggers or new skill effects.

## Overview

The skill system is split across these files:

- `scripts/skill/SkillTreeManager.gd`
- `scripts/skill/SkillProcessor.gd`
- `scripts/data/SkillTreeEntry.gd`
- `scripts/data/SkillData.gd`
- `scripts/data/AbilityData.gd`
- `scripts/data/SkillCondition.gd`
- `scripts/data/SkillEffect.gd`
- `scripts/data/CharacterData.gd`

A character now has:

- 3 generated trees: Class, Stat, Weapon
- 9 nodes per tree
- `unlocked_skill_ids` to track what is actually learned
- equipment-granted skills/abilities that are always effective while equipped

Runtime systems should use `CharacterData.get_effective_skill_entries()` when they need the character's active learned skills and abilities.

## Generation model

Tree generation is deterministic and saved through these fields on `CharacterData`:

- `skill_tree_seed`
- `skill_tree_attribute`
- `skill_tree_weapon_category`
- `unlocked_skill_ids`

`SkillTreeManager.ensure_character_skill_trees(char_data)` regenerates the same 3 trees from those saved values.

Current generation rules:

- Class tree depends on the character class
- Stat tree depends on a randomly selected primary stat from the class
- Weapon tree depends on a weighted random weapon category from the class
- Tier unlock rule is global across all 3 trees: tier `T` requires `(T - 1) * 3` total spent points

## Adding a new trigger

A trigger is a condition that decides when a passive `SkillData` activates.

### Step 1: Add the enum value

Open `scripts/data/SkillCondition.gd` and add a new value to either:

- `MajorCondition` for a new event type
- `MinorCondition` for a new filter on an existing event type

Examples already present:

- `ON_ATTACK`
- `ON_TAKE_DAMAGE`
- `SELF_WEARING_HEAVY_ARMOR`
- `SELF_WEAPON_TYPE_IS`

### Step 2: Implement the check

Open `scripts/skill/SkillProcessor.gd`.

If you added a:

- new major condition: update `_condition_matches()`
- new minor condition: update `_minor_matches()`

Example pattern:

```gdscript
SkillCondition.MinorCondition.SELF_WEARING_HEAVY_ARMOR:
    return _self_armor_type(ctx) == ArmorData.ArmorType.HEAVY
```

If the condition needs extra context, add it to `SkillProcessor.SkillContext` first.

## Adding a new effect/result

An effect is the gameplay result produced by a passive skill.

### Step 1: Add the enum value

Open `scripts/data/SkillEffect.gd` and add a new value to `EffectType`.

Examples already present:

- `ADD_DAMAGE`
- `REDUCE_INCOMING_DAMAGE`
- `ADD_ATTACK_ACCURACY`
- `ADD_RELIABILITY`
- `ADD_RANGE`
- `REDUCE_WEIGHT`

### Step 2: Expose an aggregation helper

Open `scripts/skill/SkillProcessor.gd` and add a public helper that sums that effect type.

Example:

```gdscript
static func get_weight_reduction(ctx: SkillContext, dice_roller: DiceRoller = null) -> int:
    return _sum_effects(ctx, SkillEffect.EffectType.REDUCE_WEIGHT, dice_roller)
```

### Step 3: Apply it at the real gameplay control point

This is the most important step.

You must apply the new effect in the system that owns the gameplay calculation.

Examples in the current code:

- Weight reduction is applied in `CharacterData.get_total_burden_weight()`
- Incoming damage reduction is applied in `CombatManager._apply_attack_result_with_riposte()`
- Attack bonuses are applied in `AttackResolver.gd`

If you skip this step, the enum exists but does nothing.

## Adding new tree nodes

The generated trees are currently defined in `scripts/skill/SkillTreeManager.gd`.

Useful helpers there:

- `_make_skill(...)`
- `_make_ability_node(...)`
- `_flat_effect(...)`
- `_condition(...)`

To add a new node:

1. Pick the target builder:
   - `_build_class_tree(...)`
   - `_build_attribute_tree(...)`
   - `_build_weapon_tree(...)`
2. Add a `SkillData` or `AbilityData` node
3. Set its tier with the `tier` argument
4. Keep the tree at exactly 9 nodes

## Runtime rule for unlocked entries

Generated trees contain all possible nodes for that character, but only unlocked nodes should affect combat.

Use:

```gdscript
character.get_effective_skill_entries()
```

Do not iterate raw `character.skill_trees` in combat logic unless you explicitly want locked nodes too.

## UI/editor rule

The roster editor uses `SkillTreeManager.get_unlock_error(...)` and `SkillTreeManager.unlock_entry(...)`.

If unlock rules change later, update them in `SkillTreeManager.gd` so both UI and gameplay share the same logic.

## Adding new active abilities to trees

To place an existing `.tres` ability into a generated tree:

1. Add its resource path to `_ABILITY_FILES` in `SkillTreeManager.gd`
2. Use `_make_ability_node(...)` in the desired tree builder

This clones the base `AbilityData` and gives it a deterministic node id for unlock/save purposes.

## Recommended workflow for future changes

When adding any new trigger or effect:

1. Add the enum value
2. Implement the evaluation logic
3. Apply the result at the actual gameplay control point
4. Add at least one generated node that uses it
5. Verify that the affected system reads `get_effective_skill_entries()` rather than raw trees

That sequence keeps the system coherent and prevents dead configuration paths.
