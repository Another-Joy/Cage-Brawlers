## SupportItemData.gd
## Resource representing a consumable/support item (ammo or potions).
class_name SupportItemData
extends EquipmentData

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum SupportType {
	BULLETS,
	BOLTS,
	ARROWS,
	POTION,
}

# ---------------------------------------------------------------------------
# Support Item Properties
# ---------------------------------------------------------------------------

@export var support_type: SupportType = SupportType.BULLETS

## Amount this item restores when used (for potions: HP restored).
@export var restore_amount: float = 0.0

## Whether this item uses the Reliability modifier when rolled.
@export var uses_reliability: bool = false
