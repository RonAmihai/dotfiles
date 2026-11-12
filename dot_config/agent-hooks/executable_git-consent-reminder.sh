#!/bin/sh
# Prompt hook for Claude Code, Codex, agy and opencode, because long sessions drift from rules read once
text='Git consent reminder: commit or push only when the user asked for it in the current task. A yes covers that task only, not a later task in the same session. A request to commit does not include a push. When you are not sure that the user agreed, ask.'
case ${1:-} in
agy)  printf '{"injectSteps":[{"ephemeralMessage":"%s"}]}\n' "$text" ;;
text) printf '%s\n' "$text" ;;
*)    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$text" ;;
esac
