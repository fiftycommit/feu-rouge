#!/bin/bash
# Retire les hooks, l'agent de demarrage et l'etat.
set -euo pipefail
cd "$(dirname "$0")"
HOOK="$(pwd)/bin/codex-feu-rouge-hook"
HOOKS_FILE="${CODEX_HOME:-$HOME/.codex}/hooks.json"

if [ -f "$HOOKS_FILE" ]; then
  jq --arg hook "$HOOK" '
    .hooks = ((.hooks // {})
      | with_entries(.value |= (
          map(.hooks |= map(select((.command // "") | contains($hook) | not)))
          | map(select((.hooks | length) > 0))))
      | with_entries(select((.value | length) > 0)))
  ' "$HOOKS_FILE" > "$HOOKS_FILE.tmp" && mv "$HOOKS_FILE.tmp" "$HOOKS_FILE"
  echo "hooks retires de $HOOKS_FILE"
fi

rm -f "${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}/extensions/feu-rouge.ts"

launchctl bootout "gui/$UID/fr.max.feurouge" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/fr.max.feurouge.plist"
pkill -f 'FeuRouge.app/Contents/MacOS/FeuRouge' 2>/dev/null || true
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/codex-feu-rouge"
echo "desinstalle."
