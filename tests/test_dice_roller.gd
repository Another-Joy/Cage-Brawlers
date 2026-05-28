## tests/test_dice_roller.gd
## Unit tests for DiceRoller — pure dice mechanics.
##
## Covers:
##   • Single and multi-die rolls always stay within [min, max].
##   • d100 range.
##   • Reliability=0 does not alter the raw roll.
##   • Reliability=1 always returns the maximum possible value.
##   • Reliability=0.5 only ever increases (or equals) the raw roll.
##   • Seeded RNG is deterministic across two identical sequences.
##   • Initiative roll is in [1, 20] with and without a flat bonus.
class_name TestDiceRoller
extends TestBase

## Number of iterations for bounds-checking loops.
const ITERATIONS : int = 200

func _init() -> void:
    super._init("DiceRoller")

func run() -> void:
    print("\n=== DiceRoller ===")
    test("1d6 always in [1, 6]",                          _test_d6_range)
    test("2d8 always in [2, 16]",                         _test_2d8_range)
    test("d100 always in [1, 100]",                       _test_d100_range)
    test("reliability=0.0 does not change the raw roll",  _test_reliability_zero)
    test("reliability=1.0 always returns the maximum",    _test_reliability_one)
    test("reliability=0.5 never decreases the raw roll",  _test_reliability_half)
    test("seeded RNG is fully deterministic",             _test_seeded_deterministic)
    test("initiative roll (no bonus) in [1, 20]",         _test_initiative_range)
    test("initiative roll with +3 bonus in [4, 23]",      _test_initiative_bonus)

# ---------------------------------------------------------------------------
# Test bodies
# ---------------------------------------------------------------------------

func _test_d6_range() -> void:
    var dice := DiceRoller.new()
    for _i in ITERATIONS:
        var roll := dice.roll_dice(1, 6)
        assert_in_range(float(roll), 1.0, 6.0, "1d6 roll")

func _test_2d8_range() -> void:
    var dice := DiceRoller.new()
    for _i in ITERATIONS:
        var roll := dice.roll_dice(2, 8)
        assert_in_range(float(roll), 2.0, 16.0, "2d8 roll")

func _test_d100_range() -> void:
    var dice := DiceRoller.new()
    for _i in ITERATIONS:
        var roll := dice.roll_d100()
        assert_in_range(float(roll), 1.0, 100.0, "d100 roll")

func _test_reliability_zero() -> void:
    var dice := DiceRoller.new()
    # Same seed → same raw bytes.  reliability=0 formula: adjusted = raw + floor(0 * ...) = raw.
    dice.set_seed(12345)
    var without_rel := dice.roll_dice(2, 6, false, 0.0)
    dice.set_seed(12345)
    var with_rel_zero := dice.roll_dice(2, 6, true, 0.0)
    assert_eq(without_rel, with_rel_zero, "reliability=0.0 should not change the roll")

func _test_reliability_one() -> void:
    var dice := DiceRoller.new()
    # Reliability=1.0: adjusted = raw + floor(1.0 * (max - raw)) = max.
    for _i in ITERATIONS:
        var roll := dice.roll_dice(2, 6, true, 1.0)
        assert_eq(roll, 12, "reliability=1.0 always returns maximum (2d6 = 12)")

func _test_reliability_half() -> void:
    var dice := DiceRoller.new()
    # Roll once with a fixed seed to get the raw value, then replay the same
    # seed with reliability=0.5 and verify the adjusted result is >= raw.
    dice.set_seed(99999)
    var raw := dice.roll_dice(2, 6, false, 0.0)
    dice.set_seed(99999)
    var adjusted := dice.roll_dice(2, 6, true, 0.5)
    # Formula: adjusted = raw + floor(0.5 * (12 - raw)) ≥ raw always.
    assert_true(adjusted >= raw,
        "reliability=0.5 should not decrease the roll (raw=%d, adjusted=%d)" % [raw, adjusted])

func _test_seeded_deterministic() -> void:
    var dice := DiceRoller.new()

    dice.set_seed(42)
    var run1 : Array[int] = []
    for _i in 10:
        run1.append(dice.roll_dice(1, 20))

    dice.set_seed(42)
    var run2 : Array[int] = []
    for _i in 10:
        run2.append(dice.roll_dice(1, 20))

    for i in run1.size():
        assert_eq(run1[i], run2[i], "seeded roll index %d" % i)

func _test_initiative_range() -> void:
    var dice := DiceRoller.new()
    for _i in ITERATIONS:
        var roll := dice.roll_initiative()
        assert_in_range(float(roll), 1.0, 20.0, "initiative (no bonus)")

func _test_initiative_bonus() -> void:
    var dice := DiceRoller.new()
    var bonus := 3
    for _i in ITERATIONS:
        var roll := dice.roll_initiative(bonus)
        assert_in_range(float(roll), float(1 + bonus), float(20 + bonus),
            "initiative (+%d bonus)" % bonus)
