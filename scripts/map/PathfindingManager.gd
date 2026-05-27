## PathfindingManager.gd
## Wraps Godot's AStar3D to provide movement pathfinding on the server-side
## 3D tile grid. Respects boundary rules: walls block connections entirely,
## barricades increase crossing cost by 1 (vault characters pay no extra cost),
## and ladder edges gain a +1 movement cost penalty.
class_name PathfindingManager
extends RefCounted

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const BASE_MOVEMENT_COST: float = 1.0
const LADDER_EXTRA_COST: float = 1.0
const BARRICADE_EXTRA_COST: float = 1.0

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _astar: AStar3D = AStar3D.new()
var _tile_to_id: Dictionary = {}   # Vector3i -> int (AStar3D point ID)
var _map_data: MapData = null

# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

## Builds the AStar3D graph from the given MapData resource.
## Call once per match when the map is loaded.
func build_from_map(map_data: MapData) -> void:
	_map_data = map_data
	_astar.clear()
	_tile_to_id.clear()

	# Register all tile coordinates as AStar3D points.
	var next_id: int = 0
	for tile in map_data.tiles:
		_astar.add_point(next_id, Vector3(tile.x, tile.y, tile.z))
		_tile_to_id[tile] = next_id
		next_id += 1

	# Connect adjacent tile pairs based on boundary rules.
	for tile in map_data.tiles:
		var adjacent: Array[Vector3i] = map_data.get_adjacent_tiles(tile)
		for neighbour in adjacent:
			if not _tile_to_id.has(neighbour):
				continue
			var tile_id: int = _tile_to_id[tile]
			var neighbour_id: int = _tile_to_id[neighbour]

			# Avoid adding the same connection twice.
			if _astar.are_points_connected(tile_id, neighbour_id):
				continue

			var boundary: BoundaryData = map_data.get_boundary(tile, neighbour)

			if boundary == null:
				# No boundary record — open connection with base cost.
				_astar.connect_points(tile_id, neighbour_id, true)
				continue

			if boundary.has_wall:
				# Wall: no connection.
				continue

			if boundary.has_barricade:
				# Barricade: always passable but costs +1 for non-vault characters.
				# The AStar3D graph connects them at base cost; the extra cost is
				# applied in get_path_cost() and get_reachable_tiles() per character.
				_astar.connect_points(tile_id, neighbour_id, true)
				continue

			if boundary.has_ladder:
				# Ladder: connect but with extra movement cost.
				var ladder_cost: float = BASE_MOVEMENT_COST + LADDER_EXTRA_COST
				_astar.connect_points(tile_id, neighbour_id, true)
				_astar.set_point_weight_scale(neighbour_id, ladder_cost)
				continue

			# Standard passable edge.
			_astar.connect_points(tile_id, neighbour_id, true)

# ---------------------------------------------------------------------------
# Pathfinding Queries
# ---------------------------------------------------------------------------

## Returns the shortest movement path from start_tile to end_tile as an ordered
## Array[Vector3i]. Returns an empty array if no path exists.
## can_vault is accepted for signature compatibility but does not change routing
## (barricades are always connected; vault only reduces their crossing cost).
func find_path(start_tile: Vector3i, end_tile: Vector3i, can_vault: bool = false) -> Array[Vector3i]:
	if not _tile_to_id.has(start_tile) or not _tile_to_id.has(end_tile):
		return []

	var start_id: int = _tile_to_id[start_tile]
	var end_id: int = _tile_to_id[end_tile]
	var path_positions: PackedVector3Array = _astar.get_point_path(start_id, end_id)

	if path_positions.is_empty():
		return []

	var path_tiles: Array[Vector3i] = []
	for pos in path_positions:
		path_tiles.append(Vector3i(int(pos.x), int(pos.y), int(pos.z)))
	return path_tiles

## Returns the movement cost to traverse a given path.
## Barricade crossings cost +1 for non-vault characters; vault characters pay 0 extra.
## Ladder crossings always cost +1.
func get_path_cost(path: Array[Vector3i], can_vault: bool = false) -> int:
	if path.size() <= 1:
		return 0
	var total_cost: int = 0
	for i in range(1, path.size()):
		var boundary: BoundaryData = _map_data.get_boundary(path[i - 1], path[i])
		if boundary != null and boundary.has_ladder:
			total_cost += int(BASE_MOVEMENT_COST + LADDER_EXTRA_COST)
		elif boundary != null and boundary.has_barricade and not can_vault:
			total_cost += int(BASE_MOVEMENT_COST + BARRICADE_EXTRA_COST)
		else:
			total_cost += int(BASE_MOVEMENT_COST)
	return total_cost

## Returns all tiles reachable within a given movement budget from start_tile.
## The returned dictionary maps Vector3i -> int (movement cost to reach).
## Barricade crossings cost +1 for non-vault characters; vault characters pay 0 extra.
func get_reachable_tiles(start_tile: Vector3i, movement_budget: int, can_vault: bool = false) -> Dictionary:
	var reachable: Dictionary = {}
	if not _tile_to_id.has(start_tile):
		return reachable

	# BFS / Dijkstra-like expansion using AStar point IDs.
	var frontier: Array = [[start_tile, 0]]
	reachable[start_tile] = 0

	while not frontier.is_empty():
		# Pop the entry with the lowest cost (simple priority queue).
		frontier.sort_custom(func(a, b): return a[1] < b[1])
		var current_entry: Array = frontier.pop_front()
		var current_tile: Vector3i = current_entry[0]
		var current_cost: int = current_entry[1]

		if current_cost > movement_budget:
			continue

		var adjacent: Array[Vector3i] = _map_data.get_adjacent_tiles(current_tile)
		for neighbour in adjacent:
			if not _tile_to_id.has(neighbour):
				continue
			var current_id: int = _tile_to_id[current_tile]
			var neighbour_id: int = _tile_to_id[neighbour]
			if not _astar.are_points_connected(current_id, neighbour_id):
				continue

			var boundary: BoundaryData = _map_data.get_boundary(current_tile, neighbour)
			var step_cost: int = int(BASE_MOVEMENT_COST)
			if boundary != null and boundary.has_ladder:
				step_cost = int(BASE_MOVEMENT_COST + LADDER_EXTRA_COST)
			elif boundary != null and boundary.has_barricade and not can_vault:
				step_cost = int(BASE_MOVEMENT_COST + BARRICADE_EXTRA_COST)

			var new_cost: int = current_cost + step_cost
			if new_cost <= movement_budget:
				if not reachable.has(neighbour) or reachable[neighbour] > new_cost:
					reachable[neighbour] = new_cost
					frontier.append([neighbour, new_cost])

	return reachable
