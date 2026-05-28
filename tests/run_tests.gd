## tests/run_tests.gd
## Headless test runner for the Cage Brawlers unit-test suite.
##
## ─── How to run ──────────────────────────────────────────────────────────────
##
##   1. Open a terminal in the project root (same directory as project.godot).
##   2. Run:
##
##        godot --headless tests/run_tests.tscn
##
##      Where "godot" is the Godot 4 binary (may be "godot4",
##      "./Godot_v4.x_linux.x86_64", "Godot_v4.x_win64.exe", etc.).
##
## ─── Exit codes ──────────────────────────────────────────────────────────────
##
##   0 — all assertions passed.
##   1 — one or more assertions failed (see stderr for details).
##
## ─── Adding new test suites ──────────────────────────────────────────────────
##
##   1. Create tests/test_<module>.gd extending TestBase.
##   2. Append MyTestClass.new() to the `suites` array below.
##
extends Node

func _ready() -> void:
    # Register all test suites here.
    var suites: Array = [
        TestDiceRoller.new(),
        TestAttackResolver.new(),
    ]

    var total_pass := 0
    var total_fail := 0

    for suite in suites:
        suite.run()
        suite.print_summary()
        total_pass += suite.pass_count
        total_fail += suite.fail_count

    print("\n=== TOTAL  %d passed  /  %d failed ===" % [total_pass, total_fail])

    if total_fail > 0:
        print("One or more tests FAILED — see FAIL lines above for details.")

    get_tree().quit(0 if total_fail == 0 else 1)
