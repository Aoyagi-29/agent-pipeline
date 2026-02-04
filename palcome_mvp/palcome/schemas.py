from .prompts import SCHEMA_VERSION


SCORE_RESULT_SCHEMA = {
  "type": "object",
  "additionalProperties": False,
  "required": ["schema_version", "matrices"],
  "properties": {
    "schema_version": {"type": "string", "enum": [SCHEMA_VERSION]},
    "matrices": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": False,
        "required": ["ingredient_id","concern","origin","potency","evidence","mechanism_match","risk_penalty","final_score"],
        "properties": {
          "ingredient_id": {"type":"string"},
          "concern": {"type":"string"},
          "origin": {"type":"string"},
          "potency": {"type":"number", "minimum": 0, "maximum": 1},
          "evidence": {"type":"number", "minimum": 0, "maximum": 1},
          "mechanism_match": {"type":"number", "minimum": 0, "maximum": 1},
          "risk_penalty": {"type":"number", "minimum": 0, "maximum": 1},
          "final_score": {"type":"number", "minimum": 0, "maximum": 1},
        }
      }
    }
  }
}

# normalized is intentionally loose for MVP (we validate only score_result strictly)
NORMALIZED_SCHEMA = {
  "type": "object"
}
