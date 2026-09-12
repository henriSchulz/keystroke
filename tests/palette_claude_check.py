#!/usr/bin/env python3
"""The Claude provider is registered and produces the palette's own rows."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="keystroke-palette-claude-") as temp:
    work = Path(temp)
    project = work / "project"
    shutil.copytree(root, project, ignore=shutil.ignore_patterns(".git", ".claude", ".agents", "tests", "__pycache__"))
    (work / "qs").symlink_to("/usr/share/omarchy/shell")
    source = project / "Keystroke.qml"
    qml = source.read_text()
    qml = qml.replace("  PanelWindow {", "  Window {\n    transientParent: null\n    width: 1000; height: 800")
    qml = qml.replace("    anchors { top: true; bottom: true; left: true; right: true }\n", "")
    source.write_text("\n".join(line for line in qml.splitlines() if "exclusionMode:" not in line and "WlrLayershell." not in line))
    (work / "shell.qml").write_text('''import QtQuick
import Quickshell
import "project"
ShellRoot {
  id: test
  function check(ok, msg) { if (!ok) { console.log("FAIL", msg); Qt.quit(); throw Error(msg) } }
  function titles() { return palette.rows.map(function(r) { return r.title }) }
  Keystroke { id: palette; omarchyPath: "/usr/share/omarchy" }
  Timer { interval: 250; running: true; onTriggered: {
    palette.applyConfigText(JSON.stringify({ version: 1, matching: { mode: "off" }, providers: { claude: { enabled: true } } }))
    var entry = palette.registry.entries.filter(function(e) { return e.key === "claude" })[0]
    test.check(!!entry, "the Claude provider is registered")
    test.check(entry.provider.name === "Claude", "it is named Claude")
    test.check(palette.registry.problems.length === 0, "the registry reports no problems: " + JSON.stringify(palette.registry.problems))
    var keys = entry.settingsSchema.map(function(s) { return s.key })
    test.check(JSON.stringify(keys) === JSON.stringify(["model", "effort", "destination", "workspace"]), "settings are model/effort/destination/workspace, got " + JSON.stringify(keys))

    palette.open('{"query":"why is the sky blue"}')
    var rows = test.titles()
    test.check(rows.indexOf("Ask Claude here") >= 0, "a free-text query offers the inline ask: " + JSON.stringify(rows))
    test.check(rows.indexOf("Open task in Claude Code") >= 0, "and the external task: " + JSON.stringify(rows))

    palette.open('{"scope":"claude","title":"Claude"}')
    test.check(palette.scope === "claude", "the Claude screen is reachable")
    test.check(test.titles().indexOf("Ask Claude here") >= 0, "the Claude screen offers a new question")

    palette.applyConfigText(JSON.stringify({ version: 1, matching: { mode: "off" }, providers: { claude: { enabled: false } } }))
    palette.open('{"query":"why is the sky blue"}')
    test.check(test.titles().indexOf("Ask Claude here") < 0, "turning the provider off removes its rows")
    palette.cancel()
    console.log("PASS palette claude: provider registered, settings schema, inline ask, scoped screen and the off switch")
    Qt.quit()
  } }
  Timer { interval: 8000; running: true; onTriggered: { console.log("FAIL timeout", palette.errorMessage); Qt.quit() } }
}
''')
    env = dict(os.environ, HOME=str(work), XDG_RUNTIME_DIR=str(work), QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic", QT_QUICK_BACKEND="software", QML_IMPORT_PATH=str(work))
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(work / "shell.qml")], env=env, capture_output=True, text=True, timeout=15)
    out = result.stdout + result.stderr
    assert "PASS palette claude" in out and "FAIL" not in out, out
    assert "TypeError" not in out and "ReferenceError" not in out, out
    print(out.strip().splitlines()[-1])
