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

## Number of dice to roll for damage (e.g. 2 for 2d6).
@export var damage_dice_count: int = 1
## Number of sides on each damage die (e.g. 6 for d6).
@export var damage_dice_sides: int = 6

## Attack range in grid tiles. 1 = melee adjacent only.
@export var attack_range: int = 1

## The ammo type this weapon consumes per attack.
## NONE means no ammo is needed; any other value requires the matching count > 0.
@export var ammo_type: AmmoType = AmmoType.NONE

# ---------------------------------------------------------------------------
# Derived Helpers
# ---------------------------------------------------------------------------

## Returns true if this weapon can be placed in the off-hand (has the "Light" keyword).
func is_light_weapon() -> bool:
	return has_keyword("Light")

## Returns true if this is a two-handed weapon (locks the off-hand slot).
func is_two_handed() -> bool:
	return has_keyword("Two-Handed")

## Returns true if this is a ranged weapon (DamageType.RANGED).
func is_ranged() -> bool:
	return damage_type == DamageType.RANGED

## Returns true if this is a magical weapon (DamageType.MAGICAL).
func is_magical() -> bool:
	return damage_type == DamageType.MAGICAL

## Returns true if this weapon requires any ammo to fire.
func requires_ammo() -> bool:
	return ammo_type != AmmoType.NONE

## Returns the display name of this weapon's damage type.
func get_damage_type_name() -> String:
	return DamageType.keys()[damage_type] if damage_type < DamageType.size() else "UNKNOWN"
