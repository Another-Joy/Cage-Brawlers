## MapData.gd
## Server-authoritative map layout. Stores the set of valid tile coordinates
## (Vector3i) and the centralised boundary lookup table that maps each
## directed edge between adjacent tiles to a BoundaryData resource.
##
## Coordinate convention:
##   x, y  = horizontal grid axes
##   z     = floor level (0 = ground floor, 1 = first elevated floor, etc.)
class_name MapData
extends Resource

# ---------------------------------------------------------------------------
# Tile Registry
# ---------------------------------------------------------------------------

## All valid tile positions on this map.
@export var tiles: Array[Vector3i] = []

# ---------------------------------------------------------------------------
# Boundary Lookup Table
# ---------------------------------------------------------------------------

## Key: encoded String of the form "x1,y1,z1|x2,y2,z2" (always sorted so that
## the pair is order-independent).
## Value: BoundaryData resource.
var _boundaries: Dictionary = {}

# ---------------------------------------------------------------------------
# Boundary API
# ---------------------------------------------------------------------------

## Registers a boundary between two adjacent tiles.
func set_boundary(tile_a: Vector3i, tile_b: Vector3i, boundary: BoundaryData) -> void:
	var key: String = _make_key(tile_a, tile_b)
	_boundaries[key] = boundary

## Returns the BoundaryData between two tiles, or null if no boundary exists.
func get_boundary(tile_a: Vector3i, tile_b: Vector3i) -> BoundaryData:
	var key: String = _make_key(tile_a, tile_b)
	return _boundaries.get(key, null)

## Returns true if there is a registered boundary between the two tiles.
func has_boundary(tile_a: Vector3i, tile_b: Vector3i) -> bool:
	return _boundaries.has(_make_key(tile_a, tile_b))

## Returns true if the tile exists in the map's tile registry.
func is_valid_tile(tile: Vector3i) -> bool:
	return tile in tiles

# ---------------------------------------------------------------------------
# Adjacency Helpers
# ---------------------------------------------------------------------------

## Returns all tiles directly adjacent to the given tile (same Z or Z±1 via ladder).
## Includes cardinal and diagonal horizontal neighbours plus the tile directly
## above/below (Z±1) if a ladder boundary exists.
func get_adjacent_tiles(tile: Vector3i) -> Array[Vector3i]:
	var neighbours: Array[Vector3i] = []
	var offsets: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(1, 1, 0), Vector3i(1, -1, 0),
		Vector3i(-1, 1, 0), Vector3i(-1, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),  # Vertical (ladder) connections
	]
	for offset in offsets:
		var candidate: Vector3i = tile + offset
		if is_valid_tile(candidate):
			neighbours.append(candidate)
	return neighbours

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Creates a canonical, order-independent string key for a tile pair.
func _make_key(a: Vector3i, b: Vector3i) -> String:
	var sa: String = "%d,%d,%d" % [a.x, a.y, a.z]
	var sb: String = "%d,%d,%d" % [b.x, b.y, b.z]
	if sa < sb:
		return sa + "|" + sb
	return sb + "|" + sa
