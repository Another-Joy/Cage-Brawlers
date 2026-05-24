## AbilityCondition.gd
## Sub-resource encoding one pre-condition that must be satisfied before an
## AbilityData can be used. All conditions on an ability must be true
## simultaneously (AND semantics). Use must_be_true = false to invert.
##
## Example — Stand Up ability:
##   condition_type = SELF_CROUCHED, must_be_true = true
##   → ability can only be used while crouched.
class_name AbilityCondition
extends Resource

# ---------------------------------------------------------------------------
# Condition Types
# ---------------------------------------------------------------------------

enum ConditionType {
	SELF_CROUCHED,      ## Owner must currently be crouched.
	ADJACENT_BARRICADE, ## At least one adjacent boundary must have a barricade.
	HAS_AMMO,           ## Owner must have at least one unit of ammo.
	                    ## string_param = ammo type name ("bullets","bolts","arrows").
	HAS_SKILL,          ## Owner must have learned a skill or ability with this ID.
	                    ## string_param = the entry_id to check.
	TARGET_IN_RANGE,    ## A valid target must be within the ability's range.
}

# ---------------------------------------------------------------------------
# Exported Properties
# ---------------------------------------------------------------------------

@export var condition_type: ConditionType = ConditionType.SELF_CROUCHED

## When true the condition must hold; when false it must NOT hold.
## E.g. must_be_true=false with SELF_CROUCHED means "must NOT be crouched".
@export var must_be_true: bool = true

## Optional string parameter used by HAS_AMMO (ammo type) and HAS_SKILL (entry ID).
@export var string_param: String = ""
