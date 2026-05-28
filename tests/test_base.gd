## tests/test_base.gd
## Minimal test-suite base class used by all test files in this project.
##
## Usage — create a subclass, override run(), and register cases with test():
##
##   class_name TestMyModule
##   extends TestBase
##
##   func _init() -> void:
##       super._init("MyModule")
##
##   func run() -> void:
##       test("something works", _test_something)
##
##   func _test_something() -> void:
##       assert_eq(1 + 1, 2, "basic arithmetic")
##
class_name TestBase
extends RefCounted

var pass_count : int = 0
var fail_count : int = 0

var _suite_name    : String = ""
var _current_test  : String = ""

func _init(suite_name: String) -> void:
    _suite_name = suite_name

# ---------------------------------------------------------------------------
# Core assertion helpers
# ---------------------------------------------------------------------------

## Records a single assertion.  Prints an error on failure with full context.
func _record(ok: bool, detail: String) -> void:
    if ok:
        pass_count += 1
    else:
        fail_count += 1
        printerr("  FAIL [%s::%s]  %s" % [_suite_name, _current_test, detail])

func assert_eq(actual: Variant, expected: Variant, label: String = "") -> void:
    _record(actual == expected,
        "%s  got=%s  expected=%s" % [label, str(actual), str(expected)])

func assert_ne(actual: Variant, unexpected: Variant, label: String = "") -> void:
    _record(actual != unexpected,
        "%s  got=%s  (should differ from %s)" % [label, str(actual), str(unexpected)])

func assert_true(cond: bool, label: String = "") -> void:
    _record(cond, "%s  (expected true, got false)" % label)

func assert_false(cond: bool, label: String = "") -> void:
    _record(not cond, "%s  (expected false, got true)" % label)

func assert_in_range(value: float, lo: float, hi: float, label: String = "") -> void:
    _record(value >= lo and value <= hi,
        "%s  value=%s  not in [%s, %s]" % [label, str(value), str(lo), str(hi)])

## Floating-point near-equality with a configurable tolerance.
func assert_approx_eq(actual: float, expected: float,
        tolerance: float = 0.001, label: String = "") -> void:
    _record(absf(actual - expected) <= tolerance,
        "%s  got=%s  expected=%s ±%s" % [label, str(actual), str(expected), str(tolerance)])

# ---------------------------------------------------------------------------
# Test case registration
# ---------------------------------------------------------------------------

## Wraps a single named test case.
## Sets the context for error messages, calls fn, and prints a ✓ on success.
func test(name: String, fn: Callable) -> void:
    _current_test = name
    var fails_before := fail_count
    fn.call()
    if fail_count == fails_before:
        print("  ✓ %s" % name)
    # Failures are already printed inside _record.

# ---------------------------------------------------------------------------
# Override in subclass
# ---------------------------------------------------------------------------

## Override this to register all test cases using test("name", callable).
func run() -> void:
    pass

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

func print_summary() -> void:
    var total := pass_count + fail_count
    var icon  := "✓" if fail_count == 0 else "✗"
    print("%s [%s]  %d / %d assertions passed" % [icon, _suite_name, pass_count, total])
