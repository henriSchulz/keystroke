#!/usr/bin/env bash
# Keystroke owns this process: one `claude -p` per conversation, started with
# the argv Policy.js builds. Do not attach to another client's session.
set -euo pipefail

min=2.0.0
raw="$(claude --version 2>/dev/null || true)"
actual="${raw%% *}"
if [[ -z $actual ]]; then
  echo "Keystroke requires the Claude Code CLI on PATH; none was found." >&2
  exit 65
fi
lowest="$(printf '%s\n%s\n' "$min" "$actual" | sort -V | head -n1)"
if [[ $lowest != "$min" && $actual != "$min" ]]; then
  echo "Keystroke requires Claude Code $min or newer; found $actual." >&2
  exit 65
fi

mkdir -p "$HOME/.local/state/keystroke/questions"
exec claude "$@"
