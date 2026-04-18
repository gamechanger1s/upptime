#!/bin/bash
# =============================================================================
# auto-commit.sh
# Uses Google Gemini API (free tier) to generate semantic commit messages.
#
# First-time setup:
#   ./auto-commit.sh --setup
#
# Usage:
#   ./auto-commit.sh            # fully automatic
#   ./auto-commit.sh --dry-run  # preview message only, no commit
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ── Config file (outside repo, never committed) ───────────────────────────────
CONFIG_DIR="$HOME/.config/auto-commit"
CONFIG_FILE="$CONFIG_DIR/config"

# ── Setup wizard ──────────────────────────────────────────────────────────────
run_setup() {
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           🔧  Auto-Commit First-Time Setup              ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${CYAN}How to get your FREE Gemini API key:${NC}"
    echo -e "  1. Go to ${YELLOW}https://aistudio.google.com/apikey${NC}"
    echo -e "  2. Click ${GREEN}+ Create API key${NC}"
    echo -e "  3. Select ${GREEN}Default Gemini Project${NC} (already shown in your screen)"
    echo -e "  4. Copy the key and paste it below"
    echo ""
    echo -e "${GREEN}✅ Free tier: 15 requests/min, 1500 requests/day — more than enough${NC}"
    echo ""

    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    read -rp "Paste your Gemini API key (AIza...): " INPUT_KEY

    if [[ -z "$INPUT_KEY" ]]; then
        echo -e "${RED}❌ No key entered. Setup cancelled.${NC}"
        exit 1
    fi

    cat > "$CONFIG_FILE" <<EOF
# Auto-commit configuration — DO NOT commit this file
# Stored at: $CONFIG_FILE (outside all git repos)
# Generated: $(date)
GEMINI_API_KEY=$INPUT_KEY
EOF

    chmod 600 "$CONFIG_FILE"

    echo ""
    echo -e "${GREEN}✅ Key saved to ${CONFIG_FILE}${NC}"
    echo -e "${GREEN}   Permissions: 600 (only you can read it)${NC}"
    echo ""
    echo -e "${CYAN}You're all set! Now run:${NC}"
    echo -e "   ${YELLOW}./auto-commit.sh${NC}"
    exit 0
}

# ── Load key from config ──────────────────────────────────────────────────────
load_api_key() {
    if [[ -f "$CONFIG_FILE" ]]; then
        GEMINI_API_KEY=$(grep '^GEMINI_API_KEY=' "$CONFIG_FILE" | cut -d'=' -f2-)
        export GEMINI_API_KEY
    fi
}

# ── Handle flags ──────────────────────────────────────────────────────────────
DRY_RUN=false
case "${1:-}" in
    --setup) run_setup ;;
    --dry-run) DRY_RUN=true ;;
esac

load_api_key

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║        🤖  AI-Powered Auto Commit Generator             ║"
echo "║              Powered by Google Gemini (Free)            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Guard: nothing to commit? ─────────────────────────────────────────────────
if [[ -z "$(git status --porcelain)" ]]; then
    echo -e "${YELLOW}⚠️  No changes detected. Nothing to commit.${NC}"
    exit 0
fi

# ── Stage everything ──────────────────────────────────────────────────────────
echo -e "${CYAN}📂 Staging all changes...${NC}"
git add -A

# ── Collect diff context ──────────────────────────────────────────────────────
CHANGED_FILES=$(git diff --cached --name-only)
NUM_FILES=$(echo "$CHANGED_FILES" | grep -c . || true)
ADDITIONS=$(git diff --cached --numstat | awk '{s+=$1} END {print s+0}')
DELETIONS=$(git diff --cached --numstat | awk '{s+=$2} END {print s+0}')

echo -e "${CYAN}📊 Change summary:${NC}"
echo -e "   Files  : ${GREEN}${NUM_FILES}${NC}"
echo -e "   Added  : ${GREEN}+${ADDITIONS}${NC}"
echo -e "   Removed: ${RED}-${DELETIONS}${NC}"
echo ""

# Truncate diff to ~3000 chars to stay within token limits
RAW_DIFF=$(git diff --cached --unified=3)
DIFF_SNIPPET="${RAW_DIFF:0:3000}"
[[ ${#RAW_DIFF} -gt 3000 ]] && DIFF_SNIPPET+="
... (diff truncated)"

# ── Gemini API call ───────────────────────────────────────────────────────────
generate_with_gemini() {
    echo -e "${MAGENTA}🧠 Asking Gemini to analyse the diff...${NC}"

    local prompt
    prompt="You are a senior engineer. Given a git diff, output ONLY a single conventional commit message (no explanation, no markdown, no quotes, no code blocks). Format: <type>(<optional scope>): <short description>. Types: feat, fix, docs, style, refactor, test, chore. Use BREAKING CHANGE: prefix for breaking changes. Keep it under 72 chars.

Files changed:
${CHANGED_FILES}

Diff:
${DIFF_SNIPPET}"

    # Detect python command (Windows uses 'python', Linux/Mac uses 'python3')
    local PY
    if command -v python3 &>/dev/null && python3 -c "import sys" &>/dev/null; then
        PY="python3"
    elif command -v python &>/dev/null && python -c "import sys" &>/dev/null; then
        PY="python"
    else
        echo -e "${YELLOW}⚠️  Python not found. Falling back to rule-based.${NC}" >&2
        return 1
    fi

    # Use python to safely build the JSON payload — avoids all escaping issues
    local payload
    payload=$($PY -c "
import json, sys
prompt = sys.argv[1]
payload = {
    'contents': [{'parts': [{'text': prompt}]}],
    'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 80}
}
print(json.dumps(payload))
" "$prompt")

    local response
    response=$(curl -s -X POST \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${GEMINI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    # Extract the text from Gemini's response using python for reliable parsing
    local ai_msg
    ai_msg=$(echo "$response" | $PY -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['candidates'][0]['content']['parts'][0]['text'].strip().splitlines()[0])
except Exception as e:
    sys.exit(1)
" 2>/dev/null)

    if [[ -z "$ai_msg" ]]; then
        echo -e "${YELLOW}⚠️  Gemini returned empty response. Falling back to rule-based.${NC}" >&2
        return 1
    fi

    echo "$ai_msg"
}

# ── Rule-based fallback ───────────────────────────────────────────────────────
generate_with_rules() {
    echo -e "${YELLOW}⚙️  Using rule-based fallback (no API key configured)...${NC}" >&2
    echo -e "${CYAN}   Run ${YELLOW}./auto-commit.sh --setup${CYAN} to enable Gemini AI.${NC}" >&2
    echo "" >&2

    local type="chore" scope="" files_short

    if echo "$CHANGED_FILES" | grep -qE '\.(test|spec)\.(tsx?|jsx?)$'; then
        type="test"
    elif echo "$CHANGED_FILES" | grep -qE '\.(md|txt|rst)$'; then
        type="docs"
    elif echo "$CHANGED_FILES" | grep -qE '\.(css|scss|sass|less)$'; then
        type="style"
    elif echo "$CHANGED_FILES" | grep -qE '(package\.json|tsconfig|vite\.config|tailwind\.config)'; then
        type="chore"
    elif echo "$RAW_DIFF" | grep -qiE '^\+.*(fix|bug|resolve|patch|correct)'; then
        type="fix"
    elif echo "$RAW_DIFF" | grep -qE '^\+.*(export (default |const |function |class ))'; then
        type="feat"
    elif [[ $DELETIONS -gt 0 && $ADDITIONS -gt 0 ]]; then
        type="refactor"
    fi

    if echo "$CHANGED_FILES" | grep -q "components/"; then scope="components"
    elif echo "$CHANGED_FILES" | grep -q "pages/"; then scope="pages"
    elif echo "$CHANGED_FILES" | grep -q "hooks/"; then scope="hooks"
    elif echo "$CHANGED_FILES" | grep -q "data/"; then scope="data"
    fi

    files_short=$(echo "$CHANGED_FILES" | head -3 \
                  | while IFS= read -r f; do basename "$f" | sed 's/\.[^.]*$//'; done \
                  | paste -sd ", ")

    if [[ -n "$scope" ]]; then
        echo "${type}(${scope}): update ${files_short}"
    else
        echo "${type}: update ${files_short}"
    fi
}

# ── Pick generation method ────────────────────────────────────────────────────
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
    GENERATED_MSG=$(generate_with_gemini) || GENERATED_MSG=$(generate_with_rules)
else
    GENERATED_MSG=$(generate_with_rules)
fi

# ── Show result ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✨ Generated commit message:${NC}"
echo -e "   ${YELLOW}${BOLD}${GENERATED_MSG}${NC}"
echo ""

$DRY_RUN && { echo -e "${CYAN}--dry-run: no commit created.${NC}"; exit 0; }

# ── Confirm / edit ────────────────────────────────────────────────────────────
echo -e "${CYAN}What would you like to do?${NC}"
echo -e "  ${GREEN}[Enter]${NC}  Use this message"
echo -e "  ${GREEN}[e]${NC}      Edit it"
echo -e "  ${GREEN}[c]${NC}      Type a custom message"
echo -e "  ${GREEN}[q]${NC}      Cancel"
echo ""
read -rp "Choice: " ACTION

case "${ACTION,,}" in
    ""|y)  FINAL_MSG="$GENERATED_MSG" ;;
    e)
        read -rp "Edit: " EDITED
        FINAL_MSG="${EDITED:-$GENERATED_MSG}"
        ;;
    c)
        echo -e "${CYAN}Types: feat | fix | docs | style | refactor | test | chore | BREAKING CHANGE${NC}"
        read -rp "Custom message: " CUSTOM
        [[ -z "$CUSTOM" ]] && { echo -e "${RED}❌ Cannot be empty.${NC}"; exit 1; }
        FINAL_MSG="$CUSTOM"
        ;;
    q)
        echo -e "${YELLOW}Cancelled. Changes are staged but not committed.${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}❌ Invalid choice.${NC}"; exit 1 ;;
esac

# ── Commit (post-commit hook handles versioning + push) ───────────────────────
echo ""
echo -e "${YELLOW}💾 Committing: ${BOLD}${FINAL_MSG}${NC}"
git commit -m "$FINAL_MSG"

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}${BOLD}✅ Commit created!${NC}"
    echo -e "${CYAN}The post-commit hook should now tag and push automatically.${NC}"
    echo -e "${CYAN}If push didn't happen, run: ${YELLOW}git push origin main --tags${NC}"
else
    echo -e "${RED}❌ Commit failed${NC}"
    exit 1
fi
