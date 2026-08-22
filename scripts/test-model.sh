#!/usr/bin/env zsh
# test-model.sh - run benchmark test cases against a llama-server instance
# Usage:
#   ./scripts/test-model.sh [port] [tag]
#   ./scripts/test-model.sh 8080 "gemma-4-12b Q3_K_S Vulkan"
#
# Exits 1 if any test fails (wrong answer or server error).

set -euo pipefail

PORT="${1:-8080}"
TAG="${2:-model}"
PASS=0; FAIL=0

ask() {
  local prompt="$1"; local max_tokens="${2:-200}"
  curl -sS --max-time 600 http://127.0.0.1:$PORT/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"messages\":[{\"role\":\"user\",\"content\":$(printf '%s' "$prompt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}],\"max_tokens\":$max_tokens,\"temperature\":0,\"chat_template_kwargs\":{\"enable_thinking\":false}}" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
if 'error' in d: print('ERROR:', d['error']); sys.exit(2)
c=d['choices'][0]['message']['content']
t=d.get('timings',{})
print(c)
print(f'--- tg/s: {t.get(\"predicted_per_second\",\"?\")} | prompt t/s: {t.get(\"prompt_per_second\",\"?\")}')
"
}

check() {
  local name="$1"; local prompt="$2"; local pattern="$3"; local max="${4:-200}"
  echo "=== $name ==="
  local out; out=$(ask "$prompt" "$max" 2>&1) || { echo "FAIL (server error)"; FAIL=$((FAIL+1)); return; }
  echo "$out"
  if printf '%s' "$out" | sed -E 's/\*\*//g; s/__//g; s/`//g; s/\*//g' | grep -qiE "$pattern"; then
    echo "PASS"; PASS=$((PASS+1))
  else
    echo "FAIL (expected: $pattern)"; FAIL=$((FAIL+1))
  fi
  echo
}

echo "############################################"
echo "# Test cases: $TAG"
echo "# Endpoint: http://127.0.0.1:$PORT"
echo "############################################"
echo

# ── Knowledge & math ───────────────────────────────────────────────────────
check "Capital of France" \
  "What is the capital of France? Answer with one word." \
  "paris" 10

check "Multiplication 7*8" \
  "How much is 7 * 8? Answer with one number." \
  "56" 10

check "Primary colors" \
  "Name 3 primary colors." \
  "red|blue|yellow" 30

check "Author Romeo and Juliet" \
  "Who wrote Romeo and Juliet? Answer with the author name only." \
  "shakespeare" 10

check "Chemical symbol for water" \
  "What is the chemical symbol for water?" \
  "h2o|h₂o|h.*_2.*o|H.*₂.*O" 20

# ── Coding ──────────────────────────────────────────────────────────────────
check "Python palindrome function" \
  "Write a Python function that checks if a string is a palindrome. Include docstring and type hints." \
  "def.*palindrome" 400

# ── Reasoning ───────────────────────────────────────────────────────────────
check "Logic: if A>B and B>C then?" \
  "If A is greater than B, and B is greater than C, which is greater: A or C? Answer with one letter." \
  "^a|greater.*a" 10

# ── Summary ─────────────────────────────────────────────────────────────────
echo "############################################"
echo "# Results: $PASS passed, $FAIL failed"
echo "############################################"
exit $((FAIL > 0 ? 1 : 0))