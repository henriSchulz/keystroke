import QtQuick
import Quickshell
import Quickshell.Io
import "../claude"
import "../claude/Policy.js" as Policy
import "../core/AiTargets.js" as AiTargets
import "../core/Match.js" as Match

Item {
  id: root
  property var host: null
  property var available: ({})
  readonly property var preferences: host ? host.settingsFor({key: "claude", provider: provider}) : ({})
  readonly property bool active: host ? host.providerEnabled({key: "claude", source: "bundled"}) : false
  readonly property alias session: session
  readonly property Component view: Component { ConversationView { session: root.session } }
  readonly property var provider: ({
    apiVersion: 1, id: "claude", name: "Claude", icon: "✳", description: "Ask here, follow up, or continue a task in Claude Code",
    settings: [
      {key: "model", type: "string", label: "Model", "default": "claude-opus-5", description: "Any model your Claude plan can run, for example claude-opus-5, claude-sonnet-5 or claude-haiku-4-5"},
      {key: "effort", type: "enum", label: "Effort", "default": "low", options: ["low", "medium", "high", "xhigh", "max"], description: "How hard Claude works on an inline answer; low keeps the palette fast"},
      {key: "destination", type: "enum", label: "Start new tasks in", "default": "cli", options: ["cli", "desktop"], description: "A conversation already started here always continues in the terminal, because only the CLI can resume it"},
      {key: "workspace", type: "string", label: "Task working folder", "default": "", description: "Absolute folder for file and project tasks; desktop settings use ~/.config"}
    ],
    view: root.view,
    query: ctx => root.query(ctx),
    activate: (row, ctx) => root.activate(row, ctx),
    opened: function() { if (root.active) session.warm() },
    dismiss: function() { session.dismiss() }
  })
  ClaudeSession {
    id: session
    host: root.host
    settings: root.preferences
    onChanged: if (root.host) root.host.requery({ catalog: false, provider: root.provider.id })
    onHandoffReady: id => root.resume(id, session.cwd)
  }
  Process {
    id: detect
    command: ["bash", "-lc", "for c in claude claude-desktop; do command -v \"$c\" >/dev/null 2>&1 && echo \"$c\"; done"]
    running: true
    stdout: StdioCollector { onStreamFinished: { var a = {}; text.trim().split("\n").forEach(x => a[x] = true); root.available = a } }
  }
  Connections { target: DesktopEntries.applications; function onValuesChanged() { if (!detect.running) detect.running = true } }
  onActiveChanged: if (!active) { session.shutdown(); if (host && host.activeProviderKey === "claude") host.closeProviderView() }
  function preferredScore() {
    var entry = host ? host.registryEntry("ai") : null
    return entry && host.settingsFor(entry).provider === "chatgpt" ? 2.5 : 5
  }
  function raw(ctx) { return String(ctx.rawQuery === undefined ? ctx.query || "" : ctx.rawQuery).replace(/^\?\s*/, "") }
  function query(ctx) {
    if (ctx.scope && ctx.scope !== "claude") return []
    var text = raw(ctx), rows = [], scoped = ctx.scope === "claude"
    if (text.trim()) {
      rows.push({id: "ask", title: "Ask Claude here", subtitle: text, icon: "✳", section: "Continue with", tier: /^\?/.test(ctx.query) ? "answer" : "fallback", score: root.preferredScore(), verb: "Ask", hint: "Ctrl+Enter opens a task in Claude Code", action: {type: "provider-view", provider: "claude", text: text}, altAction: {type: "claude-external", text: text}})
      rows.push({id: "task", title: "Open task in Claude Code", subtitle: (root.preferences.destination === "desktop" ? "Desktop" : "Terminal") + " · full request ready to continue", icon: "↗", section: "Continue with", tier: "fallback", score: root.preferredScore() - 0.1, verb: "Open", action: {type: "claude-external", text: text}})
      if (scoped) rows.push({id: "desktop-task", title: "Do this here · desktop settings", subtitle: "Agent may edit ~/.config · uses the Omarchy skill", icon: "⌘", score: 3, verb: "Start task", action: {type: "provider-view", provider: "claude", text: text, cwd: root.host.home + "/.config"}})
      if (scoped && root.preferences.workspace) rows.push({id: "project-task", title: "Do this here · working folder", subtitle: root.preferences.workspace, icon: "⌘", score: 2, verb: "Start task", action: {type: "provider-view", provider: "claude", text: text, cwd: root.preferences.workspace}})
    }
    if (!text.trim()) {
      if (!scoped) rows.push({id: "open", title: "Claude", subtitle: "Quick questions, recent conversations and tasks", icon: "✳", score: 24, verb: "Open", action: {type: "navigate", scope: "claude", title: "Claude"}})
      rows.push({id: "new", title: "Ask Claude here", subtitle: "Type or speak a quick question", icon: "✳", score: scoped ? 100 : 23, verb: "Ask", action: {type: "provider-view", provider: "claude", text: ""}})
    }
    var recent = session.recent
    for (var i = 0; i < Math.min(recent.length, scoped ? 40 : (text.trim() ? 0 : 1)); i++) {
      var row = recent[i], score = text.trim() ? Match.match(text, row.title) : 20 - i
      if (score) rows.push({id: "recent/" + row.id, title: scoped ? row.title : "Resume last question", subtitle: scoped ? new Date(row.updated).toLocaleString() : row.title,
        icon: "↶", section: "Recent questions", score: score, verb: "Resume", action: {type: "provider-view", provider: "claude", recent: row}})
    }
    return rows
  }
  function activate(row, ctx) {
    var effect = ctx.alternate && row.altAction ? row.altAction : row.action
    if (effect.type === "claude-external") { startTask(effect.text, preferences.workspace); return {type: "noop"} }
    if (effect.type === "provider-view") {
      if (effect.cwd && effect.cwd.charAt(0) !== "/") { host.errorMessage = "Choose an absolute working folder in Claude settings"; return {type: "noop"} }
      var success = effect.recent ? session.openRecent(effect.recent) : session.newQuestion(effect.text, effect.cwd)
      if (!success) { host.errorMessage = session.error; return {type: "noop"} }
      session.visible = true
    }
    return effect
  }

  // A brand-new request honours the destination preference.
  function startTask(text, cwd) {
    var prompt = String(text || "")
    if (preferences.destination === "desktop" && available["claude-desktop"])
      return run(AiTargets.openLink("claude-desktop", AiTargets.claudeCodeUrl(prompt), available))
    if (!available.claude) { session.error = "The Claude Code CLI is not installed. Your question is still here."; host.errorMessage = session.error; return }
    run({type: "exec", argv: Policy.newTaskArgv(cwd, prompt)})
  }
  // An existing conversation can only be continued where it lives: the CLI.
  function resume(id, cwd) {
    if (!available.claude) { session.error = "Continuing needs the Claude Code CLI on your PATH."; host.errorMessage = session.error; return }
    run({type: "exec", argv: Policy.resumeArgv(cwd, id)})
  }
  function run(effect) {
    if (!effect) return
    var argv = effect.argv || []
    // Keep the full request. argv transport has an OS limit, not a hidden text cap.
    if (argv.some(x => String(x).length > 100000)) { session.error = "This request is too long for an app launch. Ask here, then continue the saved conversation."; host.errorMessage = session.error; return }
    host.cancel()
    if (effect.type === "url") Quickshell.execDetached(["xdg-open", String(effect.url || "")])
    else Quickshell.execDetached(argv)
  }
}
