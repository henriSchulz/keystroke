import QtQuick
import Quickshell.Io
import "Policy.js" as Policy

// One `claude -p --input-format stream-json` child per conversation, owned by
// Keystroke. Claude Code binds a print-mode process to a single session, so
// this is a per-conversation transport rather than one shared server:
// `start(argv)` swaps the conversation by replacing the child. Readiness is the answer to the initialize control request, which
// arrives before any user message. Ten idle minutes shut the child down; the
// session id survives, so reopening resumes.
Item {
  id: root
  property var argv: []
  property string workdir: ""
  property bool ready: false
  property bool starting: false
  property bool keepBusy: false
  property bool expectedExit: false
  property var pendingArgv: null
  property string error: ""
  property string diagnostic: ""
  property int sequence: 0
  property var pending: ({})
  readonly property string script: Qt.resolvedUrl("../helpers/claude-start.sh").toString().replace("file://", "")
  // Test seam: an argv prefix that replaces the start script.
  property var launcher: []
  signal message(var msg)
  signal disconnected(string text)
  signal stopped()

  // A login shell so the CLI is found wherever the user installed it (mise,
  // npm prefix, ~/.local/bin); omarchy-shell's own PATH is not enough.
  // The child's working directory is the conversation's scope: Claude Code
  // resolves project context, permissions and the transcript folder from it.
  function command(args) {
    var rest = (args || []).map(String)
    if (launcher.length) return launcher.map(String).concat(rest)
    return ["bash", "-lc", 'cd "$1" 2>/dev/null || cd "$HOME"; shift; exec bash "$0" "$@"',
            root.script, String(root.workdir || "")].concat(rest)
  }

  function start(args) {
    idle.restart()
    if (proc.running) {
      // Replace the running conversation: stop this child, start the next one
      // from onExited so the two never hold the same session id at once.
      pendingArgv = args
      if (!expectedExit) shutdown()
      return
    }
    root.argv = args
    error = ""; diagnostic = ""; starting = true; expectedExit = false; ready = false
    proc.command = command(args)
    proc.running = true
    startup.restart()
  }
  function ensure() { if (!proc.running && !starting && root.argv.length) start(root.argv) }

  function send(value) { if (proc.running) proc.write(JSON.stringify(value) + "\n") }
  function control(request, callback) {
    var id = "keystroke-" + (++sequence)
    var copy = Object.assign({}, pending)
    copy[id] = { callback: callback || function() {}, expires: Date.now() + 45000 }
    pending = copy
    send(request(id))
    idle.restart()
    return id
  }
  function ask(text) { send(Policy.userMessage(text)); idle.restart() }
  function interrupt(callback) { control(Policy.interruptRequest, callback) }

  function receive(line) {
    if (line.length > 8 * 1024 * 1024) { fail("Claude Code sent an oversized message"); return }
    var msg
    try { msg = JSON.parse(line) } catch (_) { return }   // non-JSON chatter is not fatal
    if (msg.type === "control_response") {
      var response = msg.response || {}, id = response.request_id
      if (id && pending[id]) {
        var entry = pending[id], copy = Object.assign({}, pending)
        delete copy[id]; pending = copy
        entry.callback(response.response || {}, response.subtype === "error" ? response : null)
      }
      if (starting) { starting = false; startup.stop(); ready = true }
      return
    }
    if (msg.type === "control_request") { send({type: "control_response", response: {subtype: "error", request_id: msg.request_id, error: "Keystroke cannot answer this request. Continue in Claude Code."}}); return }
    root.message(msg)
  }

  function fail(text) {
    error = text
    ready = false; starting = false
    startup.stop()
    var callbacks = pending; pending = ({})
    for (var id in callbacks) callbacks[id].callback(null, {message: text})
    disconnected(text)
    expectedExit = true; proc.running = false
  }
  function shutdown() {
    expectedExit = true; ready = false; starting = false
    startup.stop(); idle.stop()
    var callbacks = pending; pending = ({})
    for (var id in callbacks) callbacks[id].callback(null, {message: "Claude Code connection closed"})
    proc.running = false
  }

  Process {
    id: proc
    stdinEnabled: true
    onStarted: root.control(Policy.initializeRequest, function(result, error) {
      if (error) root.fail(Policy.plainError(error))
    })
    stdout: SplitParser { onRead: data => root.receive(data) }
    stderr: SplitParser { onRead: data => { root.diagnostic = (root.diagnostic + "\n" + data).slice(-3000) } }
    onExited: function(code) {
      var next = root.pendingArgv; root.pendingArgv = null
      if (root.expectedExit) {
        root.stopped()
        if (next) Qt.callLater(function() { root.start(next) })
        return
      }
      root.fail(code === 65
        ? (root.diagnostic.trim().split("\n").pop() || "Claude Code " + Policy.MIN_VERSION + " or newer is required.")
        : "Claude Code stopped. Your conversation is saved; reopen it to continue.")
      if (next) Qt.callLater(function() { root.start(next) })
    }
  }
  Timer { id: startup; interval: 45000; onTriggered: root.fail("Claude Code did not start. Check `claude` on your PATH and your login.") }
  Timer { interval: 1000; repeat: true; running: proc.running && Object.keys(root.pending).length > 0; onTriggered: {
    var now = Date.now()
    for (var id in root.pending) if (root.pending[id].expires < now) { root.fail("Claude Code did not answer. The request was not retried."); break }
  } }
  Timer { id: idle; interval: 600000; onTriggered: { if (root.keepBusy || Object.keys(root.pending).length) restart(); else root.shutdown() } }
  Component.onDestruction: shutdown()
}
