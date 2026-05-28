## WeaponType.gd
## Globally-accessible weapon type constants.
## All scripts can reference e.g. WeaponType.Type.SWORD, WeaponType.Type.AXE without
## needing to access them through WeaponData.
class_name WeaponType
extends RefCounted

## Weapon type identifiers. Values match the integer stored in WeaponData.weapon_type.
enum Type {
	SWORD    = 0,  ## One- or two-handed bladed weapon (longsword, greatsword…)
	AXE      = 1,  ## Axe-type weapon (handaxe, battleaxe, greataxe…)
	DAGGER   = 2,  ## Light finesse blade (dagger)
	BOW      = 3,  ## Bow (shortbow, longbow…)
	CROSSBOW = 4,  ## Crossbow (hand, light, heavy…)
	RIFLE    = 5,  ## Firearm with magazine and Aiming (rifle…)
	TOME     = 6,  ## Magical focus: tome variant (ancient tome…)
	BALL     = 7,  ## Magical focus: ball/orb variant (crystal ball…)
}

## Ordered lowercase names for display and requirement matching.
const NAMES: Array[String] = ["sword", "axe", "dagger", "bow", "crossbow", "rifle", "tome", "ball"]

## Returns the lowercase name for a given weapon type integer.
static func get_type_name(type: int) -> String:
	if type >= 0 and type < NAMES.size():
		return NAMES[type]
	return "unknown"
