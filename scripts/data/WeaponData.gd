## WeaponData.gd
## Resource representing a weapon equippable in a hand slot.
class_name WeaponData
extends EquipmentData

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum DamageType {
	PHYSICAL,
	RANGED,
	MAGICAL,
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

## The ammo type this weapon consumes (empty string = no ammo needed).
## Valid values: "bullets", "bolts", "arrows", ""
@export var ammo_type: String = ""

## Set to true when this weapon consumes ammo on each attack.
## This should be consistent with the ammo_type field: if ammo_type is non-empty,
## requires_ammo should also be true. Configured manually in the item resource.
@export var requires_ammo: bool = false

# ---------------------------------------------------------------------------
# Derived Helpers
# ---------------------------------------------------------------------------

## Returns true if this weapon can be placed in the off-hand (has the Light keyword).
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
