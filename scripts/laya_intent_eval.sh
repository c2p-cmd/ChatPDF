#!/bin/bash
# Asks an Ollama-hosted Laya decision model the IntentRouter question for every line of
# ChatPDFTests/Fixtures/intent_questions.tsv (label<TAB>question) and scores it.
#
#   scripts/laya_intent_eval.sh [model] [tsv]
#   VARIANT=choice (default) asks one 3-way choice question;
#   VARIANT=noul asks two yes/no questions (is it a summary request? is it unrelated?).
#
# Needs: curl, python3, a running Ollama with a Laya model (POST /v1/systemone).
set -euo pipefail

MODEL="${1:-laya:421m-typed-decisions-mlx-fp16}"
TSV="${2:-$(dirname "$0")/../ChatPDFTests/Fixtures/intent_questions.tsv}"
HOST="${OLLAMA_HOST:-localhost:11434}"
VARIANT="${VARIANT:-choice}"
OUT="${OUT:-/tmp/laya_eval_$(echo "$MODEL" | tr ':/' '__').tsv}"

curl -sf "http://$HOST/api/tags" >/dev/null || { echo "Ollama not reachable at $HOST" >&2; exit 1; }

: > "$OUT"
printf 'expected\tlaya\tconf\tp_general\tp_topical\tp_unrelated\tms\tquestion\n' >> "$OUT"

ask() { # $1 = question text -> prints JSON
  python3 - "$MODEL" "$1" "$VARIANT" <<'PY'
import json, sys
model, text, variant = sys.argv[1:4]
if variant == "noul":
    qs = {
      "general": {"type": "noul", "instructions": "Is the user asking for an overview or summary of the whole document, rather than about a specific detail?"},
      "unrelated": {"type": "noul", "instructions": "Is the message unrelated to any document (small talk, trivia, jokes, coding help, maths)?"},
    }
else:
    qs = {"intent": {
      "type": "choice",
      "instructions": "A user is chatting with an uploaded PDF document. What kind of message is this?",
      "criteria": {
        "general": "asks for an overview, summary or the main idea of the whole document",
        "topical": "asks about a specific fact, detail, section, number or concept that would be found inside the document",
        "unrelated": "has nothing to do with any document (weather, jokes, trivia, chit-chat, coding help)"}}}
print(json.dumps({"model": model, "state": text, "questions": qs}))
PY
}

# warm-up (model load) so latency below is steady state
curl -s "http://$HOST/v1/systemone" -d "$(ask "warm up")" >/dev/null

while IFS=$'\t' read -r label question; do
  [ -z "$label" ] && continue
  body="$(ask "$question")"
  start=$(python3 -c 'import time;print(time.time())')
  resp="$(curl -s "http://$HOST/v1/systemone" -d "$body")"
  end=$(python3 -c 'import time;print(time.time())')
  python3 - "$label" "$question" "$resp" "$start" "$end" "$VARIANT" >> "$OUT" <<'PY'
import json, sys
label, q, resp, s, e, variant = sys.argv[1:7]
ms = f"{(float(e)-float(s))*1000:.0f}"
try:
    ans = json.loads(resp)["answers"]
    if variant == "noul":
        g = ans["general"]; u = ans["unrelated"]
        pg = g["noul"]
        pu = u["noul"]
        # Default to topical unless one yes clearly wins (same safety rule as the embedding router).
        choice = "topical"
        if pu >= 0.5 and pu >= pg: choice = "unrelated"
        elif pg >= 0.5: choice = "general"
        print("\t".join([label, choice, "0", f"{pg:.3f}", "0", f"{pu:.3f}", ms, q]))
    else:
        a = ans["intent"]; p = a["probabilities"]
        print("\t".join([label, a["choice"], f'{a["confidence"]:.3f}', f'{p["general"]:.3f}',
                         f'{p["topical"]:.3f}', f'{p["unrelated"]:.3f}', ms, q]))
except Exception:
    print("\t".join([label, "ERROR", "0", "0", "0", "0", "0", q + " :: " + resp[:120]]))
PY
done < "$TSV"

python3 - "$OUT" "$MODEL" <<'PY'
import csv, sys, statistics as st
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
n = len(rows); ok = sum(r["expected"] == r["laya"] for r in rows)
topical = [r for r in rows if r["expected"] == "topical"]
bad_topical = [r for r in topical if r["laya"] != "topical"]
print(f"\nModel: {sys.argv[2]}")
print(f"Accuracy: {ok}/{n} = {ok/n:.0%}")
for lab in ("general", "topical", "unrelated"):
    sub = [r for r in rows if r["expected"] == lab]
    print(f"  {lab:10} {sum(r['laya']==lab for r in sub)}/{len(sub)}")
print(f"Topical questions wrongly diverted (costly error): {len(bad_topical)}/{len(topical)}")
lat = [float(r["ms"]) for r in rows if r["laya"] != "ERROR"]
print(f"Latency/query: median {st.median(lat):.0f} ms, p95 {sorted(lat)[int(len(lat)*.95)-1]:.0f} ms")
print("Misses:")
for r in rows:
    if r["expected"] != r["laya"]:
        print(f"  [{r['expected']} -> {r['laya']} conf={r['conf']}] {r['question']}")
print(f"Full results: {sys.argv[1]}")
PY
