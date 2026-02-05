# HANDOFF — PalCome MVP（scoring_jobs → worker → pipeline → LLM 到達）引き継ぎ

更新: 2026-02-05（JST想定）
対象: palcome_mvp（WSL2 Ubuntu / Supabase）

## 0. 目的（今回の合意点）
- scoring_jobs.id=1 を pending に戻して worker.py --once を回す
- コンソールで [obs] before/after llm.json_call を観測し、LLM 呼び出しに到達していることを確認する
- DB で status=succeeded かつ scoring_result != NULL を観測して収束する
- 併せて「誤succeeded（scoring_result=NULL のまま succeeded）」を再発防止する Gate/Audit を恒久化する

## 1. 発生していた問題（相違点 → 原因へ収束）
### 症状
- Supabase 観測で status=succeeded なのに scoring_result=NULL のケースがあり得た
- コンソールに [obs] before/after llm.json_call が出ない局面があった

### 原因（収束）
- db.set_done(job_id) が無条件に走ると、途中工程が落ちても succeeded に収束し得る
- [obs] はコード上に出力行が無ければ出ない（OBS の問題ではなく “行が無い” 問題）

## 2. 実施した変更（決定ログ）
### 2.1 観測点の恒久化
- OBS=1 のときだけ [obs] を出す仕組みを導入
- llm.json_call(sys, user) の直前直後に _obs("[obs] before/after ...") を差し込む
- 観測ログが2回出ることで、LLM到達が即判定できる

### 2.2 恒久ガード（誤succeeded遮断）
- succeeded の条件を明確化：status=succeeded なら scoring_result は必須
- db.set_done(job_id) の直前で scoring_result を検証し、無ければ set_error("JOB_FAILED", ...) に収束させる方針

### 2.3 Gate/Audit（DB invariant チェック）を追加
- scripts/check_db_invariants.sh を追加（依存ゼロ、curl + Supabase REST で件数判定）
- 不変条件：status=succeeded かつ scoring_result IS NULL が 0件
- 破ったら exit 1
- コミット: 8190c79（audit: add DB invariant check）

## 3. 再現手順（省略なし）
### 3.1 Supabase：id=1 を pending に戻す（SQL Editor）
update scoring_jobs
set
  status = 'pending',
  running_at = null,
  lease_expires_at = null,
  last_error = null,
  ingredients_normalized = null,
  scoring_result = null,
  error_detail = null,
  error_code = null,
  updated_at = now()
where id = 1;

### 3.2 WSL：Gate/Audit → worker を1回実行
./scripts/check_db_invariants.sh && OBS=1 python -u worker.py --once

### 3.3 成功条件（観測）
- コンソール：claimed job: 1 / [obs] before/after が2回 / run_one_job done
- DB：status=succeeded / scoring_result != NULL / last_error, error_detail, error_code が NULL

## 4. 最終観測（今回の収束点）
- id=1 を pending にリセット（Supabase）
- invariant チェック OK（WSL）
- worker が claimed job: 1
- [obs] before/after llm.json_call が2回
- run_one_job done
