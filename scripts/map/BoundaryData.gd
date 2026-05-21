## BoundaryData.gd
## Stores the traversal flags for a single directional edge between two
## adjacent grid tiles. The authoritative map boundary lookup table
## contains one BoundaryData per unique pair of adjacent tile cells.
class_name BoundaryData
extends Resource

## If true, this edge is a solid wall. Blocks movement, melee, ranged, and sight.
@export var has_wall: bool = false

## If true, this edge is a barricade. Blocks movement (unless vault skill) and
## provides crouching cover against ranged attacks. Melee attacks across it
## are still permitted.
@export var has_barricade: bool = false

## If true, this edge connects a tile at floor Z to the tile at floor Z+1
## via a ladder. Traversal is allowed but costs an extra movement step.
@export var has_ladder: bool = false

## Returns true if this edge completely blocks movement (wall or barricade
## without a vault-capable character).
func blocks_movement(can_vault: bool = false) -> bool:
	if has_wall:
		return true
	if has_barricade and not can_vault:
		return true
	return false

## Returns true if this edge blocks a sight line at the given target crouching state.
## Walls always block; barricades block only if the target is crouched AND
## the observer is not on the immediately adjacent tile.
func blocks_sight(target_is_crouched: bool, observer_is_adjacent: bool = false) -> bool:
	if has_wall:
		return true
	if has_barricade and target_is_crouched and not observer_is_adjacent:
		return true
	return false

## Returns true if this edge blocks a ranged attack given defender crouch state.
func blocks_ranged_attack(target_is_crouched: bool) -> bool:
	if has_wall:
		return true
	if has_barricade and target_is_crouched:
		return true
	return false

## Returns true if crossing this barricade edge applies a cover accuracy penalty
## (target is standing behind a barricade but not crouched).
func applies_cover_penalty(target_is_crouched: bool) -> bool:
	return has_barricade and not target_is_crouched
