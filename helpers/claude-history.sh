#!/usr/bin/env bash
# Repaint a resumed conversation. Claude Code owns the conversation record;
# this reads its transcript for the given session id and prints the subset
# Keystroke displays as {"messages":[{id,role,text}]}. The transcript folder
# is derived from the working directory, so it is found by search rather than
# by reproducing that name.
set -euo pipefail
id="${1:-}"
[[ $id =~ ^[0-9a-fA-F-]{36}$ ]] || { echo '{"messages":[]}'; exit 0; }
file="$(find "$HOME/.claude/projects" -maxdepth 3 -name "$id.jsonl" -print -quit 2>/dev/null || true)"
[[ -n $file ]] || { echo '{"messages":[]}'; exit 0; }

python3 - "$file" <<'PY'
import json, sys

out = []
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("type") not in ("user", "assistant") or entry.get("isSidechain"):
            continue
        message = entry.get("message") or {}
        blocks = message.get("content")
        if isinstance(blocks, str):
            blocks = [{"type": "text", "text": blocks}]
        if not isinstance(blocks, list):
            continue
        uid = entry.get("uuid") or ""
        for index, block in enumerate(blocks):
            if not isinstance(block, dict):
                continue
            kind = block.get("type")
            key = "%s:%d" % (uid, index)
            if kind == "text":
                text = block.get("text") or ""
                if not text.strip():
                    continue
                out.append({"id": key, "role": "user" if entry["type"] == "user" else "assistant", "text": text})
            elif kind == "tool_use":
                name = block.get("name") or "tool"
                args = block.get("input") or {}
                detail = args.get("command") or args.get("file_path") or args.get("query") or args.get("pattern") or ""
                out.append({"id": key, "role": "activity", "text": (name + ": " + str(detail)).strip(": ")})

print(json.dumps({"messages": out[-160:]}))
PY
