## ArmorData.gd
## Resource representing an armor item occupying the armor slot.
class_name ArmorData
extends EquipmentData

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum ArmorType {
	LIGHT,
	MEDIUM,
	HEAVY,
}

# ---------------------------------------------------------------------------
# Armor Properties
# ---------------------------------------------------------------------------

@export var armor_type: ArmorType = ArmorType.MEDIUM

## Armor Value: flat damage reduction applied before HP loss.
@export var armor_value: int = 0

## Modifier applied to the character's base evasion (negative for heavy armor).
@export var evasion_modifier: int = 0

## Modifier applied to the character's base movement speed.
@export var movement_modifier: int = 0

## Total ammo slot capacity units.
## Bullets and bolts consume 1 unit each; arrows consume 2 units each.
@export var ammo_slots_capacity: int = 4

## Whether this armor allows arrows to be carried.
@export var allows_arrows: bool = true

## Number of potion slots available in the belt.
@export var potion_slots: int = 2
