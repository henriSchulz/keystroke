#!/usr/bin/env python3
"""Deterministic `claude -p --output-format stream-json` fixture.

Speaks the exact transport Keystroke depends on: the initialize control
request, partial-message stream events, a completed assistant message, the
result that ends a turn, and interrupt. Shapes were taken from a real
Claude Code 2.1.263 process.
"""
import json, os, sys, threading, time

lock = threading.Lock()
stop = threading.Event()
turn = 0
argv = sys.argv[1:]


def flag(name, default=""):
    return argv[argv.index(name) + 1] if name in argv else default


SESSION = flag("--session-id") or flag("--resume") or "00000000-0000-4000-8000-000000000000"


def emit(value):
    with lock:
        print(json.dumps(value), flush=True)


def stream(text):
    global turn
    turn += 1
    n = str(turn)
    mid = "msg_" + n
    stop.clear()
    emit({"type": "system", "subtype": "init", "session_id": SESSION, "cwd": os.getcwd(), "tools": ["WebSearch"]})
    emit({"type": "stream_event", "session_id": SESSION,
          "event": {"type": "message_start", "message": {"id": mid, "role": "assistant", "content": []}}})
    emit({"type": "stream_event", "session_id": SESSION,
          "event": {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}})
    emit({"type": "stream_event", "session_id": SESSION,
          "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello "}}})
    if "slow" in text:
        stop.wait(3)
    time.sleep(.05)
    if not stop.is_set():
        emit({"type": "stream_event", "session_id": SESSION,
              "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "world"}}})
        emit({"type": "stream_event", "session_id": SESSION, "event": {"type": "content_block_stop", "index": 0}})
        emit({"type": "assistant", "session_id": SESSION,
              "message": {"id": mid, "role": "assistant", "content": [{"type": "text", "text": "Hello world"}]}})
    if "permission" in text:
        emit({"type": "system", "subtype": "permission_denied", "session_id": SESSION, "tool_name": "Write",
              "message": "Claude requested permissions to write to /tmp/fixture, but you haven't granted it yet."})
    if stop.is_set():
        emit({"type": "user", "session_id": SESSION,
              "message": {"role": "user", "content": [{"type": "text", "text": "[Request interrupted by user]"}]}})
    emit({"type": "result", "session_id": SESSION,
          "subtype": "error_during_execution" if stop.is_set() else "success",
          "result": "" if stop.is_set() else "Hello world", "duration_api_ms": 10})


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    kind = msg.get("type")
    if kind == "control_request":
        subtype = (msg.get("request") or {}).get("subtype")
        if subtype == "initialize":
            emit({"type": "control_response", "response": {"subtype": "success", "request_id": msg["request_id"], "response": {"commands": []}}})
        elif subtype == "interrupt":
            stop.set()
            emit({"type": "control_response", "response": {"subtype": "success", "request_id": msg["request_id"], "response": {"still_queued": []}}})
    elif kind == "user":
        text = "".join(b.get("text", "") for b in msg["message"]["content"])
        if text == "crash now":
            os._exit(7)
        threading.Thread(target=stream, args=(text,), daemon=True).start()
