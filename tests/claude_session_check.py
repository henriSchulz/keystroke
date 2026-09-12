#!/usr/bin/env python3
"""Exercise production QML transport/session and view against a fake CLI."""
import os,json,pathlib,tempfile,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='keystroke-claude-test-') as temp:
 p=pathlib.Path(temp);(p/'.local/state/keystroke/questions').mkdir(parents=True)
 # A transcript for the resume path: openRecent repaints from Claude Code's own record.
 saved='11111111-2222-4333-8444-555555555555'
 (p/'.claude/projects/-fixture').mkdir(parents=True)
 (p/'.claude/projects/-fixture'/(saved+'.jsonl')).write_text('\n'.join(json.dumps(row) for row in [
   {'type':'user','uuid':'u1','message':{'role':'user','content':[{'type':'text','text':'saved question'}]}},
   {'type':'assistant','uuid':'a1','message':{'role':'assistant','content':[{'type':'text','text':'saved answer'}]}},
   {'type':'assistant','uuid':'a2','message':{'role':'assistant','content':[{'type':'tool_use','name':'Bash','input':{'command':'ls'}}]}},
 ])+'\n')
 (p/'claude').symlink_to(root/'claude');(p/'helpers').symlink_to(root/'helpers');(p/'qs').symlink_to('/usr/share/omarchy/shell')
 for name in ['ui','voice']: (p/name).symlink_to(root/name)
 for name in ['Commons','Ui']: (p/name).symlink_to('/usr/share/omarchy/shell/'+name)
 (p/'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
import "claude"
ShellRoot {
 id: test
 property int stage: 0
 function check(value,message) { if (!value) { console.log("FAIL",message); Qt.quit(); throw Error(message) } }
 ClaudeSession { id: session; home: %s; server.launcher: ["python3",%s] }
 Window { visible: true; width: 700; height: 580
   ConversationView { id: view; anchors.fill: parent; session: session; host: stub }
 }
 QtObject { id: stub
   property color foreground: "#eeeeee"; property color muted: "#aaaaaa"; property color accent: "#aabbff"; property color background: "#222222"
   property var voice: ({active:false,phase:"idle",level:0,history:[]})
   property int backCalls: 0
   function goBack() { backCalls++; return true }
   function cancel() { session.dismiss() }
   function isModifierKey(key) { return key===Qt.Key_Shift }
   function voiceCancel() { voice = ({active:false,phase:"idle",level:0,history:[]}) }
   function voiceStop() { voice = ({active:true,phase:"transcribing",level:0,history:[]}) }
 }
 TestCase { id: keys; name: "ConversationKeys"; when: false }
 Timer { interval: 100; running: true; onTriggered: {
   session.newQuestion("");view.beginVoice();view.transcript("Open the document, please.",false)
   view.transcript("Open the document, please. Keep two lines!\\nSecond line.",true)
   test.check(session.draft.indexOf("Open the document,")===0 && session.draft.indexOf("Second line.")>0,"voice preserves complete prose")
   var editor=keys.findChild(view,"composer");test.check(!!editor,"composer is reachable")
   view.focusInput();session.draft="edit me";editor.cursorPosition=4
   keys.keyClick(Qt.Key_Left);test.check(stub.backCalls===0 && editor.cursorPosition===3,"Left edits a nonempty draft")
   session.draft="";keys.keyClick(Qt.Key_Left);keys.keyClick(Qt.Key_Backspace)
   test.check(stub.backCalls===2,"empty composer uses palette back navigation")
   session.draft="first question"
   view.focusInput();stub.voice=({active:true,phase:"listening",level:0,history:[]})
   keys.keyClick(Qt.Key_Return);test.check(!session.busy && stub.voice.phase==="transcribing","Enter finishes voice without sending")
   keys.keyClick(Qt.Key_A);test.check(!stub.voice.active,"manual correction cancels voice")
   test.check(/^[0-9a-f-]{36}$/.test(session.sessionId),"a session id is claimed before the first turn")
   session.draft="first question";view.focusInput();keys.keyClick(Qt.Key_Return);test.stage=1
 } }
 Timer { interval: 50; repeat: true; running: true; onTriggered: {
   if (test.stage===1 && !session.busy && session.messages.length) {
     test.check(session.answer()==="Hello world","streamed deltas reconcile with the completed message");
     test.check(session.recent.length===1,"durable recent index")
     view.grabToImage(function(result) { result.saveToFile("/tmp/keystroke-claude-preview.png") })
     session.newQuestion("please permission");test.stage=2
   } else if (test.stage===2 && !session.busy && session.permission) {
     test.check(view.approval,"a blocked tool raises the permission panel");
     session.permission="";test.check(!view.approval,"staying here clears the panel");
     session.newQuestion("slow question");test.stage=3
   } else if(test.stage===3 && session.phase==="running") {session.stop();test.stage=4}
   else if(test.stage===4 && !session.busy) {
     test.check(session.activity==="Stopped","stop acknowledged");session.newQuestion("next question");test.stage=5
   } else if(test.stage===5 && !session.busy) {
     session.openRecent({id:%s,title:"saved question",cwd:session.home,mode:"quick",draft:""})
     // Enter while a resumed conversation is still connecting must be kept.
     test.check(session.phase==="preparing","openRecent connects before it is usable")
     session.draft="early enter"
     test.check(session.submit() && session.pendingSubmit,"Enter while reconnecting is queued, not dropped")
     test.stage=51
   } else if(test.stage===51 && !session.busy && session.messages.length>3) {
     test.check(session.messages[0].text==="saved question" && session.messages[1].text==="saved answer","a resumed conversation repaints from the transcript")
     test.check(session.messages[2].role==="activity","tool calls repaint as activity")
     test.check(session.answer()==="Hello world","the queued question was sent once the child was ready")
     test.stage=6;session.requestHandoff()
   }
   else if(test.stage===7 && !session.busy && session.error) {
     test.check(session.draft==="crash now","disconnect preserves unsent or uncertain draft");
     test.check(!!session.sessionId,"disconnect retains the saved conversation");test.stage=8;session.requestHandoff()
   }
 } }
 Connections { target: session
   function onHandoffReady(id) {
     test.check(!session.server.ready,"the child exits before another client resumes the session")
     if(test.stage===6) {test.stage=7;session.newQuestion("crash now");return}
     test.check(test.stage===8,"handoff waits");console.log("PASS Claude stream, voice keys, permission, cancel, disconnect, session release and view");Qt.quit()
   }
 }
 Timer { interval: 12000; running: true; onTriggered: {console.log("FAIL timeout",test.stage,session.phase,session.error);Qt.quit()} }
}'''%(json.dumps(str(p)),json.dumps(str(root/'tests/claude_fake_cli.py')),json.dumps(saved)))
 env=os.environ.copy();env.pop('DISPLAY',None);env.update(HOME=str(p),XDG_RUNTIME_DIR=str(p),QML_IMPORT_PATH=str(p),QT_QPA_PLATFORM='offscreen',QT_QPA_PLATFORMTHEME='generic',QT_QUICK_BACKEND='software')
 r=subprocess.run(['quickshell','-p',str(p/'shell.qml')],env=env,text=True,capture_output=True,timeout=18)
 out=r.stdout+r.stderr
 assert 'PASS Claude' in out and 'FAIL' not in out,out
 assert 'TypeError' not in out and 'ReferenceError' not in out,out
 print(out)
