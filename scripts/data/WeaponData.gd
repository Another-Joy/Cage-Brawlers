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

## Specific weapon type used for class weapon-category filtering and
## ability/skill requirement checks.
## Store the integer value in .tres files.
enum WeaponType {
	SWORD,     ## 0 — One- or two-handed bladed weapon (longsword, greatsword…)
	AXE,       ## 1 — Axe-type weapon (handaxe, battleaxe, greataxe…)
	DAGGER,    ## 2 — Light finesse blade (dagger)
	BOW,       ## 3 — Bow (shortbow, longbow…)
	CROSSBOW,  ## 4 — Crossbow (hand crossbow, light crossbow, heavy crossbow…)
	RIFLE,     ## 5 — Firearm with magazine and Aiming (rifle…)
	TOME,      ## 6 — Magical focus: tome variant (ancient tome…)
	BALL,      ## 7 — Magical focus: ball/orb variant (crystal ball…)
}

# ---------------------------------------------------------------------------
# Weapon Properties
# ---------------------------------------------------------------------------

@export var damage_type: DamageType = DamageType.PHYSICAL
@export var weapon_type: WeaponType = WeaponType.SWORD

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
# Versatile Keyword
# ---------------------------------------------------------------------------

## Two-handed damage dice count when Versatile keyword is present.
## E.g. 1d10 two-handed on a longsword (1d8 one-handed): set to 1.
## 0 means not Versatile (or not set).
@export var versatile_two_handed_count: int = 0
## Two-handed damage die size when Versatile keyword is present (e.g. 10 for d10).
@export var versatile_two_handed_sides: int = 0

# ---------------------------------------------------------------------------
# Magazine Keyword
# ---------------------------------------------------------------------------

## Maximum magazine size for weapons with the "Magazine" keyword.
## 0 means no magazine (weapon does not consume from a magazine).
## Attacking consumes 1 ammo per shot. A full reload is a Beginning phase action.
## The weapon starts each match with a full magazine (not counted towards belt capacity).
@export var magazine_capacity: int = 0

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

## Returns true if this weapon has a magazine.
func has_magazine() -> bool:
	return has_keyword("Magazine")

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

## Returns the damage dice count and sides considering whether the character is
## wielding the weapon two-handed (only relevant for Versatile weapons).
func get_effective_damage_dice(two_handed: bool) -> Array[int]:
	if two_handed and is_versatile() and versatile_two_handed_count > 0:
		return [versatile_two_handed_count, versatile_two_handed_sides]
	return [damage_dice_count, damage_dice_sides]

## Returns the weapon type name as a lowercase string (e.g. "axe", "sword").
func get_weapon_type_name() -> String:
	return WeaponType.keys()[weapon_type].to_lower()

## Returns the display name of this weapon's damage type.
func get_damage_type_name() -> String:
	return DamageType.keys()[damage_type] if damage_type < DamageType.size() else "UNKNOWN"
