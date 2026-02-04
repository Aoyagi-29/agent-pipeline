from typing import Dict, List

ACTION_POINTS_CANONICAL: Dict[str, List[str]] = {
    "acne": ["keratin_unplug","sebum_regulation","antimicrobial_c_acnes","inflammation_quell","oxidation_lipid_protect"],
    "pores": ["keratin_unplug","sebum_regulation","comedone_prevention","oxidation_blackhead_block","pore_wall_firming_support","surface_texture_optics"],
    "dullness": ["clearance_turnover_up","keratin_transparency_optics_up","oxidation_yellowing_block","glycation_yellowing_block","microcirculation_balance"],
    "stain": ["signal_block","uv_pathway_protect","melanogenesis_enzyme_block","transfer_block","darkening_fixation_block","clearance_turnover_up"],
    "wrinkle": ["hydration_plumping","muscle_relaxation_support","collagen_synthesis_up","elastin_fiber_protect","glycation_block"],
    "yuragi": ["barrier_repair","irritant_exposure_shield","inflammation_quell","microbiome_immune_balance","redness_vasomotor_control"],
}

SCHEMA_VERSION = "ver3_action_point"


def score_system_prompt() -> str:
    lines = [
        "You are a cosmetics scoring engine.",
        "We score by action_point (field name: origin).",
        "IMPORTANT:",
        "- concern MUST be one of: " + ", ".join(ACTION_POINTS_CANONICAL.keys()),
        "- origin MUST be one of the allowed action_points for that concern; never invent new origin strings.",
        f'- Output JSON only with schema_version="{SCHEMA_VERSION}".',
        "",
        "Allowed action_points by concern (canonical):",
    ]
    for k, v in ACTION_POINTS_CANONICAL.items():
        lines.append(f"{k}: " + ", ".join(v))
    lines += [
        "",
        "For each matrix row, output:",
        "- ingredient_id, concern, origin, potency, evidence, mechanism_match, risk_penalty, final_score",
        "- Values potency/evidence/mechanism_match/risk_penalty in [0,1].",
        "Compute final_score = max(0, potency*evidence*mechanism_match - risk_penalty).",
    ]
    return "\n".join(lines)


def score_constraints_text() -> str:
    lines = [
        "Constraints:",
        "- concern must be one of: " + ", ".join(ACTION_POINTS_CANONICAL.keys()),
        "- origin must be one of the allowed action_points for that concern.",
        f'- schema_version must be "{SCHEMA_VERSION}".',
    ]
    for k, v in ACTION_POINTS_CANONICAL.items():
        lines.append(f"{k}: " + ", ".join(v))
    return "\n".join(lines)


def rakuten_url_prompt(brand: str, product: str) -> str:
    return f"""
楽天の商品URLを1つ返してください。出力はJSONのみ。

優先順位：
1) 公式ショップ（最小判定：URLにブランド名文字列「{brand}」が含まれる）
2) 楽天24 / 楽天公式系
3) 認定/正規取扱
4) その他（転売臭いものは避ける）

入力：
brand="{brand}"
product="{product}"

出力形式：
{{"rakuten_url": "...", "shop_type": "official|rakuten24|authorized|other", "reason": "short"}}
""".strip()


def ingredient_extract_prompt(brand: str, product: str, rakuten_url: str | None) -> str:
    return f"""
以下の製品の全成分（日本語表記）を抽出してJSONで返してください。
不確実なら推定せず "unknown" とする。

brand="{brand}"
product="{product}"
rakuten_url="{rakuten_url or ''}"

出力JSON：
{{
  "source_url": "{rakuten_url or ''}",
  "ingredients_text": "成分: ...（原文）",
  "ingredients_list_jp": ["水","BG", "..."]
}}
""".strip()


def normalize_prompt(ingredients_list_jp: list[str]) -> str:
    return f"""
以下の日本語成分名リストを正規化してJSONで返してください。
出力はJSONのみ。

入力：
{ingredients_list_jp}

出力：
{{
  "ingredients": [
    {{
      "rank_index": 1,
      "name_jp": "",
      "ingredient_id": "ING_...",
      "inci_name": "",
      "is_medicated_active": false
    }}
  ]
}}
""".strip()
