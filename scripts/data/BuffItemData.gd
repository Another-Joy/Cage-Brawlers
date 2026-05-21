## BuffItemData.gd
## Resource representing a buff item equippable in the off-hand slot.
## Buff items can increase various stats or provide conditional bonuses.
class_name BuffItemData
extends EquipmentData

# ---------------------------------------------------------------------------
# Buff Properties
# ---------------------------------------------------------------------------

## Flat bonus added to equipment evasion.
@export var evasion_bonus: int = 0

## Flat bonus added to the character's movement speed.
@export var movement_bonus: int = 0

## Flat bonus added to strength stat.
@export var strength_bonus: int = 0
## Flat bonus added to dexterity stat.
@export var dexterity_bonus: int = 0
## Flat bonus added to constitution stat.
@export var constitution_bonus: int = 0
## Flat bonus added to wisdom stat.
@export var wisdom_bonus: int = 0
## Flat bonus added to intelligence stat.
@export var intelligence_bonus: int = 0

## Free-form description of any additional conditional buff this item provides.
@export_multiline var conditional_buff_description: String = ""
