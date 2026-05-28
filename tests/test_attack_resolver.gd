## tests/test_attack_resolver.gd
## Unit tests for AttackResolver.
##
## Tests are grouped into four areas:
##
##   1. Dice structure  — confirms the correct number and type of dice are used
##      for each weapon (battleaxe 1d8 / 1d10 Versatile, greataxe 1d12,
##      handaxe 1d6, crystal ball 1d6 / 1d8 Versatile).
##
##   2. Damage range    — all hits stay within [dice_min + stat_bonus,
##      dice_max + stat_bonus]; no magic constants needed because the expected
##      bounds are derived directly from AttackResult fields.
##
##   3. Critical hit    — with extreme DEX the accuracy overflow guarantees
##      every attack is a crit; verifies damage_dealt == (raw + stat_bonus) × 1.5.
##
##   4. Validation      — out-of-range, wall-blocked, height-mismatch, and
##      non-Direct magic (ignores LoS) rejection / acceptance.
class_name TestAttackResolver
extends TestBase

# ---------------------------------------------------------------------------
# Stat shorthand constants
# ---------------------------------------------------------------------------

## stat_bonus(18) = 4 → accuracy_stat_bonus = 20 → final_accuracy = 100.
## Every d100 roll is a hit (≤ min(100, 100) = 100); crit_floor = max(0,0) = 0.
const STAT_HIT   : int = 18

## stat_bonus(200) = 95 → accuracy_stat_bonus = 475 → final_accuracy = 555.
## Every d100 roll ≤ 455 is a crit; since max d100 is 100, every roll is a crit.
const STAT_CRIT  : int = 200

## Number of iterations for damage-range assertions.
const ITERATIONS : int = 50

func _init() -> void:
    super._init("AttackResolver")

func run() -> void:
    print("\n=== AttackResolver ===")

    # ── Axe dice structure ────────────────────────────────────────────────────
    test("battleaxe one-handed (Versatile, off-hand occupied): dice = 1d8",
        _test_battleaxe_one_handed)
    test("battleaxe two-handed (Versatile, no off-hand): dice = 1d10",
        _test_battleaxe_two_handed)
    test("greataxe (Two-Handed): dice = 1d12",
        _test_greataxe)
    test("handaxe (Light, 1d6): dice = 1d6",
        _test_handaxe)

    # ── Magic dice structure ──────────────────────────────────────────────────
    test("crystal ball one-handed (Versatile, off-hand occupied): dice = 1d6",
        _test_crystal_ball_one_handed)
    test("crystal ball two-handed (Versatile, no off-hand): dice = 1d8",
        _test_crystal_ball_two_handed)

    # ── Damage range ──────────────────────────────────────────────────────────
    test("physical 1d8 hit damage stays in [roll_min, roll_max] (STR=10, no bonus)",
        _test_physical_damage_range)
    test("magic 1d6 hit damage stays in [roll_min, roll_max]",
        _test_magic_damage_range)

    # ── Critical hit mechanics ────────────────────────────────────────────────
    test("crit multiplier: damage_dealt == (raw_roll + stat_bonus) × 1.5",
        _test_crit_multiplier)

    # ── Validation / rejection ────────────────────────────────────────────────
    test("melee rejected: target beyond attack range",      _test_melee_out_of_range)
    test("melee rejected: solid wall between attacker and target", _test_melee_wall_blocked)
    test("melee rejected: attacker and target on different floors", _test_height_mismatch)
    test("non-Direct magic valid even with a wall blocking the path", _test_magic_no_los)

# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------

## Returns an open MapData with no registered boundaries (no walls, no barricades).
func _open_map() -> MapData:
    return MapData.new()

## Returns a MapData with a solid wall on the boundary between tile_a and tile_b.
func _walled_map(tile_a: Vector3i, tile_b: Vector3i) -> MapData:
    var map  := MapData.new()
    var wall := BoundaryData.new()
    wall.has_wall = true
    map.set_boundary(tile_a, tile_b, wall)
    return map

## Builds an AttackResolver with a fresh DiceRoller on the given map.
## Pass null to use a plain open map.
func _resolver(map: MapData = null) -> AttackResolver:
    var dice := DiceRoller.new()
    var los  := LineOfSightManager.new()
    return AttackResolver.new(dice, los, map if map != null else _open_map())

## Builds a minimal CharacterData.  All stats default to 10 unless overridden.
## segment_hp is intentionally left empty — apply_damage() is not called here.
func _char(pos: Vector3i,
        str_val: int = 10, dex_val: int = 10,
        wis_val: int = 10, int_val: int = 10) -> CharacterData:
    var c := CharacterData.new()
    c.grid_position = pos
    c.strength      = str_val
    c.dexterity     = dex_val
    c.wisdom        = wis_val
    c.intelligence  = int_val
    return c

## Creates a PHYSICAL weapon (AXE type) with the given dice expression.
## Keywords and their params can be passed to test Versatile, Light, etc.
func _phys(dice_count: int, dice_sides: int, attack_range: int = 1,
        kws: Array = [], kw_params: Dictionary = {}) -> WeaponData:
    var w := WeaponData.new()
    w.damage_type       = WeaponData.DamageType.PHYSICAL
    w.weapon_type       = WeaponType.Type.AXE
    w.damage_dice_count = dice_count
    w.damage_dice_sides = dice_sides
    w.attack_range      = attack_range
    for kw in kws:
        w.keywords.append(kw)
    w.keyword_params = kw_params
    return w

## Creates a MAGICAL weapon (BALL type) with the given dice expression.
func _magic(dice_count: int, dice_sides: int, attack_range: int = 10,
        kws: Array = [], kw_params: Dictionary = {}) -> WeaponData:
    var w := WeaponData.new()
    w.damage_type       = WeaponData.DamageType.MAGICAL
    w.weapon_type       = WeaponType.Type.BALL
    w.damage_dice_count = dice_count
    w.damage_dice_sides = dice_sides
    w.attack_range      = attack_range
    for kw in kws:
        w.keywords.append(kw)
    w.keyword_params = kw_params
    return w

# ---------------------------------------------------------------------------
# 1. Dice structure tests
# ---------------------------------------------------------------------------

func _test_battleaxe_one_handed() -> void:
    # Battleaxe is Versatile: 1d8 one-handed (off_hand_slot is not null → not two-handed grip).
    # Attacker DEX=18 → final_accuracy=100 → guaranteed hit, never crit.
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, STAT_HIT)
    attacker.off_hand_slot = EquipmentData.new()        # Occupies the off-hand slot.
    var target   := _char(Vector3i(1, 0, 0))
    var weapon   := _phys(1, 8, 1, ["Versatile"], {"Versatile": {"count": 1, "sides": 10}})

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_true(r.valid, "attack should be valid")
    assert_true(r.hit,   "DEX=18 → final_accuracy=100 → guaranteed hit")
    assert_eq(r.dmg_dice_count, 1, "dice count (battleaxe one-handed)")
    assert_eq(r.dmg_dice_sides, 8, "dice sides (battleaxe one-handed = d8)")

func _test_battleaxe_two_handed() -> void:
    # Battleaxe Versatile: 1d10 two-handed when off_hand_slot is null.
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, STAT_HIT)
    # off_hand_slot defaults to null → Versatile two-handed grip.
    var target   := _char(Vector3i(1, 0, 0))
    var weapon   := _phys(1, 8, 1, ["Versatile"], {"Versatile": {"count": 1, "sides": 10}})

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_true(r.valid, "attack should be valid")
    assert_true(r.hit,   "DEX=18 → guaranteed hit")
    assert_eq(r.dmg_dice_count, 1,  "dice count (battleaxe two-handed)")
    assert_eq(r.dmg_dice_sides, 10, "dice sides (battleaxe two-handed = d10)")

func _test_greataxe() -> void:
    # Greataxe: Two-Handed, 1d12.  No Versatile — dice never change.
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, STAT_HIT)
    var target   := _char(Vector3i(1, 0, 0))
    var weapon   := _phys(1, 12, 1, ["Two-Handed"])

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_true(r.valid, "attack should be valid")
    assert_true(r.hit,   "DEX=18 → guaranteed hit")
    assert_eq(r.dmg_dice_count, 1,  "dice count (greataxe)")
    assert_eq(r.dmg_dice_sides, 12, "dice sides (greataxe = d12)")

func _test_handaxe() -> void:
    # Handaxe: Light, 1d6, no Versatile.
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, STAT_HIT)
    var target   := _char(Vector3i(1, 0, 0))
    var weapon   := _phys(1, 6, 1, ["Light"])

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_true(r.valid, "attack should be valid")
    assert_true(r.hit,   "DEX=18 → guaranteed hit")
    assert_eq(r.dmg_dice_count, 1, "dice count (handaxe)")
    assert_eq(r.dmg_dice_sides, 6, "dice sides (handaxe = d6)")

func _test_crystal_ball_one_handed() -> void:
    # Crystal Ball: 1d6 one-handed.
    # Magic accuracy uses (INT+WIS)/2: stat_bonus(18)*2/2*5 = 4*5=20 → accuracy=100.
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, 10, STAT_HIT, STAT_HIT) # WIS=INT=18
    attacker.off_hand_slot = EquipmentData.new()
    var target   := _char(Vector3i(3, 0, 0))
    var weapon   := _magic(1, 6, 10, ["Versatile"], {"Versatile": {"count": 1, "sides": 8}})

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_true(r.valid, "magic attack should be valid")
    assert_true(r.hit,   "INT=WIS=18 → final_accuracy=100 → guaranteed hit")
    assert_eq(r.dmg_dice_count, 1, "dice count (crystal ball one-handed)")
    assert_eq(r.dmg_dice_sides, 6, "dice sides (crystal ball one-handed = d6)")

func _test_crystal_ball_two_handed() -> void:
    # Crystal Ball Versatile: 1d8 two-handed.
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, 10, STAT_HIT, STAT_HIT) # WIS=INT=18
    # off_hand_slot is null → two-handed grip.
    var target   := _char(Vector3i(3, 0, 0))
    var weapon   := _magic(1, 6, 10, ["Versatile"], {"Versatile": {"count": 1, "sides": 8}})

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_true(r.valid, "magic attack should be valid")
    assert_true(r.hit,   "INT=WIS=18 → guaranteed hit")
    assert_eq(r.dmg_dice_count, 1, "dice count (crystal ball two-handed)")
    assert_eq(r.dmg_dice_sides, 8, "dice sides (crystal ball two-handed = d8)")

# ---------------------------------------------------------------------------
# 2. Damage range tests
# ---------------------------------------------------------------------------

func _test_physical_damage_range() -> void:
    # Battleaxe 1d8, STR=10 (damage bonus = 0).
    # All hits must land in [dice_count + stat_bonus, dice_count * dice_sides + stat_bonus].
    # The bounds are read from the AttackResult fields to remain robust to stat changes.
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, STAT_HIT)   # STR=10, DEX=18
    var target   := _char(Vector3i(1, 0, 0))
    var weapon   := _phys(1, 8)

    for _i in ITERATIONS:
        var r := resolver.resolve_attack(attacker, target, weapon)
        assert_true(r.hit, "DEX=18 guarantees a hit")
        var min_dmg := float(r.dmg_dice_count) + float(r.dmg_stat_bonus)
        var max_dmg := float(r.dmg_dice_count * r.dmg_dice_sides) + float(r.dmg_stat_bonus)
        assert_in_range(r.damage_dealt, min_dmg, max_dmg, "1d8 physical damage")

func _test_magic_damage_range() -> void:
    # Crystal Ball 1d6, WIS=INT=18 (guarantees the hit; damage bonus is derived from result).
    # All hits must stay within the same [min, max] bounds formula.
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, 10, STAT_HIT, STAT_HIT) # WIS=INT=18
    var target   := _char(Vector3i(3, 0, 0))
    var weapon   := _magic(1, 6)

    for _i in ITERATIONS:
        var r := resolver.resolve_attack(attacker, target, weapon)
        assert_true(r.hit, "INT=WIS=18 guarantees a hit")
        var min_dmg := float(r.dmg_dice_count) + float(r.dmg_stat_bonus)
        var max_dmg := float(r.dmg_dice_count * r.dmg_dice_sides) + float(r.dmg_stat_bonus)
        assert_in_range(r.damage_dealt, min_dmg, max_dmg, "1d6 magic damage")

# ---------------------------------------------------------------------------
# 3. Critical hit mechanics
# ---------------------------------------------------------------------------

func _test_crit_multiplier() -> void:
    # DEX=200 → accuracy_stat_bonus = 95*5 = 475 → final_accuracy = 555.
    # Crit floor = 555 - 100 = 455 → every d100 roll (1–100) triggers a crit.
    # Expected: damage_dealt == (dmg_raw_roll + dmg_stat_bonus) × 1.5.
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, STAT_CRIT)  # STR=10, DEX=200
    var target   := _char(Vector3i(1, 0, 0))
    var weapon   := _phys(1, 8)

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_true(r.valid, "attack should be valid")
    assert_true(r.hit,   "DEX=200 → accuracy=555 → always a hit")
    assert_true(r.crit,  "DEX=200 → crit_floor=455 → every d100 roll is a crit")

    # damage_dealt = (raw_roll + stat_bonus) * 1.5  (no bonus_dice, no ability modifiers)
    var expected := (r.dmg_raw_roll + r.dmg_stat_bonus) * 1.5
    assert_approx_eq(r.damage_dealt, expected, 0.001,
        "crit damage should equal (raw + stat_bonus) × 1.5")

# ---------------------------------------------------------------------------
# 4. Validation / rejection tests
# ---------------------------------------------------------------------------

func _test_melee_out_of_range() -> void:
    # Melee weapon has attack_range=1; target is 5 tiles away → rejected.
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, STAT_HIT)
    var target   := _char(Vector3i(5, 0, 0))           # Manhattan distance = 5 > 1
    var weapon   := _phys(1, 8, 1)

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_false(r.valid, "melee attack beyond range should be rejected")
    assert_false(r.hit,   "a rejected attack should not register a hit")

func _test_melee_wall_blocked() -> void:
    # A solid wall on the boundary between the two adjacent tiles blocks melee.
    var pos_a    := Vector3i(0, 0, 0)
    var pos_b    := Vector3i(1, 0, 0)
    var resolver := _resolver(_walled_map(pos_a, pos_b))
    var attacker := _char(pos_a, 10, STAT_HIT)
    var target   := _char(pos_b)
    var weapon   := _phys(1, 8, 1)

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_false(r.valid, "melee attack across a wall should be rejected")

func _test_height_mismatch() -> void:
    # Physical attacks require attacker and target to share the same floor (z level).
    var resolver := _resolver()
    var attacker := _char(Vector3i(0, 0, 0), 10, STAT_HIT)
    var target   := _char(Vector3i(1, 0, 1))           # z=1 vs z=0 → height mismatch
    var weapon   := _phys(1, 8, 1)

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_false(r.valid, "melee with a floor-level mismatch should be rejected")

func _test_magic_no_los() -> void:
    # Non-Direct magic bypasses all line-of-sight and wall checks.
    # Place a wall between attacker and an intermediate tile; target is still in range.
    var pos_a    := Vector3i(0, 0, 0)
    var pos_b    := Vector3i(1, 0, 0)
    var resolver := _resolver(_walled_map(pos_a, pos_b))
    var attacker := _char(pos_a, 10, 10, STAT_HIT, STAT_HIT)
    var target   := _char(Vector3i(4, 0, 0))           # 4 tiles away, well within range=10
    var weapon   := _magic(1, 6, 10)                   # No "Direct" keyword

    var r := resolver.resolve_attack(attacker, target, weapon)

    assert_true(r.valid, "non-Direct magic should ignore walls and LoS")
    assert_true(r.hit,   "INT=WIS=18 guarantees a hit for the magic attack")
