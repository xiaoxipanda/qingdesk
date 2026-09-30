#!/usr/bin/env python3
"""Read-only workbench MCP smoke test. Never launches Hermes or target apps."""
import json
import subprocess
import sys

helper = sys.argv[1]
process = subprocess.Popen([helper, "--no-autostart"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True)

def send(message, response=True):
    process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
    process.stdin.flush()
    if response:
        line = process.stdout.readline()
        assert line, "Helper closed stdout"
        return json.loads(line)

try:
    cold = send({"jsonrpc": "2.0", "id": 0, "method": "tools/list"})
    assert cold["error"]["code"] == -32002
    init = send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}}})
    assert init["result"]["serverInfo"]["name"] == "desktop-workbench"
    send({"jsonrpc": "2.0", "method": "notifications/initialized"}, response=False)
    listing = send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    assert len(listing["result"]["tools"]) == 6
    state = send({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                  "params": {"name": "get_workspace_state", "arguments": {}}})
    assert state["result"]["isError"] is False, state
    data = state["result"]["structuredContent"]
    assert data["ok"] is True and len(data["screens"]) >= 1
    denied = send({"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {
        "name": "ensure_app", "arguments": {"app_id": "test.not-a-favorite"}}})
    assert denied["result"]["isError"] is True
    assert denied["result"]["structuredContent"]["code"] == "app_not_allowed"
    invalid = send({"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {
        "name": "apply_layout", "arguments": {"app_ids": ["a", "a"], "preset": "left_right"}}})
    assert invalid["error"]["code"] == -32602
    print(json.dumps({"passed": True, "tools": 6, "favorite_apps": len(data["apps"]),
                      "screens": len(data["screens"]), "accessibility_granted": data["accessibility_granted"]}, ensure_ascii=False))
finally:
    process.stdin.close()
    process.wait(timeout=5)
