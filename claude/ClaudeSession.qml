import QtQuick
import Quickshell
import Quickshell.Io
import "Policy.js" as Policy

// The durable inline conversation. Claude Code owns the conversation record
// under ~/.claude/projects; Keystroke keeps only its own forty-entry index of
// session ids, titles, working folders and drafts, and repaints a resumed
// conversation from the transcript. A session id is claimed before the first
// turn, so a conversation stays resumable even if the first answer fails.
Item {
  id: root
  property var host: null
  property var settings: ({})
  property string home: Quickshell.env("HOME")
  property string sessionId: ""
  property string title: "Quick question"
  property string draft: ""
  property string error: ""
  property string activity: ""
  property string permission: ""
  property string mode: "quick"
  property string cwd: home + "/.local/state/keystroke/questions"
  property string phase: "idle"
  readonly property bool busy: phase !== "idle"
  visible: false
  property bool loaded: false
  property bool warmed: false
  property bool cancelRequested: false
  property bool pendingSubmit: false
  property bool handoffPending: false
  property int epoch: 0
  property real startedTime: 0
  property int lastMs: 0
  property int firstTextMs: 0
  property string submitted: ""
  property var messages: []
  property var recent: []
  property var deltas: ({})
  property string streamId: ""
  property var streamed: ({})
  property var afterReady: null
  signal changed()
  signal handoffReady(string sessionId)
  readonly property alias server: rpc

  AppServer {
    id: rpc
    keepBusy: root.busy
    onReadyChanged: if (ready && root.afterReady) { var fn = root.afterReady; root.afterReady = null; fn() }
    onMessage: msg => root.handleMessage(msg)
    onStopped: { root.loaded = false; if (root.handoffPending && !root.busy && root.sessionId) { root.handoffPending = false; root.handoffReady(root.sessionId) } }
    onDisconnected: function(text) {
      root.loaded = false; root.afterReady = null; root.handoffPending = false; root.pendingSubmit = false
      root.phase = "idle"; root.error = text
      if (root.submitted && !root.draft) root.draft = root.submitted
      root.saveRecent(); root.changed()
    }
  }

  FileView {
    id: historyFile
    path: root.home + "/.local/state/keystroke/claude.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        if (d.version === 1 && Array.isArray(d.recent)) root.recent = d.recent.filter(x => Policy.safeId(x.id)).slice(0, 40)
      } catch (_) { root.error = "Could not read recent questions" }
    }
  }
  function saveRecent() {
    if (!Policy.safeId(sessionId) || (!messages.length && !submitted && !draft)) return
    var row = {id: sessionId, title: title, cwd: cwd, mode: mode, draft: draft, updated: Date.now()}
    recent = [row].concat(recent.filter(x => x.id !== sessionId)).slice(0, 40)
    historyFile.setText(JSON.stringify({version: 1, recent: recent}, null, 2) + "\n")
    changed()
  }

  // Repaint a resumed conversation from Claude Code's own transcript.
  Process {
    id: transcript
    property int token: 0
    stdout: StdioCollector { onStreamFinished: {
      if (transcript.token !== root.epoch) return
      var d = null
      try { d = JSON.parse(text) } catch (e) { root.activity = "Could not read the saved conversation"; return }
      if (!d || !Array.isArray(d.messages)) return
      // A queued question can start streaming before the transcript is read,
      // so the saved rows go in front of what is already here, never over it.
      var known = ({})
      root.messages.forEach(function(m) { known[m.id] = true })
      var head = d.messages.filter(function(m) { return !known[m.id] })
      if (head.length) root.messages = head.concat(root.messages).slice(-160)
    } }
  }
  function repaint() {
    transcript.token = epoch
    transcript.command = ["bash", "-lc", 'exec bash "$0" "$@"',
      Qt.resolvedUrl("../helpers/claude-history.sh").toString().replace("file://", ""), sessionId]
    transcript.running = true
  }

  // A palette open starts one quick-mode child on a fresh id, so the first
  // question does not pay process start-up. It is reused until a question is
  // actually asked, and a ten-minute idle child shuts itself down.
  function warm() {
    if (busy || rpc.starting || loaded || messages.length) return
    if (!sessionId) { sessionId = Policy.newId(); mode = "quick"; cwd = home + "/.local/state/keystroke/questions" }
    if (mode !== "quick") return
    warmed = true
    rpc.workdir = cwd
    rpc.start(Policy.args("quick", sessionId, false, settings))
  }
  function whenReady(fn) {
    if (rpc.ready) fn()
    else { afterReady = fn; rpc.ensure() }
  }

  function reset() {
    paint.stop(); deltas = ({}); streamed = ({}); streamId = ""
    epoch++; messages = []; error = ""; activity = ""; submitted = ""; permission = ""
    loaded = false; cancelRequested = false; handoffPending = false; pendingSubmit = false
  }

  function newQuestion(text, agentCwd) {
    if (busy) { error = "Stop the current answer before starting another question"; return false }
    saveRecent()
    var reusable = warmed && !agentCwd && mode === "quick" && !messages.length && Policy.safeId(sessionId)
    reset()
    mode = agentCwd ? "agent" : "quick"
    cwd = agentCwd || home + "/.local/state/keystroke/questions"
    title = mode === "agent" ? "Task" : "Quick question"
    if (!reusable) { sessionId = Policy.newId(); warmed = false }
    draft = String(text || "")
    if (draft.trim()) submit()
    return true
  }

  function openRecent(row) {
    if (busy) return false
    saveRecent(); reset()
    sessionId = row.id; title = row.title; cwd = row.cwd; mode = row.mode || "quick"
    draft = row.draft || ""; warmed = false
    phase = "preparing"
    var token = epoch
    // The transcript repaints from disk long before the child is ready, so the
    // conversation is readable while the connection is still coming up.
    repaint()
    connect(true, function() {
      if (token !== root.epoch || root.cancelRequested) return
      root.phase = "idle"
      root.flushPendingSubmit()
    })
    return true
  }

  // Start (or resume) the child for this conversation and run `done` once the
  // transport has answered the initialize request.
  function connect(resume, done) {
    var token = epoch
    afterReady = function() { if (token === root.epoch) { root.loaded = true; root.saveRecent(); done() } }
    rpc.workdir = cwd
    rpc.start(Policy.args(mode, sessionId, resume, settings))
  }

  // Enter pressed while a resumed conversation is still connecting is kept and
  // sent once the child is ready, rather than silently dropped.
  function flushPendingSubmit() { if (pendingSubmit) { pendingSubmit = false; submit() } }
  function submit() {
    var text = draft
    if (!text.trim() || phase === "stopping") return false
    if (phase === "preparing") { pendingSubmit = true; activity = "Connecting…"; return true }
    if (busy) { steer(text); return true }
    error = ""; permission = ""; activity = "Connecting…"; cancelRequested = false
    submitted = text; phase = "preparing"; handoffPending = false
    var token = epoch
    var begin = function() {
      if (token !== root.epoch || root.cancelRequested) { root.phase = "idle"; return }
      root.beginTurn(text)
    }
    if (loaded && rpc.ready) begin()
    else if (rpc.ready && warmed) { loaded = true; begin() }
    else connect(!warmed && !!messages.length, begin)
    return true
  }

  function beginTurn(text) {
    startedTime = Date.now(); lastMs = 0; firstTextMs = 0
    activity = "Answering…"; phase = "running"
    if (title === "Quick question" || title === "Task") title = text.replace(/\s+/g, " ").trim().slice(0, 80)
    warmed = false
    rpc.ask(text)
    if (draft === text) draft = ""
    saveRecent()
  }
  function steer(text) {
    if (phase !== "running") return
    rpc.ask(text)
    if (draft === text) draft = ""
    saveRecent()
  }

  function fail(message) { phase = "idle"; error = message; activity = ""; handoffPending = false; pendingSubmit = false; saveRecent() }
  function stop() {
    if (!busy) return
    cancelRequested = true; pendingSubmit = false
    if (afterReady) { afterReady = null; phase = "idle"; finishHandoff(); return }
    interrupt()
  }
  function interrupt() {
    if (phase === "stopping") return
    phase = "stopping"; activity = "Stopping…"
    rpc.interrupt(function(result, error) { if (error) { root.error = Policy.plainError(error); root.handoffPending = false } })
  }
  Timer { interval: 10000; running: root.phase === "stopping"; onTriggered: rpc.fail("Claude Code did not acknowledge stopping. The connection was closed; reopen the saved question to continue.") }
  function dismiss() { visible = false; handoffPending = false; stop(); saveRecent() }
  function shutdown() { dismiss(); rpc.shutdown(); loaded = false; warmed = false }

  function upsert(id, role, text) {
    var copy = messages.slice(), index = copy.findIndex(x => x.id === id)
    var item = {id: id, role: role, text: String(text === undefined || text === null ? "" : text).slice(-250000)}
    if (index < 0) copy.push(item); else copy[index] = item
    messages = copy.slice(-160)
  }
  function flush() {
    var copy = deltas; deltas = ({})
    for (var id in copy) {
      var existing = messages.find(x => x.id === id)
      upsert(id, "assistant", (existing ? existing.text : "") + copy[id])
    }
  }
  Timer { id: paint; interval: 32; onTriggered: root.flush() }

  // ------------------------------------------------------------- transport
  function handleMessage(m) {
    var type = m.type
    if (type === "system") {
      if (m.subtype === "init") {
        if (m.session_id && m.session_id !== sessionId) { sessionId = m.session_id; saveRecent() }
      } else if (m.subtype === "permission_denied") {
        permission = String(m.message || ("Claude needs permission to use " + (m.tool_name || "a tool") + "."))
        activity = "Permission needed"
      }
      return
    }
    if (type === "stream_event") { handleStream(m.event || {}); return }
    if (type === "assistant") { handleAssistant(m.message || {}); return }
    if (type === "user") { handleEcho(m.message || {}); return }
    if (type === "result") { finishTurn(m); return }
  }

  function handleStream(e) {
    if (e.type === "message_start") { streamId = (e.message && e.message.id) || ""; return }
    if (e.type === "content_block_start") {
      if (e.content_block && e.content_block.type === "text" && streamId) {
        var copy = Object.assign({}, streamed); copy[streamId] = true; streamed = copy
        upsert(streamId + ":" + e.index, "assistant", "")
      }
      return
    }
    if (e.type === "content_block_delta" && e.delta && e.delta.type === "text_delta") {
      if (!busy || !streamId) return
      if (!firstTextMs) firstTextMs = Date.now() - startedTime
      var d = Object.assign({}, deltas), key = streamId + ":" + e.index
      d[key] = (d[key] || "") + (e.delta.text || ""); deltas = d
      if (!paint.running) paint.start()
      return
    }
    if (e.type === "content_block_stop" || e.type === "message_stop") flush()
  }

  // Streamed deltas are the authoritative text, so a completed text block is
  // only added when partial messages never arrived for that message.
  function handleAssistant(message) {
    var blocks = message.content || []
    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i]
      if (block.type === "tool_use") {
        activity = Policy.toolLabel(block)
        upsert(String(block.id), "activity", Policy.toolDetail(block))
      } else if (block.type === "text" && !streamed[message.id]) {
        flush()
        upsert(String(message.id) + ":text" + i, "assistant", block.text || "")
      }
    }
  }

  function handleEcho(message) {
    var blocks = message.content || []
    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i]
      if (block.type === "text" && /interrupted by user/i.test(String(block.text || ""))) activity = "Stopped"
      else if (block.type === "tool_result" && block.is_error) activity = "A tool call failed"
    }
  }

  function finishTurn(m) {
    flush()
    if (m.session_id) sessionId = m.session_id
    phase = "idle"; lastMs = Date.now() - startedTime
    var interrupted = cancelRequested || m.subtype === "error_during_execution"
    if (m.subtype === "success") { activity = "Done"; error = "" }
    else if (interrupted) { activity = "Stopped" }
    else {
      activity = "Failed"
      error = Policy.plainError(m.result || m.error || m.subtype || "The request did not finish")
      if (!draft) draft = submitted
    }
    cancelRequested = false; submitted = ""
    saveRecent(); finishHandoff()
  }

  function requestHandoff() {
    if (!Policy.safeId(sessionId)) { error = "Send a question before continuing in Claude Code"; return }
    if (!rpc.ready && !busy && !rpc.starting) { handoffReady(sessionId); return }
    handoffPending = true
    if (busy) stop(); else finishHandoff()
  }
  function finishHandoff() {
    if (!handoffPending || busy || !Policy.safeId(sessionId)) return
    saveRecent()
    // Claude Code binds a session to one running process. Exit the child that
    // Keystroke owns before another client resumes the same session.
    loaded = false; warmed = false
    rpc.shutdown()
  }

  function answer() { var replies = messages.filter(x => x.role === "assistant"); return replies.length ? replies[replies.length - 1].text : "" }
}
