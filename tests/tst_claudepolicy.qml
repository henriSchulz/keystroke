import QtQuick
import QtTest
import "../claude/Policy.js" as Policy
TestCase {
  name: "ClaudePolicy"
  function test_full_request() {
    var text = "Open the document, please.\n" + "Long dictation 🐈 ".repeat(400)
    compare(Policy.userMessage(text).message.content[0].text, text)
    verify(Policy.userMessage(text).message.content[0].text.length > 2000)
  }
  function test_quick_mode_has_no_local_capability() {
    var a = Policy.args("quick", "11111111-2222-4333-8444-555555555555", false, {})
    compare(a[a.indexOf("--permission-mode") + 1], "plan")
    compare(a[a.indexOf("--tools") + 1], "WebSearch,WebFetch")
    // No project, user or local settings, and no inherited MCP servers.
    compare(a[a.indexOf("--setting-sources") + 1], "")
    verify(a.indexOf("--strict-mcp-config") >= 0)
    verify(a.indexOf("--session-id") >= 0 && a.indexOf("--resume") < 0)
    verify(a[a.indexOf("--append-system-prompt") + 1].indexOf("no access to local files") > 0)
  }
  function test_agent_mode_is_scoped_and_resumable() {
    var a = Policy.args("agent", "11111111-2222-4333-8444-555555555555", true, {model: "claude-sonnet-5", effort: "high"})
    compare(a[a.indexOf("--permission-mode") + 1], "acceptEdits")
    compare(a[a.indexOf("--model") + 1], "claude-sonnet-5")
    compare(a[a.indexOf("--effort") + 1], "high")
    compare(a[a.indexOf("--resume") + 1], "11111111-2222-4333-8444-555555555555")
    verify(a.indexOf("--session-id") < 0)
    verify(a[a.indexOf("--append-system-prompt") + 1].indexOf("/usr/share/omarchy") > 0)
  }
  function test_defaults_and_bad_settings_fall_back() {
    var a = Policy.args("quick", "11111111-2222-4333-8444-555555555555", false, {effort: "ludicrous"})
    compare(a[a.indexOf("--model") + 1], "claude-opus-5")
    compare(a[a.indexOf("--effort") + 1], "low")
  }
  function test_session_ids_are_uuids() {
    verify(Policy.safeId(Policy.newId()))
    verify(!Policy.safeId("../new?q=other"))
    verify(!Policy.safeId("thread-test"))
    verify(Policy.newId() !== Policy.newId())
  }
  function test_handoff_passes_the_id_as_a_literal_argument() {
    var id = "11111111-2222-4333-8444-555555555555"
    var argv = Policy.resumeArgv("/home/test/project", id)
    compare(argv[0], "omarchy-launch-terminal")
    compare(argv[argv.length - 2], "/home/test/project")
    compare(argv[argv.length - 1], id)
    compare(Policy.resumeArgv("/tmp", "not-a-uuid").length, 0)
  }
  function test_tool_activity_is_one_readable_line() {
    compare(Policy.toolLabel({name: "Bash", input: {command: "ls -la"}}), "Running: ls -la")
    compare(Policy.toolLabel({name: "Edit", input: {file_path: "/etc/hosts"}}), "Edit: /etc/hosts")
    compare(Policy.toolLabel({name: "Mystery", input: {}}), "Using Mystery")
  }
}
