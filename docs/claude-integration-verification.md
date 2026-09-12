# Claude Code integration checkpoint — 2026-09-12

This fork replaces Keystroke's Codex integration with Claude Code. Verified on
this machine against **Claude Code 2.1.263** and Omarchy's Quickshell build.
The v1 voice tag is unchanged.

## What the transport actually is

Claude Code has no app-server. The integration drives the CLI's stream-json
transport, and every shape below was read off a live process rather than
inferred:

| Need | Mechanism |
|---|---|
| Start a conversation | `claude -p --input-format stream-json --output-format stream-json --include-partial-messages --verbose --session-id <uuid>` |
| Resume one | the same, with `--resume <session-id>` instead |
| Readiness | `control_request {subtype:"initialize"}`; its `control_response` arrives before any user message |
| Send a turn | `{"type":"user","message":{...}}` on stdin |
| Follow up mid-turn | a second user message on stdin; the CLI queues it |
| Stream the answer | `stream_event` → `content_block_delta` → `text_delta` |
| Tool activity | `assistant` messages carrying `tool_use` blocks |
| Stop | `control_request {subtype:"interrupt"}` → `{still_queued:[]}`, then `[Request interrupted by user]` and `result` `error_during_execution` |
| End of turn | `result`, which repeats `session_id` |
| History | `~/.claude/projects/<dir>/<session-id>.jsonl` |

The child's working directory is the conversation's scope: Claude Code resolves
project context, permissions and the transcript folder from it. Quick questions
run in `~/.local/state/keystroke/questions`.

## Delivered

- Claude provider with inline quick questions, streamed selectable answers,
  follow-ups, stop, copy, and recent questions.
- Normal root results: **Ask Claude here** and **Open task in Claude Code**.
  `? ` prioritizes the inline ask; `Ctrl+↵` takes the external path.
- One `claude -p` child per conversation, owned by Keystroke, shut down after
  ten idle minutes. A session id is claimed before the first turn, so a
  conversation stays resumable even if the first answer never lands.
- Quick mode: `--permission-mode plan`, `--tools WebSearch,WebFetch`,
  `--setting-sources ""`, `--strict-mcp-config`. No shell, no files, no
  inherited MCP servers, no user/project/local settings.
- Agent mode: explicitly chosen, with a visible working folder,
  `--permission-mode acceptEdits`, and the Omarchy skill named in the system
  prompt. Never edits `/usr/share/omarchy`.
- Hand-off: **Continue in Claude Code** exits the owned child, then resumes the
  same session in a terminal. **Open task in Claude Code** honours the
  destination preference for a brand-new request.
- A resumed conversation is repainted from Claude Code's own transcript by
  `helpers/claude-history.sh`.
- No credential reads, no transcript edits, no blind Enter dispatch, no
  automatic retry of a submitted request after a disconnect.

## Measured

- `tests/claude_session_check.py`: the production QML transport, session and
  conversation view against `tests/claude_fake_cli.py` — streamed deltas
  reconciling with the completed message, voice keys, the permission panel,
  cancel, disconnect with draft preservation, transcript repaint on resume, and
  child exit before hand-off. Passes.
- `tests/tst_claudepolicy.qml`: quick-mode capability isolation, agent-mode
  scoping, model/effort defaults, UUID session ids, literal-argument hand-off.
- Live, against the real CLI on this machine: a streamed inline answer, a
  follow-up in the same session, the recent index written to
  `~/.local/state/keystroke/claude.json`, and the transcript landing in
  `~/.claude/projects/-home-henri--local-state-keystroke-questions`.

## Known limits

- **Interactive approvals are not available.** In print mode the CLI does not
  route `can_use_tool` to a stream-json host without a permission-prompt MCP
  tool, so a blocked tool arrives as `system/permission_denied` and a failed
  tool result. Agent mode therefore auto-accepts edits in the chosen working
  folder and reports anything else, offering the terminal. Keystroke never
  silently grants a permission.
- **The desktop app cannot continue an existing local conversation.** There is
  no `claude://` route into a running local session, so continuing always uses
  the CLI; only a brand-new request honours the desktop preference.
- **The version gate is a floor (2.0.0), not a pin.** Pinning an exact CLI
  version — what the Codex integration did — breaks the feature on every CLI
  update; this fork was written after finding exactly that failure.
- Thinking blocks are not displayed; only answer text and one line of activity
  per tool call.
