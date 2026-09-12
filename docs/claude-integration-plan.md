# Keystroke with Claude Code — design

2026-09-12. This fork of [evindor/keystroke](https://github.com/evindor/keystroke)
1.4.2 replaces the Codex integration with Claude Code. The palette, voice,
matching, extensions and every other provider are unchanged; only the assistant
behind the inline conversation moved. See
[integration verification](claude-integration-verification.md) for what was
measured and what the limits are.

## Why a port and not a rename

The Codex integration was not branding. It spoke a JSON-RPC protocol to
`codex app-server --stdio`, set Codex-specific config keys, and handed off over
`codex://threads/<id>`. None of those exist for Claude Code, so a text
substitution would have produced a plugin that says "Claude" and talks to Codex.

It also pinned `codex-cli 0.153.2` exactly, which already failed on this machine
against the installed 0.153.4 — the version gate here is a floor.

## Shape of the port

| Codex | Claude Code |
|---|---|
| one shared `codex app-server`, many threads | one `claude -p` child per conversation |
| `initialize` / `initialized` RPC | `control_request {subtype:"initialize"}` |
| `thread/start` / `thread/resume` | `--session-id <uuid>` / `--resume <id>` |
| `turn/start`, `turn/steer` | a `user` message on stdin; a second one is queued |
| `turn/interrupt` | `control_request {subtype:"interrupt"}` |
| `item/agentMessage/delta` | `stream_event` → `content_block_delta` → `text_delta` |
| `commandExecution` / `fileChange` items | `assistant` messages with `tool_use` blocks |
| `turn/completed` | `result` |
| sandbox `read-only`, feature flags off | `--permission-mode plan`, `--tools WebSearch,WebFetch`, `--setting-sources ""`, `--strict-mcp-config` |
| sandbox `workspace-write`, `on-request` approvals | `--permission-mode acceptEdits` in the chosen folder |
| `codex://threads/<id>` hand-off | `claude --resume <id>` in a terminal |
| Codex owns history | Claude Code owns `~/.claude/projects/<dir>/<id>.jsonl` |

## What changed in behaviour

- **Working directory is now load-bearing.** Claude Code derives project
  context, permissions and the transcript folder from the child's cwd, so the
  transport sets it per conversation instead of passing a `cwd` parameter.
- **Effort replaces Fast/Standard.** Claude Code exposes `--effort`
  (`low`…`max`); the palette defaults to `low` so a quick answer stays quick.
- **Approvals became a notice.** Print mode cannot ask the user, so a blocked
  tool is reported with an offer to continue in the terminal rather than an
  Allow/Decline panel that could not be honoured.
- **Continuing is always the CLI.** Only the CLI can resume a local session.

## Unchanged contracts

One native Omarchy menu replacement, the `omarchy.clonedFrom` contract, shared
shell services, capabilities implemented as providers, cheap operation while
hidden, and explicit execution. Local search, calculations and clipboard
actions stay immediate and never wait on the assistant. Speech recognition
stays local on Vulkan.
