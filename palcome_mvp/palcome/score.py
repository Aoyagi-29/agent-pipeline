from typing import Any, Dict, List
from decimal import Decimal, ROUND_DOWN
from jsonschema import validate
from .prompts import ACTION_POINTS_CANONICAL, SCHEMA_VERSION


def trunc_2dp(x: float) -> float:
    d = Decimal(str(x)).quantize(Decimal("0.00"), rounding=ROUND_DOWN)
    return float(d)


def enforce_numeric_rules(score_obj: Dict[str, Any]) -> Dict[str, Any]:
    for row in score_obj.get("matrices", []):
        row["potency"] = trunc_2dp(row["potency"])
        row["evidence"] = trunc_2dp(row["evidence"])
        row["mechanism_match"] = trunc_2dp(row["mechanism_match"])
        row["risk_penalty"] = trunc_2dp(row["risk_penalty"])
        final = max(0.0, row["potency"] * row["evidence"] * row["mechanism_match"] - row["risk_penalty"])
        row["final_score"] = trunc_2dp(final)
    return score_obj


def validate_action_points(score_obj: Dict[str, Any]) -> None:
    errors: List[str] = []
    matrices = score_obj.get("matrices", [])
    if not isinstance(matrices, list):
        raise ValueError("score_result.matrices must be an array")
    for i, row in enumerate(matrices):
        concern = row.get("concern")
        origin = row.get("origin")
        if concern not in ACTION_POINTS_CANONICAL:
            errors.append(f"matrices[{i}].concern invalid: {concern!r}")
            continue
        allowed = ACTION_POINTS_CANONICAL[concern]
        if origin not in allowed:
            errors.append(
                f"matrices[{i}].origin invalid for concern={concern!r}: {origin!r} (allowed: {allowed})"
            )
    if errors:
        head = errors[:10]
        more = "" if len(errors) <= 10 else f" (+{len(errors) - 10} more)"
        raise ValueError("Invalid concern/origin: " + " | ".join(head) + more)


def finalize_and_validate(out: Dict[str, Any], schema: Dict[str, Any]) -> Dict[str, Any]:
    validate(instance=out, schema=schema)
    out["schema_version"] = SCHEMA_VERSION
    validate_action_points(out)
    return enforce_numeric_rules(out)
