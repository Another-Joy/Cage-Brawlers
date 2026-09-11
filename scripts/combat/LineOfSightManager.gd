## LineOfSightManager.gd
## Server-authoritative sight engine.
## Computes what tiles are visible to a character by combining:
##   1. A 2-tile Chebyshev proximity bubble (always visible, ignores walls).
##   2. A 90-degree vision cone extending in the character's facing direction.
##
## Facing direction indices (0-7):
##   0=North (+Y), 1=NE, 2=East (+X), 3=SE, 4=South (-Y),
##   5=SW, 6=West (-X), 7=NW
class_name LineOfSightManager
extends RefCounted

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PROXIMITY_RADIUS: int = 2
## Half-angle of the vision cone in degrees (90° cone = ±45° from facing).
const HALF_CONE_ANGLE_DEG: float = 45.0

# Direction vectors for facing indices 0-7.
const DIRECTION_VECTORS: Array = [
	Vector2(0, 1),   # 0 North
	Vector2(1, 1),   # 1 NE
	Vector2(1, 0),   # 2 East
	Vector2(1, -1),  # 3 SE
	Vector2(0, -1),  # 4 South
	Vector2(-1, -1), # 5 SW
	Vector2(-1, 0),  # 6 West
	Vector2(-1, 1),  # 7 NW
]

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns a set (Dictionary<Vector3i, bool>) of all tile positions visible
## to the observer character on the given map. The observer's floor (Z level)
## is used as the cone's origin floor.
func compute_visible_tiles(
		observer: CharacterData,
		map_data: MapData,
		all_characters: Array[CharacterData]) -> Dictionary:

	var visible: Dictionary = {}
	var origin: Vector3i = observer.grid_position
	var facing_vec: Vector2 = DIRECTION_VECTORS[observer.facing_direction].normalized()

	# Build a lookup of crouched characters for barricade raytrace checks.
	var crouched_at: Dictionary = {}  # Vector3i -> bool
	for c in all_characters:
		crouched_at[c.grid_position] = c.is_crouched

	for tile in map_data.tiles:
		# --- Proximity Bubble ---
		if _chebyshev_distance_2d(origin, tile) <= PROXIMITY_RADIUS:
			visible[tile] = true
			continue

		# --- Only check same-floor tiles for the vision cone ---
		if tile.z != origin.z:
			continue

		# --- 90-Degree Cone Check ---
		var delta: Vector2 = Vector2(tile.x - origin.x, tile.y - origin.y)
		if delta.length_squared() == 0.0:
			visible[tile] = true
			continue

		var angle_to_tile: float = rad_to_deg(delta.normalized().angle_to(facing_vec))
		if abs(angle_to_tile) >= HALF_CONE_ANGLE_DEG:
			continue  # Outside the vision cone.

		# --- Boundary Raytracing ---
		if _has_clear_sightline(origin, tile, map_data, crouched_at):
			visible[tile] = true

	return visible

# ---------------------------------------------------------------------------
# Attack Targeting Checks (used by AttackResolver)
# ---------------------------------------------------------------------------

## Returns true if the target tile is visible to the observer for ranged targeting.
## Applies cover_penalty_out if the attack would cross an un-crouched barricade.
## Also checks that the target is within the observer's 90-degree vision cone.
func check_ranged_target(
		observer: CharacterData,
		target: CharacterData,
		map_data: MapData) -> Dictionary:
	# Returns { "valid": bool, "cover_penalty": bool }
	var result: Dictionary = { "valid": false, "cover_penalty": false }

	# Facing cone check: target must be within the observer's 90-degree forward cone.
	var facing_vec: Vector2 = DIRECTION_VECTORS[observer.facing_direction].normalized()
	var delta: Vector2 = Vector2(
		target.grid_position.x - observer.grid_position.x,
		target.grid_position.y - observer.grid_position.y)
	if delta.length_squared() > 0.0:
		var angle_to_target: float = rad_to_deg(delta.normalized().angle_to(facing_vec))
		if abs(angle_to_target) >= HALF_CONE_ANGLE_DEG:
			return result  # Target is outside the attacker's vision cone.

	var path_tiles: Array[Vector3i] = _get_line_tiles(observer.grid_position, target.grid_position)

	for i in range(1, path_tiles.size()):
		var from_tile: Vector3i = path_tiles[i - 1]
		var to_tile: Vector3i = path_tiles[i]
		var dx: int = to_tile.x - from_tile.x
		var dy: int = to_tile.y - from_tile.y

		if abs(dx) == 1 and abs(dy) == 1:
			# Diagonal step: check both cardinal sub-steps for blocking walls.
			var h_tile := Vector3i(from_tile.x + dx, from_tile.y, from_tile.z)
			var v_tile := Vector3i(from_tile.x, from_tile.y + dy, from_tile.z)
			var h_boundary: BoundaryData = map_data.get_boundary(from_tile, h_tile)
			var v_boundary: BoundaryData = map_data.get_boundary(from_tile, v_tile)
			if (h_boundary != null and h_boundary.has_wall) or (v_boundary != null and v_boundary.has_wall):
				return result  # Blocked by wall on diagonal.
			if (h_boundary != null and h_boundary.has_barricade) or (v_boundary != null and v_boundary.has_barricade):
				if target.is_crouched:
					return result
				else:
					result["cover_penalty"] = true
		else:
			var boundary: BoundaryData = map_data.get_boundary(from_tile, to_tile)
			if boundary == null:
				continue
			if boundary.has_wall:
				return result  # Blocked by wall.
			if boundary.has_barricade:
				if target.is_crouched:
					return result  # Blocked by barricade + crouch.
				else:
					result["cover_penalty"] = true  # Cover penalty applies.

	result["valid"] = true
	return result

# ---------------------------------------------------------------------------
# Internal Helpers
# ---------------------------------------------------------------------------

## 2D Chebyshev distance (ignores Z/floor level).
func _chebyshev_distance_2d(a: Vector3i, b: Vector3i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

## Returns true if there is a clear sightline between origin and target tile.
func _has_clear_sightline(
		origin: Vector3i,
		target: Vector3i,
		map_data: MapData,
		crouched_at: Dictionary) -> bool:

	var path_tiles: Array[Vector3i] = _get_line_tiles(origin, target)
	for i in range(1, path_tiles.size()):
		var from_tile: Vector3i = path_tiles[i - 1]
		var to_tile: Vector3i = path_tiles[i]
		var dx: int = to_tile.x - from_tile.x
		var dy: int = to_tile.y - from_tile.y

		if abs(dx) == 1 and abs(dy) == 1:
			# Diagonal step: check both cardinal sub-steps for blocking boundaries.
			var h_tile := Vector3i(from_tile.x + dx, from_tile.y, from_tile.z)
			var v_tile := Vector3i(from_tile.x, from_tile.y + dy, from_tile.z)
			for sub_tile in [h_tile, v_tile]:
				var sub_boundary: BoundaryData = map_data.get_boundary(from_tile, sub_tile)
				if sub_boundary == null:
					continue
				var target_is_crouched: bool = crouched_at.get(to_tile, false)
				var observer_is_adjacent: bool = (i == path_tiles.size() - 1)
				if sub_boundary.blocks_sight(target_is_crouched, observer_is_adjacent):
					return false
		else:
			var boundary: BoundaryData = map_data.get_boundary(from_tile, to_tile)
			if boundary == null:
				continue

			var target_is_crouched: bool = crouched_at.get(to_tile, false)
			# Observer is adjacent to the barricade if this is the last step.
			var observer_is_adjacent: bool = (i == path_tiles.size() - 1)
			if boundary.blocks_sight(target_is_crouched, observer_is_adjacent):
				return false

	return true

## Generates the discrete tile path from origin to target using a line-draw
## algorithm (2D Bresenham on x/y, ignoring Z transitions).
func _get_line_tiles(origin: Vector3i, target: Vector3i) -> Array[Vector3i]:
	var tiles: Array[Vector3i] = []
	var x0: int = origin.x
	var y0: int = origin.y
	var x1: int = target.x
	var y1: int = target.y
	var z: int = origin.z  # Treat sight as same-floor; Z changes handled separately.

	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy

	while true:
		tiles.append(Vector3i(x0, y0, z))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy

	return tiles
