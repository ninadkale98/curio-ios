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
