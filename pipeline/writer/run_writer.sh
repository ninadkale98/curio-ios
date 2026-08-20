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
# A trailing imperative so the instructions are executed as a task, not read as
# reference material.
PROMPT="$(cat writer_prompt.md)

BEGIN NOW. This is your task, not a document to review. Read \$CLAIM_FILE and
carry out every step: fetch the source, write the blog, and publish it via the
RPCs end to end. Do not ask questions or merely summarize what to do."
# stream-json + verbose so the dispatcher can parse the real rate_limit_event
# lines out of stdout (ground truth for the account's 5-hour/7-day usage
# window) instead of guessing from arbitrary error text.
claude -p "$PROMPT" \
  --model sonnet \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions
