#!/bin/bash
# Curio writer — one blog per invocation, via headless Claude Code.
# Usage: ./run_writer.sh [backlog|fresh]   (default: backlog)
# Secrets come from .env.writer (gitignored, local only).
set -uo pipefail

cd "$(dirname "$0")"          # pipeline/writer — prompt reads ../../CURIO_BLOG_SPEC.md
source ./.env.writer
export SUPABASE_URL SB_ANON SB_SERVICE GITHUB_TOKEN PUSHOVER_TOKEN PUSHOVER_USER
# CLAIM_FILE is set by the dispatcher (the pre-claimed item to write).
: "${CLAIM_FILE:?CLAIM_FILE not set — run via dispatch.py}"

echo "=== $(date '+%Y-%m-%d %H:%M:%S') writer run (item=$CLAIM_FILE) ==="
claude -p "$(cat writer_prompt.md)" \
  --model sonnet \
  --dangerously-skip-permissions
