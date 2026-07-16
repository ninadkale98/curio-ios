#!/bin/bash
# Curio aggregator watchdog.
#
# Checks the latest GitHub Actions run of the content aggregator and, ONLY if
# something is wrong (failed run, or no run in >26h so the daily schedule was
# missed), sends a Pushover alert and re-triggers the workflow. Healthy runs are
# silent — you only hear from it when there's a problem.
#
# Pushover creds come from the environment (set by the launchd plist), so this
# committed script holds no secrets. Run daily via
# ~/Library/LaunchAgents/com.curio.aggregator-watchdog.plist
set -uo pipefail

REPO="ninadkale98/curio-ios"
WORKFLOW="aggregator.yml"
GH="/opt/homebrew/bin/gh"
PY="/usr/bin/python3"

notify() {
  curl -s --form-string "token=${PUSHOVER_TOKEN:-}" \
          --form-string "user=${PUSHOVER_USER:-}" \
          --form-string "title=$1" \
          --form-string "message=$2" \
          https://api.pushover.net/1/messages.json >/dev/null 2>&1 || true
}

run=$("$GH" run list -R "$REPO" --workflow="$WORKFLOW" --limit 1 \
      --json status,conclusion,createdAt,url 2>/dev/null)

if [ -z "$run" ] || [ "$run" = "[]" ]; then
  notify "Curio aggregator ⚠️" "No workflow runs found — is the schedule active?"
  exit 0
fi

read -r status conclusion created url <<EOF
$(echo "$run" | "$PY" -c "import sys,json;r=json.load(sys.stdin)[0];print(r['status'],r['conclusion'] or '-',r['createdAt'],r['url'])")
EOF

age_h=$("$PY" -c "
from datetime import datetime, timezone
c=datetime.fromisoformat('$created'.replace('Z','+00:00'))
print(int((datetime.now(timezone.utc)-c).total_seconds()//3600))
")

if [ "$status" = "completed" ] && [ "$conclusion" != "success" ]; then
  notify "Curio aggregator ❌ $conclusion" "Latest run $conclusion — re-triggering.
$url"
  "$GH" workflow run "$WORKFLOW" -R "$REPO" >/dev/null 2>&1 || true
elif [ "$age_h" -gt 26 ]; then
  notify "Curio aggregator ⚠️ stale" "No run in ${age_h}h (daily expected) — re-triggering."
  "$GH" workflow run "$WORKFLOW" -R "$REPO" >/dev/null 2>&1 || true
fi

# --- Writer daily rollup (uses the public anon RPC; no secret needed) ---
SB="https://mixkzotcnwvkdvlxhobe.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1peGt6b3Rjbnd2a2R2bHhob2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4NzI0ODYsImV4cCI6MjA5ODQ0ODQ4Nn0.3ALwtoucsBj976IN02l4bvkHz2Vaog6fVQaPvxHDVOE"
summary=$(curl -s -X POST "$SB/rest/v1/rpc/written_today_by_source" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" -d '{}' \
  | "$PY" -c "import sys,json
d=json.load(sys.stdin) or {}
t=sum(d.values())
print(f'{t} today: ' + ', '.join(f'{k} {v}' for k,v in sorted(d.items())) if d else '0 today (writer idle or Mac asleep)')" 2>/dev/null)
notify "Curio writer — daily" "${summary:-summary unavailable}"
