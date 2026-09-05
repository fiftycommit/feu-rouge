#!/bin/bash
# Installe les hooks (codex, claude code, antigravity) + l'app barre de menus.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
HOOK="$ROOT/bin/codex-feu-rouge-hook"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
HOOKS_FILE="$CODEX_HOME/hooks.json"

[ -x "$ROOT/build/FeuRouge.app/Contents/MacOS/FeuRouge" ] || ./build.sh

mkdir -p "$CODEX_HOME"

# --- hooks codex ---------------------------------------------------------
mapping='{
  "SessionStart":      "idle",
  "UserPromptSubmit":  "running",
  "PreToolUse":        "running",
  "PermissionRequest": "waiting",
  "PostToolUse":       "running",
  "Stop":              "idle",
  "Interrupt":         "idle",
  "SessionEnd":        "gone"
}'

ours=$(jq -n --arg hook "$HOOK" --argjson map "$mapping" '
  $map | to_entries | map({
    key: .key,
    value: [ { hooks: [ { type: "command", command: ($hook + " " + .value) } ] } ]
  }) | from_entries')

if [ -f "$HOOKS_FILE" ]; then
  cp "$HOOKS_FILE" "$HOOKS_FILE.bak.$(date +%s)"
  # Retire nos anciennes entrees (reinstall idempotente), puis concatene les notres.
  jq --argjson ours "$ours" --arg hook "$HOOK" '
    ((.hooks // {})
      | with_entries(.value |= (
          map(.hooks |= map(select((.command // "") | contains($hook) | not)))
          | map(select((.hooks | length) > 0))))
      | with_entries(select((.value | length) > 0))) as $clean
    | .hooks = (reduce ($ours | keys_unsorted[]) as $k ($clean;
        .[$k] = (($clean[$k] // []) + $ours[$k])))
  ' "$HOOKS_FILE" > "$HOOKS_FILE.tmp"
  mv "$HOOKS_FILE.tmp" "$HOOKS_FILE"
else
  jq -n --argjson ours "$ours" '{hooks: $ours}' > "$HOOKS_FILE"
fi
echo "hooks codex -> $HOOKS_FILE"

# --- hooks claude code ---------------------------------------------------
# Claude Code n'a pas de PermissionRequest : c'est Notification qui signale
# "j'attends une autorisation" (ou une saisie).
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ -d "$HOME/.claude" ]; then
  [ -f "$CLAUDE_SETTINGS" ] || echo '{}' > "$CLAUDE_SETTINGS"
  cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak.$(date +%s)"
  claude_map='{
    "SessionStart":     "idle",
    "UserPromptSubmit": "running",
    "PreToolUse":       "running",
    "PostToolUse":      "running",
    "Notification":     "waiting",
    "Stop":             "idle",
    "SessionEnd":       "gone"
  }'
  cours=$(jq -n --arg hook "$HOOK" --argjson map "$claude_map" '
    $map | to_entries | map({
      key: .key,
      value: [ { hooks: [ { type: "command", command: ($hook + " " + .value + " claude") } ] } ]
    }) | from_entries')
  jq --argjson ours "$cours" --arg hook "$HOOK" '
    ((.hooks // {})
      | with_entries(.value |= (
          map(.hooks |= map(select((.command // "") | contains($hook) | not)))
          | map(select((.hooks | length) > 0))))
      | with_entries(select((.value | length) > 0))) as $clean
    | .hooks = (reduce ($ours | keys_unsorted[]) as $k ($clean;
        .[$k] = (($clean[$k] // []) + $ours[$k])))
  ' "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp"
  mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
  echo "hooks claude -> $CLAUDE_SETTINGS"
fi

# --- hooks antigravity ---------------------------------------------------
# Schema PROPRE a antigravity, rien a voir avec celui de codex/claude :
#   { "<nom du hook>": { "PreToolUse": [ {matcher, hooks:[...]} ],
#                        "PreInvocation": [ {type, command} ], ... } }
# Evenements disponibles : PreToolUse, PostToolUse (avec matcher),
# PreInvocation, PostInvocation, Stop (liste plate). Pas de SessionStart/End
# ni d'evenement de permission : d'ou l'absence de rouge pour cet agent, et
# la detection de fin de session par mort du process.
AGY_HOOKS="$HOME/.gemini/config/hooks.json"
if [ -d "$HOME/.gemini/config" ]; then
  [ -f "$AGY_HOOKS" ] || echo '{}' > "$AGY_HOOKS"
  cp "$AGY_HOOKS" "$AGY_HOOKS.bak.$(date +%s)" 2>/dev/null || true
  jq --arg hook "$HOOK" '
    def cmd($state): { type: "command", command: ($hook + " " + $state + " antigravity"), timeout: 5 };
    del(."feu-rouge")
    | ."feu-rouge" = {
        enabled: true,
        PreInvocation:  [ cmd("running") ],
        PreToolUse:     [ { matcher: "*", hooks: [ cmd("running") ] } ],
        PostToolUse:    [ { matcher: "*", hooks: [ cmd("running") ] } ],
        PostInvocation: [ cmd("running") ],
        Stop:           [ cmd("idle") ]
      }
  ' "$AGY_HOOKS" > "$AGY_HOOKS.tmp"
  mv "$AGY_HOOKS.tmp" "$AGY_HOOKS"
  echo "hooks antigravity -> $AGY_HOOKS"
fi

# --- lancement au demarrage ---------------------------------------------
PLIST="$HOME/Library/LaunchAgents/fr.max.feurouge.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>fr.max.feurouge</string>
  <key>ProgramArguments</key>
  <array><string>$ROOT/build/FeuRouge.app/Contents/MacOS/FeuRouge</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
PL

# bootout est asynchrone : bootstrap echoue en erreur 5 s'il arrive trop tot.
launchctl bootout "gui/$UID/fr.max.feurouge" 2>/dev/null || true
for _ in 1 2 3 4 5; do
  launchctl bootstrap "gui/$UID" "$PLIST" 2>/dev/null && break
  sleep 1
done
echo "app lancee (et relancee a chaque ouverture de session)"
echo
echo "Derniere etape : dans codex, tape /hooks et fais confiance aux hooks 'codex-feu-rouge-hook'."
echo "Dans tous les cas, les hooks ne s'appliquent qu'aux NOUVELLES sessions."
