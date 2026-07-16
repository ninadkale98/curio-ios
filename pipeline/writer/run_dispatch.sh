#!/bin/bash
# Entry point for the launchd writer job. Sources local secrets, then runs the
# dispatcher (which decides what to write and invokes the writer).
set -uo pipefail
cd "$(dirname "$0")"
source ./.env.writer
export SUPABASE_URL SB_ANON SB_SERVICE GITHUB_TOKEN PUSHOVER_TOKEN PUSHOVER_USER
exec /Users/ninad/experiment/Curio_ios/Curio/pipeline/.venv/bin/python3 dispatch.py
