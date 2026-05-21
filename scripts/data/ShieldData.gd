## ShieldData.gd
## Resource representing a shield equippable in the off-hand slot.
class_name ShieldData
extends EquipmentData

# ---------------------------------------------------------------------------
# Shield Properties
# ---------------------------------------------------------------------------

## Bonus added to equipment evasion.
@export var evasion_bonus: int = 2

## Movement speed modifier (usually 0 or negative for heavy shields).
@export var movement_modifier: int = 0
