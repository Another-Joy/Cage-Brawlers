## WeaponData.gd
## Resource representing a weapon equippable in a hand slot.
class_name WeaponData
extends EquipmentData

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum DamageType {
	PHYSICAL,  ## 0
	RANGED,    ## 1
	MAGICAL,   ## 2
}

## Ammo category consumed by this weapon on each attack.
## Store the integer value in .tres files.
enum AmmoType {
	NONE,     ## 0 — No ammo required.
	BULLETS,  ## 1 — Consumes bullets from the character's belt.
	BOLTS,    ## 2 — Consumes crossbow bolts from the character's belt.
	ARROWS,   ## 3 — Consumes arrows (2 capacity units each) from the belt.
}

# ---------------------------------------------------------------------------
# Weapon Properties
# ---------------------------------------------------------------------------

@export var damage_type: DamageType = DamageType.PHYSICAL
## Weapon type identifier. Use WeaponType constants (e.g. WeaponType.SWORD).
## The WeaponType class is globally accessible from any script.
@export var weapon_type: int = WeaponType.SWORD

## Number of dice to roll for damage (e.g. 2 for 2d6).
@export var damage_dice_count: int = 1
## Number of sides on each damage die (e.g. 6 for d6).
@export var damage_dice_sides: int = 6

## Attack range in grid tiles. 1 = melee adjacent only.
@export var attack_range: int = 1

## The ammo type this weapon consumes per attack.
## NONE means no ammo is needed; any other value requires the matching count > 0.
@export var ammo_type: AmmoType = AmmoType.NONE

## Base reliability (0.0–1.0) baked into this weapon's damage roll.
## 0.0 = fully random; 1.0 = always maximum roll.
## Applied before ability-level reliability modifiers.
## Note: "Dice Value can have incorporated Reliability" from the spec —
## no base reliability is set on any weapon currently; the field is here
## for future use and for class hit dice expressions (via DiceValue).
@export var base_reliability: float = 0.0

# ---------------------------------------------------------------------------
# Derived Helpers
# ---------------------------------------------------------------------------

## Returns true if this weapon can be placed in the off-hand (Light keyword).
func is_light_weapon() -> bool:
	return has_keyword("Light")

## Returns true if this is a two-handed weapon (locks the off-hand slot).
func is_two_handed() -> bool:
	return has_keyword("Two-Handed")

## Returns true if this weapon can be used one- or two-handed (Versatile keyword).
func is_versatile() -> bool:
	return has_keyword("Versatile")

## Returns true if this is a Finesse weapon.
## Finesse weapons use Wis for damage, double Dex accuracy bonus, and gain
## reliability from Dex at the same rate as the accuracy bonus.
func is_finesse() -> bool:
	return has_keyword("Finesse")

## Returns true if this weapon has a magazine (Magazine keyword).
func has_magazine() -> bool:
	return has_keyword("Magazine")

## Returns this weapon's magazine capacity from keyword_params.
## Returns 0 if the Magazine keyword is absent or capacity is not set.
func get_magazine_capacity() -> int:
	return int(get_keyword_param("Magazine", "capacity", 0))

## Returns true if this weapon requires no movement in the Beginning Phase to fire.
## Abilities with ignore_aiming_restriction bypass this check.
func requires_aiming() -> bool:
	return has_keyword("Aiming")

## Returns true if this weapon has doubled accuracy fall-off (Inaccurate keyword).
func is_inaccurate() -> bool:
	return has_keyword("Inaccurate")

## Returns true if this is a ranged weapon (DamageType.RANGED).
func is_ranged() -> bool:
	return damage_type == DamageType.RANGED

## Returns true if this is a magical weapon (DamageType.MAGICAL).
func is_magical() -> bool:
	return damage_type == DamageType.MAGICAL

## Returns true if this weapon requires any ammo to fire.
func requires_ammo() -> bool:
	return ammo_type != AmmoType.NONE

## Returns the effective [count, sides] for the damage roll, considering
## whether the weapon is wielded two-handed (only relevant for Versatile weapons).
## Two-handed dice are stored in keyword_params["Versatile"]["count"/"sides"].
func get_effective_damage_dice(two_handed: bool) -> Array[int]:
	if two_handed and is_versatile():
		var count: int = int(get_keyword_param("Versatile", "count", damage_dice_count))
		var sides: int = int(get_keyword_param("Versatile", "sides", damage_dice_sides))
		if count > 0 and sides > 0:
			return [count, sides]
	return [damage_dice_count, damage_dice_sides]

## Returns the weapon type name as a lowercase string (e.g. "axe", "sword").
func get_weapon_type_name() -> String:
	return WeaponType.get_name(weapon_type)

## Returns the display name of this weapon's damage type.
func get_damage_type_name() -> String:
	return DamageType.keys()[damage_type] if damage_type < DamageType.size() else "UNKNOWN"
